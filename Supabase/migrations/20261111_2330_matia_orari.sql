-- Don Bosko Connect · Orari javor i klasës (kërkesa e Matias)
-- Mësuesi krijon orët e klasës së vet (dita e javës, ora e fillimit/mbarimit, lënda, salla). Nxënësit e klasës dhe
-- prindërit e tyre e shohin; mësuesi sheh orarin e vet me të gjitha klasat. Vetëm përmes public.api_schedule*.
-- Mund të ekzekutohet përsëri.

create table if not exists app.schedule_slots (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references app.classes(id) on delete cascade,
  owner_id uuid not null references app.profiles(id) on delete cascade,
  weekday smallint not null check (weekday between 1 and 7),          -- 1 = e hënë ... 7 = e diel (ISO)
  starts time not null,
  ends time not null,
  subject text not null check (length(subject) between 1 and 80),
  room text not null default '' check (length(room) <= 40),
  created_at timestamptz not null default now(),
  check (ends > starts)
);
create index if not exists schedule_slots_class_idx on app.schedule_slots(class_id);
create index if not exists schedule_slots_owner_idx on app.schedule_slots(owner_id);
alter table app.schedule_slots enable row level security;

-- Orari që sheh përdoruesi: mësuesi → orët e veta; nxënësi → klasat ku është anëtar i miratuar; prindi → klasat e fëmijëve.
create or replace function public.api_scheduleGet(p_body jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = app, pg_temp as $$
begin
  perform app.gate(array['student','parent','teacher']);
  return jsonb_build_object('slots', coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', s.id, 'classID', s.class_id, 'className', c.name, 'weekday', s.weekday,
             'starts', to_char(s.starts, 'HH24:MI'), 'ends', to_char(s.ends, 'HH24:MI'),
             'subject', s.subject, 'room', s.room, 'mine', s.owner_id = auth.uid())
           order by s.weekday, s.starts)
      from app.schedule_slots s join app.classes c on c.id = s.class_id
     where s.owner_id = auth.uid() or app.in_class(s.class_id) or app.parent_sees_class(s.class_id)), '[]'::jsonb));
end $$;

create or replace function public.api_scheduleCreate(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare
  v_class uuid := (p_body->>'classID')::uuid;
  v_day int := (p_body->>'weekday')::int;
  v_start time; v_end time;
  v_subject text := trim(coalesce(p_body->>'subject',''));
  v_room text := left(trim(coalesce(p_body->>'room','')), 40);
begin
  perform app.gate(array['teacher']);
  if not app.owns_class(v_class) then raise exception 'Nuk ke të drejtë mbi këtë klasë.' using errcode = 'PT403'; end if;
  if v_day is null or v_day not between 1 and 7 then return jsonb_build_object('error','Zgjidh ditën e javës.'); end if;
  if v_subject = '' or length(v_subject) > 80 then return jsonb_build_object('error','Shkruaj lëndën.'); end if;
  begin v_start := (p_body->>'starts')::time; v_end := (p_body->>'ends')::time;
  exception when others then return jsonb_build_object('error','Ora nuk është e vlefshme (p.sh. 08:00).'); end;
  if v_end <= v_start then return jsonb_build_object('error','Ora e mbarimit duhet të jetë pas fillimit.'); end if;
  if (select count(*) from app.schedule_slots where class_id = v_class) >= 80 then
    return jsonb_build_object('error','Klasa ka shumë orë në orar.'); end if;
  if exists(select 1 from app.schedule_slots where owner_id = auth.uid() and weekday = v_day and starts < v_end and ends > v_start) then
    return jsonb_build_object('error','Ke tashmë një orë tjetër në këtë kohë.'); end if;
  if exists(select 1 from app.schedule_slots where class_id = v_class and weekday = v_day and starts < v_end and ends > v_start) then
    return jsonb_build_object('error','Klasa ka tashmë një orë në këtë kohë.'); end if;
  insert into app.schedule_slots(class_id, owner_id, weekday, starts, ends, subject, room)
    values (v_class, auth.uid(), v_day, v_start, v_end, v_subject, v_room);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.api_scheduleDelete(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
begin
  perform app.gate(array['teacher']);
  delete from app.schedule_slots where id = (p_body->>'slotID')::uuid and owner_id = auth.uid();
  if not found then raise exception 'Ora nuk është e jotja.' using errcode = 'PT403'; end if;
  return jsonb_build_object('ok', true);
end $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname like 'api\_schedule%'
  loop execute format('revoke all on function %s from public, anon', f.sig); execute format('grant execute on function %s to authenticated', f.sig); end loop;
end $$;
