-- ScienceQuest · Supabase · 0002 · klasat, prindi, testet, eventet, progresi
-- STATUSI: I PA-EKZEKUTUAR. Varet nga 0001. Pa politika RLS për klientin; qasja vetëm përmes public.api_*.

create table app.classes (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references app.profiles(id) on delete cascade,
  name text not null check (length(name) between 1 and 100),
  level int not null check (level between 1 and 5),
  join_code text not null unique,
  created_at timestamptz not null default now()
);
create table app.class_members (
  class_id uuid references app.classes(id) on delete cascade,
  user_id uuid references app.profiles(id) on delete cascade,
  approved boolean not null default false,
  requested_at timestamptz not null default now(),
  primary key (class_id, user_id)
);
create table app.parent_links (
  parent_id uuid references app.profiles(id) on delete cascade,
  child_id uuid references app.profiles(id) on delete cascade,
  linked_at timestamptz not null default now(),
  primary key (parent_id, child_id)
);
create table app.family_codes (
  code_hash text primary key,
  child_id uuid not null references app.profiles(id) on delete cascade,
  expires_at timestamptz not null
);
create table app.exams (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references app.classes(id) on delete cascade,
  owner_id uuid not null references app.profiles(id) on delete cascade,
  title text not null check (length(title) between 1 and 200),
  subject text not null check (subject in ('Matematikë','Fizikë','Kimi','Biologji')),
  minutes int not null check (minutes between 1 and 180),
  status text not null default 'draft' check (status in ('draft','published','closed')),
  closes_at timestamptz,
  created_at timestamptz not null default now(),
  published_at timestamptz
);
create table app.exam_questions (
  id uuid primary key default gen_random_uuid(),
  exam_id uuid not null references app.exams(id) on delete cascade,
  position int not null,
  kind text not null check (kind in ('number','text','choice','open')),
  prompt text not null, unit text not null default '',
  points int not null default 4 check (points between 1 and 20),
  tolerance numeric not null default 0.005 check (tolerance >= 0),
  options jsonb
);
create table app.exam_keys (
  question_id uuid primary key references app.exam_questions(id) on delete cascade,
  answer text not null default '', explanation text not null default ''
);
create table app.attempts (
  id uuid primary key default gen_random_uuid(),
  exam_id uuid not null references app.exams(id) on delete cascade,
  student_id uuid not null references app.profiles(id) on delete cascade,
  started_at timestamptz not null default now(),
  deadline_at timestamptz not null,
  submitted_at timestamptz,
  results_published_at timestamptz,
  unique (exam_id, student_id)
);
create table app.attempt_answers (
  attempt_id uuid references app.attempts(id) on delete cascade,
  question_id uuid references app.exam_questions(id) on delete cascade,
  value text not null default '', reasoning text not null default '',
  saved_at timestamptz not null default now(),
  auto_points int, points int, feedback text not null default '',
  primary key (attempt_id, question_id)
);
create table app.events (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references app.classes(id) on delete cascade,
  owner_id uuid not null references app.profiles(id) on delete cascade,
  title text not null check (length(title) between 1 and 200),
  subject text, starts_at timestamptz not null, note text not null default '',
  exam_id uuid references app.exams(id) on delete set null
);
create table app.user_progress (
  user_id uuid references app.profiles(id) on delete cascade,
  key text not null check (length(key) <= 120),
  value jsonb not null, version int not null default 1,
  primary key (user_id, key)
);
do $$ declare t text; begin
  for t in select unnest(array['classes','class_members','parent_links','family_codes','exams','exam_questions','exam_keys','attempts','attempt_answers','events','user_progress'])
  loop execute format('alter table app.%I enable row level security', t); end loop;
end $$;

