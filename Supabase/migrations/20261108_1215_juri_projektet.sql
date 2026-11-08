-- Don Bosko Connect · Projekte individuale dhe në grup (Juri, issue #6, prompt §8)
-- Mësuesi krijon projekt për klasën e vet (individual ose në grup). Në grup mësuesi krijon ekipet dhe cakton nxënësit;
-- anëtarët vendosin rolet, mbajnë ditarin e kontributeve dhe dorëzojnë versione (v1, v2, ...) me shënim dhe skedarë.
-- Skedarët ruhen në kovën private `projects`; leja kontrollohet nga sq_can_project_* (si te 0006).
-- Privatësia: nxënësi sheh vetëm ekipin e vet; prindi sheh vetëm pjesën e fëmijës së vet dhe skedarët pas vlerësimit.
-- Varet nga 0001–0006. Klienti nuk ka akses te tabelat; vetëm përmes public.api_project*. Mund të ekzekutohet përsëri.

-- 1) Tabelat ---------------------------------------------------------------------------------------------
create table if not exists app.projects (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references app.classes(id) on delete cascade,
  owner_id uuid not null references app.profiles(id) on delete cascade,
  title text not null check (length(title) between 1 and 200),
  description text not null default '' check (length(description) <= 4000),
  kind text not null check (kind in ('individual','group')),
  due_at timestamptz,
  status text not null default 'open' check (status in ('open','closed')),
  created_at timestamptz not null default now()
);
create table if not exists app.project_teams (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references app.projects(id) on delete cascade,
  name text not null check (length(name) between 1 and 100),
  created_at timestamptz not null default now()
);
create table if not exists app.project_members (
  team_id uuid not null references app.project_teams(id) on delete cascade,
  project_id uuid not null references app.projects(id) on delete cascade,
  student_id uuid not null references app.profiles(id) on delete cascade,
  role text not null default '' check (length(role) <= 60),
  joined_at timestamptz not null default now(),
  primary key (team_id, student_id),
  unique (project_id, student_id)              -- një nxënës = një ekip për projekt
);
create table if not exists app.project_contributions (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references app.project_teams(id) on delete cascade,
  student_id uuid not null references app.profiles(id) on delete cascade,
  note text not null check (length(note) between 1 and 1000),
  created_at timestamptz not null default now()
);
create table if not exists app.project_versions (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references app.project_teams(id) on delete cascade,
  number int not null check (number between 1 and 50),
  note text not null default '' check (length(note) <= 2000),
  created_by uuid references app.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  submitted_by uuid references app.profiles(id) on delete set null,
  submitted_at timestamptz,
  feedback text not null default '' check (length(feedback) <= 4000),
  reviewed_at timestamptz,
  unique (team_id, number)
);
-- Vetëm një draft i hapur për ekip: dy anëtarë që shtypin njëkohësisht "Version i ri" marrin të njëjtin draft.
create unique index if not exists project_versions_one_draft on app.project_versions(team_id) where submitted_at is null;
create index if not exists projects_class_idx on app.projects(class_id);
create index if not exists project_teams_project_idx on app.project_teams(project_id);
create index if not exists project_members_student_idx on app.project_members(student_id);
create index if not exists project_contributions_team_idx on app.project_contributions(team_id);

alter table app.projects enable row level security;
alter table app.project_teams enable row level security;
alter table app.project_members enable row level security;
alter table app.project_contributions enable row level security;
alter table app.project_versions enable row level security;

-- 2) Ndihmës --------------------------------------------------------------------------------------------
create or replace function app.in_team(p_team uuid) returns boolean
language sql stable security definer set search_path = app, pg_temp as
$$ select exists(select 1 from app.project_members where team_id = p_team and student_id = auth.uid()) $$;

create or replace function app.owns_project(p_project uuid) returns boolean
language sql stable security definer set search_path = app, pg_temp as
$$ select exists(select 1 from app.projects where id = p_project and owner_id = auth.uid()) $$;

-- Prindi i një anëtari të ekipit.
create or replace function app.parent_of_team(p_team uuid) returns boolean
language sql stable security definer set search_path = app, pg_temp as
$$ select exists(select 1 from app.project_members m join app.parent_links pl on pl.child_id = m.student_id
                  where m.team_id = p_team and pl.parent_id = auth.uid()) $$;

