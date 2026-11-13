-- Don Bosko Connect · Bosko AI: pëlqimi i qartë dhe kufijtë e përdorimit (Matia, #62).
-- Apple App Review 5.1.2(i): para se të dhënat e përdoruesit të dërgohen te një AI i palës së tretë duhet njoftim i qartë dhe leje
-- e shprehur, që mund të tërhiqet. Leja ruhet këtu (jo vetëm në pajisje) dhe Edge Function `bosko-ai` e kontrollon për çdo pyetje,
-- kështu që as një klient i modifikuar nuk dërgon dot asgjë pa leje.
-- Kufijtë ditorë mbrojnë kuotën falas të shkollës: një llogari nuk e harxhon dot për të gjithë.

alter table app.profiles
  add column if not exists ai_consent_at timestamptz,
  add column if not exists ai_consent_version smallint;

-- Versioni i tekstit të njoftimit. Kur ndryshon (p.sh. ofrues i ri), rritet dhe pëlqimi kërkohet përsëri.
insert into app.settings(name, value) values ('ai_consent_version', '1'), ('ai_daily_limit', '60'), ('ai_daily_limit_teacher', '150'), ('ai_school_daily_limit', '3000')
on conflict (name) do nothing;

create or replace function app.ai_setting(p_name text, p_default int) returns int
language sql stable security definer set search_path = app, pg_temp as $$
  select coalesce((select nullif(value, '')::int from app.settings where name = p_name), p_default)
$$;
revoke all on function app.ai_setting(text, int) from public, anon, authenticated;

create or replace function app.ai_used_today(p_key text) returns int
language sql stable security definer set search_path = app, pg_temp as $$
  select coalesce((select n from app.throttle where key = p_key and started > now() - interval '1 day'), 0)
$$;
revoke all on function app.ai_used_today(text) from public, anon, authenticated;

-- Gjendja: a ka dhënë leje dhe sa pyetje i kanë mbetur sot.
create or replace function public.api_aiStatus(p_body jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = app, pg_temp as $$
declare v_role text; p app.profiles; v_limit int;
begin
  v_role := app.gate(array['student','parent','teacher']);
  select * into p from app.profiles where id = auth.uid();
  v_limit := case when v_role = 'teacher' then app.ai_setting('ai_daily_limit_teacher', 150) else app.ai_setting('ai_daily_limit', 60) end;
  return jsonb_build_object(
    'consent', p.ai_consent_at is not null and coalesce(p.ai_consent_version, 0) >= app.ai_setting('ai_consent_version', 1),
    'version', app.ai_setting('ai_consent_version', 1),
    'limit', v_limit,
    'remaining', greatest(v_limit - app.ai_used_today('ai:' || auth.uid()), 0));
end $$;

-- Jep ose tërheq lejen.
create or replace function public.api_aiConsent(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare v_accept boolean := coalesce((p_body->>'accept')::boolean, false);
begin
  perform app.gate(array['student','parent','teacher']);
  update app.profiles set
    ai_consent_at = case when v_accept then now() else null end,
    ai_consent_version = case when v_accept then app.ai_setting('ai_consent_version', 1)::smallint else null end
  where id = auth.uid();
  perform app.audit(case when v_accept then 'ai_consent_given' else 'ai_consent_revoked' end, auth.uid()::text, '{}');
  return jsonb_build_object('ok', true, 'consent', v_accept);
end $$;

-- Thirret nga Edge Function `bosko-ai` me token-in e vetë përdoruesit, para çdo pyetjeje.
-- Kontrollon lejen dhe numëron pyetjen (kufiri i llogarisë + kufiri i shkollës). Kthen `code` që app-i ta kuptojë.
create or replace function public.api_aiAllow(p_body jsonb default '{}') returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare v_role text; p app.profiles; v_limit int;
begin
  v_role := app.gate(array['student','parent','teacher']);
  select * into p from app.profiles where id = auth.uid();
  if p.ai_consent_at is null or coalesce(p.ai_consent_version, 0) < app.ai_setting('ai_consent_version', 1) then
    return jsonb_build_object('allowed', false, 'code', 'consent', 'message', 'Për Bosko AI me internet duhet leja jote. Hape te Bosko → Më shumë → Privatësia.');
  end if;
  v_limit := case when v_role = 'teacher' then app.ai_setting('ai_daily_limit_teacher', 150) else app.ai_setting('ai_daily_limit', 60) end;
  if app.ai_used_today('ai:' || auth.uid()) >= v_limit then
    return jsonb_build_object('allowed', false, 'code', 'limit', 'message', 'Ke përdorur ' || v_limit || ' pyetjet e sotme me internet. Nesër vazhdojmë! Deri atëherë, Bosko të përgjigjet nga mësimet e aplikacionit.');
  end if;
  if app.ai_used_today('ai:shkolla') >= app.ai_setting('ai_school_daily_limit', 3000) then
    return jsonb_build_object('allowed', false, 'code', 'school', 'message', 'Shkolla ka arritur kufirin e sotëm të pyetjeve me internet. Provo nesër.');
  end if;
  perform app.hit('ai:' || auth.uid(), 1000000, interval '1 day');
  perform app.hit('ai:shkolla', 1000000, interval '1 day');
  return jsonb_build_object('allowed', true, 'remaining', greatest(v_limit - app.ai_used_today('ai:' || auth.uid()), 0));
end $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname in ('api_aistatus', 'api_aiconsent', 'api_aiallow')
  loop execute format('revoke all on function %s from public, anon', f.sig); execute format('grant execute on function %s to authenticated', f.sig); end loop;
end $$;
