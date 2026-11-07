# Raporti i ndryshimeve dhe i provave — ScienceQuest 7.1 (ndërtuar mbi 7.0 build 16)

**Mjedisi i punës:** Linux, Python 3.12. **Nuk kishte Swift, Xcode, Apple SDK, PostgreSQL ose Supabase.** Prandaj asnjë kod Swift nuk u kompilua dhe asnjë SQL nuk u ekzekutua.

## 1. Çfarë u ndryshua dhe pse
| Ndryshimi | Arsyeja | Provuar? |
| --- | --- | --- |
| `Server/server.py`: ftesa e mësuesit është kod **5-shifror** (opsion 5–12 ose kod i gjatë), i lidhur me emailin, 7 ditë, një përdorim; **blloqohet pas 5 gabimesh**; ftesa e re shfuqizon të vjetrën; hash me email si kripë (ftesat e vjetra pranohen ende) | Kodi 5-shifror është i sigurt vetëm me kufizim tentativash. Numëruesi ruhet në transaksion të veçantë, që mos humbet kur kërkesa dështon | **Po**: 4 teste të reja Python (format, bllokim, ri-lëshim, ftesë e vjetër, kod i gjatë, student nuk bëhet mësues) |
| Migrim: kolona `invites.failures` shtohet me `ALTER TABLE`, pa humbur rreshta | Mos prish bazat ekzistuese | **Po** (test migrimi) |
| `NumericAnswer.swift` (+`NotebookCodec`), `Games.swift`, `ChemistryMixer.swift`, `SpringLab.swift`: fletoret e laboratorit **nuk mbishkruhen** më me listë bosh kur të dhënat e ruajtura nuk lexohen; shfaqet mesazh | Defekt real humbjeje të dhënash (`try? … ?? []` pastaj ruajtje) | **Jo kompiluar.** Kontrolluar vetëm balancimi i kllapave |
| `Accounts.swift`: teksti i ftesës 5-shifrore | Përputhje me serverin | Jo kompiluar |
| `Lessons.json`/`Exercises.json`: hequr 15+14 fragmente bosh (“Llogaritja ndahet në veprime: .”), rregulluar fjalë të ngjitura me numra (“Nga5”, “ka80+70”, “dhe4”, “intervaliAB”) dhe 2154 dyfishime hapësirash rreth “×”. ID-të e çelësat e pandryshuar | Defekte të dukshme të shabllonit | **Po**: JSON i vlefshëm, `check_content.py` PASS |
| `Supabase/` (SQL + README) | Vlerësim dhe plan lidhjeje me RLS, rol mësuesi nga serveri, afat nga serveri, çelësat e fshehur | **Jo**: SQL i pa-ekzekutuar; klienti Swift **nuk është lidhur**; sinkronizimi me Supabase nuk është aktiv |
| `CONTRIBUTING.md`, `.gitignore`, `.gitattributes`, `.github/workflows/ci.yml`, `Tools/check_no_secrets.sh` | Bashkëpunim, mbrojtje sekretesh | Skripti i sekreteve: **ekzekutuar**, pa gjetje. Workflow-i CI **nuk është ekzekutuar** |
Skedarët e rinj Swift nuk u shtuan (kodi i ri u fut në skedarë ekzistues), që `project.pbxproj` të mos prekej pa Xcode.

## 2. Çfarë u ekzekutua realisht
- `python3 -m unittest test_server.py`: **17 teste, OK** (13 ekzistues + 4 të rinj), ~23 s.
- `python3 Tests/check_content.py`: **PASS** (600 mësime, 600 ushtrime, 120 kapituj, 411 çifte llogaritjesh).
- `bash Tools/check_no_secrets.sh`: pa gjetje.
- Konfigurimi në `project.pbxproj` (lexuar, jo ndërtuar): iOS 16 / macOS 13, Swift 5, pa kufizim arkitekture, sandbox me lidhje dalëse të lejuara. **Kjo nuk provon** që ndërtohet në MacBook Pro 2019 Intel me macOS Tahoe 26.7.2: versioni i saktë i Xcode që funksionon aty duhet verifikuar nga ju. Nuk ka kërkesë të shkruar për Xcode 27 ose Apple silicon.

## 3. Çfarë NUK u provua
Kompilimi Swift/typecheck, XCTest, Simulator, UI, VoiceOver, kontrasti, zmadhimi i tekstit, ekranet e vogla, pajisje fizike, TLS real, sinkronizimi dy-pajisje, SQL/RLS Supabase, workflow CI.

## 4. Problemet e mbetura
1. **Shkenca/përmbajtja:** rishikova nga afër vetëm 3 mësime (LF3-13, LK1-06, LB2-28) dhe rregullova vetëm defekte mekanike. Nuk është rishikim shkencor i 600 temave. Në LF3-13 (rezistencat në seri) “gabimi tipik” flet për rezistencën në paralel: shabllon jo i përshtatur; ka të ngjara qindra raste të ngjashme. Teksti i diagramave përsërit hapat e zgjidhjes. Shumica e temave kanë vetëm hartë hapash (27 ilustrime). Fjalë të ngjitura me numra të tjera mund të ekzistojnë jashtë modeleve të rregulluara.
2. **UI:** `preferredColorScheme(.light)` ignoron mënyrën e errët; mungon rikthimi automatik i seancës pas rinisjes (token ruhet në Keychain por s’lexohet); asnjë auditim VoiceOver.
3. **Siguria e serverit:** emaili nuk verifikohet; regjistrimi zbulon nëse emaili ekziston (409); kodi i klasës (40 bit) s’ka kufizim të veçantë për përdorues; serveri është një proces me SQLite, pa TLS të paracaktuar; s’ka endpoint për fshirje/redaktim testi; nuk ka audit të jashtëm.
4. **Ushtrimet publike (600)** përmbajnë zgjidhjet në paketë; janë për stërvitje, jo provim.
5. **Pa Supabase aktiv:** duhet vendim (server Python ose Supabase), projekt prove, ekzekutim i SQL, dhe punë Swift për klientin.

## 5. Çfarë kërkohet nga ju
Hapni në Mac dhe ekzekutoni `bash VERIFY-ON-MAC.command` (duhet Xcode i plotë); vendosni ekipin te Signing & Capabilities; zgjidhni Bundle ID real vetëm para një instalimi të ri (mos e ndryshoni te instalimet ekzistuese pa migrim); vendosni serverin (START-HERE.md); nëse zgjidhni Supabase, ndiqni `Supabase/README.md`.