revoke all on function app.in_team(uuid) from public, anon, authenticated;
revoke all on function app.owns_project(uuid) from public, anon, authenticated;
revoke all on function app.parent_of_team(uuid) from public, anon, authenticated;

-- 3) Kova private `projects` dhe rregullat e saj ---------------------------------------------------------
-- Rruga: <teamID>/<versionID>/<8 shenja>-<emri>. 25 MB për skedar, deri në 10 skedarë për version.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('projects', 'projects', false, 26214400, array[
  'application/pdf', 'text/plain',
  'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-powerpoint', 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'image/jpeg', 'image/png', 'image/heic', 'image/heif',
  'audio/mpeg', 'audio/mp4', 'audio/x-m4a', 'audio/m4a', 'audio/aac',
  'video/mp4', 'video/quicktime'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.sq_project_parts(p_name text, out team_id uuid, out version_id uuid)
language plpgsql immutable set search_path = pg_catalog as $$
begin
  if p_name !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[^/]{1,160}$' then
    team_id := null; version_id := null; return;
  end if;
  team_id := split_part(p_name, '/', 1)::uuid;
  version_id := split_part(p_name, '/', 2)::uuid;
end $$;

-- Ngarkim/fshirje: vetëm anëtari i ekipit, te drafti i hapur, kur projekti është i hapur, deri në 10 skedarë.
create or replace function public.sq_can_project_upload(p_name text) returns boolean
language plpgsql stable security definer set search_path = app, storage, pg_temp as $$
declare p record;
begin
  select * into p from public.sq_project_parts(p_name);
  if p.team_id is null or app."current_role"() is distinct from 'student' then return false; end if;
  return exists(
      select 1 from app.project_versions v
        join app.project_teams t on t.id = v.team_id
        join app.projects pr on pr.id = t.project_id
        join app.project_members m on m.team_id = t.id and m.student_id = auth.uid()
       where v.id = p.version_id and v.team_id = p.team_id and v.submitted_at is null and pr.status = 'open')
    and (select count(*) from storage.objects o
          where o.bucket_id = 'projects' and o.name like p.team_id::text || '/' || p.version_id::text || '/%') < 10;
end $$;

-- Lexim: anëtarët e ekipit, mësuesi i projektit; prindi i anëtarit vetëm pasi versioni është vlerësuar.
create or replace function public.sq_can_project_read(p_name text) returns boolean
language plpgsql stable security definer set search_path = app, pg_temp as $$
declare p record;
begin
  select * into p from public.sq_project_parts(p_name);
  if p.team_id is null or app."current_role"() is null then return false; end if;
  return exists(
    select 1 from app.project_versions v join app.project_teams t on t.id = v.team_id join app.projects pr on pr.id = t.project_id
     where v.id = p.version_id and v.team_id = p.team_id
       and (app.in_team(t.id) or pr.owner_id = auth.uid() or (v.reviewed_at is not null and app.parent_of_team(t.id))));
end $$;

revoke all on function public.sq_project_parts(text) from public, anon;
revoke all on function public.sq_can_project_upload(text) from public, anon;
revoke all on function public.sq_can_project_read(text) from public, anon;
grant execute on function public.sq_project_parts(text) to authenticated;
grant execute on function public.sq_can_project_upload(text) to authenticated;
grant execute on function public.sq_can_project_read(text) to authenticated;

drop policy if exists "sq_projects_insert" on storage.objects;
drop policy if exists "sq_projects_select" on storage.objects;
drop policy if exists "sq_projects_delete" on storage.objects;
-- Pa rregull UPDATE: skedari nuk mbishkruhet; hiqet dhe ngarkohet sërish ndërsa versioni është draft.
create policy "sq_projects_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'projects' and public.sq_can_project_upload(name));
create policy "sq_projects_select" on storage.objects for select to authenticated
  using (bucket_id = 'projects' and public.sq_can_project_read(name));
create policy "sq_projects_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'projects' and public.sq_can_project_upload(name));

create or replace function app.project_files(p_team uuid, p_version uuid) returns jsonb
language sql stable security definer set search_path = app, storage, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'path', o.name,
           'question', split_part(o.name, '/', 2),
           'name', regexp_replace(split_part(o.name, '/', 3), '^[0-9a-zA-Z]{8}-', ''),
           'size', coalesce((o.metadata->>'size')::bigint, 0),
           'mime', coalesce(o.metadata->>'mimetype', ''),
           'uploaded', extract(epoch from o.created_at)) order by o.created_at), '[]')
    from storage.objects o where o.bucket_id = 'projects' and o.name like p_team::text || '/' || p_version::text || '/%'
