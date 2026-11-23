-- Shokët dhe moderimi (#69, Apple 1.2 / Google Play UGC).
--  · Filtri i emrave: username dhe emri i shfaqur nuk lejojnë fjalët e listës `chat_blocked_words`.
--  · Blloko përdorues (me username): fshin shoqërinë/ftesat, e fsheh nga kërkimi dhe ndalon ftesat e reja në të dy drejtimet.
--  · Raporto përdorues (app.user_reports).
--  · Moderatori = sekretaria: radha e raportimeve (mesazhe, përdorues, Bosko AI) me «Mbyll» dhe «Fshi mesazhin».

create table if not exists app.user_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references app.profiles(id) on delete cascade,
  reported_id uuid not null references app.profiles(id) on delete cascade,
  reason text not null default 'other' check (reason in ('bullying', 'inappropriate', 'impersonation', 'spam', 'other')),
  note text check (note is null or length(note) <= 300),
  status text not null default 'open' check (status in ('open', 'closed')),
  created_at timestamptz not null default now(),
  unique (reporter_id, reported_id)
);
alter table app.user_reports enable row level security;
create index if not exists user_reports_reported_idx on app.user_reports(reported_id);

-- Fjalët e ndaluara në emra: kontrollohet edhe username-i duke i kthyer . _ dhe shifrat në hapësira.
create or replace function app.name_bad(p text) returns boolean
language plpgsql stable security definer set search_path = app, pg_temp as $$
declare v_words text; v_pattern text; v_text text := lower(coalesce(p, ''));
begin
  select value into v_words from app.settings where name = 'chat_blocked_words';
  if coalesce(v_words, '') = '' then return false; end if;
  select string_agg(regexp_replace(trim(w), '([.^$*+?()\[\]{}|\\])', '\\\1', 'g'), '|') into v_pattern
    from unnest(string_to_array(v_words, ',')) w where trim(w) <> '';
  if v_pattern is null then return false; end if;
  v_text := regexp_replace(v_text, '[._0-9]+', ' ', 'g');
  return v_text ~* ('\m(' || v_pattern || ')\M');
end $$;

create or replace function app.blocked_either(p_a uuid, p_b uuid) returns boolean
language sql stable security definer set search_path = app, pg_temp as $$
  select exists(select 1 from app.chat_blocks where (blocker = p_a and blocked = p_b) or (blocker = p_b and blocked = p_a))
$$;

create or replace function public.api_profileupdate(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare
  v_username text := lower(trim(p_body->>'username'));
  v_display text := trim(p_body->>'displayName');
  v_emoji text := p_body->>'avatarEmoji';
  v_color int := (p_body->>'avatarColor')::int;
begin
  perform app.gate(array['student','parent','teacher']);
  if p_body ? 'username' then
    if v_username !~ '^[a-z0-9._]{3,20}$' then
      return jsonb_build_object('error', 'Username duhet të ketë 3–20 shkronja të vogla, numra, pikë ose _ (pa hapësira).');
    end if;
    if app.name_bad(v_username) then return jsonb_build_object('error', 'Ky username ka fjalë të papërshtatshme. Zgjidh një tjetër.'); end if;
    if exists(select 1 from app.profiles where username = v_username and id <> auth.uid()) then
      return jsonb_build_object('error', 'Ky username është i zënë. Provo një tjetër.');
    end if;
  end if;
  if p_body ? 'displayName' then
    if v_display is null or length(v_display) not between 1 and 40 then
      return jsonb_build_object('error', 'Emri i shfaqur duhet të ketë 1–40 shkronja.');
    end if;
    if app.name_bad(v_display) then return jsonb_build_object('error', 'Emri ka fjalë të papërshtatshme. Shkruaje ndryshe.'); end if;
  end if;
  if p_body ? 'avatarEmoji' and (v_emoji is null or length(v_emoji) > 16) then
    return jsonb_build_object('error', 'Avatari nuk është i vlefshëm.');
  end if;
  update app.profiles set
    username = case when p_body ? 'username' then v_username else username end,
    display_name = case when p_body ? 'displayName' then v_display else display_name end,
    avatar_emoji = case when p_body ? 'avatarEmoji' then v_emoji else avatar_emoji end,
    avatar_color = case when p_body ? 'avatarColor' then greatest(0, least(coalesce(v_color, 0), 20)) else avatar_color end
  where id = auth.uid();
  return jsonb_build_object('ok', true);
exception when unique_violation then
  return jsonb_build_object('error', 'Ky username është i zënë. Provo një tjetër.');
end $$;

create or replace function public.api_usernameavailable(p_body jsonb) returns jsonb
language plpgsql stable security definer set search_path = app, pg_temp as $$
declare v_username text := lower(trim(p_body->>'username'));
begin
  perform app.gate(array['student','parent','teacher']);
  if v_username !~ '^[a-z0-9._]{3,20}$' or app.name_bad(v_username) then return jsonb_build_object('available', false); end if;
  return jsonb_build_object('available', not exists(select 1 from app.profiles where username = v_username and id <> auth.uid()));
end $$;

create or replace function public.api_usersearch(p_body jsonb) returns jsonb
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
            and role = 'student' and app.friend_eligible(id) and not app.blocked_either(auth.uid(), id)
            and not app.is_review_account(id)
          order by username limit 10) p), '[]'::jsonb));
