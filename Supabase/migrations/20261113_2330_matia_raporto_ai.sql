-- Don Bosko Connect · Raporto përgjigjen e Bosko AI (Matia, #70).
-- Google Play (AI-Generated Content) dhe Apple 1.2: përdoruesi duhet të mund të raportojë brenda app-it një përgjigje të papërshtatshme
-- ose të gabuar të AI. Raportet ruhen këtu që shkolla t'i kontrollojë (Supabase → Table Editor → app.ai_reports) dhe të përmirësojë udhëzimet.
-- Ruhen vetëm pyetja e fundit dhe përgjigja (jo e gjithë biseda), për privatësi.

create table if not exists app.ai_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  reason text not null check (reason in ('wrong', 'inappropriate', 'other')),
  question text not null default '' check (length(question) <= 2000),
  answer text not null check (length(answer) between 1 and 6000),
  status text not null default 'new' check (status in ('new', 'reviewed'))
);
create index if not exists ai_reports_created_idx on app.ai_reports(created_at desc);
alter table app.ai_reports enable row level security;

create or replace function public.api_aiReport(p_body jsonb) returns jsonb
language plpgsql security definer set search_path = app, pg_temp as $$
declare
  v_reason text := coalesce(p_body->>'reason', 'other');
  v_answer text := left(trim(coalesce(p_body->>'answer', '')), 6000);
  v_question text := left(trim(coalesce(p_body->>'question', '')), 2000);
begin
  perform app.gate(array['student','parent','teacher']);
  if v_reason not in ('wrong', 'inappropriate', 'other') then v_reason := 'other'; end if;
  if v_answer = '' then return jsonb_build_object('error', 'Mungon përgjigjja që po raporton.'); end if;
  if not app.hit('aireport:' || auth.uid(), 20, interval '1 day') then
    return jsonb_build_object('error', 'Ke dërguar shumë raporte sot. Faleminderit, i kemi marrë!');
  end if;
  insert into app.ai_reports(user_id, reason, question, answer) values (auth.uid(), v_reason, v_question, v_answer);
  perform app.audit('ai_report', auth.uid()::text, jsonb_build_object('reason', v_reason));
  return jsonb_build_object('ok', true);
end $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname = 'api_aireport'
  loop execute format('revoke all on function %s from public, anon', f.sig); execute format('grant execute on function %s to authenticated', f.sig); end loop;
end $$;