$$;
revoke all on function app.project_files(uuid, uuid) from public, anon, authenticated;

-- 4) Pamja e një ekipi ------------------------------------------------------------------------------------
-- p_mode: 'full' (mësuesi i projektit ose anëtar i ekipit) | 'parent' (vetëm fëmija i vet; skedarët pas vlerësimit).
create or replace function app.project_team_view(p_team uuid, p_mode text) returns jsonb
language plpgsql stable security definer set search_path = app, pg_temp as $$
declare t app.project_teams%rowtype; pr app.projects%rowtype; v_members jsonb; v_contrib jsonb; v_versions jsonb;
begin
  select * into t from app.project_teams where id = p_team;
  select * into pr from app.projects where id = t.project_id;
  select coalesce(jsonb_agg(jsonb_build_object('id', m.student_id, 'email', p.email, 'role', m.role) order by p.email), '[]')
    into v_members from app.project_members m join app.profiles p on p.id = m.student_id
   where m.team_id = p_team
     and (p_mode = 'full' or exists(select 1 from app.parent_links pl where pl.parent_id = auth.uid() and pl.child_id = m.student_id));
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'student', p.email, 'note', c.note, 'date', app.epoch(c.created_at)) order by c.created_at desc), '[]')
    into v_contrib from (select * from app.project_contributions where team_id = p_team order by created_at desc limit 200) c
    join app.profiles p on p.id = c.student_id
   where p_mode = 'full' or exists(select 1 from app.parent_links pl where pl.parent_id = auth.uid() and pl.child_id = c.student_id);
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', v.id, 'number', v.number, 'note', v.note,
           'created', app.epoch(v.created_at),
           'submitted', case when v.submitted_at is null then null else app.epoch(v.submitted_at) end,
           'submittedBy', sb.email,
           'late', pr.due_at is not null and v.submitted_at > pr.due_at,
           'feedback', case when v.reviewed_at is not null then v.feedback else '' end,
           'reviewed', case when v.reviewed_at is null then null else app.epoch(v.reviewed_at) end,
           'files', case when p_mode = 'full' or v.reviewed_at is not null then app.project_files(v.team_id, v.id) else '[]'::jsonb end)
         order by v.number desc), '[]')
    into v_versions from app.project_versions v left join app.profiles sb on sb.id = v.submitted_by
   where v.team_id = p_team and (p_mode = 'full' or v.submitted_at is not null);
  return jsonb_build_object('id', t.id, 'name', t.name, 'members', v_members, 'contributions', v_contrib, 'versions', v_versions);
end $$;
revoke all on function app.project_team_view(uuid, text) from public, anon, authenticated;

