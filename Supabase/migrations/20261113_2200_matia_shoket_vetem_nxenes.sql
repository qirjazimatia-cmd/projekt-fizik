-- Don Bosko Connect · Shokët vetëm mes nxënësve të verifikuar (Matia, issue i sigurisë, vazhdim i #52 të Jurit).
-- Problemi: api_userSearch / api_friendRequest lejonin çdo rol. Një i rritur që regjistrohej si «prind» (ose si «nxënës»)
-- mund të gjente fëmijët me @username dhe t'u dërgonte ftesë. Kërkesat §8: të dhënat e nxënësve nuk shfaqen publikisht.
-- Rregulli i ri: shokë mund të jenë vetëm dy nxënës që janë anëtarë të MIRATUAR të të paktën një klase.
-- Miratimi në klasë e bën mësuesi, kështu që një llogari e rreme «nxënësi» nuk arrin dot te fëmijët.
-- Miqësitë ekzistuese nuk fshihen: ato që nuk e plotësojnë rregullin thjesht nuk shfaqen dhe nuk pranohen.

create or replace function app.friend_eligible(p_user uuid) returns boolean
language sql stable security definer set search_path = app, pg_temp as $$
  select exists(select 1 from app.profiles p where p.id = p_user and p.role = 'student' and p.username is not null)
     and exists(select 1 from app.class_members m where m.user_id = p_user and m.approved)
$$;
revoke all on function app.friend_eligible(uuid) from public, anon, authenticated;

create or replace function app.friend_block_reason() returns text
language sql stable security definer set search_path = app, pg_temp as $$
  select case
    when (select role from app.profiles where id = auth.uid()) is distinct from 'student'
      then 'Shokët janë vetëm për nxënësit.'
    when (select username from app.profiles where id = auth.uid()) is null
      then 'Krijo fillimisht username-in tënd te Cilësimet.'
    when not exists(select 1 from app.class_members where user_id = auth.uid() and approved)
      then 'Shokët hapen pasi mësuesi të pranon në një klasë.'
    else null end
$$;
revoke all on function app.friend_block_reason() from public, anon, authenticated;

create or replace function public.api_userSearch(p_body jsonb) returns jsonb
language plpgsql stable security definer set search_path = app, pg_temp as $$
declare v_query text := lower(trim(coalesce(p_body->>'query', '')));
begin
  perform app.gate(array['student','parent','teacher']);
  if app.friend_block_reason() is not null then return jsonb_build_object('users', '[]'::jsonb); end if;
  v_query := regexp_replace(v_query, '^@', '');
  if length(v_query) < 3 or v_query !~ '^[a-z0-9._]+$' then return jsonb_build_object('users', '[]'::jsonb); end if;
  return jsonb_build_object('users', coalesce((
    select jsonb_agg(app.public_user(p) || jsonb_build_object('relation', app.relation(p.id)) order by (p.username = v_query) desc, p.username)
    from (select * from app.profiles
          where username is not null and id <> auth.uid() and username like v_query || '%'
            and role = 'student' and app.friend_eligible(id)
          order by username limit 10) p), '[]'::jsonb));
end $$;

create or replace function public.api_friendRequest(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare
  v_other uuid;
  v_block text;
  v_username text := lower(regexp_replace(trim(coalesce(p_body->>'username', '')), '^@', ''));
begin
  perform app.gate(array['student','parent','teacher']);
  v_block := app.friend_block_reason();
  if v_block is not null then return jsonb_build_object('error', v_block); end if;
  select id into v_other from app.profiles where username = v_username;
  -- I njëjti mesazh kur përdoruesi nuk ekziston ose nuk lejohet: nuk zbulohet se kush është prind/mësues.
  if v_other is null or not app.friend_eligible(v_other) then
    return jsonb_build_object('error', 'Nuk u gjet asnjë nxënës me këtë username.');
  end if;
  if v_other = auth.uid() then return jsonb_build_object('error', 'Nuk mund t''i dërgosh ftesë vetes.'); end if;
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
declare v_other uuid := (select id from app.profiles where username = lower(trim(coalesce(p_body->>'username', '')))); v_block text;
begin
  perform app.gate(array['student','parent','teacher']);
  if v_other is null then return jsonb_build_object('error', 'Përdoruesi nuk u gjet.'); end if;
  if coalesce((p_body->>'accept')::boolean, false) then
    v_block := app.friend_block_reason();
    if v_block is not null then return jsonb_build_object('error', v_block); end if;
    if not app.friend_eligible(v_other) then return jsonb_build_object('error', 'Kjo ftesë nuk mund të pranohet.'); end if;
    update app.friendships set status = 'accepted' where requester = v_other and addressee = auth.uid() and status = 'pending';
  else
    -- Refuzimi lejohet gjithmonë, që çdokush të pastrojë ftesat e vjetra.
    delete from app.friendships where requester = v_other and addressee = auth.uid() and status = 'pending';
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.api_friendsList(p_body jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = app, pg_temp as $$
declare v_block text;
begin
  perform app.gate(array['student','parent','teacher']);
  v_block := app.friend_block_reason();
  if v_block is not null then
    return jsonb_build_object('friends', '[]'::jsonb, 'incoming', '[]'::jsonb, 'outgoing', '[]'::jsonb, 'blocked', v_block);
  end if;
  return jsonb_build_object(
    'friends', coalesce((select jsonb_agg(app.public_user(p) order by coalesce(p.display_name, p.username))
                         from app.friendships f join app.profiles p on p.id = case when f.requester = auth.uid() then f.addressee else f.requester end
                         where f.status = 'accepted' and auth.uid() in (f.requester, f.addressee) and app.friend_eligible(p.id)), '[]'::jsonb),
    'incoming', coalesce((select jsonb_agg(app.public_user(p) order by f.created_at desc)
                          from app.friendships f join app.profiles p on p.id = f.requester
                          where f.status = 'pending' and f.addressee = auth.uid() and app.friend_eligible(p.id)), '[]'::jsonb),
    'outgoing', coalesce((select jsonb_agg(app.public_user(p) order by f.created_at desc)
                          from app.friendships f join app.profiles p on p.id = f.addressee
                          where f.status = 'pending' and f.requester = auth.uid() and app.friend_eligible(p.id)), '[]'::jsonb));
end $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and (p.proname like 'api\_friend%' or p.proname = 'api_usersearch')
  loop execute format('revoke all on function %s from public, anon', f.sig); execute format('grant execute on function %s to authenticated', f.sig); end loop;
end $$;
