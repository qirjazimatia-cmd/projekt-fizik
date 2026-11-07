-- ScienceQuest · Supabase · 0001 · autentikimi, rolet, kodi i mësuesit, throttling, audit
-- STATUSI: I PA-EKZEKUTUAR (nuk kishte PostgreSQL/Supabase gjatë shkrimit). Ekzekutoje në projekt PROVË; shih SUPABASE-SETUP.md.
-- Parimi: tabelat jetojnë në skemën `app` (e pa-ekspozuar nga API), RLS aktiv dhe pa politika për klientin.
-- Klienti thërret vetëm public.api_* (security definer), që kontrollojnë rolin, emailin e konfirmuar, MFA, klasën dhe pronësinë.
-- Asnjë sekret/kod nuk shkruhet në këtë skedar.

create extension if not exists pgcrypto with schema extensions;
create schema if not exists app;
revoke all on schema app from public, anon, authenticated;

create table app.settings (name text primary key, value text not null);
insert into app.settings values ('teacher_approval_required','false'), ('require_teacher_mfa','false') on conflict do nothing;
create table app.secrets (name text primary key, salt text not null, hash text not null);
alter table app.settings enable row level security;
alter table app.secrets enable row level security;
create function app.setting(p_name text) returns text language sql stable security definer set search_path = app, pg_temp as
$$ select value from app.settings where name = p_name $$;

create table app.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  role text not null default 'unassigned' check (role in ('unassigned','student','parent','teacher')),
  teacher_status text not null default 'none' check (teacher_status in ('none','active','pending_approval','rejected')),
  created_at timestamptz not null default now()
);
alter table app.profiles enable row level security;

-- Roli NUK lexohet nga user_metadata: çdo përdorues i ri është 'unassigned'.
create function app.handle_new_user() returns trigger language plpgsql security definer set search_path = app, pg_temp as $$
begin insert into app.profiles(id, email) values (new.id, lower(new.email)); return new; end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function app.handle_new_user();

-- MFA: nëse përdoruesi ka faktor të verifikuar, sesioni duhet të jetë aal2 (edhe pse klienti mund të "harrojë" ta kërkojë).
-- Kur require_teacher_mfa='true', mësuesi kërkon gjithmonë aal2.
create function app.mfa_ok(p_role text) returns boolean language sql stable security definer set search_path = app, auth, pg_temp as $$
  select coalesce(auth.jwt()->>'aal','aal1') = 'aal2'
      or (not exists(select 1 from auth.mfa_factors where user_id = auth.uid() and status = 'verified')
          and not (p_role = 'teacher' and coalesce(app.setting('require_teacher_mfa'),'false') = 'true'))
$$;

create function app.current_role() returns text language sql stable security definer set search_path = app, auth, pg_temp as $$
  select p.role from app.profiles p join auth.users u on u.id = p.id
   where p.id = auth.uid() and u.email_confirmed_at is not null and p.role <> 'unassigned'
     and (p.role <> 'teacher' or p.teacher_status = 'active') and app.mfa_ok(p.role)
$$;

create function app.gate(p_roles text[]) returns text language plpgsql stable security definer set search_path = app, auth, pg_temp as $$
declare v_role text;
begin
  if auth.uid() is null then raise exception 'Seanca ka mbaruar. Hyr përsëri.' using errcode = 'PT401'; end if;
  v_role := app.current_role();
  if v_role is null then
    if exists(select 1 from app.profiles where id = auth.uid() and role = 'teacher' and teacher_status = 'pending_approval') then
      raise exception 'Llogaria e mësuesit pret miratimin e administratorit.' using errcode = 'PT403'; end if;
    raise exception 'Llogaria nuk është gati: konfirmo emailin, zgjidh rolin ose jep faktorin e dytë.' using errcode = 'PT403';
  end if;
  if not (v_role = any(p_roles)) then raise exception 'Veprimi nuk lejohet për rolin tënd.' using errcode = 'PT403'; end if;
  return v_role;