create function app.owns_class(p_class uuid) returns boolean language sql stable security definer set search_path = app, pg_temp as
$$ select exists(select 1 from app.classes where id = p_class and owner_id = auth.uid()) $$;
create function app.in_class(p_class uuid) returns boolean language sql stable security definer set search_path = app, pg_temp as
$$ select exists(select 1 from app.class_members where class_id = p_class and user_id = auth.uid() and approved) $$;
create function app.parent_sees_class(p_class uuid) returns boolean language sql stable security definer set search_path = app, pg_temp as
$$ select exists(select 1 from app.parent_links pl join app.class_members m on m.user_id = pl.child_id where pl.parent_id = auth.uid() and m.class_id = p_class and m.approved) $$;
create function app.can_see_class(p_class uuid) returns boolean language sql stable security definer set search_path = app, pg_temp as
$$ select app.owns_class(p_class) or app.in_class(p_class) or app.parent_sees_class(p_class) $$;
create function app.epoch(t timestamptz) returns double precision language sql immutable as $$ select extract(epoch from t)::double precision $$;
create function app.new_code(p_bytes int) returns text language sql volatile security definer set search_path = app, extensions, pg_temp as
$$ select upper(encode(gen_random_bytes(p_bytes),'hex')) $$;

create function app.parse_number(p text) returns numeric language plpgsql immutable as $$
declare v text := replace(replace(trim(coalesce(p,'')), ',', '.'), '−', '-'); n numeric; d numeric;
begin
  if v ~ '^-?[0-9]+(\.[0-9]+)?$' then return v::numeric; end if;
  if v ~ '^-?[0-9]+(\.[0-9]+)?\s*/\s*[0-9]+(\.[0-9]+)?$' then
    n := trim(split_part(v,'/',1))::numeric; d := trim(split_part(v,'/',2))::numeric;
    if d = 0 then return null; end if; return n / d;
  end if;
  return null;
end $$;

-- Mbyll përpjekjet e skaduara, krijon rreshta bosh për pyetjet pa përgjigje, llogarit pikët AUTOMATIKE (paraprake).
-- Publikon automatikisht vetëm kur testi nuk ka pyetje 'open'.
create function app.finalize_attempt(p_attempt uuid) returns void language plpgsql security definer set search_path = app, pg_temp as $$
declare v_exam uuid;
begin
  update app.attempts set submitted_at = least(now(), deadline_at) where id = p_attempt and submitted_at is null and deadline_at <= now();
  select a.exam_id into v_exam from app.attempts a where a.id = p_attempt and a.submitted_at is not null;
  if v_exam is null then return; end if;
  insert into app.attempt_answers(attempt_id, question_id) select p_attempt, q.id from app.exam_questions q where q.exam_id = v_exam on conflict do nothing;
  update app.attempt_answers aa set auto_points = case
      when q.kind = 'number' and app.parse_number(aa.value) is not null and app.parse_number(k.answer) is not null
           and abs(app.parse_number(aa.value) - app.parse_number(k.answer)) <= q.tolerance + 1e-12 then q.points
      when q.kind in ('text','choice') and lower(trim(aa.value)) = lower(trim(k.answer)) then q.points
      else 0 end
    from app.exam_questions q left join app.exam_keys k on k.question_id = q.id
   where aa.attempt_id = p_attempt and q.id = aa.question_id and aa.auto_points is null and q.kind <> 'open';
  update app.attempts a set results_published_at = now()
   where a.id = p_attempt and a.results_published_at is null
     and not exists(select 1 from app.exam_questions q where q.exam_id = a.exam_id and q.kind = 'open');
end $$;

-- p_mode: 'student' | 'teacher' | 'parent'. Nxënësi/prindi shohin pikët, komentet dhe (prindi) përgjigjet vetëm pas publikimit.
create function app.attempt_view(p_attempt uuid, p_mode text) returns jsonb language plpgsql stable security definer set search_path = app, pg_temp as $$
declare a app.attempts%rowtype; e app.exams%rowtype; v_pub boolean; v_status text; v_final int; v_prelim int; v_max int;
        v_q jsonb; v_ans jsonb; v_fb jsonb := '{}'; v_rev jsonb := null; v_grades jsonb := null; v_student text; v_class text;
