# Konfigurimi i Supabase — hap pas hapi (për fillestarë)

> **Kujdes:** asgjë këtu nuk është provuar kundër një projekti real. Emrat e menuve te dashboard-i i Supabase ndryshojnë herë pas here; nëse një menu nuk gjendet, përdor kërkimin e dashboard-it. Dokumentacioni zyrtar: https://supabase.com/docs/guides/auth (Auth, MFA, SMTP) dhe https://supabase.com/docs/guides/api.

## 0. Çfarë duhet të dish para se të nisësh
- **Kosto:** plani falas mjafton për provë. Mos kalo te plan me pagesë pa vendim të përbashkët. Projektet falas mund të pezullohen kur nuk përdoren dhe nuk kanë rezerva të garantuara; për përdorim shkollor real kontrollo kushtet aktuale të planit.
- **Email:** serveri i integruar i Supabase dërgon vetëm te anëtarët e ekipit të projektit dhe me kufi shumë të ulët (disa email në orë). Për nxënës e prindër realë **duhet SMTP i jashtëm (custom SMTP)** nga një ofrues email (shumë kanë plan falas me kufi; kontrollo çmimin përpara se ta aktivizosh). Për provën e parë, shto emailet e testit si anëtarë të ekipit të projektit.
- **Të dhëna të të miturve:** zgjidh rajon në Evropë dhe rishiko kushtet e privatësisë me shkollën/prindërit para përdorimit real.
- **Një sistem i vetëm:** aplikacioni përdor Supabase vetëm kur Info.plist ka `SupabaseURL` dhe `SupabaseKey`; përndryshe përdor serverin Python (`Server/`). Mos i përdor të dyja për të njëjtat llogari.

## 1. Krijo projektin
1. Hyr në https://supabase.com me llogari të shkollës (jo personale, nëse është e mundur) → **New project**.
2. Emri p.sh. `sciencequest-prove`, **fjalëkalim të fortë për bazën e të dhënave** (ruaje në password manager; aplikacioni nuk e përdor), rajon në BE, plan **Free**.
3. Prit derisa projekti të jetë gati.

## 2. Ekzekuto migrimet SQL
1. Menuja majtas → **SQL Editor** → **New query**.
2. Hap `Supabase/migrations/0001_auth_roles.sql`, kopjo gjithë përmbajtjen, ngjite → **Run**. Duhet të dalë "Success". Nëse del gabim, ndalo dhe më dërgo mesazhin e saktë (skedari nuk është provuar).
3. E njëjta gjë me `0002_school.sql` (pasi 0001 ka kaluar).
4. Pastaj `0003_mfa_email_delete.sql`: 2FA i detyrueshëm në çdo hyrje (`require_mfa`, parazgjedhja `all`), një email = një llogari (edhe me pika/+etiketë), fshirja e klasave dhe e testeve nga pronari. Nëse del gabimi "Ka llogari të dyfishuara", fshi llogaritë e provës te **Authentication → Users** dhe ekzekuto përsëri.
5. Pastaj `0004_email_2fa.sql` (kodi me email në çdo hyrje) dhe `0005_email_key_exact.sql`: emaili krahasohet vetëm pa hapësira dhe pa dallim shkronjash të mëdha/vogla; pikat dhe +etiketa NUK hiqen (zëvendëson rregullin e 0003).
6. Pastaj `0006_phase2_submissions.sql`: mbyllja e testit dorëzon menjëherë përpjekjet e hapura; kova private **submissions** (25 MB/skedar, 10 skedarë/test, vetëm PDF, Word, tekst, foto, audio, video) me rregulla Storage që kontrollohen në server; `api_snapshot` kthen vetëm përpjekjet e përdoruesit.
Funksionet `api_*` janë vetë "backend-i": nuk ka Edge Functions për t'u publikuar.

