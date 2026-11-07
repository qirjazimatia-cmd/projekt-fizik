-- ScienceQuest 8.3 · Një email = një llogari, pa rregulla të supozuara të Gmail-it.
-- Më parë app.email_key hiqte pikat dhe +etiketën (p.sh. a.b+x@gmail.com = ab@gmail.com). Kjo binte ndesh me kërkesën:
-- "Normalizo emailin me heqjen e hapësirave anësore dhe trajtim të njëtrajtshëm të shkronjave; mos hiq pika ose pjesë të adresës".
-- Tani çelësi është vetëm lower(trim(email)), i njëjti rregull që zbaton Supabase Auth.
-- I sigurt për të dhënat ekzistuese: çelësat e rinj janë më të veçantë se të vjetrit, ndaj indeksi unik nuk mund të shkelet.
-- Kontrolli më poshtë ndalon migrimin (pa ndryshuar gjë) nëse megjithatë gjendet ndonjë përplasje.

create or replace function app.email_key(p_email text) returns text
language sql immutable set search_path = pg_catalog as $$
  select lower(btrim(p_email))
$$;

do $$
begin
  if exists (select 1 from app.profiles group by lower(btrim(email)) having count(*) > 1) then
    raise exception 'Ka profile me të njëjtin email (pa marrë parasysh shkronjat e mëdha). Shqyrtoji te Authentication → Users para se të vazhdosh.';
  end if;
end $$;

update app.profiles set email_key = app.email_key(email) where email_key is distinct from app.email_key(email);