end $$;

create or replace function public.api_friendrequest(p_body jsonb) returns jsonb
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
  if v_other is null or not app.friend_eligible(v_other) or app.blocked_either(auth.uid(), v_other) then
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

-- Blloko/zhblloko me username (Shokët). Bllokimi heq edhe shoqërinë dhe ftesat.
create or replace function public.api_userblock(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare v_other uuid; v_block boolean := coalesce((p_body->>'block')::boolean, true);
begin
  perform app.gate(array['student','parent','teacher']);
  select id into v_other from app.profiles where username = lower(regexp_replace(trim(coalesce(p_body->>'username','')), '^@', ''));
  if v_other is null or v_other = auth.uid() then return jsonb_build_object('error', 'Përdoruesi nuk u gjet.'); end if;
  if v_block then
    insert into app.chat_blocks(blocker, blocked) values (auth.uid(), v_other) on conflict do nothing;
    delete from app.friendships where (requester = auth.uid() and addressee = v_other) or (requester = v_other and addressee = auth.uid());
    perform app.audit('user_block', v_other::text);
  else
    delete from app.chat_blocks where blocker = auth.uid() and blocked = v_other;
    perform app.audit('user_unblock', v_other::text);
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.api_userblocks(p_body jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = app, pg_temp as $$
begin
  perform app.gate(array['student','parent','teacher']);
  return jsonb_build_object('users', coalesce((select jsonb_agg(app.public_user(p) order by p.username)
    from app.chat_blocks b join app.profiles p on p.id = b.blocked
   where b.blocker = auth.uid() and p.username is not null), '[]'::jsonb));
end $$;

create or replace function public.api_userreport(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare v_other uuid; v_reason text := coalesce(p_body->>'reason', 'other'); v_note text := nullif(left(trim(coalesce(p_body->>'note','')), 300), '');
begin
  perform app.gate(array['student','parent','teacher']);
  select id into v_other from app.profiles where username = lower(regexp_replace(trim(coalesce(p_body->>'username','')), '^@', ''));
  if v_other is null or v_other = auth.uid() then return jsonb_build_object('error', 'Përdoruesi nuk u gjet.'); end if;
  if v_reason not in ('bullying', 'inappropriate', 'impersonation', 'spam', 'other') then v_reason := 'other'; end if;
  if not app.hit('userreport:' || auth.uid(), 20, interval '1 day') then return jsonb_build_object('error', 'Ke dërguar shumë raporte sot.'); end if;
  insert into app.user_reports(reporter_id, reported_id, reason, note) values (auth.uid(), v_other, v_reason, v_note)
  on conflict (reporter_id, reported_id) do update set reason = excluded.reason, note = excluded.note, status = 'open', created_at = now();
  perform app.audit('user_report', v_other::text, jsonb_build_object('reason', v_reason));
  return jsonb_build_object('ok', true);
end $$;

-- Moderatori (sekretaria): radha e raportimeve të hapura.
create or replace function public.api_adminreports(p_body jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = app, pg_temp as $$
begin
  perform app.gate_admin();
  return jsonb_build_object(
    'messages', coalesce((select jsonb_agg(jsonb_build_object(
        'id', r.id, 'reason', r.reason, 'at', app.epoch(r.created_at),
        'reporter', app.chat_name(r.reporter_id), 'sender', app.chat_name(m.sender_id),
        'body', case when m.deleted_at is null then m.body else '(u fshi)' end, 'deleted', m.deleted_at is not null,
        'place', case c.kind when 'class' then 'Grupi ' || coalesce((select name from app.classes where id = c.class_id), '')
                             when 'office' then 'Sekretaria' when 'friend' then 'Bisedë shokësh'
                             when 'tutor' then 'Mësues ↔ nxënës' else 'Prind ↔ mësues' end) order by r.created_at)
      from app.message_reports r join app.messages m on m.id = r.message_id join app.conversations c on c.id = m.conversation_id
     where r.status = 'new'), '[]'::jsonb),
    'users', coalesce((select jsonb_agg(jsonb_build_object(
        'id', r.id, 'reason', r.reason, 'note', r.note, 'at', app.epoch(r.created_at),
        'reporter', app.chat_name(r.reporter_id), 'reported', app.chat_name(r.reported_id),
        'username', (select username from app.profiles where id = r.reported_id),
        'count', (select count(*) from app.user_reports x where x.reported_id = r.reported_id)) order by r.created_at)
      from app.user_reports r where r.status = 'open'), '[]'::jsonb),
    'ai', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'reason', r.reason, 'at', app.epoch(r.created_at),
        'question', left(coalesce(r.question, ''), 300), 'answer', left(coalesce(r.answer, ''), 600)) order by r.created_at)
      from app.ai_reports r where r.status = 'new'), '[]'::jsonb));
