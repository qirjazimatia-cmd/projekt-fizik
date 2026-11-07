# Bashkëpunimi në ScienceQuest (Git/GitHub, për fillestarë)

## Kush mund të bëjë çfarë
| Detyra | Windows/VS Code | Mac me Xcode |
| --- | :---: | :---: |
| Redaktim përmbajtjeje (`Lessons.json`, `Exercises.json`), `Tests/check_content.py` | po | po |
| Serveri Python dhe testet e tij, SQL i Supabase, dokumentacion | po | po |
| Kompilim, testet XCTest, Simulator, pajisje fizike, nënshkrim (Signing) | **jo** | **po** |
| Ndryshime te `project.pbxproj`, ikona, entitlements | **jo** | **po** |
Kodi Swift mund të lexohet në VS Code, por **vetëm Mac-u provon se kompilon**. Çdo PR me Swift duhet provuar në Mac para bashkimit.

## Rrjedha e punës
1. Një herë: `git clone <adresa>`. Për çdo punë të re: `git checkout main && git pull`, pastaj `git checkout -b emri-i-shkurtër` (p.sh. `permbajtje-kimi-niveli2`).
2. Ndrysho pak, bëj `git add <skedarët>` dhe `git commit -m "Çfarë ndryshoi dhe pse"`. Mos përdor `git add .` pa parë `git status`.
3. `git push -u origin emri-i-shkurtër`, hap **Pull Request** në GitHub. Pa u bashkuar, `main` nuk ndryshon.
4. Pritet që kontrollet automatike (`.github/workflows/ci.yml`) të kalojnë dhe një person tjetër ta shqyrtojë. `main` duhet të mbrohet te Settings → Branches (kërko PR dhe kontrolle të kaluara).

## Konfliktet
- **Lessons.json / Exercises.json:** puno në PR të vegjël, sipas lënde/niveli, dhe bëj `git pull` shpesh. Në konflikt, mos e zgjidh me “Accept both” verbalisht: hap të dyja versionet, ruaj çdo ndryshim, pastaj ekzekuto `python3 Tests/check_content.py`. Mos ndrysho kurrë një `id` ekzistues.
- **project.pbxproj:** një person i vetëm ndryshon strukturën e projektit (shton/heq skedarë) në një kohë. Nëse del konflikt, merr versionin e `main` (`git checkout --theirs ScienceQuest.xcodeproj/project.pbxproj` gjatë rebase/merge, ose `--ours` sipas rastit), pastaj **rishto skedarët e rinj në Xcode** dhe provo kompilimin. Mos përdor `merge=union`: mund të dublikojë objekte dhe ta prishë projektin.
- Nëse s’je i sigurt, ndalo dhe pyet; `git merge --abort` kthen gjendjen para konfliktit.

## Sekretet dhe të dhënat e nxënësve
- **Asnjëherë në Git:** çelësa `service_role`, fjalëkalime, çelësa privatë/certifikata (`.p12`, `.pem`, `.mobileprovision`), skedarë `.sqlite3` ose rezerva të serverit, emra/email nxënësish, `.env`, `Config.xcconfig`. `.gitignore` i mbulon shumicën, por nuk të mbron nëse e shton me `git add -f`.
- URL-ja e Supabase dhe çelësi publik (anon/publishable) vendosen në `Config.xcconfig` lokal, jashtë Git. Çelësi `service_role` nuk i duhet kurrë aplikacionit.
- Nëse një sekret futet gabimisht: **zëvendësoje/revoko menjëherë** te shërbimi përkatës; heqja nga Git nuk mjafton sepse mbetet në histori.
- `Tools/check_no_secrets.sh` kontrollon modelet e dukshme; përdoret edhe nga CI. Nuk zëvendëson skanuesin e plotë (p.sh. gitleaks).
- Workflow-et: `permissions: contents: read`, pa sekrete për PR nga forke; certifikatat e nënshkrimit nuk vendosen në CI pa miratim.
- Përdor llogari prove në zhvillim, jo të dhëna reale nxënësish.

## Para çdo PR
```bash
python3 Tests/check_content.py
(cd Server && python3 -m unittest -v test_server.py)
bash Tools/check_no_secrets.sh
```
Në Mac shtohet: `bash VERIFY-ON-MAC.command` (kompilim + XCTest). Mos shkruaj në PR “u testua” nëse nuk e ke ekzekutuar.
