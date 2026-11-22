-- Sekretaria (#106), fshirja e llogarisë (#67), llogaritë e rishikimit (#68).
--  · app.student_exempt: llogari nxënësish që hyjnë pa kodin e sekretarisë (p.sh. llogaritë e provës).
--  · app.review_accounts: llogaritë demo të App Review / Google Play; nuk kërkojnë kodin e dytë me email
--    (rishikuesi nuk merr dot email). Krijohen vetëm nga serveri, kurrë nga app-i; fjalëkalimet NUK janë në repo.
--  · api_adminExempt, api_adminAdmins: sekretaria menaxhon përjashtimet dhe sekretarët e tjerë.
--  · api_deleteAccount: çdo llogari me email të konfirmuar mund të fshihet (edhe pa rol, edhe nxënës i paverifikuar);
--    mësuesi duhet të ketë kaluar faktorin e dytë. Regjistri i shkollës ruhet, por rreshti shkëputet.

create table if not exists app.student_exempt (
  user_id uuid primary key references app.profiles(id) on delete cascade,
  added_by uuid references app.profiles(id) on delete set null,
  added_at timestamptz not null default now()
);
alter table app.student_exempt enable row level security;

create table if not exists app.review_accounts (
  user_id uuid primary key references app.profiles(id) on delete cascade,
  note text,
  added_at timestamptz not null default now()
);
alter table app.review_accounts enable row level security;

create or replace function app.is_review_account(p_uid uuid) returns boolean
language sql stable security definer set search_path = app, pg_temp as $$
  select exists(select 1 from app.review_accounts where user_id = p_uid)
$$;

-- Nxënësi lejohet: detyrimi i fikur, ose rresht aktiv në regjistër, ose i përjashtuar nga sekretaria.
create or replace function app.student_ok(p_uid uuid) returns boolean
language sql stable security definer set search_path = app, pg_temp as $$
  select not app.student_verification_required() or app.student_verified(p_uid)
      or exists(select 1 from app.student_exempt where user_id = p_uid)
$$;

create or replace function app.mfa_ok(p_role text) returns boolean
language sql stable security definer set search_path = app, auth, pg_temp as $$
  select coalesce(auth.jwt()->>'aal','aal1') = 'aal2'
      or app.is_review_account(auth.uid())
      or (not exists(select 1 from auth.mfa_factors where user_id = auth.uid() and status = 'verified')
          and (not app.mfa_required(p_role)
               or (app.mfa_method() = 'email' and app.session_2fa_ok())))
$$;

create or replace function app."current_role"() returns text
language sql stable security definer set search_path = app, auth, pg_temp as $$
  select p.role from app.profiles p join auth.users u on u.id = p.id
   where p.id = auth.uid() and u.email_confirmed_at is not null and p.role <> 'unassigned'
     and (p.role <> 'teacher' or p.teacher_status = 'active') and app.mfa_ok(p.role)
     and (p.role <> 'student' or app.student_ok(p.id))
$$;

create or replace function app.gate(p_roles text[]) returns text
language plpgsql stable security definer set search_path = app, auth, pg_temp as $$
declare v_role text;
begin
  if auth.uid() is null then raise exception 'Seanca ka mbaruar. Hyr përsëri.' using errcode = 'PT401'; end if;
  v_role := app.current_role();
  if v_role is null then
    if exists(select 1 from app.profiles where id = auth.uid() and role = 'teacher' and teacher_status = 'pending_approval') then
      raise exception 'Llogaria e mësuesit pret miratimin e administratorit.' using errcode = 'PT403'; end if;
    if exists(select 1 from app.profiles where id = auth.uid() and role = 'student') and not app.student_ok(auth.uid()) then
      raise exception 'Aktivizo llogarinë me kodin personal nga sekretaria e shkollës.' using errcode = 'PT403'; end if;
    raise exception 'Llogaria nuk është gati: konfirmo emailin, zgjidh rolin ose jep faktorin e dytë.' using errcode = 'PT403';
  end if;
  if not (v_role = any(p_roles)) then raise exception 'Veprimi nuk lejohet për rolin tënd.' using errcode = 'PT403'; end if;
  return v_role;
end $$;

create or replace function public.api_me(p_body jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = app, auth, pg_temp as $$
declare p app.profiles%rowtype; u auth.users%rowtype;
begin
  if auth.uid() is null then raise exception 'Seanca ka mbaruar. Hyr përsëri.' using errcode = 'PT401'; end if;
  select * into p from app.profiles where id = auth.uid();
  select * into u from auth.users where id = auth.uid();
  if p.id is null or u.email_confirmed_at is null then raise exception 'Emaili nuk është konfirmuar.' using errcode = 'PT403'; end if;
  return jsonb_build_object('id', p.id, 'email', p.email, 'role', p.role, 'teacherStatus', p.teacher_status,
    'mfaEnrolled', exists(select 1 from auth.mfa_factors where user_id = auth.uid() and status = 'verified'),
    'mfaRequired', app.mfa_required(p.role) and not app.is_review_account(p.id),
    'mfaMethod', app.mfa_method(),
    'secondFactorOk', app.session_2fa_ok() or app.is_review_account(p.id),
    'aal', coalesce(auth.jwt()->>'aal','aal1'),
    'studentCodeRequired', app.student_verification_required(),
    'studentVerified', app.student_ok(p.id),
    'schoolAdmin', app.is_school_admin(p.id));
end $$;

-- Fshirja e llogarisë: Apple 5.1.1(v) dhe Google Play e kërkojnë për çdo llogari, edhe nga web-i.
create or replace function public.api_deleteaccount(p_body jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = app, auth, pg_temp as $$
declare v_role text;
begin
  if auth.uid() is null then raise exception 'Seanca ka mbaruar. Hyr përsëri.' using errcode = 'PT401'; end if;
  select p.role into v_role from app.profiles p join auth.users u on u.id = p.id
   where p.id = auth.uid() and u.email_confirmed_at is not null;
  if v_role is null then return jsonb_build_object('error','Emaili nuk është konfirmuar.'); end if;
  if app.is_review_account(auth.uid()) then
    return jsonb_build_object('error','Kjo është llogari demo e rishikimit dhe nuk fshihet nga këtu.'); end if;
  if v_role = 'teacher' and not app.mfa_ok('teacher') then
    return jsonb_build_object('error','Për llogarinë e mësuesit konfirmo fillimisht kodin që të vjen me email.', 'needsSecondFactor', true);
  end if;
  update app.roster set user_id = null, activated_at = null, updated_at = now(),
         status = case when status = 'left' then 'left' else 'pending' end
   where user_id = auth.uid();
  perform app.audit('account_deleted', v_role);
  delete from auth.users where id = auth.uid();
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.api_adminroster(p_body jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = app, auth, pg_temp as $$
begin
  perform app.gate_admin();
  return jsonb_build_object(
    'required', app.student_verification_required(),
    'codeDays', coalesce(app.setting('student_code_days'),'30')::int,
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
        'id', r.id, 'amza', r.amza, 'firstName', r.first_name, 'lastName', r.last_name, 'className', r.class_name,
        'birthYear', r.birth_year, 'status', r.status, 'account', p.email,
        'hasCode', r.code_hash is not null and r.code_expires > now(), 'codeExpires', r.code_expires,
        'activatedAt', r.activated_at)
      order by app.class_key(r.class_name), r.last_name, r.first_name)
      from app.roster r left join app.profiles p on p.id = r.user_id), '[]'::jsonb),
    'unverifiedStudents', (select count(*) from app.profiles p where p.role = 'student'
        and not app.student_verified(p.id) and not exists(select 1 from app.student_exempt e where e.user_id = p.id)),
    'exempt', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'email', p.email, 'name', coalesce(p.display_name, p.username, p.email))
        order by p.email) from app.student_exempt e join app.profiles p on p.id = e.user_id), '[]'::jsonb));
