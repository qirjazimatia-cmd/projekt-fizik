# Don Bosko Connect (ScienceQuest) · rregullat e punës për Claude

Ky repo punohet nga **dy persona, secili në bisedën e vet me Claude**: **Matia** dhe **Juri**.
Bisedat nuk e shohin njëra-tjetrën. E vetmja kujtesë e përbashkët është ky repo (kodi + GitHub Issues) dhe Supabase `projekt-fizik`.
Ndiq këto rregulla në çdo bisedë, pa përjashtim.

## 1. Kush po flet
- Në fillim të bisedës, nëse nuk e di, pyet: "Je Matia apo Juri?" Pastaj punon vetëm në emër të atij personi.
- Gjuha e punës: shqip.

## 2. Para çdo pune: lexo detyrat
Në bisedat e Claude, GraphQL i GitHub nuk lejohet (`gh issue list`, `gh pr list`, `gh label list` dështojnë). Përdor REST me `gh api`:
- Detyrat e hapura: `gh api "repos/qirjazimatia-cmd/projekt-fizik/issues?state=open&per_page=100" --jq '.[] | select(.pull_request|not) | "#\(.number) [\(.labels|map(.name)|join(","))] \(.title)"'`
- Merr detyrën: `gh api -X POST repos/qirjazimatia-cmd/projekt-fizik/issues/<nr>/labels -f "labels[]=<matia|juri>" -f "labels[]=në-punë"` dhe koment: `gh api -X POST repos/qirjazimatia-cmd/projekt-fizik/issues/<nr>/comments -f body="Filloi: ..."`
- PR-të e hapura dhe skedarët e tyre: `gh api "repos/qirjazimatia-cmd/projekt-fizik/pulls?state=open" --jq '.[] | "#\(.number) \(.head.ref) \(.title)"'` dhe `gh api repos/qirjazimatia-cmd/projekt-fizik/pulls/<nr>/files --jq '.[].filename'`
- Krijo PR: `gh api -X POST repos/qirjazimatia-cmd/projekt-fizik/pulls -f title=... -f head=<dega> -f base=main -f body=...`
- Gjendja e CI: `gh api "repos/qirjazimatia-cmd/projekt-fizik/actions/runs?branch=<dega>&per_page=3" --jq '.workflow_runs[] | "\(.status) \(.conclusion)"'`
- Bashko PR (vetëm kur CI kalon): `gh api -X PUT repos/qirjazimatia-cmd/projekt-fizik/pulls/<nr>/merge -f merge_method=squash`
- Etiketat: `matia`, `juri` (pronari), `në-punë` (po punohet tani), `supabase` (prek bazën e të dhënave), `zona-e-përbashkët`.
- **Mos prek kurrë një detyrë me etiketën e personit tjetër**, edhe nëse ai është offline. Thuaj kush e ka dhe sugjero një detyrë të lirë (pa pronar) ose të personit që po flet.
- Kur fillon një detyrë: vendos etiketën e personit + `në-punë` dhe shkruaj një koment "Filloi: <çfarë>".
- Detyrë e re që del gjatë punës: krijo Issue me etiketën e personit që e kërkoi.

## 3. Zonat
- **Matia:** faqja "Sot", koordinimi i ngarkesës së testeve, versioni web.
- **Juri:** projektet, portofoli, aktivitetet/klubet.
- **Zona e përbashkët** (`App/SchoolService.swift`, `App/Accounts.swift`, `App/ScienceQuestApp.swift`, `app.gate`, `api_snapshot`, `api_me`, autentikimi): ndryshime të vogla, në PR të veçantë, bashkohen shpejt. Para ndryshimit kontrollo PR-të e hapura të personit tjetër që prekin të njëjtin skedar (shih komandat e PR-ve më sipër). Nëse po, prit ose koordinohu me një koment te PR-ja e tij.

## 4. Git
- Askush nuk shkruan direkt te `main`. Degë: `matia/<detyra>` ose `juri/<detyra>`.
- Para se të fillosh: `git fetch origin main` dhe nis degën nga `origin/main` më i ri.
- Hap Pull Request me `Closes #<nr>`. CI (`.github/workflows/ci.yml`) kontrollon dhe ndërton në macOS dhe iOS Simulator (kjo është prova e vetme e kompilimit kur Xcode i personit nuk është i arritshëm); bashko vetëm kur CI kalon.
- Pas bashkimit, thuaj personit: Xcode → Source Control → Pull (ose `git pull`).

## 5. Supabase (`projekt-fizik`, i përbashkët)
- Migrime të reja: `Supabase/migrations/YYYYMMDD_HHMM_<emri>_<përshkrimi>.sql` (p.sh. `20261108_1200_matia_sot.sql`).
- Zbato në Supabase **vetëm pasi PR-ja të jetë bashkuar** (ose me pëlqimin e qartë të personit, për prova), dhe vetëm pasi të kesh kontrolluar `list_migrations` dhe Issues me `supabase` + `në-punë` të personit tjetër.
- Mos ridefino një funksion/tabelë që po ndryshohet në PR-në e hapur të personit tjetër.
- Skema `app` mbetet e mbyllur për klientin: çdo veprim i ri kalon nga `public.api_*` me `app.gate(...)`. Rregulla RLS lejohen vetëm për `storage.objects` (shih `Tests/check_supabase_contract.py`).
- Provat e serverit bëhen brenda transaksionit që anulohet (`raise exception` në fund), që të mos mbeten të dhëna prove.

## 6. Ndershmëria
- Mos thuaj "punon" pa e provuar. Dallo: implementuar · provuar realisht · në pritje konfigurimi · i papërfunduar.
- Mos vendos sekrete, kodin e mësuesit ose çelësa `service_role`/`sb_secret_` në repo. Çelësi `sb_publishable_...` lejohet (është publik).
- Mos ndrysho përmbajtjen e mësimeve/laboratorëve dhe Bundle ID-në pa kërkesë të qartë.

## 7. Udhëzimi bazë
Kërkesat e plota të produktit janë te `PROMPT-DON-BOSKO.md`. Raportet e versioneve: `RAPORTI-*.md`.