## 3. Kodi privat i regjistrimit të mësuesit
Te **SQL Editor** ekzekuto (zëvendëso me kodin 5-shifror që ke vendosur; mos e shkruaj në Git, në dokument ose në aplikacion):
```sql
select app.admin_set_teacher_code('KODI-5-SHIFROR');
```
Kodi ruhet vetëm si hash me kripë dhe nuk mund të lexohet më. Për ta ndërruar, ekzekuto përsëri komandën. Kufizimi: 5 gabime për llogari në 24 orë dhe 40 gabime në orë për të gjithë.
**Kufi i qëndrueshëm:** kodi është i përbashkët; kush e merr mund të regjistrohet mësues. Për kontroll real aktivizo miratimin nga administratori:
```sql
select app.admin_set_setting('teacher_approval_required','true');
-- pastaj, pas çdo regjistrimi mësuesi:
select app.admin_review_teacher('mesuesi@shkolla.example', true);   -- false = refuzo
```
Pa miratim të aktivizuar, çdo mësues me kodin hyn menjëherë. Ky vendim është i yti; **nuk është aktivizuar si parazgjedhje**.
Nga 0003, 2FA është i detyrueshëm për të gjithë (`require_mfa` = `all`). Për vetëm mësuesit: `select app.admin_set_setting('require_mfa','teacher');`; për ta lënë opsional: `'none'`. Serveri e zbaton rregullin, jo aplikacioni.
Veçori e vjetër (zëvendësohet nga `require_mfa`): `select app.admin_set_setting('require_teacher_mfa','true');` e bën 2FA të detyrueshme për mësuesit (ata duhet ta konfigurojnë para se të përdorin funksionet e mësuesit; përdoruesit pa 2FA do të bllokohen derisa ta aktivizojnë — aktivizoje vetëm pasi t'i kenë konfiguruar).

## 4. Verifikimi i emailit, reset-i i fjalëkalimit dhe 2FA
1. **Authentication → Sign In / Providers → Email:** mbaje **Enable Email provider** ndezur dhe **Confirm email** ndezur (kjo është verifikimi i emailit gjatë regjistrimit; nuk është 2FA). Vendos fjalëkalim minimal 10 karaktere.
2. **Kodi në vend të lidhjes (rekomandim):** aplikacioni pret kod 6-shifror nga emaili, kështu që nuk duhen deep links. Te **Authentication → Emails → Templates** ndrysho dy shabllonet:
   - *Confirm signup* — trupi p.sh.: `<p>Kodi i konfirmimit: <b>{{ .Token }}</b></p>`
   - *Reset password* — trupi p.sh.: `<p>Kodi për fjalëkalim të ri: <b>{{ .Token }}</b></p>`
   (Redaktimi i shablloneve mund të kërkojë SMTP të jashtëm të aktivizuar.)
3. **Afati i kodit:** parazgjedhja është rreth 1 orë (parametri OTP expiry te cilësimet e Email provider). Mund ta ulësh. Kodi i skaduar jep mesazh te aplikacioni dhe butoni **Ridërgo kodin** kërkon një të ri. Supabase lejon një kërkesë për përdorues në çdo 60 sekonda.
4. **SMTP:** **Authentication → Emails → SMTP Settings** → **Enable custom SMTP** me të dhënat e ofruesit që zgjedh (host, port, përdorues, fjalëkalim SMTP, adresë dërguesi). Mos vendos këto të dhëna në aplikacion ose Git.
5. **2FA (MFA):** TOTP me aplikacion autentikimi është i aktivizuar si parazgjedhje në projektet Supabase dhe nuk ka kosto shtesë sipas dokumentacionit. Kontrollo te **Authentication → Sign In / Providers** (seksioni Multi-Factor) që "TOTP" të jetë "Enabled" për regjistrim dhe verifikim. SMS/telefon nuk përdoret.
6. **Redirect/deep links:** me rrjedhën me kod nuk nevojiten. Nëse më vonë kalon te lidhjet në email, shto URL-në e aplikacionit te **Authentication → URL Configuration → Redirect URLs** dhe një URL scheme te Xcode.

## 5. URL-ja dhe çelësi publik për aplikacionin
1. Dashboard → **Project Settings → API** (ose butoni **Connect**).
2. Kopjo **Project URL** (`https://xxxx.supabase.co`) dhe çelësin **publishable** (fillon me `sb_publishable_`) ose **anon** (JWT i vjetër).
3. Hap `App/Info.plist` në Xcode dhe plotëso `SupabaseURL` dhe `SupabaseKey`.
   - Këta dy nuk janë sekret (janë të destinuar të jenë publikë; RLS/funksionet i mbrojnë të dhënat).
   - **Kurrë** mos vendos `service_role` ose çelës që fillon me `sb_secret_`: aplikacioni e refuzon dhe injoron Supabase-in, por mos e fut aty fare.
4. Nëse nuk i plotëson, aplikacioni punon me serverin Python si më parë.

## 6. Administratori
Nuk ka tabelë administratorësh. "Administrator" është kushdo që ka qasje në projektin Supabase (rolet e organizatës: **Settings → Team / Organization**). Ai ekzekuton komandat e seksionit 3 te SQL Editor. Shto vetëm njerëz të besuar; ata shohin të gjitha të dhënat. Rekomandim: 2FA për llogaritë e Supabase të administratorëve.
Nëse dikush humb faktorin e dytë: te SQL Editor `select app.admin_reset_mfa('email@shembull.al');` heq faktorin dhe mbyll seancat; në hyrjen tjetër konfiguron një faktor të ri. Aplikacioni nuk ka anashkalim të 2FA.

## 7. Prova me një mësues, dy nxënës dhe një prind (pajisje të ndryshme)
Përgatitje: kodi i mësuesit vendosur (§3), custom SMTP ose emailet e provës si anëtarë ekipi, Info.plist i plotësuar, aplikacioni i ndërtuar në Mac (mësues), iPhone/iPad ose Simulator (nxënës/prind).
1. **Mësuesi (Mac):** ekrani *Mësues* → Regjistrohu me email, fjalëkalim, kodin → merr kodin e emailit → konfirmo. Duhet të hapet si mësues. Provo kodin e gabuar 6 herë (llogari tjetër): duhet të bllokohet pas 5.
2. Krijo klasën (p.sh. XI B). Kopjo kodin e klasës.
3. **Nxënësi A (iPhone):** ekrani *Nxënës / Prind* → Regjistrohu si Nxënës → kodi email → te Shkolla ime futi kodin e klasës. **Nxënësi B** te klasë tjetër ose pa klasë.
4. Mësuesi miraton nxënësin A. Nxënësi B nuk duhet të shohë asgjë nga klasa.
5. **Prindi (iPad/pajisje e tretë):** regjistrohu si Prind. Nxënësi A te "Lidh prindin" krijon kod 15-minutësh; prindi e vendos. Prindi duhet të shohë testet/eventet e A, jo të B.
6. Mësuesi krijon test (draft, pastaj publiko; një pyetje alternativash, një numerike, një e zhvilluar). Kontrollo që draft-i **nuk** shfaqet te nxënësi; pas publikimit shfaqet te A dhe te prindi (pa çelësa).
7. A e nis testin, përgjigjet, del dhe rihapet: koha nuk rinis. Mbyll WiFi gjatë testit: përgjigjja mbetet në pajisje; kujto që afati nuk zgjatet. Dorëzo.
8. Mësuesi hap Vlerësimi: sheh automatiket paraprake, vlerëson të zhvilluarën, shkruan koment, shtyp **Publiko rezultatin**. Vetëm atëherë A dhe prindi shohin pikët dhe komentin. Dorëzimi i dytë dhe ndryshimi pas afatit duhet të dështojnë.
9. Mësuesi krijon event të lidhur me testin; shfaqet te A dhe prindi në pajisjet e tyre; ndrysho dhe anulo.
10. **2FA:** te Profili → Siguria → Konfiguro 2FA, skano QR, aktivizo. Dil dhe hyr: kërkohet kodi 6-shifror. Provo kod të gabuar. Provo çaktivizimin (kërkon fjalëkalim + kod).
11. **Rikuperimi:** Harrove fjalëkalimin → kod me email → fjalëkalim i ri (me 2FA kërkohet edhe faktori i dytë).
Shëno çdo hap që dështon (mesazhin e saktë) dhe dërgoje; asnjë nga këto nuk është provuar ende.

## 8. Kodi me email në çdo hyrje (faktori i dytë, i detyruar nga serveri)
Nga versioni 8.2 faktori i dytë parazgjedhës është një kod 6-shifror që vjen te emaili i llogarisë në çdo hyrje (Gmail, Yahoo, etj.). Kodi ruhet vetëm si hash, lidhet me seancën dhe serveri nuk lejon veprime pa e verifikuar. Aplikacioni i autentikimit (TOTP) mbetet opsion.
1. **SQL:** ekzekuto `0004_email_2fa.sql` te SQL Editor (pas 0001–0003). Parazgjedhja bëhet `mfa_method = email`.
2. **Secrets (një herë):** Supabase → **Edge Functions → Secrets** (ose Project Settings → Edge Functions) → shto `SMTP_USER` (adresa Gmail e dërguesit) dhe `SMTP_PASS` (fjalëkalimi i aplikacionit të Google; i njëjti lloj si te SMTP i Auth). Mos i shkruaj në Git.
3. **Funksioni:** **Edge Functions → Deploy a new function → Via Editor**, emri saktësisht `send-login-code`. Ngjit gjithë përmbajtjen e `Supabase/functions/send-login-code/index.ts` dhe shtyp Deploy. Te cilësimet e funksionit **fik** "Enforce JWT verification" (funksioni vetë e verifikon token-in te Supabase Auth); në projekte me çelësa të rinj kontrolli i vjetër i JWT mund ta refuzojë kërkesën.
4. **Kufijt:** 1 kod në 30 sekonda dhe 10 në orë për përdorues; kodi vlen 10 minuta; 5 gabime e fshijnë kodin. Gmail lejon rreth 500 email në ditë (kodet e hyrjes shtohen te ato të regjistrimit).
5. **Kthim prapa:** `select app.admin_set_setting('mfa_method','totp');` kthen te aplikacioni i autentikimit. Nëse funksioni nuk është i vendosur ende, aplikacioni tregon "nuk është konfiguruar" dhe hyrja ndalon: kthe `totp` ose vendose funksionin.
6. **Kufi i njohur:** kush ka edhe fjalëkalimin edhe qasje te emaili hyn; kjo është natyra e kodit me email (TOTP e kalon këtë rast). Seanca e ruajtur te Keychain rikthehet pa kod të ri derisa të skadojë.