begin
  select * into a from app.attempts where id = p_attempt;
  select * into e from app.exams where id = a.exam_id;
  v_pub := a.results_published_at is not null;
  select sum(points) into v_max from app.exam_questions where exam_id = e.id;
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'prompt',q.prompt,'kind',q.kind,'unit',q.unit,'points',q.points,'tolerance',q.tolerance,'options',q.options) order by q.position),'[]')
    into v_q from app.exam_questions q where q.exam_id = e.id;
  if p_mode = 'parent' and not v_pub then v_ans := '{}';
  else select coalesce(jsonb_object_agg(question_id, jsonb_build_object('value',value,'reasoning',reasoning)),'{}') into v_ans from app.attempt_answers where attempt_id = a.id; end if;
  select sum(coalesce(points, auto_points, 0)), sum(coalesce(auto_points, 0)) into v_final, v_prelim from app.attempt_answers where attempt_id = a.id;
  v_status := case when a.submitted_at is null then 'në zhvillim' when v_pub then 'vlerësuar' else 'në korrigjim' end;
  if p_mode = 'teacher' or v_pub then
    select coalesce(jsonb_object_agg(question_id, feedback) filter (where feedback <> ''),'{}') into v_fb from app.attempt_answers where attempt_id = a.id;
  end if;
  select p.email into v_student from app.profiles p where p.id = a.student_id;
  select name into v_class from app.classes where id = e.class_id;
  if p_mode = 'teacher' then
    select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'prompt',q.prompt,'kind',q.kind,'unit',q.unit,'points',q.points,'tolerance',q.tolerance,'options',q.options,'answer',k.answer,'explanation',k.explanation) order by q.position),'[]')
      into v_rev from app.exam_questions q left join app.exam_keys k on k.question_id = q.id where q.exam_id = e.id;
    select coalesce(jsonb_object_agg(question_id, points) filter (where points is not null),'{}') into v_grades from app.attempt_answers where attempt_id = a.id;
  end if;
  return jsonb_build_object('id',a.id,'exam',e.id,'title',e.title,'deadline',app.epoch(a.deadline_at),'serverNow',app.epoch(now()),
    'submitted',a.submitted_at is not null,'status',v_status,'questions',v_q,'answers',v_ans,
    'score', case when a.submitted_at is not null and (v_pub or p_mode = 'teacher') then v_final else null end,
    'preliminary', case when p_mode = 'teacher' and a.submitted_at is not null then v_prelim else null end,
    'maximum',coalesce(v_max,0),'feedback',v_fb,'student',v_student,'className',v_class,'reviewQuestions',v_rev,'grades',v_grades);
end $$;

-- ---------- klasat dhe prindi ----------
create function public.api_classCreate(p_body jsonb) returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare v_name text := trim(coalesce(p_body->>'name','')); v_level int := (p_body->>'level')::int;
begin
  perform app.gate(array['teacher']);
  if v_name = '' or length(v_name) > 100 or v_level not between 1 and 5 then return jsonb_build_object('error','Shkruaj emrin e klasës dhe nivelin.'); end if;
  insert into app.classes(owner_id, name, level, join_code) values (auth.uid(), v_name, v_level, app.new_code(5));
  return jsonb_build_object('ok', true);
end $$;
create function public.api_classJoin(p_body jsonb) returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare v_class uuid;
begin
  perform app.gate(array['student']);
  if not app.hit('join:' || auth.uid(), 20, interval '15 minutes') then return jsonb_build_object('error','Shumë tentativa. Prit pak dhe provo përsëri.'); end if;
  select id into v_class from app.classes where join_code = upper(trim(coalesce(p_body->>'code','')));
  if v_class is null then return jsonb_build_object('error','Kodi i klasës nuk u gjet.'); end if;
  insert into app.class_members(class_id, user_id, approved) values (v_class, auth.uid(), false) on conflict do nothing;
  return jsonb_build_object('ok', true);
end $$;
create function public.api_approve(p_body jsonb) returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare v_class uuid := (p_body->>'classID')::uuid;
begin
  perform app.gate(array['teacher']);
  if not app.owns_class(v_class) then raise exception 'Nuk ke të drejtë mbi këtë klasë.' using errcode = 'PT403'; end if;
  update app.class_members set approved = true where class_id = v_class and user_id = (p_body->>'student')::uuid;
  perform app.audit('member_approved', v_class::text, jsonb_build_object('student', p_body->>'student'));
  return jsonb_build_object('ok', true);
