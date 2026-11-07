-- ScienceQuest · Supabase · 0004 · faktori i dytë me kod emaili (i detyruar nga serveri)
-- STATUSI: I PA-EKZEKUTUAR nga autori. Varet nga 0001–0003 dhe nga Edge Function `send-login-code` (shih SUPABASE-SETUP.md §8).
-- Si punon: pas fjalëkalimit, Edge Function dërgon një kod 6-shifror te emaili i llogarisë. Kodi ruhet vetëm si hash dhe lidhet me ID-në e seancës (claim session_id).
-- Pa u verifikuar kodi për atë seancë, asnjë funksion api_* i punës nuk lejohet (app.mfa_ok). Nuk ka sekrete në këtë skedar.

-- Metoda: 'email' (parazgjedhja) ose 'totp' (aplikacion autentikimi si më parë).  select app.admin_set_setting('mfa_method','totp');
insert into app.settings values ('mfa_method','email') on conflict do nothing;
create function app.mfa_method() returns text language sql stable security definer set search_path = app, pg_temp as
$$ select coalesce(app.setting('mfa_method'),'email') $$;

create table app.login_codes (
  user_id uuid primary key references auth.users(id) on delete cascade,
  session_id uuid not null,
  code_hash text not null,
  expires_at timestamptz not null,
  failures int not null default 0,
  created_at timestamptz not null default now()
);
create table app.session_2fa (
  session_id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  verified_at timestamptz not null default now()
);
alter table app.login_codes enable row level security;
alter table app.session_2fa enable row level security;

-- Seanca ka kaluar faktorin e dytë: ose TOTP (aal2), ose kodi i emailit i verifikuar për këtë seancë.
create function app.session_2fa_ok() returns boolean language sql stable security definer set search_path = app, auth, pg_temp as $$
  select coalesce(auth.jwt()->>'aal','aal1') = 'aal2'
      or exists(select 1 from app.session_2fa s where s.user_id = auth.uid() and s.session_id = nullif(auth.jwt()->>'session_id','')::uuid)
$$;

-- Nëse përdoruesi ka TOTP të verifikuar, mbetet aal2 i detyrueshëm. Përndryshe, kur 2FA kërkohet:
-- në mënyrën 'email' mjafton kodi i emailit për seancën; në 'totp' duhet aal2.
create or replace function app.mfa_ok(p_role text) returns boolean language sql stable security definer set search_path = app, auth, pg_temp as $$
  select coalesce(auth.jwt()->>'aal','aal1') = 'aal2'
      or (not exists(select 1 from auth.mfa_factors where user_id = auth.uid() and status = 'verified')
          and (not app.mfa_required(p_role)
               or (app.mfa_method() = 'email' and app.session_2fa_ok())))
$$;

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
    'mfaMethod', app.mfa_method(),
    'secondFactorOk', app.session_2fa_ok(),
    'aal', coalesce(auth.jwt()->>'aal','aal1'));
end $$;

-- Thirret VETËM nga Edge Function (me çelësin e shërbimit, i cili nuk është në aplikacion). Kthen {code} ose {error}.
-- Kufijt: 1 kod në 30 sekonda, 10 kode në orë për përdorues; kodi vlen 10 minuta; një kod aktiv për përdorues.
create function public.internal_issue_login_code(p_user uuid, p_session uuid) returns jsonb language plpgsql security definer set search_path = app, extensions, pg_temp as $$
declare v_code text; v_last timestamptz;
begin
  select created_at into v_last from app.login_codes where user_id = p_user;
  if v_last is not null and v_last > now() - interval '30 seconds' then
    return jsonb_build_object('error','Për siguri prit rreth 30 sekonda para se të kërkosh një kod tjetër.'); end if;
  if not app.hit('lc:issue:' || p_user, 10, interval '1 hour') then
    return jsonb_build_object('error','U kërkuan shumë kode. Provo përsëri pas një ore.'); end if;
  v_code := lpad(((('x' || encode(gen_random_bytes(4),'hex'))::bit(32)::bigint) % 1000000)::text, 6, '0');
  insert into app.login_codes(user_id, session_id, code_hash, expires_at, failures)
  values (p_user, p_session, encode(digest(p_user::text || ':' || p_session::text || ':' || v_code, 'sha256'), 'hex'), now() + interval '10 minutes', 0)
  on conflict (user_id) do update set session_id = excluded.session_id, code_hash = excluded.code_hash,
        expires_at = excluded.expires_at, failures = 0, created_at = now();
  delete from app.session_2fa where verified_at < now() - interval '60 days';
  insert into app.audit_log(actor, action) values (p_user, 'login_code_issued');
  return jsonb_build_object('code', v_code);
end $$;
revoke all on function public.internal_issue_login_code(uuid, uuid) from public, anon, authenticated;
grant execute on function public.internal_issue_login_code(uuid, uuid) to service_role;

-- 5 gabime për kod; pastaj kodi fshihet dhe duhet kërkuar një i ri (që sistemi i kërkesave kufizon). Gabimet kthehen si {error}, jo exception, që numëruesi të ruhet.
create function public.api_loginCodeVerify(p_body jsonb) returns jsonb language plpgsql security definer set search_path = app, auth, extensions, pg_temp as $$
declare r app.login_codes%rowtype; v_code text := trim(coalesce(p_body->>'code',''));
        v_sess uuid := nullif(auth.jwt()->>'session_id','')::uuid;
        v_bad constant text := 'Kodi nuk është i saktë ose ka skaduar. Kërko një kod të ri.';
begin
  if auth.uid() is null or v_sess is null then raise exception 'Seanca ka mbaruar. Hyr përsëri.' using errcode = 'PT401'; end if;
  if not exists(select 1 from auth.users where id = auth.uid() and email_confirmed_at is not null) then
    raise exception 'Emaili nuk është konfirmuar.' using errcode = 'PT403'; end if;
  select * into r from app.login_codes where user_id = auth.uid() for update;
  if not found or r.expires_at < now() or r.session_id <> v_sess then return jsonb_build_object('error', v_bad); end if;
  if r.failures >= 5 then delete from app.login_codes where user_id = auth.uid(); return jsonb_build_object('error', v_bad); end if;
  if encode(digest(auth.uid()::text || ':' || v_sess::text || ':' || v_code, 'sha256'), 'hex') <> r.code_hash then
    update app.login_codes set failures = failures + 1 where user_id = auth.uid();
    perform app.audit('login_code_failed');
    return jsonb_build_object('error', v_bad);
  end if;
  delete from app.login_codes where user_id = auth.uid();
  insert into app.session_2fa(session_id, user_id) values (v_sess, auth.uid())
    on conflict (session_id) do update set verified_at = now();
  perform app.audit('login_code_ok');
  return jsonb_build_object('ok', true);
end $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname like 'api\_%'
  loop execute format('revoke all on function %s from public, anon', f.sig); execute format('grant execute on function %s to authenticated', f.sig); end loop;
end $$;
