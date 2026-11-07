# ScienceQuest — Versioni i fundit 7.0 · build 16 (+ faza 8: Supabase, pa u provuar)

> **Faza 8:** hyrja me Supabase (dy ekrane, email i konfirmuar, 2FA, klasa/teste/evente) është shkruar por **nuk është provuar**. Shih **SUPABASE-SETUP.md** dhe **RAPORTI-8.0.md**. Pa `SupabaseURL`/`SupabaseKey` te Info.plist aplikacioni punon si më parë me serverin Python.

Ky është folderi i plotë për Xcode, me kodin e shërbimit të shkollës brenda **Server/**. Nuk përdor Firebase, Supabase, AWS ose shërbim të jashtëm llogarish. Nuk përdor CloudKit. Hyrja mbetet me **email dhe fjalëkalim, pa 2FA**.

## Hape në Xcode

1. Çkompreso ZIP-in dhe hap **ScienceQuest.xcodeproj**.
2. Zgjidh skemën **ScienceQuest**, pastaj **My Mac** ose një simulator iPhone/iPad.
3. Shtyp **⌘R**. Për pajisje fizike vendos ekipin tënd te Signing & Capabilities.
4. Për t'i parë menjëherë mësimet dhe laboratorët, shtyp **Shfleto mësimet pa llogari** dhe zgjidh nivelin.
5. Për llogaritë, klasat, testet dhe sinkronizimin, nise shërbimin sipas hapave më poshtë.

Mos ndrysho Bundle Identifier-in dhe ekipin e një instalimi ekzistues nëse do të ruash të dhënat e vjetra. Mos fshi aplikacionin ose të dhënat e tij para importimit.

## Nise shërbimin për provë në Mac

Kërkohet Python 3.11 ose më i ri. Nuk ka paketa `pip` për serverin.

Në Terminal, shkruaj `cd `, tërhiq folderin **Server** mbi dritaren e Terminalit dhe shtyp Enter. Pastaj:

```bash
python3 server.py
```

Lëre Terminalin hapur. Në aplikacion hap **Lidhja e shkollës**, vendos **http://localhost:8443** dhe shtyp **Ruaj adresën**. Kjo adresë funksionon për aplikacionin në atë Mac dhe për iPhone Simulator në atë Mac, në konfigurimin Debug.

**Pajisjet e ndryshme duhet të lidhen me të njëjtin shërbim.** Mos nis një server të veçantë në çdo laptop; kjo do të krijonte përsëri sisteme të ndara. Për telefon fizik në rrjetin lokal ose për përdorim në internet, ndiq **Server/README.md**. Serveri duhet të jetë i ndezur dhe i arritshëm.

## Mësuesi dhe klasa reale

Në një Terminal të dytë, brenda të njëjtit folder Server:

```bash
python3 server.py --invite-teacher mesuesi@shkolla.example
```

Zëvendëso adresën me emailin real të mësuesit. Komanda jep një kod 5-shifror që vlen 7 ditë, vetëm për atë email dhe vetëm për një regjistrim; pas 5 gabimesh kodi bllokohet dhe duhet dhënë një i ri (`--invite-digits 0` jep kod të gjatë). Dërgoja mësuesit nëpërmjet një kanali që e njeh personin (jo në grup të hapur). Administratorit nuk i duhet llogari te ndonjë platformë tjetër. Kodi i përbashkët i versionit të vjetër nuk jep më rol mësuesi.

1. Mësuesi regjistrohet me email, fjalëkalim dhe ftesën personale.
2. Te profili krijon klasën, p.sh. **XI B**, me nivelin përkatës.
3. Ndajnë kodin e klasës. Nxënësit kërkojnë anëtarësim dhe mësuesi i miraton.
4. Mësuesi zgjedh klasën dhe krijon testin. Mund të përdorë variante numerike të gjeneruara në server ose pyetje të shkruara vetë, me përgjigje, tolerancë dhe rubrikë.
5. Nxënësit e miratuar shohin vetëm testet e asaj klase. Dy klasa me të njëjtin nivel nuk marrin automatikisht të njëjtat teste.
6. Te **Vlerësimi**, mësuesi lexon përgjigjet dhe arsyetimet dhe mund të caktojë pikë të pjesshme e komente. Nxënësi dhe prindi i lidhur shohin rezultatin e përditësuar.

## Koha dhe përmbajtja e testit

Koha nis me **Fillo ose vazhdo testin**. Nisja, afati, varianti dhe përgjigjet ruhen në server; dalja nga aplikacioni ose hyrja nga një pajisje tjetër nuk e rinisin kohën. Serveri refuzon përgjigje pas afatit dhe e shënon testin të dorëzuar gjatë kërkesës pasuese, përfshirë hapjen e regjistrit të mësuesit.

Përgjigjet dërgohen automatikisht pas një pauze të shkurtër shkrimi dhe me butonin **Ruaj përgjigjen**. Pa rrjet, drafti mbetet në pajisje, por një draft që nuk ka arritur në server para afatit nuk llogaritet si i dorëzuar. Ora e pajisjes së nxënësit nuk përcakton afatin.

Çelësat e testeve ruhen në server dhe nuk dërgohen në klientin e nxënësit. Banka publike me 600 ushtrime vazhdon të japë zgjidhje për stërvitje. Kjo nuk zëvendëson mbikëqyrjen e një provimi formal.

## Llogaritë ekzistuese dhe rikuperimi

Llogaritë e versionit 6 ishin lokale. Ato hapen te **Llogaria ime e vjetër në këtë pajisje**; nuk bëhen automatikisht llogari interneti. Krijo një herë llogarinë e përbashkët në shërbimin e shkollës. Pastaj, te profili, përdor **Importo progresin nga llogaria e vjetër** dhe fjalëkalimin e saj. Kjo kopjon progresin personal që mungon, jo autorizimin e vjetër të mësuesit ose testet lokale si teste aktive. Testet e vjetra mbeten në ruajtjen lokale dhe duhet të rikrijohen për klasat e reja.

Emaili normalizohet dhe është unik brenda këtij shërbimi. Një fjalëkalim tjetër nuk krijon llogari të dytë për të njëjtin email. **Pronësia e adresës nuk verifikohet me email në këtë version.** Anëtarësimin në klasë e miraton mësuesi; ai duhet të kontrollojë se kujt i përket profili.

Pas regjistrimit ruaj **kodin personal të rikuperimit**. Te **Harrove fjalëkalimin?** përdor këtë kod për të caktuar një fjalëkalim të ri. Kodi ndërrohet pas përdorimit dhe seancat e mëparshme anulohen. Nuk dërgohet kod emaili dhe nuk ka 2FA.

Progresi sinkronizohet çdo 30 sekonda ndërsa aplikacioni është i hapur, gjatë hyrjes/daljes dhe me butonin **Sinkronizo progresin tani**. Kur dy pajisje ndryshojnë të njëjtën fushë, versioni lokal ruhet te **Konfliktet e shënimeve**; nuk mbishkruhet pa kopje. Këto kopje mund të përmbajnë edhe të dhëna teknike të fletoreve binare, përveç tekstit.

## Prindi dhe kalendari

Nxënësi krijon një kod privat lidhjeje me vlefshmëri 15 minuta. Prindi e vendos në profilin e vet dhe sheh rezultatet e fëmijës dhe eventet e klasave të tij. Nxënësi mund ta heqë këtë qasje. Prindërit nuk marrin qasje te shënimet private të mësimit.

Te **Eventet**, mësuesi zgjedh klasën, titullin, datën/orën dhe shënimin. Kalendari lejon shfletimin e muajve dhe listën e datave të planifikuara. Eventi i kalendarit është njoftim; nuk e nis vetë kohën e një testi.

## Mësimet, figurat dhe lojërat

- 600 mësime, 600 ushtrime, 120 kapituj; për çdo lëndë 150 mësime e 150 ushtrime.
- Pesë nivele; çdo lëndë ka 30 mësime dhe 30 ushtrime për nivel.
- Objektivat lidhen me temën. Tekstet identike të metodës për një lëndë të tërë janë hequr; udhëzimet dhe gabimet tipike janë përshtatur për 120 kapituj. 575 mësimet që përdornin shabllonin tani kanë arsyetim të lidhur me shembullin e tyre. 25 temat e zgjeruara të matematikës janë ruajtur.
- 27 tema kanë ilustrime shkencore me forma, kurba ose skema: qelizë, atom, qark, përthyerje, sustë, trekëndësh, rreth, membranë, kryqëzim gjenetik etj. Temat e tjera kanë harta zgjidhjeje që zbulohen hap pas hapi. **Nuk janë 600 vizatime të veçanta të ilustruara me dorë.**
- Diagramet ndërtohen në SwiftUI, brenda mësimit. Mësimet mbi sustat hapin edhe laboratorin përkatës.
- Ushtrimet numerike shfaqin saktësinë e kërkuar. Për 4/3 me dy shifra pas presjes pranohet 1,33, si edhe thyesa e saktë.
- Science Battle, Escape Room, memoria, çiftimi, klasifikimi dhe loja e pyetjeve marrin përmbajtje nga niveli i zgjedhur. Battle ka nga një temë për çdo lëndë për secilën skuadër. Variantet kanë ndryshueshmëri, por kjo nuk është gjenerim pa kufi i përmbajtjes së re.
- Ruhen 43 mënyrat e simulimit, përzierjet kimike dhe aktivitetet praktike të mëparshme.

## Çfarë është provuar dhe çfarë mbetet

Shih **KONTROLLI.txt**, **PROVAT-NE-XCODE.md** dhe **VERIFY-ON-MAC.command**. Janë kryer prova reale të serverit, përfshirë dy klientë HTTP, dhe kontrolle të të dhënave/sintaksës. **SwiftUI nuk është kompiluar dhe UI-ja nuk është ekzekutuar në këtë mjedis Linux.** Komanda e përfshirë ndërton projektin në Mac dhe iOS Simulator dhe ekzekuton testet; rezultati i saj duhet kontrolluar në Mac përpara publikimit. Nuk pretendohet se është gati për miratim nga App Store ose i audituar për përdorim masiv shkollor.

Harta e temave është te **HARTA-E-MESIMEVE.md**. Përmbajtja është material praktik mësimor dhe nuk është certifikuar si program zyrtar shkollor.