end $$;
create function public.api_removeMember(p_body jsonb) returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare v_class uuid := (p_body->>'classID')::uuid;
begin
  perform app.gate(array['teacher']);
  if not app.owns_class(v_class) then raise exception 'Nuk ke të drejtë mbi këtë klasë.' using errcode = 'PT403'; end if;
  delete from app.class_members where class_id = v_class and user_id = (p_body->>'student')::uuid;
  perform app.audit('member_removed', v_class::text, jsonb_build_object('student', p_body->>'student'));
  return jsonb_build_object('ok', true);
end $$;
create function public.api_rotateCode(p_body jsonb) returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare v_class uuid := (p_body->>'classID')::uuid;
begin
  perform app.gate(array['teacher']);
  if not app.owns_class(v_class) then raise exception 'Nuk ke të drejtë mbi këtë klasë.' using errcode = 'PT403'; end if;
  update app.classes set join_code = app.new_code(5) where id = v_class;
  return jsonb_build_object('ok', true);
end $$;
create function public.api_familyCode(p_body jsonb default '{}') returns jsonb language plpgsql security definer set search_path = app, extensions, pg_temp as $$
declare v_code text := encode(gen_random_bytes(9),'hex');
begin
  perform app.gate(array['student']);
  delete from app.family_codes where child_id = auth.uid();
  insert into app.family_codes values (encode(digest(v_code,'sha256'),'hex'), auth.uid(), now() + interval '15 minutes');
  return jsonb_build_object('code', v_code);
end $$;
create function public.api_familyJoin(p_body jsonb) returns jsonb language plpgsql security definer set search_path = app, extensions, pg_temp as $$
declare v_child uuid;
begin
  perform app.gate(array['parent']);
  if not app.hit('fam:' || auth.uid(), 10, interval '15 minutes') then return jsonb_build_object('error','Shumë tentativa. Prit pak dhe provo përsëri.'); end if;
  delete from app.family_codes where code_hash = encode(digest(trim(coalesce(p_body->>'code','')),'sha256'),'hex') and expires_at > now() returning child_id into v_child;
  if v_child is null then return jsonb_build_object('error','Kodi ka mbaruar ose nuk është i saktë.'); end if;
  insert into app.parent_links(parent_id, child_id) values (auth.uid(), v_child) on conflict do nothing;
  perform app.audit('family_linked', v_child::text);
  return jsonb_build_object('ok', true);
end $$;
create function public.api_unlinkParent(p_body jsonb) returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
begin
  perform app.gate(array['student']);
  delete from app.parent_links where child_id = auth.uid() and parent_id = (p_body->>'parent')::uuid;
  perform app.audit('family_unlinked', p_body->>'parent');
  return jsonb_build_object('ok', true);
end $$;
create function public.api_unlinkChild(p_body jsonb) returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
begin
  perform app.gate(array['parent']);
  delete from app.parent_links where parent_id = auth.uid() and child_id = (p_body->>'child')::uuid;
  return jsonb_build_object('ok', true);
end $$;

-- ---------- testet ----------
-- Variantet e gjeneruara nuk mbështeten në Supabase në këtë fazë. publish=true e publikon menjëherë; përndryshe mbetet draft.
create function public.api_examCreate(p_body jsonb) returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare v_class uuid := (p_body->>'classID')::uuid; v_exam uuid; q jsonb; i int := 0; v_kind text; v_min int := coalesce((p_body->>'minutes')::int, 30);
        v_close timestamptz := case when p_body->>'closesAt' is not null then to_timestamp((p_body->>'closesAt')::double precision) end;
