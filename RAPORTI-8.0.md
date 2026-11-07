# Raporti i fazës 8 — autentikim, Supabase, klasa, teste, evente

**Mjedisi:** Linux, Python 3.12. **Pa Swift/Xcode, pa PostgreSQL, pa llogari Supabase.** Prandaj:
- **Swift nuk u kompilua.** Janë kontrolluar vetëm balancat e kllapave dhe përputhja e veprimeve Swift–SQL.
- **SQL nuk u ekzekutua.** Mund të ketë gabime sintakse ose logjike.
- **Asnjë lidhje me Supabase nuk u provua.** Sinkronizimi me Supabase **nuk është aktiv** derisa ti të konfigurosh projektin.
- Shënim: folderi i punës u humb mes seancave; kodi Supabase u rishkrua nga e para.

## Implementuar (kod i shkruar, i pa-provuar kundër Supabase)
| Kërkesa | Si |
| --- | --- |
| Dy hyrje | `CloudAccessScreen`: "Nxënës / Prind" dhe "Mësues" (Accounts.swift). Ndarja është vetëm për qartësi. |
| Një email, një llogari, një rol | `app.profiles.role` fillon `unassigned`; ndryshon vetëm nga `api_chooseRole`/`api_redeemTeacherCode`, vetëm një herë; klienti nuk ka politikë shkrimi. `user_metadata` nuk përdoret. |
| Kodi i mësuesit | Vetëm hash me kripë te `app.secrets`; vendoset nga administratori (SUPABASE-SETUP §3). Nuk është në kod, Git ose ZIP. 5 gabime/llogari/24h + 40 gabime/orë global; mesazh i njëjtë gabimi. |
| Kufiri i kodit të përbashkët | Shpjeguar në UI, README dhe këtu. Miratimi nga administratori ekziston (`teacher_approval_required`), **i çaktivizuar si parazgjedhje**. |
| Verifikimi i emailit | Supabase Auth, kod 6-shifror (shablloni `{{ .Token }}`); ridërgim; kod i skaduar → mesazh + kod i ri. Serveri refuzon çdo veprim pa `email_confirmed_at`. |
| 2FA | TOTP real i Supabase MFA: konfigurim me QR, verifikim, çaktivizim me fjalëkalim + kod. Serveri kërkon `aal2` kur ka faktor të verifikuar. Nuk ka "kod emaili si MFA". Rikuperim fjalëkalimi me email (me 2FA kërkon edhe faktorin). |
| Sesioni | Access/refresh token në Keychain (`SessionVault`), rinovim automatik me një rinovim të vetëm. |
| Klasat, prindi | Funksionet `api_class*`, `api_approve`, `api_familyCode/Join`, `unlink*`. Prindi lidhet vetëm me kod 15-minutësh nga nxënësi, mund të shkëputet nga të dyja palët. |
| Testet | Draft → publikuar → mbyllur; llojet number/text/choice/open; afat nisjeje; koha e nisjes/afati nga serveri; një përpjekje për nxënës; pa përgjigje pas afatit/dorëzimit; çelësat vetëm në server; statuse "në zhvillim / në korrigjim / vlerësuar"; pikë automatike paraprake të ndara nga nota e publikuar. |
| Korrigjimi | Automatik + manual/i përzier (`api_grade`, pikë të pjesshme, koment, `api_publishResults`). |
| Eventet | Krijim/ndryshim/anulim, lidhje reale me test, shfaqje te nxënësit e klasës dhe prindërit e lidhur. |
| Audit | `app.audit_log` për rol, publikim, vlerësim, lidhje prindi (pa sekrete/kode). |
| Progres offline | I pandryshuar (lokal + sinkronizim me version). Progresi i praktikës ruhet veçmas nga rezultatet e testeve. Importi nga llogaria lokale nuk krijon nota. |

## Çfarë u provua realisht
- 17 teste Python të serverit të vjetër: **OK** (ri-ekzekutuar; kodi i mësuesit u hoq nga testi).
- `Tests/check_supabase_contract.py`: PASS — 27 veprime Swift kanë funksion SQL, 16 tabela `app` me RLS, pa politika klienti. **Kontroll statik, jo provë e SQL.**
- `check_content.py`, `check_no_secrets.sh`: pa gjetje.
- **Nuk u provua:** regjistrimi, emaili i pakonfirmuar, kodi i gabuar/kufizimi, roli i gabuar, 2FA, aksesi mes klasave, publikimi, dorëzimi, korrigjimi, shfaqja te prindi. Të gjitha këto janë plani te SUPABASE-SETUP §7 dhe pritet ekzekutimi yt.

## Vendime dhe kufij që duhet t'i dish
1. Testet vetëm me pyetje automatike publikohen te nxënësi menjëherë pas dorëzimit; me pyetje "e zhvilluar" publikon mësuesi. Mund ta ndryshojmë.
2. **Interneti ndërpritet gjatë testit:** përgjigjet mbahen si draft lokal; afati i serverit nuk zgjatet. Çfarë mbërriti para afatit llogaritet.
3. Variantet numerike të gjeneruara **nuk ekzistojnë** te Supabase (vetëm te serveri Python).
4. Pa rrjet në nisje aplikacioni nuk rikthen seancën (praktika pa llogari punon).
5. Njoftime push: nuk ka. Kalendari përditësohet kur hapet/rifreskohet.
6. Mësuesi shikon emailet e nxënësve të klasës së vet (për korrigjim). `api_snapshot` s'ka faqosje.
7. Emaili: serveri i integruar i Supabase s'mjafton për përdorues realë; duhet SMTP i jashtëm (kosto/kufizime sipas ofruesit).
8. Bundle Identifier dhe ruajtja lokale nuk u ndryshuan. Nuk u shtua varësi (klienti përdor REST me URLSession).
9. Dy sisteme (Python/Supabase) bashkëjetojnë; llogaritë nuk migrohen midis tyre.
10. Dokumentacioni i Supabase u konsultua për MFA, SMTP dhe shabllonet; emrat e menuve duhen verifikuar në dashboard.

## Veprimet e tua
1. Ndiq SUPABASE-SETUP.md §1–6, ekzekuto migrimet, më dërgo çdo gabim SQL.
2. Plotëso Info.plist (URL + çelës publik), ndërto në Mac (`bash VERIFY-ON-MAC.command`), më dërgo gabimin e parë të kompilimit nëse ka.
3. Vendos kodin e mësuesit vetëm te SQL Editor.
4. Vendos nëse aktivizohet miratimi i mësuesve dhe SMTP i jashtëm.
