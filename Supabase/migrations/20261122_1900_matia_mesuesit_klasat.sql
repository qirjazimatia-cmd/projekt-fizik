-- Rolet në shkollë (#116).
--  · Lëndët e mësuesit (profiles.subjects) — çdo lëndë e shkollës.
--  · Klasat zyrtare: sekretaria cakton kujdestarin (owner) për çdo klasë të regjistrit; nxënësit e aktivizuar futen vetë.
--  · Mësuesit e lëndëve (app.class_teachers): kujdestari i fton; ata japin teste/evente/materiale dhe flasin me klasën.
--    app.owns_class() tani do të thotë «jep mësim në këtë klasë» (kujdestar ose mësues lënde aktiv);
--    veprimet e administrimit të klasës (pranimi, heqja e nxënësve, kodi, fshirja) mbeten vetëm për kujdestarin.
--  · Bisedat: lloji 'office' (prindi ↔ sekretaria); mësuesit e lëndëve lidhen me nxënësit dhe prindërit e klasave të tyre.
--  · Eventet: lloji 'parent_meeting' (mbledhje me prindër), vetëm nga kujdestari; prindërit i shohin te kalendari.

alter table app.profiles add column if not exists subjects text[] not null default '{}';
alter table app.classes add column if not exists official boolean not null default false;
alter table app.events add column if not exists kind text not null default 'event';
alter table app.events drop constraint if exists events_kind_check;
alter table app.events add constraint events_kind_check check (kind in ('event', 'parent_meeting'));

create table if not exists app.class_teachers (
  class_id uuid not null references app.classes(id) on delete cascade,
  teacher_id uuid not null references app.profiles(id) on delete cascade,
  subject text,
  status text not null default 'invited' check (status in ('invited', 'active')),
  invited_by uuid references app.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (class_id, teacher_id)
);
alter table app.class_teachers enable row level security;
create index if not exists class_teachers_teacher_idx on app.class_teachers(teacher_id);

-- Lëndët e lejuara (shqip, si në app).
create or replace function app.school_subjects() returns text[]
language sql immutable set search_path = app, pg_temp as $$
  select array['Matematikë','Fizikë','Kimi','Biologji','Gjeografi','Histori','Gjuhë shqipe','Letërsi','Anglisht','Italisht',
               'Frëngjisht','Gjermanisht','Informatikë','TIK','Edukim fizik','Art','Muzikë','Qytetari','Filozofi','Ekonomi',
               'Psikologji','Sociologji','Edukim teknologjik','Edukim fetar']
$$;

create or replace function app.teaches_in(p_teacher uuid, p_class uuid) returns boolean
language sql stable security definer set search_path = app, pg_temp as $$
  select exists(select 1 from app.classes where id = p_class and owner_id = p_teacher)
      or exists(select 1 from app.class_teachers where class_id = p_class and teacher_id = p_teacher and status = 'active')
$$;

create or replace function app.is_class_owner(p_class uuid) returns boolean
language sql stable security definer set search_path = app, pg_temp as $$
  select exists(select 1 from app.classes where id = p_class and owner_id = auth.uid())
$$;

create or replace function app.owns_class(p_class uuid) returns boolean
language sql stable security definer set search_path = app, pg_temp as $$ select app.teaches_in(auth.uid(), p_class) $$;

-- "11B" → 11 → niveli i mësimeve (1 = 9-vjeçare, 2–4 = gjimnaz I–III).
create or replace function app.grade_level(p_class text) returns int
language sql immutable set search_path = app, pg_temp as $$
  select case when g is null then 1 when g <= 9 then 1 when g = 10 then 2 when g = 11 then 3 else 4 end
    from (select nullif(substring(app.class_key(p_class) from '^[0-9]+'), '')::int g) x
$$;

-- Veprimet e administrimit të klasës: vetëm kujdestari.
create or replace function public.api_approve(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare v_class uuid := (p_body->>'classID')::uuid;
begin
  perform app.gate(array['teacher']);
  if not app.is_class_owner(v_class) then raise exception 'Vetëm kujdestari i klasës e bën këtë.' using errcode = 'PT403'; end if;
  update app.class_members set approved = true where class_id = v_class and user_id = (p_body->>'student')::uuid;
  perform app.audit('member_approved', v_class::text, jsonb_build_object('student', p_body->>'student'));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.api_removemember(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare v_class uuid := (p_body->>'classID')::uuid;
begin
  perform app.gate(array['teacher']);
  if not app.is_class_owner(v_class) then raise exception 'Vetëm kujdestari i klasës e bën këtë.' using errcode = 'PT403'; end if;
  delete from app.class_members where class_id = v_class and user_id = (p_body->>'student')::uuid;
  perform app.audit('member_removed', v_class::text, jsonb_build_object('student', p_body->>'student'));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.api_rotatecode(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare v_class uuid := (p_body->>'classID')::uuid;
begin
  perform app.gate(array['teacher']);
  if not app.is_class_owner(v_class) then raise exception 'Vetëm kujdestari i klasës e bën këtë.' using errcode = 'PT403'; end if;
  update app.classes set join_code = app.new_code(5) where id = v_class;
  return jsonb_build_object('ok', true);
end $$;

-- Lidhjet e bisedave përfshijnë edhe mësuesit e lëndëve.
create or replace function app.chat_tutor_linked(p_teacher uuid, p_student uuid) returns boolean
language sql stable security definer set search_path = app, pg_temp as $$
  select exists(select 1 from app.class_members m where m.user_id = p_student and m.approved and app.teaches_in(p_teacher, m.class_id))
$$;

create or replace function app.chat_family_linked(p_parent uuid, p_teacher uuid) returns boolean
language sql stable security definer set search_path = app, pg_temp as $$
  select exists(select 1 from app.parent_links pl join app.class_members m on m.user_id = pl.child_id and m.approved
                 where pl.parent_id = p_parent and app.teaches_in(p_teacher, m.class_id))
$$;

-- Biseda me sekretarinë: a = prindi, b = bosh; e lexojnë prindi dhe çdo sekretar.
alter table app.conversations drop constraint if exists conversations_kind_check;
alter table app.conversations add constraint conversations_kind_check check (kind in ('class', 'friend', 'family', 'tutor', 'office'));
alter table app.conversations drop constraint if exists conversations_check;
alter table app.conversations add constraint conversations_check check (
     (kind = 'class' and class_id is not null and a is null and b is null)
  or (kind = 'office' and class_id is null and a is not null and b is null)
  or (kind not in ('class', 'office') and class_id is null and a is not null and b is not null and a < b));
create unique index if not exists conversations_office_key on app.conversations(a) where kind = 'office';

create or replace function app.chat_can_read(c app.conversations) returns boolean
language sql stable security definer set search_path = app, pg_temp as $$
  select case when c.kind = 'class' then app.can_see_class(c.class_id)
              when c.kind = 'office' then auth.uid() = c.a or app.is_school_admin(auth.uid())
              else auth.uid() in (c.a, c.b) or app.chat_parent_of(c) end
$$;

create or replace function app.chat_visible(c app.conversations) returns boolean
language sql stable security definer set search_path = app, pg_temp as $$
  select case when c.kind = 'class' then app.can_see_class(c.class_id)
              when c.kind = 'office' then auth.uid() = c.a or app.is_school_admin(auth.uid())
              else auth.uid() in (c.a, c.b) or app.chat_parent_of(c) end
$$;

create or replace function app.chat_write_block(c app.conversations) returns text
language plpgsql stable security definer set search_path = app, pg_temp as $$
declare v_role text := app."current_role"(); v_other uuid;
begin
  if not app.chat_can_read(c) then return 'Nuk je pjesë e kësaj bisede.'; end if;
  if c.kind = 'office' then return null; end if;
  if c.kind = 'class' then
    if app.owns_class(c.class_id) then return null; end if;
    if v_role = 'parent' then return 'Prindërit e lexojnë grupin e klasës. Për mësuesin, hap një bisedë private.'; end if;
    if c.teacher_only then return 'Në këtë grup shkruajnë vetëm mësuesit.'; end if;
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
                  when c.kind = 'office' then case when auth.uid() = c.a then 'Sekretaria e shkollës' else app.chat_name(c.a) end
                  when auth.uid() not in (c.a, c.b) then app.chat_name(c.a) || ' · ' || app.chat_name(c.b)
                  else app.chat_name(app.chat_other(c)) end,
    'subtitle', case c.kind when 'class' then 'Grupi i klasës' when 'friend' then 'Shok'
                  when 'office' then case when auth.uid() = c.a then 'Shkolla' else 'Prind → sekretaria' end
                  when 'tutor' then case when auth.uid() not in (c.a, c.b) then 'Mësuesi dhe fëmija yt'
                                         when app."current_role"() = 'teacher' then 'Nxënës' else 'Mësues' end
                  else case when app."current_role"() = 'teacher' then 'Prind' else 'Mësues' end end,
    'otherID', case when c.kind in ('class', 'office') or auth.uid() not in (c.a, c.b) then null else app.chat_other(c) end,
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

-- Kontaktet: nxënësi → shokët + mësuesit e klasave; mësuesi → nxënësit + prindërit e klasave ku jep mësim;
-- prindi → sekretaria + mësuesit e klasave të fëmijës.
create or replace function public.api_chatcontacts(p_body jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = app, pg_temp as $$
declare v_role text;
begin
  v_role := app.gate(array['student','parent','teacher']);
  if v_role = 'parent' then
    return jsonb_build_object('contacts', jsonb_build_array(jsonb_build_object('userID', 'office', 'name', 'Sekretaria e shkollës', 'kind', 'office',
              'detail', 'Pyetje, dokumente, mungesa, takime')) || coalesce((select jsonb_agg(x order by x->>'name') from (
      select distinct jsonb_build_object('userID', t.id, 'name', app.chat_name(t.id), 'kind', 'family',
                                         'detail', 'Mësues · ' || c.name || coalesce(' · ' || ct.subject, case when c.owner_id = t.id then ' · kujdestar' else '' end)
                                                   || ' · ' || app.chat_name(pl.child_id)) x
        from app.parent_links pl join app.class_members m on m.user_id = pl.child_id and m.approved
        join app.classes c on c.id = m.class_id
        join app.profiles t on t.role = 'teacher' and app.teaches_in(t.id, c.id)
        left join app.class_teachers ct on ct.class_id = c.id and ct.teacher_id = t.id
       where pl.parent_id = auth.uid()) s), '[]'::jsonb));
  elsif v_role = 'teacher' then
    return jsonb_build_object('contacts', coalesce((select jsonb_agg(x order by x->>'kind', x->>'name') from (
      select distinct jsonb_build_object('userID', pl.parent_id, 'name', app.chat_name(pl.parent_id), 'kind', 'family',
                                         'detail', 'Prind · ' || app.chat_name(pl.child_id) || ' · ' || c.name) x
        from app.classes c join app.class_members m on m.class_id = c.id and m.approved
        join app.parent_links pl on pl.child_id = m.user_id where app.teaches_in(auth.uid(), c.id)
      union
      select distinct jsonb_build_object('userID', m.user_id, 'name', app.chat_name(m.user_id), 'kind', 'tutor',
                                         'detail', 'Nxënës · ' || c.name) x
        from app.classes c join app.class_members m on m.class_id = c.id and m.approved where app.teaches_in(auth.uid(), c.id)) s), '[]'::jsonb));
  end if;
  return jsonb_build_object('contacts', coalesce((select jsonb_agg(x order by x->>'kind' desc, x->>'name') from (
    select jsonb_build_object('userID', p.id, 'name', app.chat_name(p.id), 'kind', 'friend', 'detail', '@' || p.username) x
      from app.friendships f join app.profiles p on p.id = case when f.requester = auth.uid() then f.addressee else f.requester end
     where f.status = 'accepted' and auth.uid() in (f.requester, f.addressee) and app.friend_eligible(p.id) and app.friend_eligible(auth.uid())
    union
    select distinct jsonb_build_object('userID', t.id, 'name', app.chat_name(t.id), 'kind', 'tutor',
                                       'detail', 'Mësues · ' || c.name || coalesce(' · ' || ct.subject, '')) x
      from app.class_members m join app.classes c on c.id = m.class_id
      join app.profiles t on t.role = 'teacher' and app.teaches_in(t.id, c.id)
      left join app.class_teachers ct on ct.class_id = c.id and ct.teacher_id = t.id
     where m.user_id = auth.uid() and m.approved) s), '[]'::jsonb));
end $$;

create or replace function public.api_chatopen(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare v_role text; v_class uuid := nullif(p_body->>'classID', '')::uuid; v_other uuid; v_other_role text; v_kind text; v_id uuid; c app.conversations;
begin
  v_role := app.gate(array['student','parent','teacher']);
  if coalesce((p_body->>'office')::boolean, false) or p_body->>'userID' = 'office' then
    if v_role <> 'parent' then return jsonb_build_object('error', 'Biseda me sekretarinë është për prindërit.'); end if;
    insert into app.conversations(kind, a) values ('office', auth.uid()) on conflict do nothing;
    select id into v_id from app.conversations where kind = 'office' and a = auth.uid();
    return jsonb_build_object('id', v_id);
  end if;
  if v_class is not null then
    if not app.can_see_class(v_class) then raise exception 'Nuk je pjesë e kësaj klase.' using errcode = 'PT403'; end if;
    insert into app.conversations(kind, class_id) values ('class', v_class) on conflict do nothing;
    select id into v_id from app.conversations where kind = 'class' and class_id = v_class;
    return jsonb_build_object('id', v_id);
  end if;
  begin v_other := nullif(p_body->>'userID', '')::uuid; exception when others then v_other := null; end;
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

-- Pamja e shkollës: klasat ku jep mësim mësuesi (kujdestar ose lëndë), kodi vetëm për kujdestarin, lloji i eventit.
create or replace function public.api_snapshot(p_body jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare v_role text; v_classes jsonb; v_members jsonb := '[]'; v_tests jsonb; v_events jsonb; v_results jsonb := '[]'; v_parents jsonb := '[]'; v_children jsonb := '[]'; r record;
begin
  v_role := app.gate(array['student','parent','teacher']);
  select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'level',c.level,'owner',c.owner_id,'code', case when c.owner_id = auth.uid() then c.join_code else '' end,
           'approved', app.owns_class(c.id) or app.in_class(c.id) or app.parent_sees_class(c.id),
           'homeroom', c.owner_id = auth.uid(), 'official', c.official,
           'mySubject', (select subject from app.class_teachers ct where ct.class_id = c.id and ct.teacher_id = auth.uid())) order by c.name),'[]')
    into v_classes from app.classes c
   where app.owns_class(c.id) or app.in_class(c.id) or app.parent_sees_class(c.id) or exists(select 1 from app.class_members m where m.class_id = c.id and m.user_id = auth.uid());
  if v_role = 'teacher' then
    select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'email',p.email,'classID',m.class_id,'approved',m.approved)),'[]')
      into v_members from app.class_members m join app.profiles p on p.id = m.user_id where app.owns_class(m.class_id);
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'classID',e.class_id,'title',e.title,'minutes',e.minutes,'subject',e.subject,'status',e.status,
           'count',(select count(*) from app.exam_questions q where q.exam_id = e.id)) order by e.created_at desc),'[]')
    into v_tests from app.exams e where e.owner_id = auth.uid() or (e.status = 'published' and (app.in_class(e.class_id) or app.parent_sees_class(e.class_id)));
  select coalesce(jsonb_agg(jsonb_build_object('id',ev.id,'classID',ev.class_id,'owner',ev.owner_id,'title',ev.title,'note',ev.note,'date',app.epoch(ev.starts_at),
           'subject',ev.subject,'examID',ev.exam_id,'kind',ev.kind) order by ev.starts_at),'[]')
    into v_events from app.events ev where app.can_see_class(ev.class_id);
  for r in select a.id, e.owner_id, a.student_id from app.attempts a join app.exams e on e.id = a.exam_id
            where e.owner_id = auth.uid() or a.student_id = auth.uid()
               or (v_role = 'parent' and exists(select 1 from app.parent_links pl where pl.parent_id = auth.uid() and pl.child_id = a.student_id)) loop
    perform app.finalize_attempt(r.id);
    if r.owner_id = auth.uid() then v_results := v_results || app.attempt_view(r.id,'teacher');
    elsif r.student_id = auth.uid() then v_results := v_results || app.attempt_view(r.id,'student');
    else v_results := v_results || app.attempt_view(r.id,'parent');
    end if;
  end loop;
  if v_role = 'student' then
    select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'email',p.email)),'[]') into v_parents from app.parent_links pl join app.profiles p on p.id = pl.parent_id where pl.child_id = auth.uid();
  elsif v_role = 'parent' then
    select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'email',p.email)),'[]') into v_children from app.parent_links pl join app.profiles p on p.id = pl.child_id where pl.parent_id = auth.uid();
  end if;
  return jsonb_build_object('classes',v_classes,'members',v_members,'tests',v_tests,'events',v_events,'results',v_results,'parents',v_parents,'children',v_children);