begin
  perform app.gate(array['teacher']);
  if not app.owns_class(v_class) then raise exception 'Nuk ke të drejtë mbi këtë klasë.' using errcode = 'PT403'; end if;
  if coalesce((p_body->>'generated')::int,0) > 0 then return jsonb_build_object('error','Variantet e gjeneruara nuk mbështeten ende. Shkruaj pyetjet vetë.'); end if;
  if jsonb_typeof(p_body->'questions') <> 'array' or jsonb_array_length(p_body->'questions') not between 1 and 30 then return jsonb_build_object('error','Testi duhet të ketë 1–30 pyetje.'); end if;
  if trim(coalesce(p_body->>'title','')) = '' or v_min not between 1 and 180 or (p_body->>'subject') not in ('Matematikë','Fizikë','Kimi','Biologji') then return jsonb_build_object('error','Plotëso titullin, lëndën dhe kohëzgjatjen (1–180 min).'); end if;
  insert into app.exams(class_id, owner_id, title, subject, minutes, closes_at) values (v_class, auth.uid(), trim(p_body->>'title'), p_body->>'subject', v_min, v_close) returning id into v_exam;
  for q in select * from jsonb_array_elements(p_body->'questions') loop
    i := i + 1; v_kind := coalesce(q->>'kind','number');
    if v_kind not in ('number','text','choice','open') or trim(coalesce(q->>'prompt','')) = '' then raise exception 'Pyetje e pavlefshme.' using errcode = 'PT400'; end if;
    if v_kind <> 'open' and trim(coalesce(q->>'answer','')) = '' then raise exception 'Çdo pyetje me korrigjim automatik kërkon përgjigje.' using errcode = 'PT400'; end if;
    if v_kind = 'number' and app.parse_number(q->>'answer') is null then raise exception 'Përgjigjja numerike duhet të jetë numër ose thyesë.' using errcode = 'PT400'; end if;
    if v_kind = 'choice' and (jsonb_typeof(q->'options') <> 'array' or jsonb_array_length(q->'options') < 2) then raise exception 'Pyetja me alternativa kërkon të paktën 2 alternativa.' using errcode = 'PT400'; end if;
    with ins as (
      insert into app.exam_questions(exam_id, position, kind, prompt, unit, points, tolerance, options)
      values (v_exam, i, v_kind, left(q->>'prompt',4000), left(coalesce(q->>'unit',''),50), coalesce((q->>'points')::int,4), coalesce((q->>'tolerance')::numeric,0.005), case when v_kind = 'choice' then q->'options' end) returning id)
    insert into app.exam_keys(question_id, answer, explanation) select id, left(coalesce(q->>'answer',''),1000), left(coalesce(q->>'explanation',''),4000) from ins;
  end loop;
  if coalesce((p_body->>'publish')::boolean, false) then
    update app.exams set status = 'published', published_at = now() where id = v_exam;
    perform app.audit('exam_published', v_exam::text);
  end if;
  perform app.audit('exam_created', v_exam::text);
  return jsonb_build_object('ok', true, 'examID', v_exam);
end $$;
create function public.api_examPublish(p_body jsonb) returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare v_exam uuid := (p_body->>'examID')::uuid; n int;
begin
  perform app.gate(array['teacher']);
  update app.exams set status = case when coalesce((p_body->>'close')::boolean,false) then 'closed' else 'published' end, published_at = coalesce(published_at, now())
   where id = v_exam and owner_id = auth.uid();
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'Testi nuk është i yti.' using errcode = 'PT403'; end if;
  perform app.audit('exam_status', v_exam::text, jsonb_build_object('close', p_body->'close'));
  return jsonb_build_object('ok', true);
end $$;
create function public.api_examStart(p_body jsonb) returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare e app.exams%rowtype; a app.attempts%rowtype; v_dead timestamptz;
begin
  perform app.gate(array['student']);
  select * into e from app.exams where id = (p_body->>'examID')::uuid and status = 'published';
  if not found or not app.in_class(e.class_id) then raise exception 'Testi nuk është i arritshëm për ty.' using errcode = 'PT403'; end if;
  select * into a from app.attempts where exam_id = e.id and student_id = auth.uid();
  if not found then
    if e.closes_at is not null and e.closes_at <= now() then return jsonb_build_object('error','Afati për nisjen e këtij testi ka kaluar.'); end if;
    v_dead := least(now() + make_interval(mins => e.minutes), coalesce(e.closes_at, 'infinity'::timestamptz));
    insert into app.attempts(exam_id, student_id, deadline_at) values (e.id, auth.uid(), v_dead) on conflict (exam_id, student_id) do nothing;
    select * into a from app.attempts where exam_id = e.id and student_id = auth.uid();
  end if;
  perform app.finalize_attempt(a.id);
  return app.attempt_view(a.id, 'student');