end $$;

-- action: 'close' (mbyll pa veprim) ose 'delete' (fsheh mesazhin e raportuar dhe mbyll).
create or replace function public.api_adminreportresolve(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare v_kind text := p_body->>'kind'; v_id uuid; v_action text := coalesce(p_body->>'action', 'close'); n int;
begin
  perform app.gate_admin();
  begin v_id := (p_body->>'id')::uuid; exception when others then return jsonb_build_object('error', 'Raport i panjohur.'); end;
  if v_kind = 'message' then
    if v_action = 'delete' then
      update app.messages set deleted_at = now() where id = (select message_id from app.message_reports where id = v_id) and deleted_at is null;
      update app.message_reports set status = 'reviewed' where message_id = (select message_id from app.message_reports where id = v_id);
    else
      update app.message_reports set status = 'reviewed' where id = v_id;
    end if;
  elsif v_kind = 'user' then
    update app.user_reports set status = 'closed' where id = v_id;
  elsif v_kind = 'ai' then
    update app.ai_reports set status = 'reviewed' where id = v_id;
  else return jsonb_build_object('error', 'Lloj i panjohur.');
  end if;
  get diagnostics n = row_count;
  perform app.audit('report_' || v_action, v_id::text, jsonb_build_object('kind', v_kind));
  return jsonb_build_object('ok', true);
end $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'app' and p.proname in ('name_bad', 'blocked_either')
  loop execute format('revoke all on function %s from public, anon, authenticated', f.sig); end loop;
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname in ('api_profileupdate', 'api_usernameavailable', 'api_usersearch', 'api_friendrequest',
                  'api_userblock', 'api_userblocks', 'api_userreport', 'api_adminreports', 'api_adminreportresolve')
  loop execute format('revoke all on function %s from public, anon', f.sig); execute format('grant execute on function %s to authenticated', f.sig); end loop;
end $$;