end $$;

create or replace function public.api_eventcreate(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare v_class uuid := (p_body->>'classID')::uuid; v_title text := trim(coalesce(p_body->>'title',''));
        v_exam uuid := nullif(p_body->>'examID','')::uuid; v_kind text := coalesce(nullif(p_body->>'kind',''), 'event');
begin
  perform app.gate(array['teacher']);
  if not app.owns_class(v_class) then raise exception 'Nuk ke të drejtë mbi këtë klasë.' using errcode = 'PT403'; end if;
  if v_kind not in ('event', 'parent_meeting') then return jsonb_build_object('error','Lloj i panjohur eventi.'); end if;
  if v_kind = 'parent_meeting' and not app.is_class_owner(v_class) then
    return jsonb_build_object('error','Mbledhjen me prindër e cakton kujdestari i klasës.'); end if;
  if v_title = '' or length(v_title) > 200 then return jsonb_build_object('error','Shkruaj titullin.'); end if;
  if v_exam is not null and not exists(select 1 from app.exams where id = v_exam and class_id = v_class and owner_id = auth.uid()) then return jsonb_build_object('error','Testi nuk i përket kësaj klase.'); end if;
  insert into app.events(class_id, owner_id, title, subject, starts_at, note, exam_id, kind)
    values (v_class, auth.uid(), v_title, nullif(p_body->>'subject',''), to_timestamp((p_body->>'date')::double precision), left(coalesce(p_body->>'note',''),2000), v_exam, v_kind);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.api_scheduleget(p_body jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = app, pg_temp as $$
begin
  perform app.gate(array['student','parent','teacher']);
  return jsonb_build_object('slots', coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', s.id, 'classID', s.class_id, 'className', c.name, 'weekday', s.weekday,
             'starts', to_char(s.starts, 'HH24:MI'), 'ends', to_char(s.ends, 'HH24:MI'),
             'subject', s.subject, 'room', s.room, 'mine', s.owner_id = auth.uid())
           order by s.weekday, s.starts)
      from app.schedule_slots s join app.classes c on c.id = s.class_id
     where s.owner_id = auth.uid() or app.owns_class(s.class_id) or app.in_class(s.class_id) or app.parent_sees_class(s.class_id)), '[]'::jsonb));