end $$;
create function public.api_attempt(p_body jsonb) returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare a app.attempts%rowtype;
begin
  perform app.gate(array['student']);
  select * into a from app.attempts where id = (p_body->>'attemptID')::uuid and student_id = auth.uid();
  if not found then raise exception 'Përpjekja nuk është e arritshme.' using errcode = 'PT403'; end if;
  perform app.finalize_attempt(a.id);
  return app.attempt_view(a.id, 'student');
end $$;
create function public.api_answer(p_body jsonb) returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare a app.attempts%rowtype; v_q uuid := (p_body->>'questionID')::uuid; v_val text := coalesce(p_body->>'value',''); v_why text := coalesce(p_body->>'reasoning','');
begin
  perform app.gate(array['student']);
  select * into a from app.attempts where id = (p_body->>'attemptID')::uuid and student_id = auth.uid() for update;
  if not found then raise exception 'Përpjekja nuk është e arritshme.' using errcode = 'PT403'; end if;
  if a.submitted_at is null and a.deadline_at > now() then
    if not exists(select 1 from app.exam_questions where id = v_q and exam_id = a.exam_id) then raise exception 'Pyetje e panjohur.' using errcode = 'PT400'; end if;
    if length(v_val) > 1000 or length(v_why) > 5000 then raise exception 'Teksti është shumë i gjatë.' using errcode = 'PT400'; end if;
    insert into app.attempt_answers(attempt_id, question_id, value, reasoning) values (a.id, v_q, v_val, v_why)
    on conflict (attempt_id, question_id) do update set value = excluded.value, reasoning = excluded.reasoning, saved_at = now();
  end if;
  perform app.finalize_attempt(a.id);
  return app.attempt_view(a.id, 'student');
end $$;
create function public.api_finish(p_body jsonb) returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare a app.attempts%rowtype;
begin
  perform app.gate(array['student']);
  update app.attempts set submitted_at = coalesce(submitted_at, now()) where id = (p_body->>'attemptID')::uuid and student_id = auth.uid() returning * into a;
  if not found then raise exception 'Përpjekja nuk është e arritshme.' using errcode = 'PT403'; end if;
  perform app.finalize_attempt(a.id);
  return app.attempt_view(a.id, 'student');
end $$;
create function public.api_grade(p_body jsonb) returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare v_att uuid := (p_body->>'attemptID')::uuid; v_q uuid := (p_body->>'questionID')::uuid; v_max int; v_pts int := (p_body->>'points')::int;
begin
  perform app.gate(array['teacher']);
  perform app.finalize_attempt(v_att);
  select q.points into v_max from app.attempts a join app.exams e on e.id = a.exam_id join app.exam_questions q on q.exam_id = e.id
   where a.id = v_att and q.id = v_q and e.owner_id = auth.uid() and a.submitted_at is not null;
  if v_max is null then raise exception 'Testi ende nuk mund të vlerësohet ose nuk është i yti.' using errcode = 'PT403'; end if;
  if v_pts not between 0 and v_max then return jsonb_build_object('error','Pikët duhet të jenë mes 0 dhe ' || v_max || '.'); end if;
  update app.attempt_answers set points = v_pts, feedback = left(coalesce(p_body->>'feedback',''),3000) where attempt_id = v_att and question_id = v_q;
  perform app.audit('answer_graded', v_att::text, jsonb_build_object('question', v_q, 'points', v_pts));
  return jsonb_build_object('ok', true);
