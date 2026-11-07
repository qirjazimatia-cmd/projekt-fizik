# Raporti 8.1 + 8.2 (ndryshimet pas testit të parë me Supabase)

**Statusi:** kodi Swift dhe SQL-i i ri NUK janë kompiluar/ekzekutuar nga autori (nuk ka Xcode/PostgreSQL në mjedisin e punës). Kontrollet e ekzekutuara: 17 teste Python të serverit të vjetër, kontrolli i përmbajtjes, kontrolli statik Swift↔SQL, kontrolli i sekreteve. Provat reale mbeten te ekipi.

## Çfarë ndryshoi
1. **2FA në çdo hyrje.** Serveri (`app.mfa_ok`) kërkon sesion aal2 kur `require_mfa` = `all` (parazgjedhja) ose kur përdoruesi ka faktor. Aplikacioni ka ekran të ri të detyrueshëm konfigurimi (QR + kod) pas konfirmimit të emailit dhe e kërkon kodin në çdo hyrje me fjalëkalim. Kodi i emailit konfirmon vetëm emailin. Faktori nuk çaktivizohet nga aplikacioni kur është i detyrueshëm; humbja rregullohet nga administratori (`app.admin_reset_mfa`). Kufi: seanca e ruajtur te Keychain rikthehet pa kod të ri derisa të skadojë (JWT aal2).
2. **Një email = një llogari.** Çelës normalizues (`app.email_key`): shkronja të vogla, heqje e +etiketës, heqje e pikave për Gmail; indeks unik; ndjekje e ndryshimit të emailit. Roli mbetet i vetëm dhe nuk ndryshohet. Mesazh i qartë nëse emaili ka llogari; nuk zbulohet nëse ekziston te ekrani i kodit.
3. **Harrova fjalëkalimin.** Kodi i rikuperimit nuk humbet kur fjalëkalimi i ri refuzohet; butoni "Ridërgo kodin"; mesazhe për kufirin 60 sekonda. KËRKON që shablloni *Reset password* te Supabase të përdorë `{{ .Token }}` (shih SUPABASE-SETUP §4).
4. **Fshirja e klasave dhe e testeve** (vetëm pronari, me konfirmim): `api_classDelete`, `api_examDelete`; testi i publikuar fshihet vetëm pasi të mbyllet. Fshirja e klasës heq në kaskadë anëtarësimet, testet, notat dhe eventet.
5. **Testet nga banka e ushtrimeve.** Zgjedhje sipas lëndës dhe nivelit të klasës, kërkim, "shto 5 rastësisht", pastaj redaktim; pyetjet personale mbeten. Përjashtohen 20 ushtrime me dy përgjigje të sakta (testi pranon një).
6. **Kalendar interaktiv.** Pamje mujore me pika për ditët me evente (portokalli = test), navigim muaji, "Sot", filtër klase, pamje "Të ardhshmet", "Shto këtu" për mësuesin.

## Ruajtur pa ndryshim
Mësimet, ushtrimet, laboratorët, Bundle ID, mekanizmi i ruajtjes. Asnjë sekret ose kod mësuesi nuk shtohet në projekt.

## 8.2 · Kodi me email në çdo hyrje
Përdoruesi kërkoi që faktori i dytë të jetë kod që vjen te emaili i regjistrimit (jo aplikacion autentikimi). Zbatuar me kontroll nga serveri: tabelat `login_codes` (hash, skadim 10 min, 5 gabime) dhe `session_2fa`, `app.mfa_ok` kërkon kodin e verifikuar për seancën (claim `session_id`), `api_loginCodeVerify`, `internal_issue_login_code` (vetëm service role), Edge Function `send-login-code` (Gmail SMTP me secrets). **Pa u vendosur funksioni te Supabase, hyrja me parazgjedhjen `email` ndalon**; shih SUPABASE-SETUP §8 dhe kthimin te `totp`. Asnjë pjesë e kësaj rruge nuk është provuar nga autori (as Swift, as SQL, as Edge Function).
