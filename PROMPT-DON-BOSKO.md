Puno mbi projektin ScienceQuest në ZIP-in bashkëngjitur. Dua ta zhvillojmë gradualisht në **Don Bosko Connect**, një aplikacion të thjeshtë dhe të avancuar për gjithë shkollën Don Bosko. ScienceQuest duhet të mbetet pjesa e mësimeve dhe laboratorëve brenda aplikacionit.

**Prioriteti i parë është rregullimi i autentikimit, roleve dhe aksesit.** Më pas puno me funksionet e shkollës. Mos u kufizo te rekomandimet: ndrysho projektin, përgatit backend-in dhe dorëzo kodin e përditësuar.

### 1. Rregullat e regjistrimit dhe hyrjes

Krijo dy hyrje të qarta:

- **Nxënës / Prind**
- **Mësues**

Ekranet janë vetëm për orientim. Serveri vendos rolin dhe autorizon çdo veprim.

**Një email = një llogari = një rol.**

Nëse dikush është edhe mësues edhe prind, përdor dy emaile të ndryshme. Mos lejo që regjistrimi i përsëritur, zgjedhja e ekranit tjetër ose ndryshimi i kërkesës nga klienti t’i ndryshojë rolin.

Zbato këto raste:

**A. Përdoruesi ka llogari, por zgjedh “Regjistrohu” përsëri**

- Mos krijo llogari ose profil të dytë.
- Mos ndrysho rolin ekzistues.
- Shfaq mesazhin: “Ke tashmë një llogari. Hyr për të vazhduar.”
- Jep butonat “Hyr” dhe “Harrova fjalëkalimin”.
- Pas autentikimit të suksesshëm, dërgoje drejtpërdrejt te profili dhe këndi i rolit të tij ekzistues.
- Nëse ka tashmë sesion të vlefshëm, hape drejtpërdrejt këndin përkatës, pa e kërkuar regjistrimin përsëri.

**B. Emaili ekziston me një rol tjetër nga ai që po zgjedh**

Shembull: `juricavo25@gmail.com` është regjistruar si mësues dhe më pas përpiqet të regjistrohet si nxënës ose prind.

- Serveri duhet ta refuzojë krijimin e rolit tjetër.
- Pas verifikimit që personi zotëron llogarinë, shfaq: **“Kjo adresë emaili ka rolin Mësues. Hyr nga seksioni Mësues. Për rol tjetër përdor një adresë tjetër emaili.”**
- Dërgoje te hyrja e duhur.
- Mos e zbulo rolin e një emaili arbitrar publikisht, përpara autentikimit ose verifikimit të pronësisë së emailit. Para këtij verifikimi përdor mesazh të përgjithshëm, që të mos krijohet mundësia e zbulimit të llogarive.

**C. Hyn nga ekrani i gabuar**

Nëse një mësues fut kredencialet te “Nxënës / Prind”, pas autentikimit serveri kthen rolin real dhe aplikacioni e orienton te këndi i mësuesit. Zgjedhja e ekranit nuk ndryshon privilegjet.

**D. Email i pakonfirmuar**

Nëse regjistrimi është nisur, por emaili nuk është verifikuar, ktheje te verifikimi ose ridërgimi i kodit. Mos krijo profil tjetër dhe mos jep akses te të dhënat e mbrojtura.

Normalizo emailin me heqjen e hapësirave anësore dhe trajtim të njëtrajtshëm të shkronjave të mëdha/vogla. Mos hiq pika ose pjesë të adresës sipas rregullave të supozuara të Gmail-it.

### 2. Roli të mbrohet në server

Kontrollo strukturën aktuale përpara ndryshimeve:

- Identiteti lidhet me UUID-në e Supabase Auth.
- Regjistrimet e njëkohshme dhe kërkesat e përsëritura nuk krijojnë profile të dyfishta.
- Përzgjedhja e rolit kryhet vetëm një herë, përmes funksionit të kontrolluar në server.
- Klienti nuk ndryshon drejtpërdrejt kolonën role.
- Mos beso role nga user_metadata, UserDefaults ose të dhëna të importuara.
- Mbrojtja duhet të funksionojë edhe nëse dikush anashkalon ndërfaqen dhe dërgon kërkesa API drejtpërdrejt.
- Përdor kufizime databaze, transaksione dhe RLS sipas nevojës.

Nëse ka të dhëna ekzistuese kontradiktore, përgatit raport dhe migrim të kontrolluar. Mos i fshi ose bashko automatikisht pa mundësi rikuperimi.

### 3. Regjistrimi i mësuesit dhe verifikimi

Mësuesi regjistrohet me email, fjalëkalim dhe kodin (kodi ruhet vetëm në server, `app.secrets`; nuk shkruhet në repo).

- Kodi kontrollohet vetëm në server, përmes konfigurimit privat.
- Mos e vendos në aplikacionin Swift, konfigurimin publik ose repository.
- Ruaj kufizimin e tentativave dhe mos lejo anashkalimin përmes regjistrimit publik.
- Shpjego se kodi i përbashkët nuk verifikon vetë profesionin e personit.
- Ruaj mundësinë e miratimit nga administratori; mos e aktivizo si kërkesë shtesë pa ma sqaruar.

Për të gjitha rolet duhet verifikim emaili. Mbështet rikuperimin e fjalëkalimit dhe mundësinë e aktivizimit të 2FA reale. Kur 2FA është aktivizuar, nuk duhet të anashkalohet gjatë hyrjes. Token-et ruhen në Keychain.

### 4. Stabilizo bazën Supabase

Verifiko implementimin aktual. Mos i merr si të provuara pretendimet në dokumentacion.

E njëjta llogari duhet të punojë në pajisje të ndryshme dhe të marrë nga serveri klasat, testet, eventet dhe rezultatet përkatëse.

Përgatit migrimet SQL, funksionet, RLS dhe udhëzimet e konfigurimit. Çelësat administrativë/service_role mbeten vetëm në server. Praktika ekzistuese duhet të vazhdojë offline dhe progresi të sinkronizohet pa u trajtuar si notë provimi e verifikuar.

### 5. Faqja kryesore “Sot”

Krijo një ekran kryesor sipas rolit:

- Nxënësi: orari, detyrat, testet, afatet dhe aktivitetet.
- Prindi: informacioni i fëmijëve të lidhur dhe veprimet që kërkojnë përgjigje.
- Mësuesi: klasat, dorëzimet për korrigjim dhe kërkesat në pritje.
- Administratori i autorizuar: administrimi i shkollës dhe miratimet.

Çdo kartë duhet të hapë drejtpërdrejt veprimin përkatës. Mos shfaq të dhëna demonstrimi si informacion real ose funksione të pakonfiguruara si aktive.

### 6. Testet, detyrat dhe kalendari

Implemento dhe provo rrjedhën:

**Mësuesi krijon → publikon për klasën → nxënësi plotëson → dorëzimi shkon te mësuesi → korrigjohet → rezultati i publikuar shfaqet te nxënësi dhe prindi i lidhur.**

Përfshi:

- Korrigjim automatik, manual dhe të përzier.
- Pikë të pjesshme dhe feedback.
- Afate dhe kohë të kontrolluara nga serveri.
- Mbrojtje nga dorëzimet e dyfishta dhe ndryshimet pas mbylljes.
- Ruajtje drafte dhe politikë të qartë për ndërprerjen e internetit.
- Dorëzime me tekst, dokumente dhe foto; audio/video me kufij madhësie dhe leje të kontrolluara.
- Evente të klasës që përditësohen te nxënësi dhe prindi.

Mos e konsidero fshehjen e zgjidhjes në ekran si mbrojtje të çelësave që ekzistojnë në paketën lokale.

