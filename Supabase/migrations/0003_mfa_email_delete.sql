-- ScienceQuest · Supabase · 0003 · 2FA i detyrueshëm, një email = një llogari, fshirja e klasave dhe e testeve
-- STATUSI: I PA-EKZEKUTUAR nga autori. Varet nga 0001 dhe 0002. Ekzekutoje te SQL Editor pasi të kenë kaluar 0001 dhe 0002.
-- Pa sekrete dhe pa kode në këtë skedar.

-- ============ A) 2FA (TOTP) ============
-- require_mfa: 'all' (parazgjedhja: nxënës, prindër dhe mësues), 'teacher' (vetëm mësuesit) ose 'none'.
-- Ndryshohet nga administratori:  select app.admin_set_setting('require_mfa','teacher');
insert into app.settings values ('require_mfa','all') on conflict do nothing;

create function app.mfa_required(p_role text) returns boolean language sql stable security definer set search_path = app, pg_temp as $$
  select (case coalesce(app.setting('require_mfa'),'all')
            when 'all' then true
            when 'teacher' then p_role = 'teacher'
            else false end)
      or (p_role = 'teacher' and coalesce(app.setting('require_teacher_mfa'),'false') = 'true')
$$;

-- Serveri vendos rregullin (jo aplikacioni): pa sesion aal2, asnjë veprim api_* nuk lejohet kur 2FA është i detyrueshëm
-- ose kur përdoruesi ka tashmë një faktor të verifikuar. Aktivizimi i faktorit bëhet përmes GoTrue me sesion aal1.
create or replace function app.mfa_ok(p_role text) returns boolean language sql stable security definer set search_path = app, auth, pg_temp as $$
  select coalesce(auth.jwt()->>'aal','aal1') = 'aal2'
      or (not exists(select 1 from auth.mfa_factors where user_id = auth.uid() and status = 'verified')
          and not app.mfa_required(p_role))
$$;

-- api_me funksionon edhe me aal1 (që aplikacioni të dijë çfarë të kërkojë), por tani raporton edhe mfaRequired.
create or replace function public.api_me(p_body jsonb default '{}') returns jsonb language plpgsql stable security definer set search_path = app, auth, pg_temp as $$
declare p app.profiles%rowtype; u auth.users%rowtype;
begin
  if auth.uid() is null then raise exception 'Seanca ka mbaruar. Hyr përsëri.' using errcode = 'PT401'; end if;
  select * into p from app.profiles where id = auth.uid();
  select * into u from auth.users where id = auth.uid();
  if p.id is null or u.email_confirmed_at is null then raise exception 'Emaili nuk është konfirmuar.' using errcode = 'PT403'; end if;
  return jsonb_build_object('id', p.id, 'email', p.email, 'role', p.role, 'teacherStatus', p.teacher_status,
    'mfaEnrolled', exists(select 1 from auth.mfa_factors where user_id = auth.uid() and status = 'verified'),
    'mfaRequired', app.mfa_required(p.role),
    'aal', coalesce(auth.jwt()->>'aal','aal1'));
end $$;

-- Humbi telefonin/aplikacionin e autentikimit: administratori heq faktorin dhe mbyll seancat.
-- Në hyrjen e radhës përdoruesi konfiguron një faktor të ri.  select app.admin_reset_mfa('email@shembull.al');
create function app.admin_reset_mfa(p_email text) returns text language plpgsql security definer set search_path = app, auth, pg_temp as $$
declare v_id uuid; n int;
begin
  select id into v_id from app.profiles where email = lower(trim(p_email));
  if v_id is null then return 'Nuk u gjet llogari me këtë email.'; end if;
  delete from auth.mfa_factors where user_id = v_id;
  get diagnostics n = row_count;
  delete from auth.sessions where user_id = v_id;
  insert into app.audit_log(action, target) values ('admin_reset_mfa', lower(trim(p_email)));
  return n || ' faktorë u hoqën dhe seancat u mbyllën. Përdoruesi konfiguron 2FA të ri në hyrjen tjetër.';
end $$;
revoke all on function app.mfa_required(text), app.admin_reset_mfa(text) from public, anon, authenticated;

