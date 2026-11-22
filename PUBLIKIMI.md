# Publikimi: App Store dhe Google Play

Qëllimi përfundimtar i projektit është publikimi i **BrainSpark** (`al.donbosko.connect`, versioni 1.0.0) në App Store dhe në Google Play.
Ky skedar është lista e përbashkët e kontrollit. Çdo ndryshim që prek një pikë këtu e përditëson statusin në të njëjtin PR.

Statuset: ✅ gati · 🟡 pjesërisht · ❌ mungon · ➖ nuk vlen

## Apple App Store (App Review Guidelines)

| Kërkesa | Rregulli | Statusi | Ku / shënim |
|---|---|---|---|
| Fshirja e llogarisë brenda app-it | 5.1.1(v) | ✅ | Cilësimet → «Fshi llogarinë» (`api_deleteAccount`) |
| Leje e qartë para dërgimit te AI i palës së tretë | 5.1.2(i) | ✅ | #62, #64: fleta e lejes, e kontrolluar në server, e tërheqshme |
| Tekstet e lejeve të sakta (kamera, mikrofon, Face ID) | 5.1.1(ii) | ✅ | Thonë saktë kur dërgohet fotoja/zëri |
| Privacy manifest (`PrivacyInfo.xcprivacy`) | 5.1.1 | ✅ | Email, ID, emri, foto, zë, përmbajtje, ndërveprim; pa tracking. #102: regjistri i shkollës (emri, klasa, nr. i Amzës, viti i lindjes) futet nga sekretaria, jo nga nxënësi; viti i lindjes deklarohet si «Other User Content/Other Data» në etiketat e App Store Connect dhe Data safety |
| Deklarata e enkriptimit | Export compliance | ✅ | `ITSAppUsesNonExemptEncryption = false` (vetëm HTTPS) |
| Politika e privatësisë: URL publik + lidhje në app | 5.1.1(i) | 🟡 | #67 · `docs/privatesia.html` + `docs/privacy.html` (EN); lidhje te Cilësimet dhe Info. **Mbetet:** ndiz GitHub Pages (Settings → Pages → main /docs) dhe vendos emailin e kontaktit |
| URL mbështetjeje (kontakt) | 1.5 | 🟡 | #67 · `docs/index.html` → https://qirjazimatia-cmd.github.io/projekt-fizik/ (pas ndezjes së Pages); mungon emaili |
| Llogari demo për App Review | 2.1 | 🟡 | #68 · Llogaritë demo (nxënës/mësues/prind) krijohen në server dhe shënohen te `app.review_accounts`: mësuesi demo nuk kërkon kodin me email, nxënësi demo hyn pa kodin e sekretarisë. Fjalëkalimet vendosen VETËM te App Store Connect / Play Console, kurrë në repo. Më parë: Nxënës + mësues; mësuesi ka kod me email → duhet zgjidhje për rishikuesin. Me #102: nxënësi demo duhet të jetë **i aktivizuar paraprakisht** në regjistër (rresht prove) dhe në «Notes for Review» shpjegohet që hyrja si nxënës kërkon kodin e shkollës; vizitorët shohin «Info» dhe mësimet pa llogari |
| Hyrje e kufizuar te anëtarët e shkollës (nxënës me kod sekretarie) | 2.1 / 3.1.3(f)-ngjashëm | 🟡 | #102 · Apple pranon app-e për institucione me llogari të krijuara nga shkolla, por rishikuesi duhet të ketë llogari demo; pjesa pa llogari (Info + mësime prove) e bën app-in të dobishëm edhe për vizitorët |
| Përmbajtje nga përdoruesit (shokët, emrat publikë): filtër, «Blloko», «Raporto», kontakt | 1.2 | ❌ | #69 · zona e Jurit (Shokët) |
| Bisedat (grupi i klasës, prind↔mësues, shok↔shok): filtër, «Blloko», «Raporto», mësues↔nxënës privat i dukshëm për prindin (#82) | 1.2 | 🟡 | #80, #82 · gati në app; **mungon personi/roli që shqyrton raportet** (`app.message_reports`) |
| Renditja javore me XP (emrat publikë të nxënësve) dhe Sfida e ditës | 1.2 / 5.1.1 | 🟡 | #84 (Juri) · shfaqen vetëm nxënës të pranuar në klasë (username, emër, avatar, XP); XP dhe përgjigjet ruhen në server (`app.player_xp`, `app.daily_answers`) → «Product Interaction» te etiketat dhe Data safety; renditja hyn te «Raporto/Blloko» e emrave publikë (#69) |
| Raportimi i përgjigjeve të papërshtatshme të AI | 1.2 / Play AI | ✅ | #70 · «Raporto përgjigjen» te flluska; raportet te `app.ai_reports` · buton te flluska e Bosko AI |
| Vlerësimi i moshës (pyetësori i ri: AI chatbot, përmbajtje përdoruesish, biseda mes përdoruesve) | 2.3.6 | ❌ | Mos zgjidhni kategorinë «Kids»: ajo ndalon dërgimin e të dhënave te palë të treta |
| Etiketat e privatësisë në App Store Connect | 5.1.1 | ❌ | Të përputhen me `PrivacyInfo.xcprivacy` dhe me AI-në |
| Asnjë funksion demo/i pakonfiguruar i shfaqur si real | 2.1 / 2.3.1 | 🟡 | Kontrollo para dërgimit |
| Llogaria Apple Developer | – | ❌ | 99 USD/vit; shkollat e akredituara mund të kërkojnë përjashtim nga tarifa (Apple fee waiver) |
| Pamjet (screenshots), përshkrimi në shqip, fjalët kyçe | 2.3 | ❌ | |

## Google Play

| Kërkesa | Statusi | Ku / shënim |
|---|---|---|
| Versioni web i paketuar si TWA (Android) | ❌ | #4 |
| Formulari «Data safety» | ❌ | Njëlloj si etiketat e Apple |
| Fshirja e llogarisë: në app **dhe** me një URL në web | 🟡 | Në app ✅; web: `docs/fshi-llogarine.html` (hyrje + konfirmim; mësuesi me kodin me email). Duhet ndezur GitHub Pages |
| Politika e privatësisë (URL) | 🟡 | E njëjta si te Apple (#67) |
| Bisedat: Data safety → «Messages» (në app), «User-generated content» me moderim | 🟡 | #80 · moderatori mungon |
| Përmbajtje e krijuar nga AI: raportim brenda app-it | ✅ | E njëjta pikë si te Apple |
| Leje e qartë para dërgimit te AI | ✅ | E njëjta fletë leje (në web) |
| Politika «Families» nëse publiku përfshin nën 13 vjeç | ❌ | Vendim: publiku i synuar (13+ ose edhe më të vegjël) |
| Llogaria Google Play Console | ❌ | 25 USD një herë |

## Rregulli i punës
Para çdo PR-je: a ndikon ky ndryshim te ndonjë pikë më sipër? Nëse po, përditëso statusin këtu. Kur shtohet një leje e re (kamera, vendndodhje, njoftime…), një shërbim i jashtëm, ose një e dhënë e re që mblidhet, përditëso edhe `PrivacyInfo.xcprivacy`, tekstet e lejeve dhe këtë skedar.
