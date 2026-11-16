-- Identiteti i nxënësit (#102): regjistri i sekretarisë + kodi personal i aktivizimit.
--  · Sekretaria = mësues aktiv i shënuar te app.school_admins (2FA i mësuesit vlen edhe këtu).
--  · Regjistri: numri i Amzës (ID unike), emri, mbiemri, klasa, viti i lindjes. Pa foto, pa adresë.
--  · Kodi: 8 shenja (40 bit), një përdorim, skadon (30 ditë), ruhet vetëm si sha256.
--  · Detyrimi `require_student_verification` mbetet 'false' derisa sekretaria ta ndezë nga paneli.
--    Kur ndizet, nxënësi pa rresht aktiv në regjistër nuk kalon app.gate (as api_* e tjera).
--  · Mësuesit (kodi i përbashkët) dhe prindërit (kodi i fëmijës) nuk ndryshojnë.

create table if not exists app.school_admins (
  user_id uuid primary key references app.profiles(id) on delete cascade,
  added_at timestamptz not null default now()
);
alter table app.school_admins enable row level security;

create table if not exists app.roster (
  id uuid primary key default gen_random_uuid(),
  amza text not null unique check (length(amza) between 1 and 20),
  first_name text not null check (length(first_name) between 1 and 40),
  last_name text not null check (length(last_name) between 1 and 40),
  class_name text not null check (length(class_name) between 1 and 12),
  birth_year smallint check (birth_year is null or birth_year between 1990 and 2030),
  status text not null default 'pending' check (status in ('pending','active','left')),
  user_id uuid unique references app.profiles(id) on delete set null,
  code_hash text unique,
  code_expires timestamptz,
  activated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table app.roster enable row level security;
create index if not exists roster_class_idx on app.roster (class_name);

insert into app.settings(name, value) values ('require_student_verification','false'), ('student_code_days','30')
on conflict (name) do nothing;

-- "XI B", "11b", "11-B" → "11B"
create or replace function app.class_key(p text) returns text
language plpgsql immutable set search_path = app, pg_temp as $$
declare s text := upper(regexp_replace(coalesce(p,''), '[^A-Za-z0-9]', '', 'g')); m text[];
begin
  m := regexp_match(s, '^(XII|XI|X|IX|VIII|VII|VI|V|IV|III|II|I)([A-Z]?)$');
  if m is not null then
    return (case m[1] when 'I' then '1' when 'II' then '2' when 'III' then '3' when 'IV' then '4' when 'V' then '5'
      when 'VI' then '6' when 'VII' then '7' when 'VIII' then '8' when 'IX' then '9' when 'X' then '10'
      when 'XI' then '11' else '12' end) || m[2];
  end if;
  return s;
end $$;

create or replace function app.student_code_norm(p text) returns text
language sql immutable set search_path = app, pg_temp as $$
  select upper(regexp_replace(coalesce(p,''), '[^A-Za-z0-9]', '', 'g'))
$$;

create or replace function app.student_verification_required() returns boolean
language sql stable security definer set search_path = app, pg_temp as $$
  select coalesce(app.setting('require_student_verification'),'false') = 'true'
$$;

create or replace function app.student_verified(p_uid uuid) returns boolean
language sql stable security definer set search_path = app, pg_temp as $$
  select exists(select 1 from app.roster r where r.user_id = p_uid and r.status = 'active')
$$;

create or replace function app.is_school_admin(p_uid uuid) returns boolean
language sql stable security definer set search_path = app, pg_temp as $$
  select exists(select 1 from app.school_admins a join app.profiles p on p.id = a.user_id
                 where a.user_id = p_uid and p.role = 'teacher' and p.teacher_status = 'active')
$$;

-- Roli i vlefshëm: si më parë + nxënësi duhet të jetë i verifikuar kur detyrimi është ndezur.
create or replace function app."current_role"() returns text
language sql stable security definer set search_path = app, auth, pg_temp as $$
  select p.role from app.profiles p join auth.users u on u.id = p.id
   where p.id = auth.uid() and u.email_confirmed_at is not null and p.role <> 'unassigned'
     and (p.role <> 'teacher' or p.teacher_status = 'active') and app.mfa_ok(p.role)
     and (p.role <> 'student' or not app.student_verification_required() or app.student_verified(p.id))
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
    if exists(select 1 from app.profiles where id = auth.uid() and role = 'student')
       and app.student_verification_required() and not app.student_verified(auth.uid()) then
      raise exception 'Aktivizo llogarinë me kodin personal nga sekretaria e shkollës.' using errcode = 'PT403'; end if;
    raise exception 'Llogaria nuk është gati: konfirmo emailin, zgjidh rolin ose jep faktorin e dytë.' using errcode = 'PT403';
  end if;
  if not (v_role = any(p_roles)) then raise exception 'Veprimi nuk lejohet për rolin tënd.' using errcode = 'PT403'; end if;
  return v_role;
end $$;

create or replace function app.gate_admin() returns void
language plpgsql stable security definer set search_path = app, auth, pg_temp as $$
begin
  perform app.gate(array['teacher']);
  if not app.is_school_admin(auth.uid()) then
    raise exception 'Ky veprim është vetëm për sekretarinë e shkollës.' using errcode = 'PT403'; end if;
end $$;

-- Me detyrimin ndezur, roli «nxënës» merret vetëm me kodin e aktivizimit.
create or replace function public.api_chooserole(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, auth, pg_temp as $$
declare v_role text := p_body->>'role'; n int;
begin
  if auth.uid() is null then raise exception 'Seanca ka mbaruar. Hyr përsëri.' using errcode = 'PT401'; end if;
  if v_role not in ('student','parent') then return jsonb_build_object('error','Zgjidh nxënës ose prind.'); end if;
  if v_role = 'student' and app.student_verification_required() then
    return jsonb_build_object('error','Nxënësit hyjnë me kodin personal të aktivizimit nga sekretaria.', 'needsActivation', true);
  end if;
  update app.profiles p set role = v_role from auth.users u
   where p.id = auth.uid() and u.id = p.id and u.email_confirmed_at is not null and p.role = 'unassigned';
  get diagnostics n = row_count;
  if n <> 1 then return jsonb_build_object('error','Roli është caktuar tashmë ose emaili nuk është konfirmuar. Roli nuk ndryshohet.'); end if;
  perform app.audit('role_chosen', v_role);
  return jsonb_build_object('ok', true, 'role', v_role);
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
    'mfaRequired', app.mfa_required(p.role),
    'mfaMethod', app.mfa_method(),
    'secondFactorOk', app.session_2fa_ok(),
    'aal', coalesce(auth.jwt()->>'aal','aal1'),
    'studentCodeRequired', app.student_verification_required(),
    'studentVerified', app.student_verified(p.id),
    'schoolAdmin', app.is_school_admin(p.id));
end $$;

-- Nxënësi: aktivizimi me kodin personal.
create or replace function public.api_studentactivate(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, auth, extensions, pg_temp as $$
declare v_role text; v_code text := app.student_code_norm(p_body->>'code'); r app.roster%rowtype; n int;
begin
  if auth.uid() is null then raise exception 'Seanca ka mbaruar. Hyr përsëri.' using errcode = 'PT401'; end if;
  select p.role into v_role from app.profiles p join auth.users u on u.id = p.id
   where p.id = auth.uid() and u.email_confirmed_at is not null;
  if v_role is null then return jsonb_build_object('error','Konfirmo fillimisht emailin.'); end if;
  if v_role not in ('unassigned','student') then return jsonb_build_object('error','Kodi i aktivizimit është vetëm për llogaritë e nxënësve.'); end if;
  if app.student_verified(auth.uid()) then return jsonb_build_object('ok', true, 'already', true); end if;
  if not app.hit('act:' || auth.uid(), 8, interval '15 minutes') then
    return jsonb_build_object('error','Shumë tentativa. Prit 15 minuta dhe provo përsëri.'); end if;
  if v_code !~ '^[A-Z0-9]{8}$' then return jsonb_build_object('error','Kodi ka 8 shkronja dhe shifra (p.sh. K7Q4-9MDR).'); end if;
  update app.roster set user_id = auth.uid(), status = 'active', activated_at = now(), code_hash = null, code_expires = null, updated_at = now()
   where code_hash = encode(digest(v_code, 'sha256'), 'hex') and code_expires > now() and status = 'pending' and user_id is null
   returning * into r;
  if r.id is null then
    perform app.audit('student_activate_failed', null);
    return jsonb_build_object('error','Kodi nuk është i saktë, është përdorur ose ka skaduar. Kërko një kod të ri te sekretaria.');
  end if;
  update app.profiles set role = 'student', display_name = left(r.first_name || ' ' || r.last_name, 40) where id = auth.uid();
  insert into app.class_members(class_id, user_id, approved)
  select c.id, auth.uid(), true from app.classes c where app.class_key(c.name) = app.class_key(r.class_name)
  on conflict (class_id, user_id) do update set approved = true;
  get diagnostics n = row_count;
  perform app.audit('student_activated', r.id::text);
  return jsonb_build_object('ok', true, 'name', r.first_name || ' ' || r.last_name, 'className', r.class_name, 'classesJoined', n);
end $$;

-- Sekretaria: regjistri.
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
    'unverifiedStudents', (select count(*) from app.profiles p where p.role = 'student' and not app.student_verified(p.id)));
end $$;

create or replace function public.api_adminrosterimport(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, auth, pg_temp as $$
declare x jsonb; i int := 0; v_amza text; v_first text; v_last text; v_class text; v_year int; v_new boolean;
        added int := 0; changed int := 0; errors jsonb := '[]'::jsonb;
begin
  perform app.gate_admin();
  if jsonb_typeof(p_body->'rows') <> 'array' then return jsonb_build_object('error','Mungojnë rreshtat.'); end if;
  if jsonb_array_length(p_body->'rows') > 3000 then return jsonb_build_object('error','Maksimumi 3000 rreshta në një ngarkim.'); end if;
  for x in select * from jsonb_array_elements(p_body->'rows') loop
    i := i + 1;
    v_amza := btrim(coalesce(x->>'amza','')); v_first := btrim(coalesce(x->>'firstName',''));
    v_last := btrim(coalesce(x->>'lastName','')); v_class := upper(btrim(coalesce(x->>'className','')));
    v_year := case when coalesce(x->>'birthYear','') ~ '^\d{4}$' then (x->>'birthYear')::int end;
    if length(v_amza) not between 1 and 20 or length(v_first) not between 1 and 40 or length(v_last) not between 1 and 40
       or length(v_class) not between 1 and 12 or (v_year is not null and v_year not between 1990 and 2030) then
      errors := errors || jsonb_build_object('row', i, 'amza', v_amza); continue;
    end if;
    insert into app.roster(amza, first_name, last_name, class_name, birth_year) values (v_amza, v_first, v_last, v_class, v_year)
    on conflict (amza) do update set first_name = excluded.first_name, last_name = excluded.last_name,
      class_name = excluded.class_name, birth_year = coalesce(excluded.birth_year, app.roster.birth_year), updated_at = now()
    returning (xmax = 0) into v_new;
    if v_new then added := added + 1; else changed := changed + 1; end if;
  end loop;
  perform app.audit('roster_import', null, jsonb_build_object('added', added, 'changed', changed, 'errors', jsonb_array_length(errors)));
  return jsonb_build_object('ok', true, 'added', added, 'changed', changed, 'errors', errors);
end $$;

-- Kodet tregohen vetëm një herë (për printim); serveri ruan vetëm hash-in.
create or replace function public.api_adminissuecodes(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, auth, extensions, pg_temp as $$
declare alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; r app.roster%rowtype; b bytea; c text;
        v_exp timestamptz := now() + make_interval(days => coalesce(app.setting('student_code_days'),'30')::int);
        out jsonb := '[]'::jsonb;
begin
  perform app.gate_admin();
  if jsonb_typeof(p_body->'ids') <> 'array' or jsonb_array_length(p_body->'ids') = 0 then return jsonb_build_object('error','Zgjidh nxënësit.'); end if;
  if jsonb_array_length(p_body->'ids') > 3000 then return jsonb_build_object('error','Shumë rreshta.'); end if;
  for r in select * from app.roster where id in (select (v)::uuid from jsonb_array_elements_text(p_body->'ids') v)
            and status = 'pending' and user_id is null
            order by app.class_key(class_name), last_name, first_name loop
    loop
      b := gen_random_bytes(8); c := '';
      for k in 0..7 loop c := c || substr(alphabet, (get_byte(b, k) & 31) + 1, 1); end loop;
      begin
        update app.roster set code_hash = encode(digest(c, 'sha256'), 'hex'), code_expires = v_exp, updated_at = now() where id = r.id;
        exit;
      exception when unique_violation then null; -- shumë e rrallë: provo një kod tjetër
      end;
    end loop;
    out := out || jsonb_build_object('id', r.id, 'amza', r.amza, 'name', r.first_name || ' ' || r.last_name,
      'className', r.class_name, 'code', substr(c,1,4) || '-' || substr(c,5,4));
  end loop;
  perform app.audit('roster_codes_issued', null, jsonb_build_object('count', jsonb_array_length(out)));
  return jsonb_build_object('ok', true, 'expires', v_exp, 'codes', out);
end $$;

create or replace function public.api_adminrosterupdate(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, auth, pg_temp as $$
declare v_id uuid; v_action text := p_body->>'action'; n int;
begin
  perform app.gate_admin();
  begin v_id := (p_body->>'id')::uuid; exception when others then return jsonb_build_object('error','Rresht i panjohur.'); end;
  case v_action
    when 'reset' then  -- shkëput llogarinë (p.sh. u lidh gabim); nxënësi kërkon kod të ri
      update app.roster set user_id = null, status = 'pending', activated_at = null, code_hash = null, code_expires = null, updated_at = now()
       where id = v_id and status <> 'left';
    when 'leave' then  -- largohet nga shkolla: llogaria bllokohet kur detyrimi është ndezur
      update app.roster set status = 'left', code_hash = null, code_expires = null, updated_at = now() where id = v_id;
    when 'return' then
      update app.roster set status = case when user_id is null then 'pending' else 'active' end, updated_at = now()
       where id = v_id and status = 'left';
    when 'revoke' then -- anulon kodin e printuar (p.sh. humbi letra)
      update app.roster set code_hash = null, code_expires = null, updated_at = now() where id = v_id and user_id is null;
    when 'delete' then
      delete from app.roster where id = v_id and user_id is null;
    else return jsonb_build_object('error','Veprim i panjohur.');
  end case;
  get diagnostics n = row_count;
  if n = 0 then return jsonb_build_object('error','Ky veprim nuk vlen për këtë rresht.'); end if;
  perform app.audit('roster_' || v_action, v_id::text);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.api_adminsetverification(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, auth, pg_temp as $$
declare v_on boolean := coalesce((p_body->>'on')::boolean, false);
begin
  perform app.gate_admin();
  if v_on and not exists(select 1 from app.roster) then
    return jsonb_build_object('error','Ngarko fillimisht regjistrin e nxënësve.'); end if;
  insert into app.settings(name, value) values ('require_student_verification', case when v_on then 'true' else 'false' end)
  on conflict (name) do update set value = excluded.value;
  perform app.audit('student_verification', case when v_on then 'on' else 'off' end);
  return jsonb_build_object('ok', true, 'required', v_on);
end $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'app' and p.proname in ('class_key','student_code_norm','student_verification_required','student_verified','is_school_admin','gate_admin')
  loop execute format('revoke all on function %s from public, anon, authenticated', f.sig); end loop;
end $$;
revoke all on function public.api_chooserole(jsonb) from public, anon;            grant execute on function public.api_chooserole(jsonb) to authenticated;
revoke all on function public.api_me(jsonb) from public, anon;                    grant execute on function public.api_me(jsonb) to authenticated;
revoke all on function public.api_studentactivate(jsonb) from public, anon;       grant execute on function public.api_studentactivate(jsonb) to authenticated;
revoke all on function public.api_adminroster(jsonb) from public, anon;           grant execute on function public.api_adminroster(jsonb) to authenticated;
revoke all on function public.api_adminrosterimport(jsonb) from public, anon;     grant execute on function public.api_adminrosterimport(jsonb) to authenticated;
revoke all on function public.api_adminissuecodes(jsonb) from public, anon;       grant execute on function public.api_adminissuecodes(jsonb) to authenticated;
revoke all on function public.api_adminrosterupdate(jsonb) from public, anon;     grant execute on function public.api_adminrosterupdate(jsonb) to authenticated;
revoke all on function public.api_adminsetverification(jsonb) from public, anon;  grant execute on function public.api_adminsetverification(jsonb) to authenticated;