-- ============ B) Një email = një llogari ============
-- GoTrue e ndalon tashmë të njëjtin email të saktë. Këtu mbyllim edhe variantet: shkronjat e mëdha, +etiketa dhe pikat e Gmail.
-- Shembull: Ana.K+1@gmail.com dhe anak@gmail.com janë i njëjti çelës.
create function app.email_key(p_email text) returns text language sql immutable as $$
  select case
    when split_part(lower(trim(p_email)),'@',2) in ('gmail.com','googlemail.com')
      then replace(split_part(split_part(lower(trim(p_email)),'@',1),'+',1),'.','') || '@gmail.com'
    else split_part(split_part(lower(trim(p_email)),'@',1),'+',1) || '@' || split_part(lower(trim(p_email)),'@',2)
  end
$$;
alter table app.profiles add column if not exists email_key text;
update app.profiles set email_key = app.email_key(email) where email_key is null;
do $$ begin
  if exists(select 1 from app.profiles group by email_key having count(*) > 1) then
    raise exception 'Ka llogari të dyfishuara (e njëjta adresë me pika ose +etiketë). Fshiji te Authentication → Users dhe ekzekuto përsëri këtë skedar.';
  end if;
end $$;
alter table app.profiles alter column email_key set not null;
create unique index if not exists profiles_email_key_uq on app.profiles(email_key);

create or replace function app.handle_new_user() returns trigger language plpgsql security definer set search_path = app, pg_temp as $$
begin insert into app.profiles(id, email, email_key) values (new.id, lower(new.email), app.email_key(new.email)); return new; end $$;

-- Nëse emaili ndryshohet te Auth, profili e ndjek; kur adresa përplaset me një llogari tjetër, ndryshimi dështon.
create function app.handle_email_change() returns trigger language plpgsql security definer set search_path = app, pg_temp as $$
begin
  update app.profiles set email = lower(new.email), email_key = app.email_key(new.email) where id = new.id;
  return new;
end $$;
create trigger on_auth_user_email_changed after update of email on auth.users
  for each row when (old.email is distinct from new.email) execute function app.handle_email_change();

-- ============ C) Fshirja e klasave dhe e testeve (vetëm pronari) ============
-- Fshirja e klasës heq në kaskadë anëtarësimet, testet, përpjekjet, notat dhe eventet e saj. Klienti dërgon confirm=true pas dialogut.
create function public.api_classDelete(p_body jsonb) returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare v_class uuid := (p_body->>'classID')::uuid; v_name text;
begin
  perform app.gate(array['teacher']);
  select name into v_name from app.classes where id = v_class and owner_id = auth.uid();
  if v_name is null then raise exception 'Klasa nuk është e jotja.' using errcode = 'PT403'; end if;
  if coalesce((p_body->>'confirm')::boolean, false) is not true then return jsonb_build_object('error','Konfirmo fshirjen e klasës.'); end if;
  delete from app.classes where id = v_class and owner_id = auth.uid();
  perform app.audit('class_deleted', v_class::text, jsonb_build_object('name', v_name));
  return jsonb_build_object('ok', true);
end $$;

-- Cikli i testit: draft → publikuar → mbyllur → fshirë. Testi i publikuar nuk fshihet pa u mbyllur.
-- Eventet e lidhura nuk fshihen (exam_id bëhet bosh).
create function public.api_examDelete(p_body jsonb) returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare v_exam uuid := (p_body->>'examID')::uuid; v_status text; v_title text;
begin
  perform app.gate(array['teacher']);
  select status, title into v_status, v_title from app.exams where id = v_exam and owner_id = auth.uid();
  if v_status is null then raise exception 'Testi nuk është i yti.' using errcode = 'PT403'; end if;
  if v_status = 'published' then return jsonb_build_object('error','Mbylle testin para se ta fshish.'); end if;
  if coalesce((p_body->>'confirm')::boolean, false) is not true then return jsonb_build_object('error','Konfirmo fshirjen e testit.'); end if;
  delete from app.exams where id = v_exam and owner_id = auth.uid();
  perform app.audit('exam_deleted', v_exam::text, jsonb_build_object('title', v_title, 'status', v_status));
  return jsonb_build_object('ok', true);
end $$;

-- Të njëjtat grant-e si te 0001: vetëm përdoruesit e kyçur mund t'i thërrasin api_*.
do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname like 'api\_%'
  loop execute format('revoke all on function %s from public, anon', f.sig); execute format('grant execute on function %s to authenticated', f.sig); end loop;
end $$;
