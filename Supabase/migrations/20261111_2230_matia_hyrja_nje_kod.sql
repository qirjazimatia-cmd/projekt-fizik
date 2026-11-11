-- Hyrja me një kod të vetëm emaili (kërkesa e Matias).
-- Më parë, pas regjistrimit përdoruesi merrte dy kode radhazi: kodin e konfirmimit të emailit dhe pastaj kodin e hyrjes.
-- Tani: një seancë e krijuar me kod emaili (konfirmimi i regjistrimit, rikuperimi i fjalëkalimit) e ka provuar tashmë
-- aksesin te emaili, prandaj vlen si faktori i dytë. Hyrja me fjalëkalim vazhdon të kërkojë një kod emaili (vetëm një).
-- Rregulli zbatohet në server (JWT amr), jo në aplikacion.
create or replace function app.session_2fa_ok() returns boolean
language sql stable security definer set search_path = app, auth, pg_temp as $$
  select coalesce(auth.jwt()->>'aal','aal1') = 'aal2'
      or exists(select 1 from app.session_2fa s
                where s.user_id = auth.uid() and s.session_id = nullif(auth.jwt()->>'session_id','')::uuid)
      or exists(select 1 from jsonb_array_elements(coalesce(auth.jwt()->'amr','[]'::jsonb)) a
                where a->>'method' in ('otp','recovery','magiclink','email/signup'))
$$;
