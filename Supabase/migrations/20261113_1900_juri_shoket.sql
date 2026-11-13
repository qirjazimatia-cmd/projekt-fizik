-- Juri · Username unik, emri i shfaqur, avatari dhe shokët (ftesa me username).
-- Skema `app` mbetet e mbyllur: klienti përdor vetëm public.api_* me app.gate(...).
-- Privatësia: kërkimi kthen vetëm username, emrin e shfaqur dhe avatarin (asnjëherë email ose rol);
-- kërkimi kërkon të paktën 3 shkronja dhe kthen maksimumi 10 rezultate.

alter table app.profiles
  add column if not exists username text,
  add column if not exists display_name text,
  add column if not exists avatar_emoji text,
  add column if not exists avatar_color smallint not null default 0;

do $$ begin
  alter table app.profiles add constraint profiles_username_format check (username is null or username ~ '^[a-z0-9._]{3,20}$');
exception when duplicate_object then null; end $$;
do $$ begin
  alter table app.profiles add constraint profiles_display_name_len check (display_name is null or length(display_name) between 1 and 40);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table app.profiles add constraint profiles_avatar_len check (avatar_emoji is null or length(avatar_emoji) <= 16);
exception when duplicate_object then null; end $$;
create unique index if not exists profiles_username_key on app.profiles (username);

create table if not exists app.friendships (
  requester uuid not null references app.profiles(id) on delete cascade,
  addressee uuid not null references app.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  primary key (requester, addressee),
  check (requester <> addressee)
);
create index if not exists friendships_addressee_idx on app.friendships(addressee);
alter table app.friendships enable row level security;

-- Pamja publike e një përdoruesi (vetëm fushat e sigurta).
create or replace function app.public_user(p app.profiles) returns jsonb language sql stable set search_path = app, pg_temp as $$
  select jsonb_build_object('username', p.username, 'displayName', coalesce(p.display_name, p.username),
                            'avatarEmoji', coalesce(p.avatar_emoji, '🦊'), 'avatarColor', p.avatar_color)
$$;