-- 5) API --------------------------------------------------------------------------------------------------
create or replace function public.api_projects(p_body jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare v_role text; v_out jsonb := '[]'; pr record; v_teams jsonb; v_students jsonb; v_mine boolean;
begin
  v_role := app.gate(array['student','parent','teacher']);
  for pr in select p.*, c.name as class_name from app.projects p join app.classes c on c.id = p.class_id
             where p.owner_id = auth.uid() or app.in_class(p.class_id) or app.parent_sees_class(p.class_id)
             order by p.status = 'closed', coalesce(p.due_at, p.created_at) loop
    v_mine := pr.owner_id = auth.uid();
    v_students := null;
    if v_mine then
      select coalesce(jsonb_agg(app.project_team_view(t.id, 'full') order by t.name), '[]') into v_teams
        from app.project_teams t where t.project_id = pr.id;
      select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'email', p.email) order by p.email), '[]') into v_students
        from app.class_members m join app.profiles p on p.id = m.user_id where m.class_id = pr.class_id and m.approved;
    elsif v_role = 'student' then
      select coalesce(jsonb_agg(app.project_team_view(t.id, 'full')), '[]') into v_teams
        from app.project_teams t where t.project_id = pr.id and app.in_team(t.id);
    else
      select coalesce(jsonb_agg(app.project_team_view(t.id, 'parent')), '[]') into v_teams
        from app.project_teams t where t.project_id = pr.id and app.parent_of_team(t.id);
    end if;
    v_out := v_out || jsonb_build_object('id', pr.id, 'classID', pr.class_id, 'className', pr.class_name, 'title', pr.title,
      'description', pr.description, 'kind', pr.kind, 'status', pr.status, 'mine', v_mine,
      'due', case when pr.due_at is null then null else app.epoch(pr.due_at) end,
      'teams', v_teams, 'students', v_students);
  end loop;
  return jsonb_build_object('projects', v_out, 'serverNow', app.epoch(now()));
end $$;

create or replace function public.api_projectCreate(p_body jsonb)
returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare v_class uuid := (p_body->>'classID')::uuid; v_title text := trim(coalesce(p_body->>'title',''));
        v_desc text := trim(coalesce(p_body->>'description','')); v_kind text := coalesce(p_body->>'kind','individual');
        v_due timestamptz := case when p_body ? 'due' and jsonb_typeof(p_body->'due') = 'number' then to_timestamp((p_body->>'due')::double precision) end;
        v_id uuid;
begin
  perform app.gate(array['teacher']);
  if not app.owns_class(v_class) then raise exception 'Nuk ke të drejtë mbi këtë klasë.' using errcode = 'PT403'; end if;
  if v_title = '' or length(v_title) > 200 then return jsonb_build_object('error','Shkruaj titullin e projektit (deri 200 shkronja).'); end if;
  if length(v_desc) > 4000 then return jsonb_build_object('error','Përshkrimi është shumë i gjatë (deri 4000 shkronja).'); end if;
  if v_kind not in ('individual','group') then return jsonb_build_object('error','Zgjidh: individual ose në grup.'); end if;
  if v_due is not null and v_due < now() - interval '1 day' then return jsonb_build_object('error','Afati është në të kaluarën.'); end if;
  insert into app.projects(class_id, owner_id, title, description, kind, due_at) values (v_class, auth.uid(), v_title, v_desc, v_kind, v_due)
  returning id into v_id;
  perform app.audit('project_created', v_id::text, jsonb_build_object('class', v_class, 'kind', v_kind));
  return jsonb_build_object('ok', true, 'code', v_id);
end $$;

-- Mbyll ose rihap projektin. I mbyllur: nuk pranohen versione, kontribute, ngarkime apo ndryshime rolesh.
create or replace function public.api_projectStatus(p_body jsonb)
returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare v_project uuid := (p_body->>'projectID')::uuid; v_close boolean := coalesce((p_body->>'close')::boolean, false);
begin
  perform app.gate(array['teacher']);
  update app.projects set status = case when v_close then 'closed' else 'open' end where id = v_project and owner_id = auth.uid();
  if not found then raise exception 'Projekti nuk është i yti.' using errcode = 'PT403'; end if;
  perform app.audit('project_status', v_project::text, jsonb_build_object('close', v_close));
  return jsonb_build_object('ok', true);
end $$;