### 7. Koordinimi i ngarkesës së klasës

Kur mësuesi planifikon një test, kontrollo testet e tjera të asaj klase.

Shfaq paralajmërim për mbingarkesë dhe sugjero data alternative. Shkolla cakton kufijtë; mësuesi ose administratori merr vendimin. Mos e blloko planifikimin me rregulla të shpikura e të pandryshueshme.

Nxënësi mund të marrë një plan të thjeshtë përgatitjeje sipas afateve. Fillo me rregulla të kuptueshme; AI nuk është kusht për këtë funksion.

### 8. Projekte, portofol dhe jeta e shkollës

Zhvillo strukturën për:

- Projekte individuale dhe në grup, me role, kontribute dhe versione dorëzimi.
- Portofol të punëve të zgjedhura nga nxënësi, me konfirmim mësuesi kur kërkohet.
- Klube, sport, art, konkurse dhe vullnetarizëm.
- Aktivitete me regjistrim, leje prindi, kujtesa dhe pjesëmarrje.
- Rezervim takimi me mësuesin dhe, më vonë, laborator/bibliotekë.
- Butonin “Kam nevojë për ndihmë”, me marrës të caktuar, status dhe kufij të qartë privatësie.

Mos i shfaq portofolat, shqetësimet personale ose të dhënat e nxënësve publikisht si parazgjedhje.

### 9. Akses nga të gjitha pajisjet dhe përdorim i thjeshtë

Përgatit edhe një version web të përshtatshëm për Android dhe Windows, me të njëjtin backend dhe të njëjtat rregulla aksesi.

Mbaje ndërfaqen në shqip të saktë, me navigim të qartë, tekst të zmadhueshëm, kontrast të mirë dhe aksesueshmëri. Shfaq statusin “U ruajt në pajisje”, “Në pritje për dërgim” ose “U dërgua”.

Njoftimet të grupohen sipas rëndësisë. Mos pretendo se push notifications punojnë pa konfigurimin përkatës.

### 10. AI si fazë pasuese

Përgatit arkitekturën për një asistent që ndihmon me sugjerime, planifikim dhe draft feedback-u. Për informacionin e shkollës duhet të përdorë dokumente të miratuara dhe të tregojë burimin.

Mos lejo që AI të ndryshojë role, të marrë vendime disiplinore ose të publikojë nota përfundimtare pa mësuesin. Mos aktivizo shërbime AI me pagesë ose dërgim të të dhënave personale pa miratim.

### Mënyra e punës dhe dorëzimi

Puno me faza që mund të verifikohen:

1. Autentikimi, emaili unik dhe roli i pandryshueshëm.
2. Supabase, klasat, lidhja me prindin dhe rrjedha e testeve/eventeve.
3. “Sot”, koordinimi i ngarkesës dhe versioni web.
4. Projektet, portofoli dhe aktivitetet.
5. AI dhe zgjerimet e tjera.

**Mos ndrysho përmbajtjen e mësimeve dhe laboratorëve në këtë fazë.** Ruaj funksionet ekzistuese, identifikuesit dhe të dhënat; mos ndrysho Bundle Identifier pa nevojë dhe migrim.

Dorëzo projektin e përditësuar, migrimet, udhëzimet e konfigurimit dhe raportin e provave. Për çdo funksion dallo: implementuar, provuar realisht, në pritje konfigurimi ose ende i papërfunduar.

Provo veçanërisht regjistrimin e përsëritur, përpjekjen për rol tjetër, hyrjen nga ekrani i gabuar, kërkesat e njëkohshme, emailin e pakonfirmuar dhe anashkalimin e UI-së me API.

Mos thuaj “punon” vetëm sepse sintaksa është e rregullt. Nëse nuk ke Xcode ose Supabase të lidhur, deklaro çfarë nuk mund të provoje dhe jep komandat/hapat për verifikim.