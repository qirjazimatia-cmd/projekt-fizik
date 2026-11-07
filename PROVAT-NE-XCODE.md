# Provat në Mac — ende për t'u kryer nga projekti i dorëzuar

Mjedisi ku u përgatit ky ZIP është Linux; nuk ka SDK Apple, Xcode ose Simulator. Prandaj nuk ka dëshmi kompilimi SwiftUI ose pamje të ekzekutuara të këtij versioni. Ky dokument nuk është raport provash të kaluara në Xcode.

## Kontrolli automatik

Hap projektin, skemën ScienceQuest, pastaj Product → Test (⌘U). Target-i ScienceQuestTests provon saktësinë numerike dhe lidhjet e të dhënave. Ose, në Terminal brenda folderit të projektit:

```bash
bash VERIFY-ON-MAC.command
```

Kjo ndërton aplikacionin për macOS dhe iOS Simulator, pastaj provon testet në Mac dhe testet Python. Regjistrat dalin te Verification/. Duhet Xcode i plotë, jo vetëm Command Line Tools, dhe komponentët e iOS Simulator. Zgjedhja e simulatorit bëhet nga pajisjet e instaluara në Xcode; nuk është fiksuar një model iPhone.

Nëse del gabim, ndalo te gabimi i parë në Issue Navigator (⌘5). Ruaj mesazhin, emrin e skedarit dhe rreshtin për korrigjim. Mos trajto një parser sintakse si provë se projekti kompiloi.

## Prova e ndërfaqes

1. Nise në My Mac dhe në një simulator iPhone. Shfleto pa llogari dhe zgjidh nivelin. Hap çdo lëndë, një kapitull, një temë dhe një ushtrim.
2. Kontrollo 9-vjeçaren, gjimnazin I/II/III dhe olimpiadën: mësimet dhe lojërat duhet të ndryshojnë sipas nivelit.
3. Hap këto tema me figura: LM1-23 (trekëndësh), LF3-13/14 (qarqe), LF4-07 (përthyerje), LB1-07 (qelizë), LB2-28 (kryqëzim provë), LK1-06 (atom). Ndrysho rrëshqitësin aty ku ka dhe krahaso vlerat numerike. Hap një temë tjetër për hartën e zgjidhjes.
4. Luaj Battle, Escape, memorien, çiftimin dhe klasifikimin në dy nivele. Kontrollo ndërrimin e pyetjeve dhe përfundimin e lojës.
5. Zmadho shkrimin, rrotullo telefonin dhe provo VoiceOver. Kontrollo që teksti të mos pritet dhe kontrollet të mbeten të prekshme.

## Prova nga dy pajisje

1. Nis vetëm një server. Vendos të njëjtën adresë në të dyja pajisjet.
2. Regjistro një nxënës në pajisjen A. Hyr me të njëjtat të dhëna në B. Provo regjistrimin e të njëjtit email me shkronja të mëdha dhe fjalëkalim tjetër: nuk duhet të krijohet llogari tjetër.
3. Krijo ftesë mësuesi nga Terminali. Provoje me email tjetër: duhet të refuzohet. Përdore me emailin e saktë: duhet të pranohet vetëm një herë.
4. Krijo XI A dhe XI B me të njëjtin nivel. Regjistro dy nxënës dhe mirato secilin në klasën e vet. Publiko test vetëm te XI A: XI B nuk duhet ta shohë.
5. Nis test 1-minutësh, ruaj një përgjigje me arsyetim, dil dhe rihape nga B: afati dhe varianti duhet të mbeten të njëjtë. Prit afatin dhe provo përgjigje të vonuar: nuk duhet të pranohet.
6. Në profilin e mësuesit përditëso regjistrin. Lexo arsyetimin, jep pikë të pjesshme dhe komento. Nxënësi duhet të shohë pikët e reja pasi përditëson.
7. Lidh prindin me kodin e nxënësit. Kontrollo rezultatin dhe kalendarin. Revoko lidhjen; prindi nuk duhet të ketë më qasje pas përditësimit.
8. Shëno një mësim të lexuar dhe shkruaj shënim në A; sinkronizo, pastaj sinkronizo B. Ndrysho të njëjtin shënim në të dyja pajisjet para sinkronizimit: kopja që konflikton duhet të ruhet te Konfliktet.
9. Fike rrjetin gjatë testit: duhet të shfaqet se përgjigjja mbetet lokale. Pas afatit, drafti i vonuar nuk duhet të marrë pikë si i dorëzuar në kohë.
10. Rikupero fjalëkalimin me kodin personal: të dyja seancat e vjetra duhet të refuzohen. Hyr me fjalëkalimin e ri. Provo fshirjen e llogarisë me fjalëkalim të pasaktë dhe pastaj të saktë.

## Para publikimit

Përfundo provat e mësipërme, cakto serverin HTTPS dhe procesin e administrimit të shkollës, dhe rishiko informacionin e privatësisë për instalimin real. Përmbajtja dhe përshtatja me programin konkret duhet të shqyrtohen nga mësuesit. Nuk janë kryer audit i jashtëm sigurie, test ngarkese shkollore ose shqyrtim App Store.

Referenca Apple:
- https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices
- https://developer.apple.com/documentation/xcode/adding-tests-to-your-xcode-project
- https://developer.apple.com/documentation/xcode/running-tests-and-interpreting-results