end $$;

create table app.throttle (key text primary key, started timestamptz not null, n int not null);
alter table app.throttle enable row level security;
create function app.hit(p_key text, p_limit int, p_window interval) returns boolean language plpgsql security definer set search_path = app, pg_temp as $$
declare r app.throttle%rowtype;
begin
  insert into app.throttle as t(key, started, n) values (p_key, now(), 1)
  on conflict (key) do update set
    started = case when t.started + p_window <= now() then now() else t.started end,
    n = case when t.started + p_window <= now() then 1 else t.n + 1 end
  returning * into r;
  return r.n <= p_limit;
end $$;
create function app.blocked(p_key text, p_limit int, p_window interval) returns boolean language sql stable security definer set search_path = app, pg_temp as
$$ select coalesce((select n >= p_limit and started + p_window > now() from app.throttle where key = p_key), false) $$;

create table app.audit_log (id bigserial primary key, at timestamptz not null default now(), actor uuid, action text not null, target text, detail jsonb not null default '{}');
alter table app.audit_log enable row level security;
create function app.audit(p_action text, p_target text default null, p_detail jsonb default '{}') returns void language sql security definer set search_path = app, pg_temp as
$$ insert into app.audit_log(actor, action, target, detail) values (auth.uid(), p_action, p_target, p_detail) $$;

-- Kodi i mësuesit: ruhet vetëm si hash me kripë. Administratori e vendos te SQL Editor:  select app.admin_set_teacher_code('KODI');
create function app.admin_set_teacher_code(p_code text) returns void language plpgsql security definer set search_path = app, extensions, pg_temp as $$
declare v_salt text := encode(gen_random_bytes(16),'hex');
begin
  if p_code !~ '^[0-9]{5}$' then raise exception 'Kodi duhet të ketë 5 shifra.'; end if;
  insert into app.secrets values ('teacher_code', v_salt, encode(digest(v_salt || p_code, 'sha256'), 'hex'))
  on conflict (name) do update set salt = excluded.salt, hash = excluded.hash;
end $$;
create function app.admin_set_setting(p_name text, p_value text) returns void language sql security definer set search_path = app, pg_temp as
$$ insert into app.settings values (p_name, p_value) on conflict (name) do update set value = excluded.value $$;
create function app.admin_review_teacher(p_email text, p_approve boolean) returns text language plpgsql security definer set search_path = app, pg_temp as $$
declare n int;
begin
  update app.profiles set teacher_status = case when p_approve then 'active' else 'rejected' end
   where email = lower(trim(p_email)) and role = 'teacher';
  get diagnostics n = row_count;
  insert into app.audit_log(action, target, detail) values ('admin_review_teacher', lower(trim(p_email)), jsonb_build_object('approve', p_approve));
  return case when n = 1 then 'U përditësua.' else 'Nuk u gjet mësues me këtë email.' end;
end $$;
revoke all on function app.admin_set_teacher_code(text), app.admin_set_setting(text,text), app.admin_review_teacher(text,boolean) from public, anon, authenticated;

create function public.api_me(p_body jsonb default '{}') returns jsonb language plpgsql stable security definer set search_path = app, auth, pg_temp as $$
declare p app.profiles%rowtype; u auth.users%rowtype;
begin
  if auth.uid() is null then raise exception 'Seanca ka mbaruar. Hyr përsëri.' using errcode = 'PT401'; end if;
  select * into p from app.profiles where id = auth.uid();
  select * into u from auth.users where id = auth.uid();
  if p.id is null or u.email_confirmed_at is null then raise exception 'Emaili nuk është konfirmuar.' using errcode = 'PT403'; end if;
  return jsonb_build_object('id', p.id, 'email', p.email, 'role', p.role, 'teacherStatus', p.teacher_status,
    'mfaEnrolled', exists(select 1 from auth.mfa_factors where user_id = auth.uid() and status = 'verified'),
    'aal', coalesce(auth.jwt()->>'aal','aal1'));