create or replace function public.api_profileGet(p_body jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = app, pg_temp as $$
declare p app.profiles;
begin
  perform app.gate(array['student','parent','teacher']);
  select * into p from app.profiles where id = auth.uid();
  return jsonb_build_object('email', p.email, 'username', p.username, 'displayName', p.display_name,
                            'avatarEmoji', coalesce(p.avatar_emoji, '🦊'), 'avatarColor', p.avatar_color);
end $$;

create or replace function public.api_profileUpdate(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare
  v_username text := lower(trim(p_body->>'username'));
  v_display text := trim(p_body->>'displayName');
  v_emoji text := p_body->>'avatarEmoji';
  v_color int := (p_body->>'avatarColor')::int;
begin
  perform app.gate(array['student','parent','teacher']);
  if p_body ? 'username' then
    if v_username !~ '^[a-z0-9._]{3,20}$' then
      return jsonb_build_object('error', 'Username duhet të ketë 3–20 shkronja të vogla, numra, pikë ose _ (pa hapësira).');
    end if;
    if exists(select 1 from app.profiles where username = v_username and id <> auth.uid()) then
      return jsonb_build_object('error', 'Ky username është i zënë. Provo një tjetër.');
    end if;
  end if;
  if p_body ? 'displayName' and (v_display is null or length(v_display) not between 1 and 40) then
    return jsonb_build_object('error', 'Emri i shfaqur duhet të ketë 1–40 shkronja.');
  end if;
  if p_body ? 'avatarEmoji' and (v_emoji is null or length(v_emoji) > 16) then
    return jsonb_build_object('error', 'Avatari nuk është i vlefshëm.');
  end if;
  update app.profiles set
    username = case when p_body ? 'username' then v_username else username end,
    display_name = case when p_body ? 'displayName' then v_display else display_name end,
    avatar_emoji = case when p_body ? 'avatarEmoji' then v_emoji else avatar_emoji end,
    avatar_color = case when p_body ? 'avatarColor' then greatest(0, least(coalesce(v_color, 0), 20)) else avatar_color end
  where id = auth.uid();
  return jsonb_build_object('ok', true);
exception when unique_violation then
  return jsonb_build_object('error', 'Ky username është i zënë. Provo një tjetër.');
end $$;

create or replace function public.api_usernameAvailable(p_body jsonb) returns jsonb
language plpgsql stable security definer set search_path = app, pg_temp as $$
declare v_username text := lower(trim(p_body->>'username'));
begin
  perform app.gate(array['student','parent','teacher']);
  if v_username !~ '^[a-z0-9._]{3,20}$' then return jsonb_build_object('available', false); end if;
  return jsonb_build_object('available', not exists(select 1 from app.profiles where username = v_username and id <> auth.uid()));
end $$;

-- Lidhja me një përdorues tjetër: friend · sent · received · none.
create or replace function app.relation(other uuid) returns text language sql stable set search_path = app, pg_temp as $$
  select coalesce((select case when f.status = 'accepted' then 'friend'
                               when f.requester = auth.uid() then 'sent' else 'received' end
                   from app.friendships f
                   where (f.requester = auth.uid() and f.addressee = other) or (f.requester = other and f.addressee = auth.uid())
                   limit 1), 'none')
$$;

create or replace function public.api_userSearch(p_body jsonb) returns jsonb
language plpgsql stable security definer set search_path = app, pg_temp as $$
declare v_query text := lower(trim(coalesce(p_body->>'query', '')));
begin
  perform app.gate(array['student','parent','teacher']);
  v_query := regexp_replace(v_query, '^@', '');
  if length(v_query) < 3 or v_query !~ '^[a-z0-9._]+$' then return jsonb_build_object('users', '[]'::jsonb); end if;
  return jsonb_build_object('users', coalesce((
    select jsonb_agg(app.public_user(p) || jsonb_build_object('relation', app.relation(p.id)) order by (p.username = v_query) desc, p.username)
    from (select * from app.profiles
          where username is not null and id <> auth.uid() and username like v_query || '%'
          order by username limit 10) p), '[]'::jsonb));
end $$;

create or replace function public.api_friendRequest(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare
  v_other uuid;
  v_username text := lower(regexp_replace(trim(coalesce(p_body->>'username', '')), '^@', ''));
begin
  perform app.gate(array['student','parent','teacher']);
  if (select username from app.profiles where id = auth.uid()) is null then
    return jsonb_build_object('error', 'Krijo fillimisht username-in tënd te Cilësimet.');
  end if;
  select id into v_other from app.profiles where username = v_username;
  if v_other is null then return jsonb_build_object('error', 'Nuk u gjet asnjë përdorues me këtë username.'); end if;
  if v_other = auth.uid() then return jsonb_build_object('error', 'Nuk mund t''i dërgosh ftesë vetes.'); end if;
  -- Nëse ai të ka ftuar tashmë, ftesa pranohet menjëherë.
  update app.friendships set status = 'accepted' where requester = v_other and addressee = auth.uid() and status = 'pending';
  if found then return jsonb_build_object('ok', true, 'relation', 'friend'); end if;
  if exists(select 1 from app.friendships where (requester = auth.uid() and addressee = v_other) or (requester = v_other and addressee = auth.uid())) then
    return jsonb_build_object('ok', true, 'relation', app.relation(v_other));
  end if;
  if (select count(*) from app.friendships where requester = auth.uid() and status = 'pending') >= 50 then
    return jsonb_build_object('error', 'Ke shumë ftesa në pritje. Prit që disa të pranohen.');
  end if;
  insert into app.friendships(requester, addressee) values (auth.uid(), v_other);
  return jsonb_build_object('ok', true, 'relation', 'sent');
end $$;

create or replace function public.api_friendRespond(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare v_other uuid := (select id from app.profiles where username = lower(trim(coalesce(p_body->>'username', ''))));
begin
  perform app.gate(array['student','parent','teacher']);
  if v_other is null then return jsonb_build_object('error', 'Përdoruesi nuk u gjet.'); end if;
  if coalesce((p_body->>'accept')::boolean, false) then
    update app.friendships set status = 'accepted' where requester = v_other and addressee = auth.uid() and status = 'pending';
  else
    delete from app.friendships where requester = v_other and addressee = auth.uid() and status = 'pending';
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.api_friendRemove(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare v_other uuid := (select id from app.profiles where username = lower(trim(coalesce(p_body->>'username', ''))));
begin
  perform app.gate(array['student','parent','teacher']);
  delete from app.friendships
   where (requester = auth.uid() and addressee = v_other) or (requester = v_other and addressee = auth.uid());
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.api_friendsList(p_body jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = app, pg_temp as $$
begin
  perform app.gate(array['student','parent','teacher']);
  return jsonb_build_object(
    'friends', coalesce((select jsonb_agg(app.public_user(p) order by coalesce(p.display_name, p.username))
                         from app.friendships f join app.profiles p on p.id = case when f.requester = auth.uid() then f.addressee else f.requester end
                         where f.status = 'accepted' and auth.uid() in (f.requester, f.addressee) and p.username is not null), '[]'::jsonb),
    'incoming', coalesce((select jsonb_agg(app.public_user(p) order by f.created_at desc)
                          from app.friendships f join app.profiles p on p.id = f.requester
                          where f.status = 'pending' and f.addressee = auth.uid() and p.username is not null), '[]'::jsonb),
    'outgoing', coalesce((select jsonb_agg(app.public_user(p) order by f.created_at desc)
                          from app.friendships f join app.profiles p on p.id = f.addressee
                          where f.status = 'pending' and f.requester = auth.uid() and p.username is not null), '[]'::jsonb));
end $$;

revoke all on function app.public_user(app.profiles) from public, anon, authenticated;
revoke all on function app.relation(uuid) from public, anon, authenticated;
do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and (p.proname like 'api\_profile%' or p.proname like 'api\_friend%'
                                            or p.proname in ('api_usernameavailable', 'api_usersearch'))
  loop execute format('revoke all on function %s from public, anon', f.sig); execute format('grant execute on function %s to authenticated', f.sig); end loop;
end $$;
