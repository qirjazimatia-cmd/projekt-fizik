# Raporti 8.4 · Faza 2: testet, dorëzimet dhe prindi

## Auditimi (çfarë ekzistonte dhe u verifikua në server)
Krijim → publikim → nisje me kohë nga serveri → ruajtje automatike → dorëzim → korrigjim automatik → korrigjim manual me pikë të pjesshme dhe koment → publikim → nxënësi dhe prindi i lidhur e shohin. Skema `app` nuk është e arritshme nga klienti; çdo veprim kalon nga `api_*`.

## Ndryshimet (`0006_phase2_submissions.sql`)
1. **Mbyllja e testit** dorëzon menjëherë përpjekjet në zhvillim (më parë vazhdonin deri në afatin personal).
2. **Dorëzime me skedarë**: kova private `submissions` në Supabase Storage. 25 MB për skedar, 10 për test, vetëm PDF/Word/tekst/foto/audio/video. Ngarkim e fshirje vetëm nga nxënësi ndërsa testi është i hapur; lexim nga nxënësi, mësuesi i testit dhe prindi i lidhur **vetëm pas publikimit**. Hapja bëhet me lidhje të përkohshme (10 min).
3. **`api_snapshot`** përpunon vetëm përpjekjet e përdoruesit (më parë të gjitha përpjekjet e shkollës, në çdo rifreskim).
4. `search_path` i fiksuar për `app.epoch` dhe `app.parse_number`.

## Aplikacioni
- Statuset te testi: "U ruajt në pajisje · dërgohet automatikisht", "Në pritje për dërgim…", "U dërgua në shërbimin e shkollës".
- Nxënësi: "Shto skedar" / "Hiq" për çdo pyetje.
- Mësuesi: skedarët dhe butoni "Hap" te ekrani i korrigjimit.
- macOS: leje vetëm-lexim për skedarët që zgjedh përdoruesi (`ENABLE_USER_SELECTED_FILES = readonly`).

## Statusi i provave
| Pjesa | Statusi |
|---|---|
| Rrjedha në server (18 prova, transaksion i anuluar) | **Provuar realisht** |
| Rregullat e skedarëve (ngarkim/lexim/fshirje sipas rolit) | Provuar realisht te funksionet `sq_can_*`; ngarkimi HTTP i vërtetë **i paprovuar** |
| `Tests/check_supabase_contract.py` | PASS |
| Kompilimi në Xcode dhe ekranet e reja | **Ende i paprovuar** |
| Pamja e skedarëve te prindi | Serveri i kthen; ekrani i prindit **ende nuk i shfaq** |

### 18 provat e serverit (të gjitha true)
krijim+publikim · ngarkim lejohet para dorëzimit, rrugë e gabuar refuzohet · dorëzim i dyfishtë s'ndryshon gjë · ndryshim pas dorëzimit refuzohet · skedar pas dorëzimit refuzohet · pa pikë para publikimit · nxënësi s'vlerëson veten · nxënësi tjetër s'lexon skedarin · mbyllja dorëzon menjëherë · s'ndryshohet pas mbylljes · mësuesi lexon skedarin · publikim pa vlerësuar pyetjen e hapur bllokohet · publikim pas vlerësimit (4/6) · nxënësi sheh 8/10 + koment · prindi lidhet me kod · prindi sheh 8/10 vetëm të fëmijës së vet · prindi lexon skedarin pas publikimit · prindi s'mund të nisë testin.

## Si të provohet në aplikacion
1. Xcode → ⌘B (dërgo çdo gabim).
2. Mësues: krijo test me një pyetje të hapur → publiko.
3. Nxënës: nis testin → shkruaj → "Shto skedar" (p.sh. një PDF ose foto) → Dorëzo.
4. Mësues: hap korrigjimin → "Hap" te skedari → vendos pikë + koment → Publiko.
5. Nxënës: duhet të shohë pikët dhe komentin.

## Kufizime të njohura
- Kur fshihet një klasë, skedarët e dorëzuar mbeten në Storage (nuk fshihen automatikisht).
- Testet plotësisht automatike publikohen menjëherë pas dorëzimit (sjellje e mëparshme, e pandryshuar).
- Mbrojtja nga fjalëkalimet e rrjedhura (HaveIBeenPwned) është e fikur te Supabase Auth; aktivizohet te Authentication → Policies nëse plani e lejon.