end $$;
create function public.api_publishResults(p_body jsonb) returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare v_att uuid := (p_body->>'attemptID')::uuid;
begin
  perform app.gate(array['teacher']);
  perform app.finalize_attempt(v_att);
  if not exists(select 1 from app.attempts a join app.exams e on e.id = a.exam_id where a.id = v_att and e.owner_id = auth.uid() and a.submitted_at is not null) then
    raise exception 'Testi ende nuk mund të publikohet ose nuk është i yti.' using errcode = 'PT403'; end if;
  if exists(select 1 from app.attempt_answers aa join app.exam_questions q on q.id = aa.question_id where aa.attempt_id = v_att and q.kind = 'open' and aa.points is null) then
    return jsonb_build_object('error','Vlerëso të gjitha pyetjet e zhvilluara para publikimit.'); end if;
  update app.attempts set results_published_at = coalesce(results_published_at, now()) where id = v_att;
  perform app.audit('results_published', v_att::text);
  return jsonb_build_object('ok', true);
end $$;

-- ---------- eventet ----------
create function public.api_eventCreate(p_body jsonb) returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare v_class uuid := (p_body->>'classID')::uuid; v_title text := trim(coalesce(p_body->>'title','')); v_exam uuid := nullif(p_body->>'examID','')::uuid;
begin
  perform app.gate(array['teacher']);
  if not app.owns_class(v_class) then raise exception 'Nuk ke të drejtë mbi këtë klasë.' using errcode = 'PT403'; end if;
  if v_title = '' or length(v_title) > 200 then return jsonb_build_object('error','Shkruaj titullin.'); end if;
  if v_exam is not null and not exists(select 1 from app.exams where id = v_exam and class_id = v_class and owner_id = auth.uid()) then return jsonb_build_object('error','Testi nuk i përket kësaj klase.'); end if;
  insert into app.events(class_id, owner_id, title, subject, starts_at, note, exam_id)
    values (v_class, auth.uid(), v_title, nullif(p_body->>'subject',''), to_timestamp((p_body->>'date')::double precision), left(coalesce(p_body->>'note',''),2000), v_exam);
  return jsonb_build_object('ok', true);
end $$;
create function public.api_eventUpdate(p_body jsonb) returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare n int;
begin
  perform app.gate(array['teacher']);
  update app.events set title = coalesce(nullif(trim(p_body->>'title'),''), title), note = coalesce(left(p_body->>'note',2000), note),
         starts_at = case when p_body ? 'date' then to_timestamp((p_body->>'date')::double precision) else starts_at end
   where id = (p_body->>'eventID')::uuid and owner_id = auth.uid();
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'Eventi nuk është i yti.' using errcode = 'PT403'; end if;
  return jsonb_build_object('ok', true);
end $$;
create function public.api_eventDelete(p_body jsonb) returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
begin
  perform app.gate(array['teacher']);
  delete from app.events where id = (p_body->>'eventID')::uuid and owner_id = auth.uid();
  return jsonb_build_object('ok', true);
end $$;

-- ---------- progresi (praktikë; nuk është rezultat i verifikuar) ----------
create function public.api_progressGet(p_body jsonb default '{}') returns jsonb language plpgsql stable security definer set search_path = app, pg_temp as $$
begin
  perform app.gate(array['student','parent','teacher']);
  return jsonb_build_object('entries', coalesce((select jsonb_agg(jsonb_build_object('key',key,'value',value,'version',version)) from app.user_progress where user_id = auth.uid()),'[]'));
end $$;
create function public.api_progressPut(p_body jsonb) returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare c jsonb; v_key text; v_cur int; v_ver int; conflicts jsonb := '[]';
begin
  perform app.gate(array['student','parent','teacher']);
  if jsonb_typeof(p_body->'changes') <> 'array' or jsonb_array_length(p_body->'changes') > 1000 then raise exception 'Kërkesë e pavlefshme.' using errcode = 'PT400'; end if;
  for c in select * from jsonb_array_elements(p_body->'changes') loop
    v_key := c->>'key';
    if v_key !~ '^(study|mastered|studentLevel|goal|quiz|lab|homeActivity|solvedTopics|spring|practical|chemMixHistory|game|familyReport)' or length(v_key) > 120 then raise exception 'Ky lloj progresi nuk sinkronizohet.' using errcode = 'PT400'; end if;
    if length((c->'value')::text) > 200000 then raise exception 'Shënim shumë i madh.' using errcode = 'PT400'; end if;
    v_ver := coalesce((c->>'version')::int, 0);
    select version into v_cur from app.user_progress where user_id = auth.uid() and key = v_key for update;
    if coalesce(v_cur,0) <> v_ver then conflicts := conflicts || to_jsonb(v_key); continue; end if;
    insert into app.user_progress values (auth.uid(), v_key, c->'value', v_ver + 1) on conflict (user_id, key) do update set value = excluded.value, version = excluded.version;
  end loop;
  return jsonb_build_object('entries', coalesce((select jsonb_agg(jsonb_build_object('key',key,'value',value,'version',version)) from app.user_progress where user_id = auth.uid()),'[]'), 'conflicts', conflicts);
