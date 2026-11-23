# BrainSpark · Auditimi inxhinierik dhe udhërrëfyesi me €0

Data: 23 nëntor 2026 · Autori: Matia (me Claude) · Gjendja e kodit: `main` @ `e660230`

**Përfundimi:** BrainSpark ka një bazë të shëndoshë: skemë `app` e mbyllur, çdo veprim kalon nga `public.api_*` me kontroll roli, shqipe kudo në app, privatësi e menduar për të miturit. Rreziqet kryesore janë katër:

- mirëmbajtja e serverit varet nga hapja e app-it nga një mësues;
- Bosko AI beson dy fusha që vijnë nga klienti;
- provat e lejeve nuk janë automatike në CI;
- asgjë e re nuk është provuar në pajisje.

Të gjitha rregullohen pa pagesë.

Shenjat: 🔴 duhet para publikimit · 🟡 e rëndësishme · ⚪ përmirësim. Gjendja dallon gjithmonë: *implementuar · provuar në server · provuar në pajisje · në pritje konfigurimi*.

---

## 1. Çfarë u kontrollua

| Fusha | Si u kontrollua |
|---|---|
| App SwiftUI (55 skedarë, ~16 200 rreshta) | Leximi i strukturës, skedarët më të mëdhenj, vargjet e përdoruesit (kontroll automatik i gjuhës), polling/kohëmatësit |
| Supabase (22 migrime, 39 tabela në `app`, 97 funksione `api_*`) | `get_advisors` (siguria), madhësia e tabelave, `Tests/check_supabase_contract.py` |
| Edge Functions (`bosko-ai` v10, `send-login-code` v9, `storage-cleanup` v1) | Leximi i kodit |
| Faqet publike (`docs/`) | Gjuha, marka, lidhjet që përdor app-i |
| CI | `.github/workflows/ci.yml` (Linux + macOS/iOS/watchOS) |
| Mësimet | Struktura e `Lessons.json` (700 mësime, 2,1 MB) — vetëm auditim, pa ndryshime |

Nuk u bë: prova në pajisje, prova HTTP nga jashtë (shell-i i Claude nuk ka rrjet), prova ngarkese.

## 2. Gjetjet sipas fushave

### 2.1 Siguria dhe autorizimi
- ✅ Skema `app` ka RLS pa rregulla (me qëllim); klienti arrin vetëm `api_*` me `app.gate(...)`, kufizime shpejtësie me `app.hit`. Këshilluesi i Supabase nuk tregon asgjë të re: 39 × `rls_enabled_no_policy` dhe 97 × `security_definer` janë dizajni; «leaked password protection» kërkon planin Pro (zëvendësuar me gjatësi minimale + shkronja/shifra).
- 🟡 **Provat e lejeve janë manuale.** Çdo migrim u provua në transaksion që anulohet, por CI nuk i riprovon. Një ndryshim i ardhshëm mund të prishë një leje pa u vënë re. Zgjidhja €0: Postgres si «service container» në GitHub Actions + skemë `auth` e thjeshtuar + prova roli (nxënësi nuk thërret `api_admin*`, prindi nuk sheh fëmijë të tjerë, mësuesi jashtë klasës nuk sheh bisedën e klasës…).
- 🟡 `Tests/check_supabase_contract.py` është i fortë, por statik: kontrollon që funksionet ekzistojnë, jo që refuzojnë rolin e gabuar.

### 2.2 Mirëmbajtja e serverit
- 🔴 **Pastrimi i ruajtjes varet nga app-i i mësuesit** (`cleanupStorage()` nis kur hapet faqja e mësuesit ose pas fshirjes së klasës/testit). Nëse asnjë mësues nuk e hap app-in, skedarët jetimë mbeten. Kërkesa «serveri nuk varet nga hapja e app-it» nuk plotësohet.
- 🟡 Tabelat e përkohshme (`login_codes`, `session_2fa`, `throttle`, `audit_log`) nuk kanë fshirje periodike. Sot janë të vogla (1–88 rreshta), por rriten me kohën.
- Zgjidhja €0: `pg_cron` (i përfshirë në planin falas) për pastrimin SQL; një workflow i planifikuar në GitHub Actions (falas për repo publike) që thërret `storage-cleanup` me një sekret të veçantë. **Kërkon miratimin tënd** (migrim + sekret).