end $$;

create function public.api_chooseRole(p_body jsonb) returns jsonb language plpgsql security definer set search_path = app, auth, pg_temp as $$
declare v_role text := p_body->>'role'; n int;
begin
  if auth.uid() is null then raise exception 'Seanca ka mbaruar. Hyr përsëri.' using errcode = 'PT401'; end if;
  if v_role not in ('student','parent') then return jsonb_build_object('error','Zgjidh nxënës ose prind.'); end if;
  update app.profiles p set role = v_role from auth.users u
   where p.id = auth.uid() and u.id = p.id and u.email_confirmed_at is not null and p.role = 'unassigned';
  get diagnostics n = row_count;
  if n <> 1 then return jsonb_build_object('error','Roli është caktuar tashmë ose emaili nuk është konfirmuar. Roli nuk ndryshohet.'); end if;
  perform app.audit('role_chosen', v_role);
  return jsonb_build_object('ok', true, 'role', v_role);
end $$;

-- Kodi i mësuesit: 5 gabime për llogari/24 orë, 40 globalisht/orë. Kthen {error} (jo exception) që numëruesi të ruhet.
create function public.api_redeemTeacherCode(p_body jsonb) returns jsonb language plpgsql security definer set search_path = app, auth, extensions, pg_temp as $$
declare s app.secrets%rowtype; v_code text := coalesce(p_body->>'code',''); v_status text; n int;
        v_generic constant text := 'Kodi nuk është i vlefshëm ose ka shumë tentativa. Provo më vonë ose kontakto administratorin.';
begin
  if auth.uid() is null then raise exception 'Seanca ka mbaruar. Hyr përsëri.' using errcode = 'PT401'; end if;
  if not exists(select 1 from app.profiles p join auth.users u on u.id = p.id where p.id = auth.uid() and p.role = 'unassigned' and u.email_confirmed_at is not null) then
    return jsonb_build_object('error','Roli është caktuar tashmë ose emaili nuk është konfirmuar. Roli nuk ndryshohet.'); end if;
  if app.blocked('tc:user:' || auth.uid(), 5, interval '24 hours') or app.blocked('tc:global', 40, interval '1 hour') then
    return jsonb_build_object('error', v_generic); end if;
  select * into s from app.secrets where name = 'teacher_code';
  if not found then return jsonb_build_object('error','Regjistrimi i mësuesve nuk është konfiguruar ende nga administratori.'); end if;
  if length(v_code) > 20 or encode(digest(s.salt || v_code, 'sha256'), 'hex') <> s.hash then
    perform app.hit('tc:user:' || auth.uid(), 5, interval '24 hours');
    perform app.hit('tc:global', 40, interval '1 hour');
    perform app.audit('teacher_code_failed');
    return jsonb_build_object('error', v_generic);
  end if;
  v_status := case when coalesce(app.setting('teacher_approval_required'),'false') = 'true' then 'pending_approval' else 'active' end;
  update app.profiles set role = 'teacher', teacher_status = v_status where id = auth.uid() and role = 'unassigned';
  get diagnostics n = row_count;
  if n <> 1 then return jsonb_build_object('error', v_generic); end if;
  perform app.audit('teacher_registered', v_status);
  return jsonb_build_object('ok', true, 'role', 'teacher', 'teacherStatus', v_status);
end $$;

create function public.api_deleteAccount(p_body jsonb default '{}') returns jsonb language plpgsql security definer set search_path = app, auth, pg_temp as $$
begin
  perform app.gate(array['student','parent','teacher']);
  perform app.audit('account_deleted');
  delete from auth.users where id = auth.uid();
  return jsonb_build_object('ok', true);
end $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname like 'api\_%'
  loop execute format('revoke all on function %s from public, anon', f.sig); execute format('grant execute on function %s to authenticated', f.sig); end loop;
end $$;