end $$;

-- action: 'existing' = përjashto të gjitha llogaritë e nxënësve që ekzistojnë sot dhe nuk janë në regjistër;
--         'remove'   = hiq përjashtimin për një llogari (userId).
create or replace function public.api_adminexempt(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, auth, pg_temp as $$
declare n int; v_uid uuid;
begin
  perform app.gate_admin();
  if p_body->>'action' = 'existing' then
    insert into app.student_exempt(user_id, added_by)
    select p.id, auth.uid() from app.profiles p
     where p.role = 'student' and not app.student_verified(p.id)
    on conflict (user_id) do nothing;
    get diagnostics n = row_count;
  elsif p_body->>'action' = 'remove' then
    begin v_uid := (p_body->>'userId')::uuid; exception when others then return jsonb_build_object('error','Llogari e panjohur.'); end;
    if app.is_review_account(v_uid) then return jsonb_build_object('error','Llogaritë demo të rishikimit mbeten të përjashtuara.'); end if;
    delete from app.student_exempt where user_id = v_uid;
    get diagnostics n = row_count;
  else return jsonb_build_object('error','Veprim i panjohur.');
  end if;
  perform app.audit('student_exempt_' || (p_body->>'action'), null, jsonb_build_object('count', n));
  return jsonb_build_object('ok', true, 'count', n);
end $$;

-- Sekretarët: 'list', 'add' (email i një mësuesi aktiv), 'remove' (jo sekretari i fundit).
create or replace function public.api_adminadmins(p_body jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = app, auth, pg_temp as $$
declare v_action text := coalesce(p_body->>'action','list'); v_uid uuid;
begin
  perform app.gate_admin();
  if v_action = 'add' then
    select id into v_uid from app.profiles where email_key = app.email_key(coalesce(p_body->>'email',''))
      and role = 'teacher' and teacher_status = 'active';
    if v_uid is null then return jsonb_build_object('error','Nuk u gjet asnjë mësues aktiv me këtë email.'); end if;
    insert into app.school_admins(user_id) values (v_uid) on conflict do nothing;
    perform app.audit('school_admin_added', v_uid::text);
  elsif v_action = 'remove' then
    begin v_uid := (p_body->>'userId')::uuid; exception when others then return jsonb_build_object('error','Llogari e panjohur.'); end;
    if (select count(*) from app.school_admins) <= 1 then
      return jsonb_build_object('error','Duhet të mbetet të paktën një sekretar.'); end if;
    delete from app.school_admins where user_id = v_uid;
    perform app.audit('school_admin_removed', v_uid::text);
  elsif v_action <> 'list' then return jsonb_build_object('error','Veprim i panjohur.');
  end if;
  return jsonb_build_object('ok', true, 'admins', coalesce((select jsonb_agg(jsonb_build_object(
      'id', p.id, 'email', p.email, 'name', coalesce(p.display_name, p.email), 'me', p.id = auth.uid()) order by a.added_at)
    from app.school_admins a join app.profiles p on p.id = a.user_id), '[]'::jsonb));
end $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'app' and p.proname in ('is_review_account','student_ok')
  loop execute format('revoke all on function %s from public, anon, authenticated', f.sig); end loop;
end $$;
revoke all on function public.api_me(jsonb) from public, anon;             grant execute on function public.api_me(jsonb) to authenticated;
revoke all on function public.api_deleteaccount(jsonb) from public, anon;  grant execute on function public.api_deleteaccount(jsonb) to authenticated;
revoke all on function public.api_adminroster(jsonb) from public, anon;    grant execute on function public.api_adminroster(jsonb) to authenticated;
revoke all on function public.api_adminexempt(jsonb) from public, anon;    grant execute on function public.api_adminexempt(jsonb) to authenticated;
revoke all on function public.api_adminadmins(jsonb) from public, anon;    grant execute on function public.api_adminadmins(jsonb) to authenticated;
