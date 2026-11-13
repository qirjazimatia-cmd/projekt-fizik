-- Don Bosko Connect · Bisedat: grupi i klasës, prind↔mësues, shok↔shok (Matia, #80).
-- Rregullat (vendimet e 13 nëntorit):
--  • Grupi i klasës: shkruajnë mësuesi (pronari i klasës) dhe nxënësit e pranuar; prindërit e lidhur vetëm lexojnë.
--    Mësuesi mund ta bëjë grupin «vetëm njoftime» (teacher_only).
--  • Mësues↔nxënës privat: NUK ka (vetëm grupi i klasës).
--  • Prind↔mësues («family»): privat, vetëm kur fëmija i prindit është nxënës i pranuar në një klasë të atij mësuesi.
--  • Shok↔shok («friend»): vetëm mes shokëve të pranuar që plotësojnë app.friend_eligible (#60); vetëm tekst.
--  • Filtër: fjalë të papërshtatshme (lista te app.settings 'chat_blocked_words', e ndryshueshme pa kod);
--    për nxënësit edhe pa numra telefoni, emaile apo lidhje, që askush të mos i nxjerrë jashtë app-it.
--  • Blloko (në çdo bisedë) dhe Raporto (ruhet te app.message_reports për shqyrtim; kush shqyrton vendoset para publikimit).
-- Skema `app` mbetet e mbyllur: çdo veprim kalon nga public.api_chat*.

create table if not exists app.conversations (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('class', 'friend', 'family')),
  class_id uuid references app.classes(id) on delete cascade,
  a uuid references app.profiles(id) on delete cascade,
  b uuid references app.profiles(id) on delete cascade,
  teacher_only boolean not null default false,
  created_at timestamptz not null default now(),
  last_at timestamptz not null default now(),
  check ((kind = 'class' and class_id is not null and a is null and b is null)
      or (kind <> 'class' and class_id is null and a is not null and b is not null and a < b))
);
create unique index if not exists conversations_class_key on app.conversations(class_id) where kind = 'class';
create unique index if not exists conversations_pair_key on app.conversations(kind, a, b) where kind <> 'class';
create index if not exists conversations_a_idx on app.conversations(a);
create index if not exists conversations_b_idx on app.conversations(b);

create table if not exists app.messages (
  id bigint generated always as identity primary key,
  conversation_id uuid not null references app.conversations(id) on delete cascade,
  sender_id uuid not null references app.profiles(id) on delete cascade,
  body text not null check (length(body) between 1 and 2000),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists messages_conversation_idx on app.messages(conversation_id, id desc);

create table if not exists app.chat_reads (
  conversation_id uuid not null references app.conversations(id) on delete cascade,
  user_id uuid not null references app.profiles(id) on delete cascade,
  last_read bigint not null default 0,
  primary key (conversation_id, user_id)
);

create table if not exists app.chat_blocks (
  blocker uuid not null references app.profiles(id) on delete cascade,
  blocked uuid not null references app.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked),
  check (blocker <> blocked)
);

create table if not exists app.message_reports (
  id uuid primary key default gen_random_uuid(),
  message_id bigint not null references app.messages(id) on delete cascade,
  reporter_id uuid not null references app.profiles(id) on delete cascade,
  reason text not null check (reason in ('bullying', 'inappropriate', 'spam', 'other')),
  created_at timestamptz not null default now(),
  status text not null default 'new' check (status in ('new', 'reviewed')),
  unique (message_id, reporter_id)
);

alter table app.conversations enable row level security;
alter table app.messages enable row level security;
alter table app.chat_reads enable row level security;
alter table app.chat_blocks enable row level security;
alter table app.message_reports enable row level security;

insert into app.settings(name, value) values ('chat_blocked_words',
  'fuck,fucking,shit,bitch,bastard,dick,pussy,slut,whore,cunt,faggot,nigger,pidh,pidhi,pidhin,kar,kari,karin,qir,qiri,qifsha,qifsh,qij,qiu,kurv,kurve,kurvë,kurva,kurvat,lavire,lavir,byth,bythë,bytha,bythen,mut,muti,pederast,peder')
on conflict (name) do nothing;

-- Emri që u shfaqet të tjerëve (pa email të plotë).
create or replace function app.chat_name(p_user uuid) returns text
language sql stable security definer set search_path = app, pg_temp as $$
  select coalesce(nullif(p.display_name, ''), p.username, split_part(p.email, '@', 1)) from app.profiles p where p.id = p_user
$$;

create or replace function app.chat_blocked_between(x uuid, y uuid) returns boolean
language sql stable security definer set search_path = app, pg_temp as $$
  select exists(select 1 from app.chat_blocks where (blocker = x and blocked = y) or (blocker = y and blocked = x))
$$;

-- Prindi dhe mësuesi janë të lidhur kur një fëmijë i prindit është nxënës i pranuar në një klasë të mësuesit.
create or replace function app.chat_family_linked(p_parent uuid, p_teacher uuid) returns boolean
language sql stable security definer set search_path = app, pg_temp as $$
  select exists(select 1 from app.parent_links pl
                  join app.class_members m on m.user_id = pl.child_id and m.approved
                  join app.classes c on c.id = m.class_id
                 where pl.parent_id = p_parent and c.owner_id = p_teacher)
$$;

create or replace function app.chat_other(c app.conversations) returns uuid
language sql stable set search_path = app, pg_temp as $$
  select case when c.a = auth.uid() then c.b else c.a end
$$;

create or replace function app.chat_can_read(c app.conversations) returns boolean
language sql stable security definer set search_path = app, pg_temp as $$
  select case when c.kind = 'class' then app.can_see_class(c.class_id) else auth.uid() in (c.a, c.b) end
$$;

-- Null = mund të shkruajë; përndryshe arsyeja (shfaqet në app në vend të kutisë së shkrimit).
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
  -- family
  if not (app.chat_family_linked(c.a, c.b) or app.chat_family_linked(c.b, c.a)) then
    return 'Kjo bisedë nuk është më aktive (fëmija nuk është më në klasën e këtij mësuesi).';
  end if;
  return null;
end $$;

-- Null = teksti lejohet; përndryshe mesazhi për përdoruesin.
create or replace function app.chat_filter(p_body text, p_student boolean) returns text
language plpgsql stable security definer set search_path = app, pg_temp as $$
declare v_words text; v_pattern text;
begin
  select value into v_words from app.settings where name = 'chat_blocked_words';
  if coalesce(v_words, '') <> '' then
    select string_agg(regexp_replace(trim(w), '([.^$*+?()\[\]{}|\\])', '\\\1', 'g'), '|') into v_pattern
      from unnest(string_to_array(v_words, ',')) w where trim(w) <> '';
    if v_pattern is not null and p_body ~* ('\m(' || v_pattern || ')\M') then
      return 'Mesazhi ka fjalë të papërshtatshme. Shkruaje ndryshe.';
    end if;
  end if;
  if p_student then
    if p_body ~* '(https?://|www\.|[a-z0-9-]+\.(com|al|net|org|io|me|gg|ly|app|link)\M)' then
      return 'Për sigurinë tënde, lidhjet nuk lejohen në biseda.';
    end if;
    if p_body ~* '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}' then
      return 'Për sigurinë tënde, emailet nuk lejohen në biseda.';
    end if;
    if regexp_replace(p_body, '[\s().-]', '', 'g') ~ '\+?\d{8,}' then
      return 'Për sigurinë tënde, numrat e telefonit nuk lejohen në biseda.';
    end if;
  end if;
  return null;
end $$;

do $$ declare f text; begin
  foreach f in array array['app.chat_name(uuid)', 'app.chat_blocked_between(uuid, uuid)', 'app.chat_family_linked(uuid, uuid)',
                           'app.chat_other(app.conversations)', 'app.chat_can_read(app.conversations)',
                           'app.chat_write_block(app.conversations)', 'app.chat_filter(text, boolean)']
  loop execute format('revoke all on function %s from public, anon, authenticated', f); end loop;
end $$;

-- Përmbledhja e një bisede për listën.
create or replace function app.chat_summary(c app.conversations) returns jsonb
language sql stable security definer set search_path = app, pg_temp as $$
  select jsonb_build_object(
    'id', c.id, 'kind', c.kind, 'classID', c.class_id, 'teacherOnly', c.teacher_only,
    'title', case when c.kind = 'class' then (select name from app.classes where id = c.class_id) else app.chat_name(app.chat_other(c)) end,
    'subtitle', case c.kind when 'class' then 'Grupi i klasës' when 'friend' then 'Shok' else
                  case when app."current_role"() = 'teacher' then 'Prind' else 'Mësues' end end,
    'otherID', case when c.kind = 'class' then null else app.chat_other(c) end,
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
revoke all on function app.chat_summary(app.conversations) from public, anon, authenticated;

create or replace function public.api_chatList(p_body jsonb default '{}') returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
begin
  perform app.gate(array['student','parent','teacher']);
  -- Grupet e klasave krijohen herën e parë që dikush i sheh.
  insert into app.conversations(kind, class_id)
    select 'class', c.id from app.classes c where app.can_see_class(c.id)
  on conflict do nothing;
  return jsonb_build_object('chats', coalesce((
    select jsonb_agg(app.chat_summary(c) order by c.last_at desc)
      from app.conversations c
     where (c.kind = 'class' and app.can_see_class(c.class_id)) or (c.kind <> 'class' and auth.uid() in (c.a, c.b))), '[]'::jsonb));
end $$;

-- Me kë mund të hapë një bisedë private: prindi → mësuesit e klasave të fëmijëve; mësuesi → prindërit e nxënësve të tij;
-- nxënësi → shokët e tij të pranuar.
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
    return jsonb_build_object('contacts', coalesce((select jsonb_agg(x order by x->>'name') from (
      select distinct jsonb_build_object('userID', pl.parent_id, 'name', app.chat_name(pl.parent_id), 'kind', 'family',
                                         'detail', 'Prind · ' || app.chat_name(pl.child_id) || ' · ' || c.name) x
        from app.classes c join app.class_members m on m.class_id = c.id and m.approved
        join app.parent_links pl on pl.child_id = m.user_id where c.owner_id = auth.uid()) s), '[]'::jsonb));
  end if;
  return jsonb_build_object('contacts', coalesce((select jsonb_agg(jsonb_build_object('userID', p.id, 'name', app.chat_name(p.id), 'kind', 'friend',
                                                                                       'detail', '@' || p.username) order by app.chat_name(p.id))
    from app.friendships f join app.profiles p on p.id = case when f.requester = auth.uid() then f.addressee else f.requester end
   where f.status = 'accepted' and auth.uid() in (f.requester, f.addressee) and app.friend_eligible(p.id) and app.friend_eligible(auth.uid())), '[]'::jsonb));
end $$;

-- Hap (ose krijon) një bisedë: {classID} për grupin, ose {userID} për bisedë private (shok ose prind↔mësues).
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
  else return jsonb_build_object('error', 'Nuk mund të hapësh bisedë private me këtë person.'); end if;
  insert into app.conversations(kind, a, b) values (v_kind, least(auth.uid(), v_other), greatest(auth.uid(), v_other)) on conflict do nothing;
  select * into c from app.conversations where kind = v_kind and a = least(auth.uid(), v_other) and b = greatest(auth.uid(), v_other);
  if v_kind = 'friend' and app.chat_write_block(c) is not null and not exists(select 1 from app.messages where conversation_id = c.id) then
    delete from app.conversations where id = c.id;
    return jsonb_build_object('error', 'Mund t''i shkruash vetëm shokëve të tu të pranuar.');
  end if;
  return jsonb_build_object('id', c.id);
end $$;

-- Mesazhet (60 të fundit, ose para `before`), dhe shënon bisedën si të lexuar.
create or replace function public.api_chatMessages(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare c app.conversations; v_before bigint := nullif(p_body->>'before', '')::bigint; v_max bigint; v_msgs jsonb;
begin
  perform app.gate(array['student','parent','teacher']);
  select * into c from app.conversations where id = (p_body->>'id')::uuid;
  if c.id is null or not app.chat_can_read(c) then raise exception 'Nuk je pjesë e kësaj bisede.' using errcode = 'PT403'; end if;
  select coalesce(jsonb_agg(x order by (x->>'id')::bigint), '[]'::jsonb) into v_msgs from (
    select jsonb_build_object('id', m.id, 'body', case when m.deleted_at is null then m.body else '' end, 'deleted', m.deleted_at is not null,
                              'at', app.epoch(m.created_at), 'mine', m.sender_id = auth.uid(), 'senderID', m.sender_id,
                              'sender', app.chat_name(m.sender_id), 'emoji', coalesce(p.avatar_emoji, '🦊'), 'color', p.avatar_color,
                              'teacher', p.role = 'teacher') x
      from app.messages m join app.profiles p on p.id = m.sender_id
     where m.conversation_id = c.id and (v_before is null or m.id < v_before)
       and not exists(select 1 from app.chat_blocks k where k.blocker = auth.uid() and k.blocked = m.sender_id)
     order by m.id desc limit 60) s;
  select max(id) into v_max from app.messages where conversation_id = c.id;
  if v_max is not null then
    insert into app.chat_reads(conversation_id, user_id, last_read) values (c.id, auth.uid(), v_max)
    on conflict (conversation_id, user_id) do update set last_read = greatest(app.chat_reads.last_read, excluded.last_read);
  end if;
  return jsonb_build_object('messages', v_msgs, 'summary', app.chat_summary(c), 'reason', app.chat_write_block(c),
                            'isOwner', c.kind = 'class' and app.owns_class(c.class_id));
end $$;

create or replace function public.api_chatSend(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare v_role text; c app.conversations; v_body text := trim(coalesce(p_body->>'body', '')); v_block text; v_id bigint;
begin
  v_role := app.gate(array['student','parent','teacher']);
  select * into c from app.conversations where id = (p_body->>'id')::uuid;
  if c.id is null then return jsonb_build_object('error', 'Biseda nuk u gjet.'); end if;
  v_block := app.chat_write_block(c);
  if v_block is not null then return jsonb_build_object('error', v_block); end if;
  if v_body = '' then return jsonb_build_object('error', 'Shkruaj një mesazh.'); end if;
  if length(v_body) > 2000 then return jsonb_build_object('error', 'Mesazhi është shumë i gjatë (deri 2000 shkronja).'); end if;
  v_block := app.chat_filter(v_body, v_role = 'student');
  if v_block is not null then return jsonb_build_object('error', v_block); end if;
  if not app.hit('chat:min:' || auth.uid(), 20, interval '1 minute') then return jsonb_build_object('error', 'Po shkruan shumë shpejt. Prit pak.'); end if;
  if not app.hit('chat:day:' || auth.uid(), 600, interval '1 day') then return jsonb_build_object('error', 'Ke arritur kufirin e mesazheve për sot.'); end if;
  insert into app.messages(conversation_id, sender_id, body) values (c.id, auth.uid(), v_body) returning id into v_id;
  update app.conversations set last_at = now() where id = c.id;
  insert into app.chat_reads(conversation_id, user_id, last_read) values (c.id, auth.uid(), v_id)
  on conflict (conversation_id, user_id) do update set last_read = greatest(app.chat_reads.last_read, excluded.last_read);
  return jsonb_build_object('ok', true, 'messageID', v_id);
end $$;

-- Fshin mesazhin tënd, ose (mësuesi) një mesazh në grupin e klasës së tij. Teksti ruhet për raportet, por nuk shfaqet.
create or replace function public.api_chatDelete(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare m app.messages; c app.conversations;
begin
  perform app.gate(array['student','parent','teacher']);
  select * into m from app.messages where id = (p_body->>'messageID')::bigint;
  select * into c from app.conversations where id = m.conversation_id;
  if m.id is null or not (m.sender_id = auth.uid() or (c.kind = 'class' and app.owns_class(c.class_id))) then
    raise exception 'Nuk mund ta fshish këtë mesazh.' using errcode = 'PT403';
  end if;
  update app.messages set deleted_at = coalesce(deleted_at, now()) where id = m.id;
  if m.sender_id <> auth.uid() then perform app.audit('chat_message_removed', m.id::text, jsonb_build_object('conversation', c.id)); end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.api_chatReport(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare m app.messages; c app.conversations; v_reason text := coalesce(p_body->>'reason', 'other');
begin
  perform app.gate(array['student','parent','teacher']);
  select * into m from app.messages where id = (p_body->>'messageID')::bigint;
  select * into c from app.conversations where id = m.conversation_id;
  if m.id is null or not app.chat_can_read(c) then raise exception 'Mesazhi nuk u gjet.' using errcode = 'PT403'; end if;
  if m.sender_id = auth.uid() then return jsonb_build_object('error', 'Nuk mund të raportosh mesazhin tënd.'); end if;
  if v_reason not in ('bullying', 'inappropriate', 'spam', 'other') then v_reason := 'other'; end if;
  if not app.hit('chatreport:' || auth.uid(), 30, interval '1 day') then return jsonb_build_object('error', 'Ke dërguar shumë raporte sot.'); end if;
  insert into app.message_reports(message_id, reporter_id, reason) values (m.id, auth.uid(), v_reason) on conflict do nothing;
  perform app.audit('chat_report', m.id::text, jsonb_build_object('reason', v_reason, 'conversation', c.id));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.api_chatBlock(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare v_user uuid := nullif(p_body->>'userID', '')::uuid; v_block boolean := coalesce((p_body->>'block')::boolean, true);
begin
  perform app.gate(array['student','parent','teacher']);
  if v_user is null or v_user = auth.uid() or not exists(select 1 from app.profiles where id = v_user) then
    return jsonb_build_object('error', 'Përdoruesi nuk u gjet.');
  end if;
  if v_block then
    insert into app.chat_blocks(blocker, blocked) values (auth.uid(), v_user) on conflict do nothing;
    perform app.audit('chat_block', v_user::text, '{}');
  else
    delete from app.chat_blocks where blocker = auth.uid() and blocked = v_user;
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.api_chatSettings(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare c app.conversations;
begin
  perform app.gate(array['teacher']);
  select * into c from app.conversations where id = (p_body->>'id')::uuid;
  if c.id is null or c.kind <> 'class' or not app.owns_class(c.class_id) then raise exception 'Vetëm mësuesi i klasës e ndryshon grupin.' using errcode = 'PT403'; end if;
  update app.conversations set teacher_only = coalesce((p_body->>'teacherOnly')::boolean, teacher_only) where id = c.id;
  return jsonb_build_object('ok', true);
end $$;

-- Numri i mesazheve të palexuara (për pikën te skeda).
create or replace function public.api_chatUnread(p_body jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = app, pg_temp as $$
begin
  perform app.gate(array['student','parent','teacher']);
  return jsonb_build_object('unread', coalesce((
    select sum((app.chat_summary(c)->>'unread')::int) from app.conversations c
     where (c.kind = 'class' and app.can_see_class(c.class_id)) or (c.kind <> 'class' and auth.uid() in (c.a, c.b))), 0));
end $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname like 'api\_chat%'
  loop execute format('revoke all on function %s from public, anon', f.sig); execute format('grant execute on function %s to authenticated', f.sig); end loop;
end $$;