end $$;

-- Mësuesi: lëndët e tij.
create or replace function public.api_teachersubjects(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare v_list text[];
begin
  perform app.gate(array['teacher']);
  select coalesce(array_agg(distinct s), '{}') into v_list
    from jsonb_array_elements_text(coalesce(p_body->'subjects', '[]'::jsonb)) s where s = any(app.school_subjects());
  if cardinality(v_list) = 0 then return jsonb_build_object('error','Zgjidh të paktën një lëndë.'); end if;
  if cardinality(v_list) > 6 then return jsonb_build_object('error','Zgjidh deri në 6 lëndë.'); end if;
  update app.profiles set subjects = v_list where id = auth.uid();
  return jsonb_build_object('ok', true, 'subjects', to_jsonb(v_list));
end $$;

-- Këndi i mësuesit: lëndët, klasat (kujdestar / lëndë), ftesat.
create or replace function public.api_teacherhome(p_body jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = app, pg_temp as $$
begin
  perform app.gate(array['teacher']);
  return jsonb_build_object(
    'subjects', (select to_jsonb(subjects) from app.profiles where id = auth.uid()),
    'allSubjects', to_jsonb(app.school_subjects()),
    'classes', coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'name', c.name, 'level', c.level, 'official', c.official, 'homeroom', c.owner_id = auth.uid(),
        'homeroomName', app.chat_name(c.owner_id),
        'subject', (select subject from app.class_teachers ct where ct.class_id = c.id and ct.teacher_id = auth.uid()),
        'students', (select count(*) from app.class_members m where m.class_id = c.id and m.approved),
        'teachers', case when c.owner_id = auth.uid() then coalesce((select jsonb_agg(jsonb_build_object(
              'id', ct.teacher_id, 'name', app.chat_name(ct.teacher_id), 'subject', ct.subject, 'status', ct.status) order by ct.subject)
            from app.class_teachers ct where ct.class_id = c.id), '[]'::jsonb) else null end)
      order by c.owner_id = auth.uid() desc, c.name) from app.classes c where app.teaches_in(auth.uid(), c.id)), '[]'::jsonb),
    'invites', coalesce((select jsonb_agg(jsonb_build_object('classID', c.id, 'className', c.name,
        'homeroomName', app.chat_name(c.owner_id), 'subject', ct.subject) order by c.name)
      from app.class_teachers ct join app.classes c on c.id = ct.class_id
     where ct.teacher_id = auth.uid() and ct.status = 'invited'), '[]'::jsonb));