-- Fshirja lejohet vetëm kur projekti nuk ka asnjë skedar në Storage (SQL nuk i fshin dot skedarët; shih #13).
create or replace function public.api_projectDelete(p_body jsonb)
returns jsonb language plpgsql security definer set search_path = app, storage, pg_temp as $$
declare v_project uuid := (p_body->>'projectID')::uuid;
begin
  perform app.gate(array['teacher']);
  if coalesce((p_body->>'confirm')::boolean, false) is not true then return jsonb_build_object('error','Konfirmo fshirjen.'); end if;
  if not app.owns_project(v_project) then raise exception 'Projekti nuk është i yti.' using errcode = 'PT403'; end if;
  if exists(select 1 from storage.objects o join app.project_teams t on o.name like t.id::text || '/%'
             where o.bucket_id = 'projects' and t.project_id = v_project) then
    return jsonb_build_object('error','Projekti ka skedarë të dorëzuar. Mbylle projektin në vend që ta fshish.');
  end if;
  delete from app.projects where id = v_project;
  perform app.audit('project_deleted', v_project::text, '{}');
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.api_projectTeamCreate(p_body jsonb)
returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare v_project uuid := (p_body->>'projectID')::uuid; v_name text := trim(coalesce(p_body->>'name','')); v_kind text; v_id uuid;
begin
  perform app.gate(array['teacher']);
  select kind into v_kind from app.projects where id = v_project and owner_id = auth.uid();
  if v_kind is null then raise exception 'Projekti nuk është i yti.' using errcode = 'PT403'; end if;
  if v_kind <> 'group' then return jsonb_build_object('error','Ekipet krijohen vetëm për projektet në grup.'); end if;
  if v_name = '' or length(v_name) > 100 then return jsonb_build_object('error','Shkruaj emrin e grupit.'); end if;
  if (select count(*) from app.project_teams where project_id = v_project) >= 60 then return jsonb_build_object('error','Ke arritur kufirin e grupeve për këtë projekt.'); end if;
  insert into app.project_teams(project_id, name) values (v_project, v_name) returning id into v_id;
  return jsonb_build_object('ok', true, 'code', v_id);
end $$;

-- Grupi fshihet vetëm kur nuk ka ende versione (puna e dorëzuar nuk humbet nga një klikim).
create or replace function public.api_projectTeamDelete(p_body jsonb)
returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare v_team uuid := (p_body->>'teamID')::uuid; v_project uuid;
begin
  perform app.gate(array['teacher']);
  select t.project_id into v_project from app.project_teams t join app.projects p on p.id = t.project_id where t.id = v_team and p.owner_id = auth.uid();
  if v_project is null then raise exception 'Grupi nuk është i yti.' using errcode = 'PT403'; end if;
  if exists(select 1 from app.project_versions where team_id = v_team) then return jsonb_build_object('error','Grupi ka versione pune. Nuk fshihet.'); end if;
  delete from app.project_teams where id = v_team;
  return jsonb_build_object('ok', true);
end $$;

-- Mësuesi shton/heq një nxënës të miratuar të klasës në një grup.
create or replace function public.api_projectMember(p_body jsonb)
returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare v_team uuid := (p_body->>'teamID')::uuid; v_student uuid := (p_body->>'student')::uuid;
        v_add boolean := coalesce((p_body->>'add')::boolean, true); pr app.projects%rowtype;
begin
  perform app.gate(array['teacher']);
  select p.* into pr from app.project_teams t join app.projects p on p.id = t.project_id where t.id = v_team and p.owner_id = auth.uid();
  if pr.id is null then raise exception 'Grupi nuk është i yti.' using errcode = 'PT403'; end if;
  if not v_add then
    delete from app.project_members where team_id = v_team and student_id = v_student;
    perform app.audit('project_member_removed', v_team::text, jsonb_build_object('student', v_student));
    return jsonb_build_object('ok', true);
  end if;
  if not exists(select 1 from app.class_members where class_id = pr.class_id and user_id = v_student and approved) then
    return jsonb_build_object('error','Nxënësi nuk është anëtar i miratuar i kësaj klase.');
  end if;
  if exists(select 1 from app.project_members where project_id = pr.id and student_id = v_student) then
    return jsonb_build_object('error','Nxënësi është tashmë në një grup të këtij projekti.');
  end if;
  if (select count(*) from app.project_members where team_id = v_team) >= 12 then return jsonb_build_object('error','Grupi ka arritur kufirin prej 12 anëtarësh.'); end if;
  insert into app.project_members(team_id, project_id, student_id) values (v_team, pr.id, v_student);
  perform app.audit('project_member_added', v_team::text, jsonb_build_object('student', v_student));
  return jsonb_build_object('ok', true);
exception when unique_violation then
  return jsonb_build_object('error','Nxënësi është tashmë në një grup të këtij projekti.');
end $$;

-- Roli brenda grupit: e vendos mësuesi ose çdo anëtar i grupit (grupi organizohet vetë), vetëm kur projekti është i hapur.
create or replace function public.api_projectRole(p_body jsonb)
returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare v_team uuid := (p_body->>'teamID')::uuid; v_student uuid := (p_body->>'student')::uuid;
        v_role text := trim(coalesce(p_body->>'role','')); pr app.projects%rowtype;
begin
  perform app.gate(array['student','teacher']);
  select p.* into pr from app.project_teams t join app.projects p on p.id = t.project_id where t.id = v_team;
  if pr.id is null or not (pr.owner_id = auth.uid() or app.in_team(v_team)) then raise exception 'Nuk je në këtë grup.' using errcode = 'PT403'; end if;
  if pr.status <> 'open' then return jsonb_build_object('error','Projekti është mbyllur.'); end if;
  if length(v_role) > 60 then return jsonb_build_object('error','Roli duhet të jetë deri në 60 shkronja.'); end if;
  update app.project_members set role = v_role where team_id = v_team and student_id = v_student;
  if not found then return jsonb_build_object('error','Ky nxënës nuk është në grup.'); end if;
  return jsonb_build_object('ok', true);
end $$;

-- Projekt individual: nxënësi i miratuar i klasës e nis vetë dhe merr "grupin" e tij personal. Idempotent.
create or replace function public.api_projectStart(p_body jsonb)
returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare v_project uuid := (p_body->>'projectID')::uuid; pr app.projects%rowtype; v_team uuid; v_email text;
begin
  perform app.gate(array['student']);
  select * into pr from app.projects where id = v_project;
  if pr.id is null or not app.in_class(pr.class_id) then raise exception 'Projekti nuk është i klasës sate.' using errcode = 'PT403'; end if;
  select team_id into v_team from app.project_members where project_id = v_project and student_id = auth.uid();
  if v_team is not null then return jsonb_build_object('ok', true, 'code', v_team); end if;
  if pr.kind <> 'individual' then return jsonb_build_object('error','Ky është projekt në grup. Mësuesi të cakton në një grup.'); end if;
  if pr.status <> 'open' then return jsonb_build_object('error','Projekti është mbyllur.'); end if;
  perform pg_advisory_xact_lock(hashtext('project_start:' || v_project::text || auth.uid()::text));
  select team_id into v_team from app.project_members where project_id = v_project and student_id = auth.uid();
  if v_team is not null then return jsonb_build_object('ok', true, 'code', v_team); end if;
  select email into v_email from app.profiles where id = auth.uid();
  insert into app.project_teams(project_id, name) values (v_project, left(coalesce(split_part(v_email,'@',1), 'Individual'), 100)) returning id into v_team;
  insert into app.project_members(team_id, project_id, student_id) values (v_team, v_project, auth.uid());
  return jsonb_build_object('ok', true, 'code', v_team);
end $$;

create or replace function public.api_projectContribute(p_body jsonb)
returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare v_team uuid := (p_body->>'teamID')::uuid; v_note text := trim(coalesce(p_body->>'note','')); v_status text;
begin
  perform app.gate(array['student']);
  if not app.in_team(v_team) then raise exception 'Nuk je në këtë grup.' using errcode = 'PT403'; end if;
  select p.status into v_status from app.project_teams t join app.projects p on p.id = t.project_id where t.id = v_team;
  if v_status <> 'open' then return jsonb_build_object('error','Projekti është mbyllur.'); end if;
  if v_note = '' or length(v_note) > 1000 then return jsonb_build_object('error','Shkruaj çfarë bëre (deri 1000 shkronja).'); end if;
  if not app.hit('contrib:' || auth.uid(), 60, interval '1 hour') then return jsonb_build_object('error','Shumë shënime brenda një ore. Prit pak.'); end if;
  insert into app.project_contributions(team_id, student_id, note) values (v_team, auth.uid(), v_note);
  return jsonb_build_object('ok', true);
end $$;

-- Hap draftin e radhës (ose kthen draftin ekzistues). Skedarët ngarkohen te drafti; dorëzimi e kyç.
create or replace function public.api_projectVersionNew(p_body jsonb)
returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare v_team uuid := (p_body->>'teamID')::uuid; v_status text; v_id uuid; v_next int;
begin
  perform app.gate(array['student']);
  if not app.in_team(v_team) then raise exception 'Nuk je në këtë grup.' using errcode = 'PT403'; end if;
  select p.status into v_status from app.project_teams t join app.projects p on p.id = t.project_id where t.id = v_team;
  if v_status <> 'open' then return jsonb_build_object('error','Projekti është mbyllur.'); end if;
  perform pg_advisory_xact_lock(hashtext('project_version:' || v_team::text));
  select id into v_id from app.project_versions where team_id = v_team and submitted_at is null;
  if v_id is not null then return jsonb_build_object('ok', true, 'code', v_id); end if;
  select coalesce(max(number), 0) + 1 into v_next from app.project_versions where team_id = v_team;
  if v_next > 50 then return jsonb_build_object('error','Ke arritur kufirin prej 50 versionesh.'); end if;
  insert into app.project_versions(team_id, number, created_by) values (v_team, v_next, auth.uid()) returning id into v_id;
  return jsonb_build_object('ok', true, 'code', v_id);
end $$;

-- Dorëzon draftin. Pas dorëzimit versioni nuk ndryshon më; për ndryshime hapet versioni pasardhës.
create or replace function public.api_projectVersionSubmit(p_body jsonb)
returns jsonb language plpgsql security definer set search_path = app, storage, pg_temp as $$
declare v_version uuid := (p_body->>'versionID')::uuid; v_note text := trim(coalesce(p_body->>'note','')); v app.project_versions%rowtype; v_status text;
begin
  perform app.gate(array['student']);
  select * into v from app.project_versions where id = v_version for update;
  if v.id is null or not app.in_team(v.team_id) then raise exception 'Nuk je në këtë grup.' using errcode = 'PT403'; end if;
  if v.submitted_at is not null then return jsonb_build_object('error','Ky version është dorëzuar tashmë. Hap një version të ri për ndryshime.'); end if;
  select p.status into v_status from app.project_teams t join app.projects p on p.id = t.project_id where t.id = v.team_id;
  if v_status <> 'open' then return jsonb_build_object('error','Projekti është mbyllur.'); end if;
  if length(v_note) > 2000 then return jsonb_build_object('error','Shënimi duhet të jetë deri në 2000 shkronja.'); end if;
  if v_note = '' and not exists(select 1 from storage.objects o where o.bucket_id = 'projects' and o.name like v.team_id::text || '/' || v.id::text || '/%') then
    return jsonb_build_object('error','Shto një shënim ose të paktën një skedar para dorëzimit.');
  end if;
  update app.project_versions set note = v_note, submitted_at = now(), submitted_by = auth.uid() where id = v.id;
  perform app.audit('project_version_submitted', v.id::text, jsonb_build_object('team', v.team_id, 'number', v.number));
  return jsonb_build_object('ok', true);
end $$;

-- Mësuesi jep vlerësim me fjalë për një version të dorëzuar. Pas kësaj prindi sheh komentin dhe skedarët e atij versioni.
create or replace function public.api_projectFeedback(p_body jsonb)
returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare v_version uuid := (p_body->>'versionID')::uuid; v_text text := trim(coalesce(p_body->>'feedback',''));
begin
  perform app.gate(array['teacher']);
  if length(v_text) > 4000 then return jsonb_build_object('error','Komenti duhet të jetë deri në 4000 shkronja.'); end if;
  update app.project_versions v set feedback = v_text, reviewed_at = now()
    from app.project_teams t, app.projects p
   where v.id = v_version and t.id = v.team_id and p.id = t.project_id and p.owner_id = auth.uid() and v.submitted_at is not null;
  if not found then raise exception 'Versioni nuk u gjet ose nuk është dorëzuar.' using errcode = 'PT403'; end if;
  perform app.audit('project_feedback', v_version::text, '{}');
  return jsonb_build_object('ok', true);
end $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname like 'api\_project%'
  loop execute format('revoke all on function %s from public, anon', f.sig); execute format('grant execute on function %s to authenticated', f.sig); end loop;
end $$;
