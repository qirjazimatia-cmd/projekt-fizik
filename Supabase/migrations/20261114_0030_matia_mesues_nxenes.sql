-- Don Bosko Connect · Bisedat mësues↔nxënës («tutor»), për pyetjet e nxënësve (Matia, #82).
-- Masë sigurie: biseda private mes një të rrituri dhe një të mituri është e dukshme për prindin e lidhur (lexon, nuk shkruan).
-- Lejohet vetëm kur nxënësi është i pranuar në një klasë të atij mësuesi. Filtri, Raporto dhe Blloko vlejnë si te bisedat e tjera.

alter table app.conversations drop constraint if exists conversations_kind_check;
alter table app.conversations add constraint conversations_kind_check check (kind in ('class', 'friend', 'family', 'tutor'));

create or replace function app.chat_tutor_linked(p_teacher uuid, p_student uuid) returns boolean
language sql stable security definer set search_path = app, pg_temp as $$
  select exists(select 1 from app.class_members m join app.classes c on c.id = m.class_id
                 where m.user_id = p_student and m.approved and c.owner_id = p_teacher)
$$;

-- Prindi i një pjesëmarrësi (nxënësit) në bisedën mësues↔nxënës.
create or replace function app.chat_parent_of(c app.conversations) returns boolean
language sql stable security definer set search_path = app, pg_temp as $$
  select c.kind = 'tutor' and exists(select 1 from app.parent_links pl where pl.parent_id = auth.uid() and pl.child_id in (c.a, c.b))
$$;

create or replace function app.chat_can_read(c app.conversations) returns boolean
language sql stable security definer set search_path = app, pg_temp as $$
  select case when c.kind = 'class' then app.can_see_class(c.class_id)
              else auth.uid() in (c.a, c.b) or app.chat_parent_of(c) end
$$;

create or replace function app.chat_write_block(c app.conversations) returns text
language plpgsql stable security definer set search_path = app, pg_temp as $$
declare v_role text := app."current_role"(); v_other uuid;
begin
  if not app.chat_can_read(c) then return 'Nuk je pjesë e kësaj bisede.'; end if;
  if c.kind = 'class' then
    if app.owns_class(c.class_id) then return null; end if;
    if v_role = 'parent' then return 'Prindërit e lexojnë grupin e klasës. Për mësuesin, hap një bisedë private.'; end if;
    if c.teacher_only then return 'Në këtë grup shkruan vetëm mësuesi.'; end if;
    if v_role = 'student' and app.in_class(c.class_id) then return null; end if;
    return 'Nuk mund të shkruash në këtë grup.';
  end if;
  if auth.uid() not in (c.a, c.b) then return 'Si prind e lexon këtë bisedë, por nuk shkruan në të.'; end if;
  v_other := app.chat_other(c);
  if app.chat_blocked_between(auth.uid(), v_other) then return 'Kjo bisedë është e bllokuar.'; end if;
  if c.kind = 'friend' then
    if not (app.friend_eligible(auth.uid()) and app.friend_eligible(v_other)
            and exists(select 1 from app.friendships f where f.status = 'accepted'
                        and ((f.requester = c.a and f.addressee = c.b) or (f.requester = c.b and f.addressee = c.a)))) then
      return 'Mund t''i shkruash vetëm shokëve të tu të pranuar.';
    end if;
    return null;
  end if;
  if c.kind = 'tutor' then
    if not (app.chat_tutor_linked(c.a, c.b) or app.chat_tutor_linked(c.b, c.a)) then
      return 'Kjo bisedë nuk është më aktive (nxënësi nuk është më në klasën e këtij mësuesi).';
    end if;
    return null;
  end if;
  if not (app.chat_family_linked(c.a, c.b) or app.chat_family_linked(c.b, c.a)) then
    return 'Kjo bisedë nuk është më aktive (fëmija nuk është më në klasën e këtij mësuesi).';
  end if;
  return null;
end $$;

create or replace function app.chat_summary(c app.conversations) returns jsonb
language sql stable security definer set search_path = app, pg_temp as $$
  select jsonb_build_object(
    'id', c.id, 'kind', c.kind, 'classID', c.class_id, 'teacherOnly', c.teacher_only,
    'title', case when c.kind = 'class' then (select name from app.classes where id = c.class_id)
                  when auth.uid() not in (c.a, c.b) then app.chat_name(c.a) || ' · ' || app.chat_name(c.b)
                  else app.chat_name(app.chat_other(c)) end,
    'subtitle', case c.kind when 'class' then 'Grupi i klasës' when 'friend' then 'Shok'
                  when 'tutor' then case when auth.uid() not in (c.a, c.b) then 'Mësuesi dhe fëmija yt'
                                         when app."current_role"() = 'teacher' then 'Nxënës' else 'Mësues' end
                  else case when app."current_role"() = 'teacher' then 'Prind' else 'Mësues' end end,
    'otherID', case when c.kind = 'class' or auth.uid() not in (c.a, c.b) then null else app.chat_other(c) end,
    'canWrite', app.chat_write_block(c) is null,
    'last', (select jsonb_build_object('body', case when m.deleted_at is null then left(m.body, 120) else 'Mesazhi u fshi' end,
                                       'at', app.epoch(m.created_at), 'mine', m.sender_id = auth.uid())
               from app.messages m where m.conversation_id = c.id
                and not exists(select 1 from app.chat_blocks k where k.blocker = auth.uid() and k.blocked = m.sender_id)
              order by m.id desc limit 1),
    'unread', (select count(*) from app.messages m where m.conversation_id = c.id and m.sender_id <> auth.uid() and m.deleted_at is null
                 and m.id > coalesce((select last_read from app.chat_reads r where r.conversation_id = c.id and r.user_id = auth.uid()), 0)
                 and not exists(select 1 from app.chat_blocks k where k.blocker = auth.uid() and k.blocked = m.sender_id)))
$$;

-- Bisedat që sheh përdoruesi (përdoret nga lista dhe nga numri i të palexuarave).
create or replace function app.chat_visible(c app.conversations) returns boolean
language sql stable security definer set search_path = app, pg_temp as $$
  select (c.kind = 'class' and app.can_see_class(c.class_id)) or (c.kind <> 'class' and (auth.uid() in (c.a, c.b) or app.chat_parent_of(c)))
$$;

do $$ declare f text; begin
  foreach f in array array['app.chat_tutor_linked(uuid, uuid)', 'app.chat_parent_of(app.conversations)', 'app.chat_can_read(app.conversations)',
                           'app.chat_write_block(app.conversations)', 'app.chat_summary(app.conversations)', 'app.chat_visible(app.conversations)']
  loop execute format('revoke all on function %s from public, anon, authenticated', f); end loop;
end $$;

create or replace function public.api_chatList(p_body jsonb default '{}') returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
begin
  perform app.gate(array['student','parent','teacher']);
  insert into app.conversations(kind, class_id)
    select 'class', c.id from app.classes c where app.can_see_class(c.id)
  on conflict do nothing;
  return jsonb_build_object('chats', coalesce((
    select jsonb_agg(app.chat_summary(c) order by c.last_at desc) from app.conversations c where app.chat_visible(c)), '[]'::jsonb));
end $$;

create or replace function public.api_chatUnread(p_body jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = app, pg_temp as $$
begin
  perform app.gate(array['student','parent','teacher']);
  return jsonb_build_object('unread', coalesce((
    select sum((app.chat_summary(c)->>'unread')::int) from app.conversations c where app.chat_visible(c)), 0));
end $$;

-- Kontaktet: nxënësi → shokët + mësuesit e klasave të tij; mësuesi → prindërit + nxënësit e klasave të tij; prindi → mësuesit.
create or replace function public.api_chatContacts(p_body jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = app, pg_temp as $$
declare v_role text;
begin
  v_role := app.gate(array['student','parent','teacher']);
  if v_role = 'parent' then
    return jsonb_build_object('contacts', coalesce((select jsonb_agg(x order by x->>'name') from (
      select distinct jsonb_build_object('userID', c.owner_id, 'name', app.chat_name(c.owner_id), 'kind', 'family',
                                         'detail', 'Mësues · ' || c.name || ' · ' || app.chat_name(pl.child_id)) x
        from app.parent_links pl join app.class_members m on m.user_id = pl.child_id and m.approved
        join app.classes c on c.id = m.class_id where pl.parent_id = auth.uid()) s), '[]'::jsonb));
  elsif v_role = 'teacher' then
    return jsonb_build_object('contacts', coalesce((select jsonb_agg(x order by x->>'kind', x->>'name') from (
      select distinct jsonb_build_object('userID', pl.parent_id, 'name', app.chat_name(pl.parent_id), 'kind', 'family',
                                         'detail', 'Prind · ' || app.chat_name(pl.child_id) || ' · ' || c.name) x
        from app.classes c join app.class_members m on m.class_id = c.id and m.approved
        join app.parent_links pl on pl.child_id = m.user_id where c.owner_id = auth.uid()
      union
      select distinct jsonb_build_object('userID', m.user_id, 'name', app.chat_name(m.user_id), 'kind', 'tutor',
                                         'detail', 'Nxënës · ' || c.name) x
        from app.classes c join app.class_members m on m.class_id = c.id and m.approved where c.owner_id = auth.uid()) s), '[]'::jsonb));
  end if;
  return jsonb_build_object('contacts', coalesce((select jsonb_agg(x order by x->>'kind' desc, x->>'name') from (
    select jsonb_build_object('userID', p.id, 'name', app.chat_name(p.id), 'kind', 'friend', 'detail', '@' || p.username) x
      from app.friendships f join app.profiles p on p.id = case when f.requester = auth.uid() then f.addressee else f.requester end
     where f.status = 'accepted' and auth.uid() in (f.requester, f.addressee) and app.friend_eligible(p.id) and app.friend_eligible(auth.uid())
    union
    select distinct jsonb_build_object('userID', c.owner_id, 'name', app.chat_name(c.owner_id), 'kind', 'tutor', 'detail', 'Mësues · ' || c.name) x
      from app.class_members m join app.classes c on c.id = m.class_id where m.user_id = auth.uid() and m.approved) s), '[]'::jsonb));
end $$;

create or replace function public.api_chatOpen(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare v_role text; v_class uuid := nullif(p_body->>'classID', '')::uuid; v_other uuid := nullif(p_body->>'userID', '')::uuid;
        v_other_role text; v_kind text; v_id uuid; c app.conversations;
begin
  v_role := app.gate(array['student','parent','teacher']);
  if v_class is not null then
    if not app.can_see_class(v_class) then raise exception 'Nuk je pjesë e kësaj klase.' using errcode = 'PT403'; end if;
    insert into app.conversations(kind, class_id) values ('class', v_class) on conflict do nothing;
    select id into v_id from app.conversations where kind = 'class' and class_id = v_class;
    return jsonb_build_object('id', v_id);
  end if;
  if v_other is null or v_other = auth.uid() then return jsonb_build_object('error', 'Zgjidh me kë do të flasësh.'); end if;
  select role into v_other_role from app.profiles where id = v_other;
  if v_role = 'student' and v_other_role = 'student' then v_kind := 'friend';
  elsif (v_role = 'parent' and v_other_role = 'teacher' and app.chat_family_linked(auth.uid(), v_other))
     or (v_role = 'teacher' and v_other_role = 'parent' and app.chat_family_linked(v_other, auth.uid())) then v_kind := 'family';
  elsif (v_role = 'student' and v_other_role = 'teacher' and app.chat_tutor_linked(v_other, auth.uid()))
     or (v_role = 'teacher' and v_other_role = 'student' and app.chat_tutor_linked(auth.uid(), v_other)) then v_kind := 'tutor';
  else return jsonb_build_object('error', 'Nuk mund të hapësh bisedë private me këtë person.'); end if;
  insert into app.conversations(kind, a, b) values (v_kind, least(auth.uid(), v_other), greatest(auth.uid(), v_other)) on conflict do nothing;
  select * into c from app.conversations where kind = v_kind and a = least(auth.uid(), v_other) and b = greatest(auth.uid(), v_other);
  if v_kind = 'friend' and app.chat_write_block(c) is not null and not exists(select 1 from app.messages where conversation_id = c.id) then
    delete from app.conversations where id = c.id;
    return jsonb_build_object('error', 'Mund t''i shkruash vetëm shokëve të tu të pranuar.');
  end if;
  return jsonb_build_object('id', c.id);
end $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname like 'api\_chat%'
  loop execute format('revoke all on function %s from public, anon', f.sig); execute format('grant execute on function %s to authenticated', f.sig); end loop;
end $$;
