-- Fshirja e skedarëve jetimë në Storage (#13).
-- Supabase nuk lejon fshirjen e skedarëve direkt nga SQL; prandaj SQL vetëm i gjen, dhe Edge Function `storage-cleanup`
-- (me service_role) i fshin përmes Storage API.
--  · submissions/<attempt_id>/<question_id>/<skedar>: jetim kur tentativa nuk ekziston më (testi, klasa ose llogaria u fshi).
--  · projects/<team_id>/<version_id>/<skedar>: jetim kur versioni ose ekipi nuk ekziston më (projekti ose llogaria u fshi).
-- Funksioni nuk është i arritshëm nga app-i (vetëm service_role).

create or replace function public.internal_storage_orphans(p_limit int default 500)
returns table(bucket text, name text)
language sql stable security definer set search_path = app, storage, pg_temp as $$
  select o.bucket_id::text, o.name::text from storage.objects o
   where o.bucket_id = 'submissions'
     and (public.sq_attachment_parts(o.name)).attempt_id is not null
     and not exists(select 1 from app.attempts a where a.id = (public.sq_attachment_parts(o.name)).attempt_id)
  union all
  select o.bucket_id::text, o.name::text from storage.objects o
   where o.bucket_id = 'projects'
     and (public.sq_project_parts(o.name)).version_id is not null
     and not exists(select 1 from app.project_versions v where v.id = (public.sq_project_parts(o.name)).version_id
                                                          and v.team_id = (public.sq_project_parts(o.name)).team_id)
  limit greatest(1, least(coalesce(p_limit, 500), 1000))
$$;

revoke all on function public.internal_storage_orphans(int) from public, anon, authenticated;
grant execute on function public.internal_storage_orphans(int) to service_role;
