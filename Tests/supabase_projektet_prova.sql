-- Prova e serverit për projektet (#6). Ekzekutohet PAS migrimit 20261108_1215_juri_projektet.sql,
-- në të njëjtën kërkesë, që gjithçka të anulohet: skripti mbaron GJITHMONË me `raise exception`.
-- Mesazhi i gabimit përmban rezultatin: "PROVA_PROJEKTET OK n/n" ose listën e dështimeve.
-- Përdoruesit e provës krijohen dhe fshihen bashkë me transaksionin; asgjë nuk mbetet në bazë.

create function pg_temp.as_user(p uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated', 'aal', 'aal2')::text, true);
end $$;
create function pg_temp.call(p_fn text, p_body jsonb) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  execute format('select public.%I($1)', p_fn) into r using p_body;
  return r;
exception when others then
  return jsonb_build_object('raised', sqlerrm, 'state', sqlstate);
end $$;
-- Ngarkim në Storage si rol `authenticated`, që të kalojë nga rregullat RLS të storage.objects.
create function pg_temp.put(p_user uuid, p_name text) returns text language plpgsql as $$
begin
  perform pg_temp.as_user(p_user);
  execute 'set local role authenticated';
  insert into storage.objects(bucket_id, name, owner, metadata) values ('projects', p_name, p_user, '{"size": 1200, "mimetype": "application/pdf"}');
  execute 'reset role';
  return 'ok';
exception when others then
  execute 'reset role';
  return 'refuzuar: ' || sqlerrm;
end $$;

do $$
declare
  t uuid := gen_random_uuid(); s1 uuid := gen_random_uuid(); s2 uuid := gen_random_uuid(); s3 uuid := gen_random_uuid();
  s4 uuid := gen_random_uuid(); par uuid := gen_random_uuid();
  c uuid; proj_i uuid; proj_g uuid; team_i uuid; team_g uuid; v1 uuid; r jsonb; x text; ok int := 0; total int := 0; fails text := '';
begin
  insert into auth.users(id, email, email_confirmed_at, aud, role) values
    (t,  'prova.mesues@juri.test',  now(), 'authenticated', 'authenticated'),
    (s1, 'prova.s1@juri.test',      now(), 'authenticated', 'authenticated'),
    (s2, 'prova.s2@juri.test',      now(), 'authenticated', 'authenticated'),
    (s3, 'prova.s3@juri.test',      now(), 'authenticated', 'authenticated'),
    (s4, 'prova.s4@juri.test',      now(), 'authenticated', 'authenticated'),
    (par,'prova.prind@juri.test',   now(), 'authenticated', 'authenticated');
  update app.profiles set role = 'teacher', teacher_status = 'active' where id = t;
  update app.profiles set role = 'student' where id in (s1, s2, s3, s4);
  update app.profiles set role = 'parent' where id = par;
  insert into app.classes(owner_id, name, level, join_code) values (t, 'Prova XI', 4, 'PROVAJURI1') returning id into c;
  insert into app.class_members(class_id, user_id, approved) values (c, s1, true), (c, s2, true), (c, s3, true);
  insert into app.parent_links(parent_id, child_id) values (par, s1);

  -- 1) Mësuesi krijon projektet; nxënësi nuk mund të krijojë.
  perform pg_temp.as_user(t);
  r := pg_temp.call('api_projectcreate', jsonb_build_object('classID', c, 'title', 'Ura me shkopinj', 'kind', 'individual'));
  proj_i := (r->>'code')::uuid;
  r := pg_temp.call('api_projectcreate', jsonb_build_object('classID', c, 'title', 'Energjia në shkollë', 'kind', 'group', 'description', 'Mat konsumin', 'due', extract(epoch from now() + interval '7 days')));
  proj_g := (r->>'code')::uuid;
  total := total + 1; if proj_i is not null and proj_g is not null then ok := ok + 1; else fails := fails || ' [1 krijimi ' || r::text || ']'; end if;
  perform pg_temp.as_user(s1);
  r := pg_temp.call('api_projectcreate', jsonb_build_object('classID', c, 'title', 'x', 'kind', 'individual'));
  total := total + 1; if r->>'state' = 'PT403' then ok := ok + 1; else fails := fails || ' [2 nxënësi krijoi projekt]'; end if;

  -- 2) Projekt individual: nisja është idempotente; projekti në grup nuk niset vetë.
  r := pg_temp.call('api_projectstart', jsonb_build_object('projectID', proj_i)); team_i := (r->>'code')::uuid;
  r := pg_temp.call('api_projectstart', jsonb_build_object('projectID', proj_i));
  total := total + 1; if team_i is not null and (r->>'code')::uuid = team_i then ok := ok + 1; else fails := fails || ' [3 nisja individuale]'; end if;
  r := pg_temp.call('api_projectstart', jsonb_build_object('projectID', proj_g));
  total := total + 1; if r ? 'error' then ok := ok + 1; else fails := fails || ' [4 nisi vetë projekt në grup]'; end if;
  perform pg_temp.as_user(s4);
  r := pg_temp.call('api_projectstart', jsonb_build_object('projectID', proj_i));
  total := total + 1; if r->>'state' = 'PT403' then ok := ok + 1; else fails := fails || ' [5 jashtë klasës nisi projekt]'; end if;

  -- 3) Grupet dhe anëtarët.
  perform pg_temp.as_user(t);
  r := pg_temp.call('api_projectteamcreate', jsonb_build_object('projectID', proj_g, 'name', 'Grupi A')); team_g := (r->>'code')::uuid;
  r := pg_temp.call('api_projectmember', jsonb_build_object('teamID', team_g, 'student', s1));
  r := pg_temp.call('api_projectmember', jsonb_build_object('teamID', team_g, 'student', s2));
  total := total + 1; if (select count(*) from app.project_members where team_id = team_g) = 2 then ok := ok + 1; else fails := fails || ' [6 anëtarët]'; end if;
  r := pg_temp.call('api_projectmember', jsonb_build_object('teamID', team_g, 'student', s1));
  total := total + 1; if r ? 'error' then ok := ok + 1; else fails := fails || ' [7 i njëjti nxënës dy herë]'; end if;
  r := pg_temp.call('api_projectmember', jsonb_build_object('teamID', team_g, 'student', s4));
  total := total + 1; if r ? 'error' then ok := ok + 1; else fails := fails || ' [8 u shtua nxënës jashtë klasës]'; end if;
  r := pg_temp.call('api_projectteamcreate', jsonb_build_object('projectID', proj_i, 'name', 'X'));
  total := total + 1; if r ? 'error' then ok := ok + 1; else fails := fails || ' [9 grup te projekt individual]'; end if;

  -- 4) Rolet dhe kontributet: vetëm anëtarët e grupit.
  perform pg_temp.as_user(s2);
  r := pg_temp.call('api_projectrole', jsonb_build_object('teamID', team_g, 'student', s1, 'role', 'Koordinator'));
  total := total + 1; if (select role from app.project_members where team_id = team_g and student_id = s1) = 'Koordinator' then ok := ok + 1; else fails := fails || ' [10 roli ' || r::text || ']'; end if;
  r := pg_temp.call('api_projectcontribute', jsonb_build_object('teamID', team_g, 'note', 'Mata konsumin e dritave në klasë.'));
  total := total + 1; if r ? 'ok' then ok := ok + 1; else fails := fails || ' [11 kontributi ' || r::text || ']'; end if;
  perform pg_temp.as_user(s3);
  r := pg_temp.call('api_projectrole', jsonb_build_object('teamID', team_g, 'student', s1, 'role', 'Asgjë'));
  x := pg_temp.call('api_projectcontribute', jsonb_build_object('teamID', team_g, 'note', 'futje'))->>'state';
  total := total + 1; if r->>'state' = 'PT403' and x = 'PT403' then ok := ok + 1; else fails := fails || ' [12 jashtë grupit ndryshoi]'; end if;

  -- 5) Versionet: një draft i vetëm për grup.
  perform pg_temp.as_user(s1);
  v1 := (pg_temp.call('api_projectversionnew', jsonb_build_object('teamID', team_g))->>'code')::uuid;
  perform pg_temp.as_user(s2);
  r := pg_temp.call('api_projectversionnew', jsonb_build_object('teamID', team_g));
  total := total + 1; if v1 is not null and (r->>'code')::uuid = v1 then ok := ok + 1; else fails := fails || ' [13 dy drafte]'; end if;
  r := pg_temp.call('api_projectversionsubmit', jsonb_build_object('versionID', v1));
  total := total + 1; if r ? 'error' then ok := ok + 1; else fails := fails || ' [14 u dorëzua version bosh]'; end if;

  -- 6) Storage: anëtari ngarkon te drafti; jo-anëtari dhe rruga e gabuar refuzohen.
  x := pg_temp.put(s2, team_g || '/' || v1 || '/abcd1234-raporti.pdf');
  total := total + 1; if x = 'ok' then ok := ok + 1; else fails := fails || ' [15 anëtari nuk ngarkoi: ' || x || ']'; end if;
  x := pg_temp.put(s3, team_g || '/' || v1 || '/abcd1234-hyrje.pdf');
  total := total + 1; if x like 'refuzuar%' then ok := ok + 1; else fails := fails || ' [16 jo-anëtari ngarkoi]'; end if;
  x := pg_temp.put(s1, team_i || '/' || v1 || '/abcd1234-gabim.pdf');
  total := total + 1; if x like 'refuzuar%' then ok := ok + 1; else fails := fails || ' [17 versioni i grupit tjetër]'; end if;

  -- 7) Prindi para dorëzimit/vlerësimit: sheh vetëm fëmijën e vet, pa draft dhe pa skedarë.
  perform pg_temp.as_user(par);
  r := pg_temp.call('api_projects', '{}');
  x := jsonb_path_query_first(r, '$.projects[*] ? (@.title == "Energjia në shkollë").teams[0]')::text;
  total := total + 1;
  if x like '%prova.s1@%' and x not like '%prova.s2@%' and x not like '%Mata konsumin%' and x like '%"versions": []%' then ok := ok + 1; else fails := fails || ' [18 prindi pa privatësi: ' || coalesce(x,'null') || ']'; end if;
  total := total + 1; if not public.sq_can_project_read(team_g || '/' || v1 || '/abcd1234-raporti.pdf') then ok := ok + 1; else fails := fails || ' [19 prindi lexoi para vlerësimit]'; end if;

  -- 8) Dorëzimi kyç versionin.
  perform pg_temp.as_user(s1);
  r := pg_temp.call('api_projectversionsubmit', jsonb_build_object('versionID', v1, 'note', 'Versioni i parë'));
  total := total + 1; if r ? 'ok' then ok := ok + 1; else fails := fails || ' [20 dorëzimi ' || r::text || ']'; end if;
  r := pg_temp.call('api_projectversionsubmit', jsonb_build_object('versionID', v1, 'note', 'përsëri'));
  total := total + 1; if r ? 'error' then ok := ok + 1; else fails := fails || ' [21 dorëzim i dyfishtë]'; end if;
  x := pg_temp.put(s2, team_g || '/' || v1 || '/abcd1234-vone.pdf');
  total := total + 1; if x like 'refuzuar%' then ok := ok + 1; else fails := fails || ' [22 ngarkim pas dorëzimit]'; end if;
  r := pg_temp.call('api_projectversionnew', jsonb_build_object('teamID', team_g));
  total := total + 1; if (select number from app.project_versions where id = (r->>'code')::uuid) = 2 then ok := ok + 1; else fails := fails || ' [23 versioni 2]'; end if;

  -- 9) Vlerësimi i mësuesit; pas tij prindi sheh komentin dhe skedarin.
  perform pg_temp.as_user(s1);
  r := pg_temp.call('api_projectfeedback', jsonb_build_object('versionID', v1, 'feedback', 'x'));
  total := total + 1; if r->>'state' = 'PT403' then ok := ok + 1; else fails := fails || ' [24 nxënësi vlerësoi]'; end if;
  perform pg_temp.as_user(t);
  r := pg_temp.call('api_projectfeedback', jsonb_build_object('versionID', v1, 'feedback', 'Matje të mira. Shto grafikun.'));
  perform pg_temp.as_user(par);
  r := pg_temp.call('api_projects', '{}');
  x := jsonb_path_query_first(r, '$.projects[*] ? (@.title == "Energjia në shkollë").teams[0].versions')::text;
  total := total + 1;
  if x like '%Shto grafikun%' and x like '%raporti.pdf%' and x not like '%"number": 2%' and public.sq_can_project_read(team_g || '/' || v1 || '/abcd1234-raporti.pdf') then ok := ok + 1;
  else fails := fails || ' [25 prindi pas vlerësimit: ' || coalesce(x,'null') || ']'; end if;

  -- 10) Nxënës tjetër i klasës sheh projektin, por jo punën e grupit; jashtë klasës nuk sheh asgjë.
  perform pg_temp.as_user(s3);
  r := pg_temp.call('api_projects', '{}');
  total := total + 1;
  if jsonb_array_length(r->'projects') = 2 and r::text not like '%Mata konsumin%' and r::text not like '%raporti.pdf%' then ok := ok + 1; else fails := fails || ' [26 s3 sheh: ' || r::text || ']'; end if;
  total := total + 1; if not public.sq_can_project_read(team_g || '/' || v1 || '/abcd1234-raporti.pdf') then ok := ok + 1; else fails := fails || ' [27 s3 lexoi skedarin]'; end if;
  perform pg_temp.as_user(s4);
  r := pg_temp.call('api_projects', '{}');
  total := total + 1; if jsonb_array_length(r->'projects') = 0 then ok := ok + 1; else fails := fails || ' [28 jashtë klasës sheh projekte]'; end if;

  -- 11) Mësuesi: sheh gjithçka; fshirja refuzohet kur ka skedarë; mbyllja ndal punën.
  perform pg_temp.as_user(t);
  r := pg_temp.call('api_projects', '{}');
  x := jsonb_path_query_first(r, '$.projects[*] ? (@.title == "Energjia në shkollë")')::text;
  total := total + 1; if x like '%Mata konsumin%' and x like '%prova.s3@%' and x like '%"late": false%' then ok := ok + 1; else fails := fails || ' [29 pamja e mësuesit]'; end if;
  r := pg_temp.call('api_projectdelete', jsonb_build_object('projectID', proj_g, 'confirm', true));
  total := total + 1; if r ? 'error' and exists(select 1 from app.projects where id = proj_g) then ok := ok + 1; else fails := fails || ' [30 u fshi projekt me skedarë]'; end if;
  r := pg_temp.call('api_projectstatus', jsonb_build_object('projectID', proj_g, 'close', true));
  perform pg_temp.as_user(s1);
  r := pg_temp.call('api_projectcontribute', jsonb_build_object('teamID', team_g, 'note', 'pas mbylljes'));
  total := total + 1; if r ? 'error' then ok := ok + 1; else fails := fails || ' [31 kontribut pas mbylljes]'; end if;
  perform pg_temp.as_user(t);
  r := pg_temp.call('api_projectdelete', jsonb_build_object('projectID', proj_i, 'confirm', true));
  total := total + 1; if r ? 'ok' and not exists(select 1 from app.projects where id = proj_i) then ok := ok + 1; else fails := fails || ' [32 fshirja pa skedarë ' || r::text || ']'; end if;

  -- 12) Pa seancë: asgjë.
  perform set_config('request.jwt.claims', '', true);
  r := pg_temp.call('api_projects', '{}');
  total := total + 1; if r->>'state' = 'PT401' then ok := ok + 1; else fails := fails || ' [33 pa seancë]'; end if;

  if fails = '' then raise exception 'PROVA_PROJEKTET OK %/% (anulohet)', ok, total;
  else raise exception 'PROVA_PROJEKTET DËSHTOI %/%:%', ok, total, fails; end if;
end $$;
