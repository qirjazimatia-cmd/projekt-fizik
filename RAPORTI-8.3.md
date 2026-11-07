# Raporti 8.3 · Faza 1: rastet e regjistrimit dhe emaili unik

## Ndryshimet
1. **Emaili krahasohet saktësisht** (`0005_email_key_exact.sql`): vetëm `lower(trim(email))`. Pikat dhe `+etiketa` nuk hiqen më. U zbatua te Supabase `projekt-fizik` më 7 nëntor; 9 profile, 0 përplasje.
2. **Rasti A · regjistrim i përsëritur**: aplikacioni e njeh nga përgjigjja e Supabase (`identities` bosh). Nuk krijohet llogari, roli nuk ndryshon. Ekrani "Ke tashmë një llogari. Hyr për të vazhduar." me butonat **Hyr** dhe **Harrova fjalëkalimin**. Roli nuk zbulohet para hyrjes.
3. **Rasti B · rol tjetër**: pas fjalëkalimit DHE kodit me email (pronësia e vërtetuar), shfaqet "Kjo adresë emaili ka rolin Mësues. Hyr nga seksioni Mësues. Për rol tjetër përdor një adresë tjetër emaili." dhe butoni për të vazhduar te këndi i rolit real. Serveri gjithsesi e refuzon ndryshimin e rolit (`api_chooserole` ndryshon vetëm `unassigned`; klienti nuk ka të drejtë shkrimi te `profiles.role`).
4. Rasti C (ekran i gabuar) dhe D (email i pakonfirmuar) ishin tashmë të mbuluara; nuk u ndryshuan.

## Statusi i provave
| Pjesa | Statusi |
|---|---|
| Migrimi 0005 në Supabase | Provuar realisht (SQL) |
| Kontrolli statik Swift↔SQL (`Tests/check_supabase_contract.py`) | PASS |
| Kompilimi në Xcode | **Ende i paprovuar** |
| Rasti A, B në aplikacion | **Ende i paprovuar** |

## Si të provohet
1. Xcode → ⌘B, pastaj ⌘R.
2. **A:** Regjistrohu me `juricavo91@gmail.com` → duhet "Ke tashmë një llogari" → Hyr → kodi me email → hapet këndi ekzistues.
3. **B:** Te seksioni tjetër (p.sh. Mësues nëse llogaria është nxënës) zgjidh Regjistrohu me të njëjtin email → "Ke tashmë një llogari" → Hyr + kodi → "Kjo adresë emaili ka rolin …".
4. **Email i ri:** regjistrim me email që s'është përdorur kurrë → duhet të vijë kodi i konfirmimit.
