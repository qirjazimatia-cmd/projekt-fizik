-- Juri · Renditja javore me XP (të gjithë nxënësit, jo vetëm shokët) dhe Sfida e ditës.
-- Privatësia (si te shokët, #52/#61 e Matias): në renditje shfaqen vetëm nxënës me username që janë anëtarë të miratuar
-- të një klase (app.friend_eligible); shfaqen vetëm username, emri i shfaqur, avatari dhe XP. Asnjë email.
-- XP-të llogariten në app nga puna e nxënësit; serveri i pranon vetëm në rritje dhe me kufi (+3000 për raport),
-- që të mos «fryhen» me një kërkesë të vetme.

create table if not exists app.player_xp (
  user_id uuid primary key references app.profiles(id) on delete cascade,
  total_xp integer not null default 0 check (total_xp >= 0),
  week_start date not null,
  week_base integer not null default 0,
  updated_at timestamptz not null default now()
);
alter table app.player_xp enable row level security;

create table if not exists app.daily_answers (
  user_id uuid not null references app.profiles(id) on delete cascade,
  day date not null,
  correct boolean not null,
  answered_at timestamptz not null default now(),
  primary key (user_id, day)
);
create index if not exists daily_answers_day_idx on app.daily_answers(day);
alter table app.daily_answers enable row level security;

-- E hëna e kësaj jave, sipas orës së Shqipërisë.
create or replace function app.week_start() returns date language sql stable set search_path = app, pg_temp as $$
  select date_trunc('week', now() at time zone 'Europe/Tirane')::date
$$;
create or replace function app.today_tirane() returns date language sql stable set search_path = app, pg_temp as $$
  select (now() at time zone 'Europe/Tirane')::date
$$;
revoke all on function app.week_start() from public, anon, authenticated;
revoke all on function app.today_tirane() from public, anon, authenticated;

create or replace function public.api_xpReport(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare
  v_xp integer := greatest(0, least(coalesce((p_body->>'xp')::integer, 0), 10000000));
  v_week date := app.week_start();
begin
  perform app.gate(array['student']);
  insert into app.player_xp(user_id, total_xp, week_start, week_base)
  values (auth.uid(), v_xp, v_week, v_xp)   -- herën e parë java nis nga zero
  on conflict (user_id) do update set
    week_base = case when app.player_xp.week_start <> v_week then app.player_xp.total_xp else app.player_xp.week_base end,
    week_start = v_week,
    total_xp = greatest(app.player_xp.total_xp, least(excluded.total_xp, app.player_xp.total_xp + 3000)),
    updated_at = now();
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.api_leaderboard(p_body jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = app, pg_temp as $$
declare
  v_week date := app.week_start();
  v_all boolean := coalesce(p_body->>'scope', 'week') = 'all';
  v_rows jsonb;
  v_me jsonb;
begin
  perform app.gate(array['student']);
  with scored as (
    select p.id, p.username, coalesce(p.display_name, p.username) as display_name,
           coalesce(p.avatar_emoji, '🦊') as avatar_emoji, p.avatar_color,
           case when v_all then x.total_xp
                when x.week_start = v_week then x.total_xp - x.week_base else 0 end as xp
    from app.player_xp x join app.profiles p on p.id = x.user_id
    where app.friend_eligible(p.id) or p.id = auth.uid()
  ), ranked as (
    select *, rank() over (order by xp desc) as place from scored where xp > 0 or id = auth.uid()
  )
  select coalesce(jsonb_agg(jsonb_build_object('rank', place, 'username', username, 'displayName', display_name,
                                               'avatarEmoji', avatar_emoji, 'avatarColor', avatar_color, 'xp', xp,
                                               'me', id = auth.uid()) order by place, username)
                  filter (where place <= 50), '[]'::jsonb),
         (select jsonb_build_object('rank', place, 'xp', xp) from ranked where id = auth.uid())
    into v_rows, v_me
  from ranked;
  return jsonb_build_object('rows', v_rows, 'me', v_me, 'weekStart', v_week);
end $$;

create or replace function public.api_dailyAnswer(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare
  v_day date := (p_body->>'day')::date;
  v_today date := app.today_tirane();
begin
  perform app.gate(array['student']);
  if v_day is null or v_day not between v_today - 1 and v_today + 1 then
    return jsonb_build_object('error', 'Sfida e kësaj dite ka mbaruar.');
  end if;
  insert into app.daily_answers(user_id, day, correct)
  values (auth.uid(), v_day, coalesce((p_body->>'correct')::boolean, false))
  on conflict (user_id, day) do nothing;
  return public.api_dailyStats(jsonb_build_object('day', v_day));
end $$;

create or replace function public.api_dailyStats(p_body jsonb) returns jsonb
language plpgsql stable security definer set search_path = app, pg_temp as $$
declare v_day date := coalesce((p_body->>'day')::date, app.today_tirane());
begin
  perform app.gate(array['student']);
  return (select jsonb_build_object(
      'answered', count(*),
      'correctPercent', case when count(*) = 0 then 0 else round(100.0 * count(*) filter (where correct) / count(*)) end,
      'mine', (select correct from app.daily_answers where user_id = auth.uid() and day = v_day))
    from app.daily_answers where day = v_day);
end $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname in ('api_xpreport', 'api_leaderboard', 'api_dailyanswer', 'api_dailystats')
  loop execute format('revoke all on function %s from public, anon', f.sig); execute format('grant execute on function %s to authenticated', f.sig); end loop;
end $$;
