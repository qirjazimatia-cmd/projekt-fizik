-- ScienceQuest 8.4 · Faza 2: mbyllja e testit, dorëzime me skedarë, snapshot më i shpejtë.
-- Varet nga 0001–0005. Mund të ekzekutohet përsëri (idempotent).

-- 1) Mbyllja e testit ndal menjëherë përpjekjet në zhvillim -------------------------------------------
-- Më parë: status = 'closed' nuk ndalte nxënësit që kishin nisur; vazhdonin deri në afatin e tyre personal.
create or replace function public.api_exampublish(p_body jsonb)
returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
declare v_exam uuid := (p_body->>'examID')::uuid; v_close boolean := coalesce((p_body->>'close')::boolean, false); n int; r record;
begin
  perform app.gate(array['teacher']);
  update app.exams set status = case when v_close then 'closed' else 'published' end, published_at = coalesce(published_at, now())
   where id = v_exam and owner_id = auth.uid();
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'Testi nuk është i yti.' using errcode = 'PT403'; end if;
  if v_close then
    -- Afati i çdo përpjekjeje të hapur bëhet "tani"; ruhen përgjigjet që kanë mbërritur deri në këtë çast.
    for r in update app.attempts set deadline_at = least(deadline_at, now())
              where exam_id = v_exam and submitted_at is null returning id loop
      perform app.finalize_attempt(r.id);
    end loop;
  end if;
  perform app.audit('exam_status', v_exam::text, jsonb_build_object('close', v_close));
  return jsonb_build_object('ok', true);
end $$;

-- 2) Dorëzime me skedarë (Supabase Storage, kovë private) ----------------------------------------------
-- Rruga e skedarit: <attemptID>/<questionID>/<8 shenja>-<emri>. Asnjë skedar nuk është publik.
-- Kufijtë: 25 MB për skedar, deri në 10 skedarë për përpjekje, vetëm llojet e listuara.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('submissions', 'submissions', false, 26214400, array[
  'application/pdf', 'text/plain',
  'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'image/jpeg', 'image/png', 'image/heic', 'image/heif',
  'audio/mpeg', 'audio/mp4', 'audio/x-m4a', 'audio/m4a', 'audio/aac',
  'video/mp4', 'video/quicktime'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- Ndihmës për rregullat e Storage. Janë te `public` sepse rregullat ekzekutohen si `authenticated`,
-- i cili nuk ka akses te skema `app`. Kthejnë vetëm true/false për përdoruesin e kyçur.
create or replace function public.sq_attachment_parts(p_name text, out attempt_id uuid, out question_id uuid)
language plpgsql immutable set search_path = pg_catalog as $$
begin
  if p_name !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[^/]{1,160}$' then
    attempt_id := null; question_id := null; return;
  end if;
  attempt_id := split_part(p_name, '/', 1)::uuid;
  question_id := split_part(p_name, '/', 2)::uuid;
end $$;

create or replace function public.sq_can_upload(p_name text) returns boolean
language plpgsql stable security definer set search_path = app, storage, pg_temp as $$
declare p record;
begin
  select * into p from public.sq_attachment_parts(p_name);
  if p.attempt_id is null or app."current_role"() is distinct from 'student' then return false; end if;
  return exists(
      select 1 from app.attempts a
        join app.exams e on e.id = a.exam_id
        join app.exam_questions q on q.exam_id = e.id and q.id = p.question_id
       where a.id = p.attempt_id and a.student_id = auth.uid()
         and a.submitted_at is null and a.deadline_at > now() and e.status <> 'closed')
    and (select count(*) from storage.objects o where o.bucket_id = 'submissions' and o.name like p.attempt_id::text || '/%') < 10;
end $$;

create or replace function public.sq_can_read(p_name text) returns boolean
language plpgsql stable security definer set search_path = app, pg_temp as $$
declare p record;
begin
  select * into p from public.sq_attachment_parts(p_name);
  if p.attempt_id is null or app."current_role"() is null then return false; end if;
  return exists(
    select 1 from app.attempts a join app.exams e on e.id = a.exam_id
     where a.id = p.attempt_id
       and (a.student_id = auth.uid()
            or e.owner_id = auth.uid()
            or (a.results_published_at is not null and exists(
                  select 1 from app.parent_links pl where pl.parent_id = auth.uid() and pl.child_id = a.student_id))));
end $$;

revoke all on function public.sq_attachment_parts(text) from public, anon;
revoke all on function public.sq_can_upload(text) from public, anon;
revoke all on function public.sq_can_read(text) from public, anon;
grant execute on function public.sq_attachment_parts(text) to authenticated;
grant execute on function public.sq_can_upload(text) to authenticated;
grant execute on function public.sq_can_read(text) to authenticated;

drop policy if exists "sq_submissions_insert" on storage.objects;
drop policy if exists "sq_submissions_select" on storage.objects;
drop policy if exists "sq_submissions_delete" on storage.objects;
-- Pa rregull UPDATE: skedari nuk mbishkruhet; nxënësi e fshin dhe ngarkon një të ri ndërsa testi është i hapur.
create policy "sq_submissions_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'submissions' and public.sq_can_upload(name));
create policy "sq_submissions_select" on storage.objects for select to authenticated
  using (bucket_id = 'submissions' and public.sq_can_read(name));
create policy "sq_submissions_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'submissions' and public.sq_can_upload(name));

-- attempt_view kthen edhe listën e skedarëve (prindi i sheh vetëm pas publikimit të rezultatit).
create or replace function app.attempt_files(p_attempt uuid) returns jsonb
language sql stable security definer set search_path = app, storage, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'path', o.name,
           'question', split_part(o.name, '/', 2),
           'name', regexp_replace(split_part(o.name, '/', 3), '^[0-9a-zA-Z]{8}-', ''),
           'size', coalesce((o.metadata->>'size')::bigint, 0),
           'mime', coalesce(o.metadata->>'mimetype', ''),
           'uploaded', extract(epoch from o.created_at)) order by o.created_at), '[]')
    from storage.objects o where o.bucket_id = 'submissions' and o.name like p_attempt::text || '/%'