### 2.3 Bosko AI
- ✅ Pëlqimi kontrollohet në server, kufizim përdorimi, heqje email/telefoni para dërgimit, raportim përgjigjesh, rregull për të miturit, shqip si parazgjedhje.
- 🟡 **Roli dhe materiali i mësimit vijnë nga klienti** dhe futen në udhëzimin e sistemit. Një klient i modifikuar mund të kërkojë sjelljen e «mësuesit» ose të fusë tekst në pjesën më të besuar të udhëzimit (prompt injection). Zgjidhja: roli lexohet nga `api_aiallow`; mësimi trajtohet si «material i pabesuar» në mesazh të veçantë, jo te udhëzimi i sistemit.
- 🟡 Udhëzimi e quan app-in «Don Bosko Connect» → duhet «BrainSpark».
- 🟡 Rregulli i gjuhës: sot përgjigjet në gjuhë tjetër «kur përdoruesi shkruan në gjuhë tjetër»; kërkesa e re është *vetëm kur kërkohet qartë për mësim gjuhe*.
- Tri ndryshimet kërkojnë rishpërndarjen e Edge Function → **pas miratimit**.

### 2.4 Identiteti, regjistri, rolet
- ✅ Regjistri, kodet (hash sha256, 30 ditë), kujdestari, ftesat, prindi, hyrja «Sekretaria»: të provuara në server.
- 🔴 Pa sekretare aktive (#109) regjistri nuk përdoret dhe raportet nuk i shqyrton njeri. Apple 1.2 kërkon moderim aktiv.
- ⚪ Detyrimi i kodit të nxënësit (`require_student_verification`) është fikur me qëllim, deri pas ngarkimit të regjistrit.

### 2.5 Bisedat dhe moderimi
- ✅ Bllokim, raportim (mesazh, përdorues, AI), filtër emrash, radha te sekretaria.
- 🟡 Bisedat pyesin serverin çdo 4 s (bisedë e hapur) dhe 15 s (lista), vetëm kur app-i është aktiv. Supabase Realtime (falas, deri në kufijtë e planit) do të ulte trafikun dhe baterinë. Kërkon kujdes: Realtime lexon tabela, ndërsa `app` është e mbyllur → kanal «broadcast» nga funksionet `api_*`.

### 2.6 App-i SwiftUI dhe dizajni
- ✅ Shqip kudo (0 tekste anglisht të gjetura), `developmentRegion = sq`, lejet në shqip.
- 🟡 Skedarë shumë të mëdhenj: `Games.swift` 1 175, `LessonAssistant.swift` 1 126, `SubjectRooms.swift` 938, `Identity.swift` 822 rreshta. I vështirë për rishikim dhe konflikte mes Matias dhe Jurit.
- 🟡 Ngjyrat dhe fontet janë të shpërndara (`Color(`/`.font(` 44–66 herë në disa skedarë). Ka bazë (`Glass.swift`, `SubjectTheme.swift`), por jo sistem dizajni të vetëm (tokenë ngjyrash, hapësirash, tipografie, gjendje bosh/ngarkimi).
- ⚪ Prova Swift: 16 prova njësie. Mungojnë prova UI për rolet.

### 2.7 Shkolla 3D
- ✅ Model procedural (pa skedarë të rëndë), pa njerëz, i dukshëm edhe për vizitorët.
- 🟡 Gjeometria është e përafërt («copë-copë», #104). Nevojiten foto shtesë; nuk shpiken detaje.

### 2.8 Faqet publike
- ✅ Shqip kryesore, anglisht për rishikuesit, fshirja e llogarisë në web.
- 🔴 Emaili i kontaktit mungon (#110).
- 🟡 Adresa teknike `qirjazimatia-cmd.github.io/projekt-fizik` tregon emrin e përdoruesit GitHub, jo markën. Faqja kryesore është faqe mbështetjeje, jo prezantim i BrainSpark (shih §5).

### 2.9 Mësimet (vetëm auditim — asgjë nuk ndryshohet tani)
- 700 mësime (4 lëndë × 175) në një skedar 2,1 MB brenda app-it. Çdo ndryshim teksti kërkon version të ri të app-it.
- Struktura është e njëjtë për çdo mësim. Objektivat duken të gjeneruara nga hyrja. Diagramet janë kryesisht të një lloji («flow» 673 herë).
- Mungon progresi sipas seksionit, videot, ushtrimet ndërvepruese brenda mësimit dhe versionimi i përmbajtjes.
- Juri ka #23 (më shumë mësime) në punë. Ridizajni bëhet te #123 «Lessons 2.0», pas tij.

### 2.10 CI dhe cilësia
- ✅ Kontrolle Linux + ndërtim macOS/iOS/watchOS, falas (repo publike).
- ✅ E re (PR #122): roja e gjuhës shqipe dhe e emrit BrainSpark.
- 🟡 Mungojnë provat e lejeve në bazë (§2.1), provat e Edge Functions (Deno) dhe një kontroll aksesueshmërie bazë.

### 2.11 Privatësia
- ✅ `PrivacyInfo.xcprivacy`, fshirja e llogarisë (app + web), pa gjurmim, të dhëna minimale në regjistër.
- ⚪ Kohë ruajtjeje e përcaktuar për `audit_log` dhe raportet e mbyllura (p.sh. 12 muaj) → të shkruhet në politikë dhe të zbatohet me `pg_cron`.

## 3. Pesë përmirësimet me ndikimin më të madh, me €0

| # | Përmirësimi | Pse | Madhësia | Miratim? |
|---|---|---|---|---|
| 1 | **Roja e gjuhës shqipe në CI** | Kërkesë e detyrueshme; mbron çdo PR të ardhshëm | I vogël | ✅ bërë → PR #122 |
| 2 | **Mirëmbajtja automatike e serverit** (`pg_cron` + workflow i planifikuar për `storage-cleanup`) | Heq varësinë nga app-i i mësuesit; tabelat nuk rriten | I vogël–mesëm | Po: migrim + sekret |
| 3 | **Bosko AI: roli nga serveri, mësimi si material i pabesuar, emri BrainSpark, rregulli i gjuhës** | Mbyll rrugën e «prompt injection» | I vogël | Po: rishpërndarje e Edge Function |
| 4 | **Provat e lejeve në CI** (Postgres në GitHub Actions) | Çdo migrim i ardhshëm provohet automatikisht për rolet | Mesëm | Jo (vetëm CI) |
| 5 | **Faqja publike BrainSpark** në shqip, mobile-first, me adresë falas me markë | Prezantim profesional; URL-të e vjetra mbeten | Mesëm | Po: llogari Cloudflare |

## 4. Udhërrëfyesi

**Prioriteti 0 · kritik**
1. PR #122 roja e shqipes → bashkohet kur kalon CI.
2. #109 sekretarja e parë, #110 emaili i kontaktit (presin Matian).
3. Mirëmbajtja automatike (përmirësimi 2).
4. Bosko AI 2.0 · faza e sigurisë (përmirësimi 3).
5. Provat e lejeve në CI (përmirësimi 4).
6. #108 provat në pajisje.

**Prioriteti 1 · i lartë**
- Sistemi i dizajnit: tokenë (ngjyra, tipografi, hapësira), karta, gjendje bosh/ngarkimi, panele sipas rolit, iPhone/iPad/Mac, errët/çelët. Bëhet me PR të vegjël, ekran pas ekrani, pa ndryshuar logjikën.
- Faqja publike (§5).
- Bateria: Realtime «broadcast» në vend të polling për bisedat.
- Bosko AI 2.0 · faza e mësimit:
  - shpjegime sipas lëndës, hap pas hapi;
  - shpjegimi i gabimeve dhe kuize opsionale;
  - përdorimi i monitoruar te sekretaria;
  - memorie e përgjigjeve (cache) vetëm për pyetje pa të dhëna personale.

**Prioriteti 2 · i avancuar**
- Shkolla e zgjuar:
  - konfliktet e testeve (#2);
  - detyrat e shtëpisë;
  - njoftimet e klasës dhe të prindërve;
  - paneli i progresit.
- BrainLabs: simulime deterministe lokale (fizikë, matematikë), me saktësi të provuar me teste numerike.
- Shkolla 3D (#104, #79): me foto të reja, me informacion për ndërtesat, optimizim i memories.
- Web + PWA, më vonë TWA (#4).

**E ardhmja:** Mësimet 2.0 (#123; nuk preket asgjë tani).

## 5. Adresa publike me markë, falas

| Mundësia | Adresa | Kosto | Shënim |
|---|---|---|---|
| **Cloudflare Pages** (rekomandim) | `brainspark.pages.dev` ose, nëse është zënë, p.sh. `brainspark-al.pages.dev` | €0 | Lidhet me këtë repo, publikon dosjen `docs/` në çdo bashkim. HTTPS automatik. Kërkon llogari Cloudflare (falas). Disponueshmëria e emrit **nuk u verifikua**: shihet vetëm kur krijohet projekti |
| Organizatë GitHub | `brainspark-…github.io` | €0 | Kërkon organizatë të re dhe repo të dytë për faqen |
| Netlify | `brainspark.netlify.app` | €0 | Njëlloj si Cloudflare, kufij më të ulët në planin falas |

Plani i migrimit, pa prishur lidhjet:
1. GitHub Pages **mbetet ndezur**: `…/privatesia.html`, `…/privacy.html` dhe `…/fshi-llogarine.html` vazhdojnë të punojnë (app-i i përdor te `PublicPages.base`).
2. Cloudflare Pages publikon të njëjtat skedarë nga `docs/` → të dy adresat shërbejnë të njëjtën përmbajtje.
3. Pasi adresa e re verifikohet live, ndryshohet `PublicPages.base` në app dhe URL-të në App Store Connect / Play Console. Adresa e vjetër mbetet si rezervë.
4. Asnjë domain nuk blihet. Asgjë nuk deklarohet «aktive» pa u hapur realisht.

Hapat që duhet të bësh ti: krijo llogari falas te dash.cloudflare.com → Workers & Pages → Create → Pages → Connect to Git → `qirjazimatia-cmd/projekt-fizik`, branch `main`, framework «None», build command bosh, output directory `docs`, emri i projektit `brainspark`. Më dërgo adresën që të jep.

## 6. Kufijtë e planeve falas (verifikohen periodikisht në faqet zyrtare)

- **Supabase Free:** baza 500 MB, ruajtja 1 GB, kufij mujorë trafiku dhe thirrjesh Edge.
  - ⚠️ Projekti **pezullohet pas rreth 1 jave pa aktivitet**: rrezik gjatë pushimeve verore. Workflow-i i planifikuar (përmirësimi 2) e mban gjallë.
- **Groq / Gemini:** kufij ditorë kërkesash në planet falas; Bosko ka kalim automatik nga njëri te tjetri dhe kufij për përdorues.
- **Gmail SMTP:** kufi ditor emailesh (rreth disa qindra në ditë) → mjafton për kodet e hyrjes së një shkolle.
- **GitHub Actions:** falas për repo publike, përfshirë macOS.

## 7. Ku kostoja €0 bie ndesh me publikimin

- **Apple App Store:** anëtarësia kushton 99 USD/vit. Apple ofron përjashtim nga tarifa për institucione arsimore të akredituara dhe organizata jofitimprurëse që shpërndajnë vetëm app-e falas ([Apple](https://developer.apple.com/support/fee-waiver)).
  - Shkolla Don Bosko (si person juridik, me numër D-U-N-S falas) mund ta kërkojë.
  - Kjo është rruga e vetme €0 për App Store.
- **Google Play:** tarifa e regjistrimit 25 USD (një herë); nuk njihet përjashtim. Alternativa €0: BrainSpark si **PWA** që instalohet nga shfletuesi në Android, pa Play Store.
- Vendimi për publikimin mbetet për më vonë, siç kërkove. Asnjë pagesë nuk bëhet.

## 8. Rregullat për çdo PR (shtuar me këtë auditim)

- Asnjë tekst anglisht për përdoruesin pa dashje (`Tests/check_shqip.py` e kontrollon në CI).
- Emri gjithmonë BrainSpark; `qirjazimatia-cmd` nuk shfaqet si markë.
- Asnjë shërbim me pagesë; çdo kufi plani falas dokumentohet këtu.
- Migrimet zbatohen vetëm pas miratimit; provat në server bëhen në transaksion që anulohet.
- «Provuar në pajisje» shkruhet vetëm pas provës në iPhone/iPad/Mac real.