end $$;

-- Lista e mësuesve aktivë (për «Fto» te kujdestari dhe te sekretaria).
create or replace function public.api_teacherdirectory(p_body jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = app, pg_temp as $$
begin
  perform app.gate(array['teacher']);
  return jsonb_build_object('teachers', coalesce((select jsonb_agg(jsonb_build_object(
      'id', p.id, 'name', app.chat_name(p.id), 'email', p.email, 'subjects', to_jsonb(p.subjects)) order by app.chat_name(p.id))
    from app.profiles p where p.role = 'teacher' and p.teacher_status = 'active' and not app.is_review_account(p.id)), '[]'::jsonb));
end $$;

create or replace function public.api_classteacherinvite(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare v_class uuid; v_teacher uuid; v_subject text := nullif(trim(coalesce(p_body->>'subject','')), '');
begin
  perform app.gate(array['teacher']);
  begin v_class := (p_body->>'classID')::uuid; v_teacher := (p_body->>'teacherID')::uuid;
  exception when others then return jsonb_build_object('error','Zgjidh klasën dhe mësuesin.'); end;
  if not app.is_class_owner(v_class) then return jsonb_build_object('error','Mësuesit i fton vetëm kujdestari i klasës.'); end if;
  if v_teacher = auth.uid() then return jsonb_build_object('error','Je vetë kujdestari i kësaj klase.'); end if;
  if not exists(select 1 from app.profiles where id = v_teacher and role = 'teacher' and teacher_status = 'active') then
    return jsonb_build_object('error','Mësuesi nuk u gjet.'); end if;
  if v_subject is not null and not (v_subject = any(app.school_subjects())) then return jsonb_build_object('error','Lëndë e panjohur.'); end if;
  if not app.hit('ctinv:' || auth.uid(), 60, interval '1 hour') then return jsonb_build_object('error','Shumë ftesa. Prit pak.'); end if;
  insert into app.class_teachers(class_id, teacher_id, subject, invited_by) values (v_class, v_teacher, v_subject, auth.uid())
  on conflict (class_id, teacher_id) do update set subject = coalesce(excluded.subject, app.class_teachers.subject);
  perform app.audit('class_teacher_invited', v_class::text, jsonb_build_object('teacher', v_teacher, 'subject', v_subject));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.api_classteacherrespond(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare v_class uuid; n int;
begin
  perform app.gate(array['teacher']);
  begin v_class := (p_body->>'classID')::uuid; exception when others then return jsonb_build_object('error','Klasë e panjohur.'); end;
  if coalesce((p_body->>'accept')::boolean, false) then
    update app.class_teachers set status = 'active' where class_id = v_class and teacher_id = auth.uid() and status = 'invited';
  else
    delete from app.class_teachers where class_id = v_class and teacher_id = auth.uid();
  end if;
  get diagnostics n = row_count;
  if n = 0 then return jsonb_build_object('error','Ftesa nuk u gjet.'); end if;
  return jsonb_build_object('ok', true);
end $$;

-- Kujdestari heq një mësues lënde, ose mësuesi largohet vetë.
create or replace function public.api_classteacherremove(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare v_class uuid; v_teacher uuid; n int;
begin
  perform app.gate(array['teacher']);
  begin v_class := (p_body->>'classID')::uuid; v_teacher := coalesce(nullif(p_body->>'teacherID','')::uuid, auth.uid());
  exception when others then return jsonb_build_object('error','Të dhëna të pavlefshme.'); end;
  if v_teacher <> auth.uid() and not app.is_class_owner(v_class) then return jsonb_build_object('error','Vetëm kujdestari heq mësuesit.'); end if;
  delete from app.class_teachers where class_id = v_class and teacher_id = v_teacher;
  get diagnostics n = row_count;
  if n = 0 then return jsonb_build_object('error','Mësuesi nuk është në këtë klasë.'); end if;
  perform app.audit('class_teacher_removed', v_class::text, jsonb_build_object('teacher', v_teacher));
  return jsonb_build_object('ok', true);
end $$;

-- Sekretaria: klasat e regjistrit dhe kujdestarët.
--  action 'list'     → klasat (nga regjistri + klasat zyrtare) me kujdestarin dhe numrin e nxënësve, dhe mësuesit aktivë
--  action 'homeroom' → {className, teacherID}: krijon klasën zyrtare ose ia kalon kujdestarinë mësuesit të ri; fut nxënësit e aktivizuar
create or replace function public.api_adminclasses(p_body jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare v_action text := coalesce(p_body->>'action','list'); v_name text := upper(trim(coalesce(p_body->>'className','')));
        v_teacher uuid; v_class uuid; n int;
begin
  perform app.gate_admin();
  if v_action = 'homeroom' then
    begin v_teacher := (p_body->>'teacherID')::uuid; exception when others then return jsonb_build_object('error','Zgjidh mësuesin.'); end;
    if length(v_name) not between 1 and 12 then return jsonb_build_object('error','Emri i klasës nuk është i vlefshëm.'); end if;
    if not exists(select 1 from app.profiles where id = v_teacher and role = 'teacher' and teacher_status = 'active') then
      return jsonb_build_object('error','Mësuesi nuk u gjet.'); end if;
    select id into v_class from app.classes where official and app.class_key(name) = app.class_key(v_name) order by created_at limit 1;
    if v_class is null then
      insert into app.classes(owner_id, name, level, join_code, official)
      values (v_teacher, v_name, app.grade_level(v_name), app.new_code(5), true) returning id into v_class;
    else
      update app.classes set owner_id = v_teacher where id = v_class;
    end if;
    delete from app.class_teachers where class_id = v_class and teacher_id = v_teacher;
    insert into app.class_members(class_id, user_id, approved)
    select v_class, r.user_id, true from app.roster r
     where r.user_id is not null and r.status = 'active' and app.class_key(r.class_name) = app.class_key(v_name)
    on conflict (class_id, user_id) do update set approved = true;
    get diagnostics n = row_count;
    perform app.audit('homeroom_set', v_class::text, jsonb_build_object('teacher', v_teacher, 'class', v_name));
    return jsonb_build_object('ok', true, 'classID', v_class, 'studentsAdded', n);
  elsif v_action <> 'list' then return jsonb_build_object('error','Veprim i panjohur.');
  end if;
  return jsonb_build_object(
    'classes', coalesce((
      with keys as (
        select key, min(name) as name from (
          select app.class_key(class_name) as key, class_name as name from app.roster
          union all select app.class_key(name), name from app.classes where official) a
        group by key)
      select jsonb_agg(jsonb_build_object('className', k.name, 'classID', c.id,
               'homeroomID', c.owner_id, 'homeroomName', case when c.id is null then null else app.chat_name(c.owner_id) end,
               'rosterStudents', (select count(*) from app.roster r where app.class_key(r.class_name) = k.key and r.status <> 'left'),
               'activeStudents', (select count(*) from app.roster r where app.class_key(r.class_name) = k.key and r.status = 'active'),
               'members', coalesce((select count(*) from app.class_members m where m.class_id = c.id and m.approved), 0),
               'teachers', coalesce((select count(*) from app.class_teachers ct where ct.class_id = c.id and ct.status = 'active'), 0))
             order by length(k.key), k.key)
        from keys k left join lateral (select * from app.classes c0 where c0.official and app.class_key(c0.name) = k.key order by c0.created_at limit 1) c on true
    ), '[]'::jsonb),
    'teachers', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', app.chat_name(p.id), 'email', p.email, 'subjects', to_jsonb(p.subjects))
        order by app.chat_name(p.id)) from app.profiles p where p.role = 'teacher' and p.teacher_status = 'active' and not app.is_review_account(p.id)), '[]'::jsonb));
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
    'schoolAdmin', app.is_school_admin(p.id),
    'subjects', to_jsonb(p.subjects));
end $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'app' and p.proname in ('school_subjects','teaches_in','is_class_owner','owns_class','grade_level',
                  'chat_tutor_linked','chat_family_linked','chat_can_read','chat_visible','chat_write_block','chat_summary')
  loop execute format('revoke all on function %s from public, anon, authenticated', f.sig); end loop;
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname in ('api_approve','api_removemember','api_rotatecode','api_chatcontacts','api_chatopen',
                  'api_snapshot','api_eventcreate','api_scheduleget','api_teachersubjects','api_teacherhome','api_teacherdirectory',
                  'api_classteacherinvite','api_classteacherrespond','api_classteacherremove','api_adminclasses','api_me')
  loop execute format('revoke all on function %s from public, anon', f.sig); execute format('grant execute on function %s to authenticated', f.sig); end loop;
end $$;
