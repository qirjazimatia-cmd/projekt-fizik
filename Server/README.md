# Shërbimi i shkollës — vetëm kod i këtij projekti

Python 3.11+, bibliotekat standarde; nuk nevojiten llogari në platforma të tjera. `school.sqlite3` krijohet automatikisht si skedar lokal i shërbimit. Ai ruan identitetet, klasat, provimet dhe progresin. Ky skedar nuk duhet shpërndarë me aplikacionin ose futur në ZIP-in publik.

## Provë në të njëjtin Mac

```bash
python3 server.py
```

Në aplikacion Debug: `http://localhost:8443`. Në një Terminal tjetër krijo ftesën e mësuesit:

```bash
python3 server.py --invite-teacher mesuesi@shkolla.example
```

Përdor të njëjtin folder dhe të njëjtin `--db` në të dyja komandat. Ftesa është kod 5-shifror (`--invite-digits 5..12`, ose `0` për kod të gjatë), lidhet me atë email, skadon pas 7 ditësh, përdoret një herë dhe bllokohet pas 5 gabimeve (numëruesi ruhet edhe kur kërkesa dështon). Një ftesë e re për të njëjtin email shfuqizon të vjetrën. Rreziku i mbetur: kush njeh emailin ka maksimumi 5 hamendje nga 100 000 për ftesë (≈0,005%); kodi duhet dhënë mësuesit përmes kanalit të besuar. Nuk shkruhet në kodin e aplikacionit.

## Provë në dy pajisje në të njëjtin Wi-Fi

Vetëm me llogari prove, në rrjet që kontrolloni:

```bash
python3 server.py --host 0.0.0.0 --allow-lan-demo
```

Në Mac gjej emrin lokal te System Settings → General → Sharing. Në aplikacionet e ndërtuara me **Debug**, vendos p.sh. `http://Emri-i-Mac.local:8443`. Lejo Local Network kur iPhone e kërkon dhe hyrjet për procesin Python në firewall-in e Mac-ut. `localhost` në telefon fizik do të thotë telefoni vetë, jo Mac-u. Routerët që izolojnë klientët Wi-Fi mund të bllokojnë këtë provë.

HTTP në këtë mënyrë është i pakriptuar: përdor vetëm llogari e përgjigje prove. Aplikacioni Release lejon vetëm HTTPS; nuk shtohen përjashtime globale ATS.

## Përdorim i përbashkët me HTTPS

Shkolla duhet të sigurojë një kompjuter/server që qëndron ndezur, një adresë të arritshme nga pajisjet dhe certifikatë TLS të besuar për atë adresë. Pastaj:

```bash
python3 server.py --host 0.0.0.0 --port 8443 --cert /rruga/fullchain.pem --key /rruga/private-key.pem --db /rruga/private/school.sqlite3
```

Vendos të njëjtën adresë `https://...:8443` te Lidhja e shkollës në të gjitha pajisjet, ose te `SchoolConfig.defaultURL` para shpërndarjes. Nuk janë konfiguruar automatikisht domain, certifikatë, firewall, adresë publike ose proces që riniset pas fikjes së serverit. Ato varen nga pajisja dhe rrjeti i shkollës.

Për instalim të qëndrueshëm, administratori duhet të vendosë rinisjen automatike të procesit, përditësimet, rezervat, kufijtë e trafikut dhe monitorimin. Serveri i përfshirë ka kufi lidhjesh, madhësie kërkese, kohë pritjeje dhe frekuence kërkesash; kjo nuk e bën zëvendësues për një audit sigurie ose provë ngarkese para përdorimit në shumë shkolla. Nuk ka certifikata ose fjalëkalime administratori të paravendosura.

## Sjellja e llogarive

- Email i normalizuar me kufi unik në ruajtjen e përbashkët; hyrja e dështuar nuk regjistron llogari.
- Scrypt N=131072, r=8, p=1, kripë e rastësishme 16-byte. Fjalëkalimet nuk ruhen si tekst.
- Seanca të veçanta për shumë pajisje, me token të rastësishëm 32-byte dhe jetë 30 ditë; vetëm hash-i i tokenit ruhet në server.
- Kodi personal i rikuperimit ruhet i hashuar, ndërrohet pas përdorimit dhe anulon të gjitha seancat.
- Emaili përdoret si identifikues; ky version nuk dërgon email verifikimi. Ftesa e mësuesit dhe miratimi i anëtarësimit kontrollohen nga shkolla.
- Roli verifikohet në server për çdo veprim. Fshirja e llogarisë kërkon fjalëkalimin aktual.
- Prindi lidhet me kod njëpërdorimësh të krijuar nga nxënësi, me mundësi revokimi.
- Çelësi dhe shpjegimet e provimit nuk dërgohen në përgjigjet API të nxënësit. Variantet e secilës përpjekje mbeten të njëjta pas rikthimit.
- Afati përdor orën e serverit. Dorëzimi i vonuar refuzohet edhe kur aplikacioni është modifikuar ose ora e telefonit është ndryshuar.

## Rezerva

Përdor mekanizmin `sqlite3.Connection.backup` për kopje të qëndrueshme gjatë punës, ose ndalo shërbimin përpara kopjimit. Mos kopjo vetëm skedarin kryesor ndërsa WAL-i po shkruhet. Ruaj kopjet në vend privat dhe provo rikthimin në një instalim të veçuar. Rezervat përmbajnë të dhëna nxënësish dhe materialet sekrete të provimeve.

Fshirja e një mësuesi fshin edhe klasat/testet e tij dhe të dhënat e lidhura. Fshirja e nxënësit fshin përpjekjet dhe lidhjet e tij. Rezervat e bëra më parë administrohen veçmas nga shkolla.

## Provat

```bash
python3 -m unittest -v test_server.py
```

Testet përdorin ruajtje të përkohshme dhe nuk prekin `school.sqlite3`. Nuk dërgojnë email. API-ja përdor POST `/api` me JSON `action`; shembujt e plotë të kontratës dhe kontrolleve të autorizimit janë te `test_server.py`.

Referenca teknike:
- https://docs.python.org/3/library/hashlib.html#hashlib.scrypt
- https://docs.python.org/3/library/sqlite3.html
- https://docs.python.org/3/library/ssl.html
- https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html
- https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html