$$;
revoke all on function app.attempt_files(uuid) from public, anon, authenticated;

create or replace function app.attempt_view(p_attempt uuid, p_mode text)
returns jsonb language plpgsql stable security definer set search_path = app, pg_temp as $$
declare a app.attempts%rowtype; e app.exams%rowtype; v_pub boolean; v_status text; v_final int; v_prelim int; v_max int;
        v_q jsonb; v_ans jsonb; v_fb jsonb := '{}'; v_rev jsonb := null; v_grades jsonb := null; v_student text; v_class text; v_files jsonb;
begin
  select * into a from app.attempts where id = p_attempt;
  select * into e from app.exams where id = a.exam_id;
  v_pub := a.results_published_at is not null;
  select sum(points) into v_max from app.exam_questions where exam_id = e.id;
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'prompt',q.prompt,'kind',q.kind,'unit',q.unit,'points',q.points,'tolerance',q.tolerance,'options',q.options) order by q.position),'[]')
    into v_q from app.exam_questions q where q.exam_id = e.id;
  if p_mode = 'parent' and not v_pub then v_ans := '{}'; v_files := '[]';
  else
    select coalesce(jsonb_object_agg(question_id, jsonb_build_object('value',value,'reasoning',reasoning)),'{}') into v_ans from app.attempt_answers where attempt_id = a.id;
    v_files := app.attempt_files(a.id);
  end if;
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
    'maximum',coalesce(v_max,0),'feedback',v_fb,'student',v_student,'className',v_class,'reviewQuestions',v_rev,'grades',v_grades,
    'files', v_files);
end $$;

-- 3) Snapshot: vetëm përpjekjet që i përkasin përdoruesit (më parë përshkonte të gjitha përpjekjet e shkollës) ----
create or replace function public.api_snapshot(p_body jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = app, pg_temp as $$
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

-- 4) Siguria: search_path i fiksuar (paralajmërim i Supabase Advisor).
alter function app.epoch(timestamptz) set search_path = pg_catalog;
alter function app.parse_number(text) set search_path = pg_catalog;
