# Supabase për ScienceQuest

Skedarët: `migrations/0001_auth_roles.sql`, `migrations/0002_school.sql`. Udhëzimet hap pas hapi: **../SUPABASE-SETUP.md**.

**Statusi:** SQL-i dhe klienti Swift u shkruan, por **nuk janë ekzekutuar** (pa PostgreSQL, Supabase dhe Xcode në mjedisin e punës). Asnjë lidhje reale nuk është provuar.

## Modeli i sigurisë
- Tabelat jetojnë te skema `app`, që API-ja e Supabase nuk e ekspozon. RLS është aktiv dhe **nuk ka politika për klientin**: klienti nuk lexon dhe nuk shkruan asnjë tabelë direkt.
- Klienti thërret vetëm funksionet `public.api_*` (`security definer`). Secili thërret `app.gate(roli)`, që kërkon: seancë e vlefshme, email i konfirmuar, rol i caktuar, mësues aktiv (dhe i miratuar, nëse kërkohet) dhe nivel `aal2` kur përdoruesi ka 2FA.
- Roli ruhet te `app.profiles` dhe caktohet vetëm nga funksionet `api_chooseRole` / `api_redeemTeacherCode`, vetëm nga gjendja `unassigned` dhe vetëm një herë. `user_metadata` nuk përdoret kurrë.
- Kodi i mësuesit ruhet vetëm si hash me kripë te `app.secrets`. Vendoset nga administratori te SQL Editor; nuk është në repository.
- Çelësat e testeve (`exam_keys`) nuk i kthehen kurrë nxënësit ose prindit.
- Afati: `deadline_at` llogaritet me `now()` të serverit; `api_answer` nuk ruan asgjë pas afatit ose dorëzimit.

## Kufijtë që mbeten
- Kodi i mësuesit është i përbashkët: kush e merr mund të regjistrohet mësues. Zgjidhja: `select app.admin_set_setting('teacher_approval_required','true');` dhe miratim me `app.admin_review_teacher(...)`.
- Variantet numerike të gjeneruara (si te `server.py`) **nuk mbështeten** te Supabase; mësuesi shkruan pyetjet vetë.
- `api_snapshot` kalon mbi të gjitha përpjekjet e përdoruesit: mirë për klasa shkollore, jo për mijëra përpjekje (duhet faqosje).
- Emailet e testeve të nxënësve shihen nga mësuesi i klasës (nevojitet për korrigjim).