end $$;

-- ---------- snapshot ----------
create function public.api_snapshot(p_body jsonb default '{}') returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare v_role text; v_classes jsonb; v_members jsonb := '[]'; v_tests jsonb; v_events jsonb; v_results jsonb := '[]'; v_parents jsonb := '[]'; v_children jsonb := '[]'; r record;
begin
  v_role := app.gate(array['student','parent','teacher']);
  select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'level',c.level,'owner',c.owner_id,'code', case when c.owner_id = auth.uid() then c.join_code else '' end,
           'approved', c.owner_id = auth.uid() or app.in_class(c.id) or app.parent_sees_class(c.id)) order by c.name),'[]')
    into v_classes from app.classes c
   where c.owner_id = auth.uid() or app.in_class(c.id) or app.parent_sees_class(c.id) or exists(select 1 from app.class_members m where m.class_id = c.id and m.user_id = auth.uid());
  if v_role = 'teacher' then
    select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'email',p.email,'classID',m.class_id,'approved',m.approved)),'[]')
      into v_members from app.class_members m join app.classes c on c.id = m.class_id and c.owner_id = auth.uid() join app.profiles p on p.id = m.user_id;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'classID',e.class_id,'title',e.title,'minutes',e.minutes,'subject',e.subject,'status',e.status,
           'count',(select count(*) from app.exam_questions q where q.exam_id = e.id)) order by e.created_at desc),'[]')
    into v_tests from app.exams e where e.owner_id = auth.uid() or (e.status = 'published' and (app.in_class(e.class_id) or app.parent_sees_class(e.class_id)));
  select coalesce(jsonb_agg(jsonb_build_object('id',ev.id,'classID',ev.class_id,'owner',ev.owner_id,'title',ev.title,'note',ev.note,'date',app.epoch(ev.starts_at),'subject',ev.subject,'examID',ev.exam_id) order by ev.starts_at),'[]')
    into v_events from app.events ev where app.can_see_class(ev.class_id);
  for r in select a.id, e.owner_id, a.student_id from app.attempts a join app.exams e on e.id = a.exam_id loop
    if r.owner_id = auth.uid() then perform app.finalize_attempt(r.id); v_results := v_results || app.attempt_view(r.id,'teacher');
    elsif r.student_id = auth.uid() then perform app.finalize_attempt(r.id); v_results := v_results || app.attempt_view(r.id,'student');
    elsif v_role = 'parent' and exists(select 1 from app.parent_links pl where pl.parent_id = auth.uid() and pl.child_id = r.student_id) then
      perform app.finalize_attempt(r.id); v_results := v_results || app.attempt_view(r.id,'parent');
    end if;
  end loop;
  if v_role = 'student' then
    select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'email',p.email)),'[]') into v_parents from app.parent_links pl join app.profiles p on p.id = pl.parent_id where pl.child_id = auth.uid();
  elsif v_role = 'parent' then
    select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'email',p.email)),'[]') into v_children from app.parent_links pl join app.profiles p on p.id = pl.child_id where pl.parent_id = auth.uid();
  end if;
  return jsonb_build_object('classes',v_classes,'members',v_members,'tests',v_tests,'events',v_events,'results',v_results,'parents',v_parents,'children',v_children);
end $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname like 'api\_%'
  loop execute format('revoke all on function %s from public, anon', f.sig); execute format('grant execute on function %s to authenticated', f.sig); end loop;
end $$;
