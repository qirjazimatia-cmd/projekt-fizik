import Foundation

enum Subject: String, CaseIterable, Identifiable {
    case physics = "Fizikë", math = "Matematikë", chemistry = "Kimi", biology = "Biologji"
    var id: Self { self }
    var icon: String {
        switch self {
        case .physics: return "atom"
        case .math: return "chart.bar.fill"
        case .chemistry: return "testtube.2"
        case .biology: return "leaf.fill"
        }
    }
}

struct Question {
    let prompt: String
    let options: [String]
    let correct: Int
    let why: String
    init(_ prompt: String, _ options: [String], _ correct: Int, _ why: String) {
        self.prompt = prompt; self.options = options; self.correct = correct; self.why = why
    }
}

struct Lesson: Identifiable {
    let subject: Subject
    let title: String
    let explanation: String
    let example: String
    let question: Question
    var id: String { title }
    var level: SchoolLevel {
        switch title {
        case "Nxitimi", "Lëvizja rrethore", "Forcat dhe ligjet e Njutonit", "Nga lartësia te shpejtësia", "Energjia e sustës",
             "Përqendrimi molar", "Reaktanti kufizues", "Neutralizimi", "Oksidimi",
             "Trashëgimia", "Faktorët kufizues të fotosintezës", "Enzimat dhe kushtet", "Osmoza në qelizë": return .first
        case "Qarqet elektrike", "Valët dhe grimcat", "Sinusi në rreth", "Pse shtata fiton te zaret?", "Shkalla logaritmike e pH-së": return .second
        default: return .basic
        }
    }

    init(_ subject: Subject, _ title: String, _ explanation: String, _ example: String, _ question: Question) {
        self.subject = subject; self.title = title; self.explanation = explanation
        self.example = example; self.question = question
    }
}

let lessons: [Lesson] = [
    Lesson(.physics, "Shpejtësia mesatare", "Pjesëto rrugën e plotë me kohën e plotë, përfshirë ndalesat. v = s / t.", "Përshkon 600 m me biçikletë për 2 minuta. Meqë 2 min = 120 s, shpejtësia mesatare është 5 m/s.", Question("Një autobus përshkon 18 km për 30 minuta. Sa është shpejtësia mesatare?", ["9 km/h", "36 km/h", "60 km/h"], 1, "Gjysmë ore është 0,5 h. Pra, 18 / 0,5 = 36 km/h.")),
    Lesson(.physics, "Nxitimi", "Nxitimi mesatar tregon sa ndryshon shpejtësia vektoriale për njësi kohe. a = Δv / Δt.", "Kur një tren ecën drejt dhe kalon nga 3 në 9 m/s për 3 s, nxitimi mesatar është 2 m/s².", Question("Një makinë ecën drejt dhe kalon nga 4 në 14 m/s për 5 s. Sa është nxitimi mesatar?", ["2 m/s²", "5 m/s²", "10 m/s²"], 0, "Ndryshimi është 14 − 4 = 10 m/s. Pjesëto 10 me 5 s.")),
    Lesson(.physics, "Lëvizja rrethore", "Edhe kur moduli i shpejtësisë mbetet konstant, në kthesë ndryshon drejtimi. Nxitimi qendërsynues drejtohet nga qendra.", "Në një rrethrrotullim të sheshtë, fërkimi ndërmjet gomave dhe rrugës siguron forcën drejt qendrës.", Question("Kur një top që rrotullohet me pe lirohet, në ç’drejtim lëviz në çastin e parë?", ["Nga qendra", "Drejt qendrës", "Sipas tangjentes"], 2, "Në çastin e lëshimit, shpejtësia ka drejtimin e tangjentes.")),
    Lesson(.physics, "Forcat dhe ligjet e Njutonit", "Kur rezultantja është zero, trupi ruan shpejtësinë vektoriale. Kur ka forcë rezultante, F = m · a. Dy trupa që bashkëveprojnë ushtrojnë mbi njëri-tjetrin forca të barabarta e të kundërta.", "Një karrocë me masë 4 kg, mbi të cilën vepron një forcë rezultante 8 N, merr nxitim 2 m/s².", Question("Ti shtyn murin me 20 N. Sa është madhësia e forcës që muri ushtron mbi ty?", ["0 N", "20 N", "40 N"], 1, "Sipas ligjit të tretë, këto dy forca kanë madhësi të njëjtë dhe veprojnë mbi trupa të ndryshëm.")),
    Lesson(.physics, "Masa dhe pesha", "Masa matet në kilogramë. Një trup i palëvizshëm mbi një mbështetëse horizontale ushtron mbi të peshën P = m · g, që matet në njutonë.", "Në Hënë një çantë ka të njëjtën masë si në Tokë, por rëndon më pak.", Question("Sa peshon një çantë 3 kg që qëndron mbi tavolinë? Merr g = 10 N/kg.", ["3 N", "0,3 N", "30 N"], 2, "P = 3 kg × 10 N/kg = 30 N.")),
    Lesson(.math, "Përqindjet", "Një për qind është një e qindta e së tërës. Shumëzo të tërën me përqindjen dhe pjesëto me 100.", "Në një klasë me 25 nxënës, 20% shkojnë me biçikletë. Pra, 25 × 20 / 100 = 5 nxënës.", Question("Një libër kushton 800 lekë. Sa paguan pas një uljeje prej 25%?", ["600 lekë", "200 lekë", "775 lekë"], 0, "Ulja është 200 lekë. Çmimi i ri është 800 − 200 = 600 lekë.")),
    Lesson(.math, "Leximi i grafikëve", "Lexo madhësinë dhe njësinë në secilin bosht. Në një grafik rrugë–kohë, pjerrësia tregon shpejtësinë.", "Një vijë horizontale për 2 minuta tregon se rruga e përshkuar mbeti e njëjtë gjatë atij intervali.", Question("Në grafikun rrugë–kohë, rruga rritet nga 10 në 40 m midis sekondës 2 dhe sekondës 8. Sa është shpejtësia mesatare?", ["4 m/s", "5 m/s", "15 m/s"], 1, "Ndaj ndryshimin e rrugës me intervalin kohor: (40 − 10) / (8 − 2) = 5 m/s.")),
    Lesson(.chemistry, "Acidet dhe bazat", "Për tretësirat ujore në 25 °C, pH nën 7 tregon mjedis acid, pH 7 neutral dhe pH mbi 7 bazik.", "Lëngu i limonit është acid. Me letër treguese mund ta krahasosh me një tretësirë sode buke.", Question("Cila nga këto tretësira ujore është bazike në 25 °C?", ["pH 3", "pH 7", "pH 9"], 2, "Vlera 9 është më e madhe se 7.")),
    Lesson(.chemistry, "Oksidimi", "Gjatë oksidimit një grimcë humbet elektrone. Ndryshku formohet kur hekuri bashkëvepron me oksigjenin në prani të ujit.", "Boja e paprekur e mbron parmakun e hekurt duke e ndarë sipërfaqen nga uji dhe oksigjeni.", Question("Pse një gërvishtje në bojë e bën parmakun më të prekshëm nga ndryshku?", ["Ekspozon hekurin", "Rrit masën e hekurit", "Largon oksigjenin"], 0, "Te gërvishtja, uji dhe oksigjeni mund të arrijnë te hekuri.")),
    Lesson(.biology, "Zemra dhe pulsi", "Zemra pompon gjak. Pulsi është vala e presionit që përhapet në arterie pas çdo tkurrjeje të barkusheve.", "Nëse numëron 18 rrahje në 15 sekonda dhe ritmi mbetet i njëjtë, në një minutë priten 72 rrahje.", Question("Numëron 20 rrahje në 15 sekonda. Sa rrahje në minutë i përgjigjen këtij ritmi?", ["60", "80", "100"], 1, "Një minutë ka katër intervale nga 15 sekonda. 20 × 4 = 80.")),
    Lesson(.biology, "Frymëmarrja", "Në alveolat e mushkërive, oksigjeni kalon nga ajri në gjak dhe dioksidi i karbonit kalon nga gjaku në ajër.", "Gjatë vrapimit, muskujt zakonisht konsumojnë më shumë oksigjen dhe prodhojnë më shumë dioksid karboni. Frymëmarrja përshpejtohet.", Question("Ku kalon oksigjeni nga ajri në gjak?", ["Në trake", "Në diafragmë", "Në alveola"], 2, "Muret shumë të holla të alveolave dhe kapilarëve mundësojnë shkëmbimin e gazeve.")),
    Lesson(.biology, "Ushqyerja", "Karbohidratet dhe yndyrat furnizojnë trupin me energji. Proteinat sigurojnë aminoacide për ndërtimin dhe riparimin e indeve.", "Në një etiketë, sasia e lëndëve ushqyese mund të jepet për 100 g. Për një racion tjetër, ndryshoje në përpjesëtim me masën.", Question("Një ushqim ka 8 g proteina për 100 g. Sa proteina ka në një racion prej 150 g?", ["12 g", "8 g", "16 g"], 0, "Racioni është 1,5 herë më i madh: 8 × 1,5 = 12 g.")),
    Lesson(.physics, "Dendësia dhe vëllimi", "Dendësia tregon masën për njësi vëllimi. Për krahasim, përdor të njëjtat njësi. Një trup homogjen pluskon në një lëng kur dendësia e tij mesatare është më e vogël se ajo e lëngut.", "Një gur me masë 90 g zhvendos 30 cm³ ujë. Dendësia është 90 / 30 = 3 g/cm³.", Question("Një kub ka masë 80 g dhe vëllim 20 cm³. Gjej dendësinë.", ["4 g/cm³", "8 g/cm³", "2 g/cm³"], 0, "ρ = 80 / 20.")),
    Lesson(.physics, "Presioni", "Presioni është forca pingule mbi njësi sipërfaqeje. Për të njëjtën forcë, zvogëlimi i sipërfaqes rrit presionin.", "Një kuti shtyp dyshemenë me 60 N mbi 0,2 m². Presioni është 300 Pa.", Question("Një pllakë ushtron forcë 90 N mbi 0,3 m². Gjej presionin.", ["600 Pa", "300 Pa", "150 Pa"], 1, "p = 90 / 0,3.")),
    Lesson(.physics, "Energjia dhe fuqia", "Fuqia mesatare tregon sa punë kryhet në njësi kohe. Një vat është një xhaul për sekondë.", "Një motor që kryen 900 J punë në 3 s ka fuqi mesatare 300 W.", Question("Një vinç kryen 2400 J punë në 8 s. Gjej fuqinë.", ["600 W", "150 W", "300 W"], 2, "P = 2400 / 8.")),
    Lesson(.physics, "Qarqet elektrike", "Për një rezistor omik, tensioni është prodhimi i rezistencës me rrymën. Në seri rryma është e njëjtë dhe rezistencat mblidhen.", "Me një burim 6 V dhe një rezistor 3 Ω, rryma është I = 6 / 3 = 2 A.", Question("Një rezistor 12 Ω lidhet në 6 V. Gjej rrymën.", ["0,5 A", "1 A", "0,25 A"], 0, "I = U / R.")),
    Lesson(.math, "Probabiliteti", "Kur rezultatet janë njësoj të mundshme, probabiliteti është raporti i rezultateve të favorshme me të gjitha rezultatet e mundshme.", "Në një qese me 2 topa blu dhe 3 të bardhë, probabiliteti për të nxjerrë një blu është 2/5, pra 40%.", Question("Nga 8 letra të njëjta në prekje, 2 janë të kuqe. Sa për qind është mundësia të të bjerë e kuqe?", ["50 %", "25 %", "12,5 %"], 1, "2 / 8 × 100 = 25%.")),
    Lesson(.math, "Ekuacionet", "Për të ruajtur barazimin, kryej të njëjtin veprim në të dyja anët. Kontrolloje zgjidhjen duke e zëvendësuar në ekuacion.", "Në 3x + 4 = 19, zbrit 4 dhe pjesëto me 3. Del x = 5.", Question("Një numër i trefishuar plus 7 jep 28. Cili është numri?", ["14 ", "3,5 ", "7 "], 2, "3x = 21, ndaj x = 7.")),
    Lesson(.math, "Gjeometria në praktikë", "Perimetri mat gjatësinë e kufirit, ndërsa syprina mat zonën brenda tij. Për trekëndëshin përdor lartësinë pingule mbi bazën.", "Një parcelë 7 m me 4 m ka perimetër 22 m dhe syprinë 28 m².", Question("Sa metra gardh duhen për një kopsht drejtkëndor 12 m me 5 m pa hyrje?", ["34 m", "68 m", "17 m"], 0, "P = 2 × (12 + 5).")),
    Lesson(.math, "Statistika", "Mesatarja përdor të gjitha vlerat. Mediana është vlera e mesit pas renditjes, ndërsa moda është vlera më e shpeshtë.", "Për 2, 3, 3, 8 mediana është 3. Mesatarja është 4 sepse shuma është 16.", Question("Gjej medianën e numrave 9, 2, 7, 4 dhe 6.", ["12 ", "6 ", "3 "], 1, "Renditja është 2, 4, 6, 7, 9.")),
    Lesson(.chemistry, "Atomet dhe jonet", "Numri atomik Z tregon numrin e protoneve. Atomi neutral ka po aq elektrone sa protone. Humbja e elektroneve jep një jon pozitiv.", "Natriumi ka 11 protone. Joni Na⁺ ka humbur një elektron, prandaj ka 10 elektrone.", Question("Karboni ka Z = 6. Sa protone ka?", ["12 protone", "3 protone", "6 protone"], 2, "Numri atomik është numri i protoneve.")),
    Lesson(.chemistry, "Reaksionet kimike", "Në një reaksion atomet riorganizohen. Koeficientët para formulave tregojnë raportet e grimcave. Në të dyja anët duhet të ketë po aq atome të secilit element.", "Në 2H₂ + O₂ → 2H₂O kemi katër atome hidrogjeni dhe dy oksigjeni në secilën anë.", Question("Në 3CO₂, sa atome oksigjeni ka gjithsej?", ["6 atome", "12 atome", "3 atome"], 0, "Çdo molekulë ka 2 atome O.")),
    Lesson(.chemistry, "Përqendrimi molar", "Përqendrimi molar llogaritet duke pjesëtuar sasinë në mol me vëllimin e tretësirës në litra. Kur vetëm shtojmë ujë, sasia e lëndës së tretur ruhet.", "Nëse 0,2 mol kripë gjenden në 0,5 L tretësirë, përqendrimi është 0,4 mol/L.", Question("Një tretësirë 2 L përmban 3 mol substancë. Gjej përqendrimin.", ["3 mol/L", "1,5 mol/L", "0,75 mol/L"], 1, "c = 3 / 2.")),
    Lesson(.chemistry, "Tretshmëria dhe kristalizimi", "Tretshmëria jep sasinë maksimale që mund të tretet në një sasi të caktuar tretësi, në temperaturën e dhënë. Lënda e tepërt mbetet e patretur.", "Nëse kufiri është 30 g për 100 g ujë, në 200 g ujë treten deri në 60 g në të njëjtën temperaturë.", Question("Në një temperaturë të caktuar treten deri 20 g kripë për 100 g ujë. Sa treten në 300 g ujë?", ["120 g", "30 g", "60 g"], 2, "Masa e ujit trefishohet.")),
    Lesson(.biology, "Mikroskopi dhe qeliza", "Zmadhimi i përgjithshëm është prodhimi i zmadhimit të okularit me atë të objektivit. Madhësia reale gjendet duke pjesëtuar madhësinë e figurës me zmadhimin.", "Okulari 10× me objektivin 40× jep zmadhim 400×. Një qelizë 0,02 mm shfaqet 8 mm në figurë.", Question("Okulari zmadhon 10 herë dhe objektivi 20 herë. Gjej zmadhimin e përgjithshëm.", ["200 herë", "400 herë", "100 herë"], 0, "10 × 20 = 200.")),
    Lesson(.biology, "Ekosistemet", "Rrjetat ushqimore tregojnë si kalon energjia nga prodhuesit te konsumatorët. Vetëm një pjesë e energjisë së një niveli kalon te niveli pasues.", "Në një model ku kalon 10% e energjisë, nga 2000 kJ të bimëve kalojnë 200 kJ te barngrënësit. Përqindja reale ndryshon sipas ekosistemit.", Question("Në një model me transferim 10%, sa kJ nga 3000 kJ të prodhuesve arrijnë te barngrënësit?", ["600 kJ", "300 kJ", "150 kJ"], 1, "3000 × 0,10 = 300.")),
    Lesson(.biology, "Trashëgimia", "Në modelin e thjeshtë mendelian, pasardhësi merr një alel nga secili prind. Për prindër Aa, çdo gametë ka mundësi të barabartë të mbajë A ose a.", "Kryqëzimi Aa × aa jep kombinimet Aa dhe aa në përpjesëtim të pritshëm 1 me 1. Ky është parashikim probabilistik.", Question("Në kryqëzimin Aa × Aa, sa për qind e pasardhësve pritet të kenë gjenotip aa?", ["50 %", "12,5 %", "25 %"], 2, "Një nga katër kombinimet është aa.")),
    Lesson(.biology, "Eksperimenti biologjik", "Për të provuar një hipotezë, ndrysho një faktor dhe mbaj të krahasueshëm të tjerët. Përsëritjet të ndihmojnë të dallosh prirjen nga rastësia.", "Për të studiuar dritën dhe rritjen, mbaji të njëjta farat, ujin dhe temperaturën. Mat gjatësinë në të njëjtën orë për çdo grup.", Question("Nga 40 fara mbijnë 32. Gjej përqindjen e mbirjes.", ["80 %", "160 %", "40 %"], 0, "32 / 40 × 100 = 80%.")),
    Lesson(.physics, "Nga lartësia te shpejtësia", "Për një trup që nis nga qetësia dhe lëviz pa fërkim, energjia potenciale gravitacionale që humbet bëhet energji kinetike: mgΔh = mv²/2. Niveli zero i EPG-së zgjidhet dhe përdoret njësoj gjatë llogaritjes.", "Një trup 2 kg zbret 5 m me g = 10 m/s². Fiton 100 J EK dhe shpejtësia bëhet 10 m/s.", Question("Sa EK fiton një trup 3 kg kur zbret 4 m pa fërkim, me g = 10?", ["30 J", "120 J", "60 J"], 1, "EK e fituar = mgΔh = 3 × 10 × 4 = 120 J.")),
    Lesson(.physics, "Energjia e sustës", "Një sustë ideale ruan energji kur shtypet ose zgjatet. E = kx²/2, ku x matet nga gjatësia natyrore. Formula zbatohet kur susta i bindet ligjit të Hukut.", "Me k = 100 N/m dhe x = 0,2 m, energjia është 2 J. Në x = 0,4 m bëhet 8 J.", Question("Nëse zgjatja dyfishohet, energjia elastike bëhet…", ["2 herë më e madhe", "E njëjtë", "4 herë më e madhe"], 2, "Energjia varet nga x², prandaj faktori është 2² = 4.")),
    Lesson(.physics, "Valët dhe grimcat", "Shpejtësia e përhapjes së një vale periodike është v = fλ. Grimcat e mjedisit lëkunden rreth pozicionit të ekuilibrit; në modelin e valës në litar, një pikë lëviz lart e poshtë ndërsa forma e valës përparon.", "Nëse f = 4 Hz dhe λ = 2 m, vala përhapet me 8 m/s.", Question("Një valë ka v = 12 m/s dhe f = 3 Hz. Sa është λ?", ["4 m", "36 m", "0,25 m"], 0, "λ = v/f = 12/3 = 4 m.")),
    Lesson(.math, "Sinusi në rreth", "Pika mbi një rreth me qendër në origjinë ka koordinata (r cos θ, r sin θ). Këndi matet nga gjysmëboshti pozitiv x, në drejtim kundër akrepave të orës.", "Me r = 2 dhe θ = 30°, y = 2 sin 30° = 1.", Question("Për r = 3 dhe θ = 90°, sa është y?", ["0", "1", "3"], 2, "sin 90° = 1, ndaj y = r = 3.")),
    Lesson(.math, "Fuqitë dhe rritja", "Në rritjen gjeometrike, çdo hap shumëzon sasinë me të njëjtin koeficient. Nëse nis me N₀ dhe koeficienti është a, pas n hapash N = N₀aⁿ.", "Me 5 pika fillestare dhe dyfishim në çdo hap, pas tre hapash ke 5 × 2³ = 40.", Question("Nis me 10 dhe trefisho çdo hap. Sa ke pas dy hapash?", ["90", "60", "30"], 0, "10 × 3² = 90.")),
    Lesson(.math, "Pse shtata fiton te zaret?", "Me dy zare të paanshme ka 36 çifte të renditura. Shuma 7 realizohet nga (1,6), (2,5), (3,4), (4,3), (5,2), (6,1). Shumat nuk janë njësoj të mundshme.", "P(shuma 7) = 6/36 = 1/6. Në një seri të shkurtër rezultatet mund të ndryshojnë shumë nga këto përpjesëtime.", Question("Sa çifte japin shumën 4?", ["2", "3", "4"], 1, "Çiftet janë (1,3), (2,2) dhe (3,1).")),
    Lesson(.chemistry, "Reaktanti kufizues", "Koeficientët e reaksionit tregojnë sasitë që reagojnë. Për të gjetur reaktantin kufizues, krahaso sasinë në mol të secilit me koeficientin e tij. Raporti më i vogël kufizon sasinë e produktit.", "Në 2H₂ + O₂ → 2H₂O, 6 mol H₂ dhe 2 mol O₂ japin 4 mol ujë. Mbeten 2 mol H₂.", Question("Me 3 mol H₂ dhe 2 mol O₂, cili është reaktanti kufizues?", ["H₂", "O₂", "H₂O"], 0, "3/2 = 1,5 është më i vogël se 2/1 = 2.")),
    Lesson(.chemistry, "Neutralizimi", "Për një acid të fortë monoprotik dhe bazë të fortë, H⁺ reagon me OH⁻ në raport 1 me 1. Krahason molët, jo vetëm vëllimet. Në pikën ekuivalente të këtij modeli, në 25°C pH është 7.", "20 mL acid 0,1 mol/L japin 0,002 mol H⁺. Duhen 10 mL bazë 0,2 mol/L për t’i neutralizuar.", Question("Përqendrimet janë të njëjta. Çfarë vëllimi baze neutralizon 40 mL acid?", ["20 mL", "40 mL", "80 mL"], 1, "Kur raporti është 1:1 dhe përqendrimet të barabarta, edhe vëllimet janë të barabarta.")),
    Lesson(.chemistry, "Shkalla logaritmike e pH-së", "Në modelin e tretësirave ideale të holluara, pH = −log₁₀[H⁺]. Një ulje me një njësi do të thotë dhjetëfishim i përqendrimit të H⁺.", "Nga pH 5 në pH 3, [H⁺] rritet 100 herë: nga 10⁻⁵ në 10⁻³ mol/L.", Question("Nga pH 4 në pH 6, përqendrimi i H⁺…", ["Rritet 100 herë", "Ulet 2 herë", "Ulet 100 herë"], 2, "10⁻⁶/10⁻⁴ = 10⁻² = 1/100.")),
    Lesson(.biology, "Faktorët kufizues të fotosintezës", "Drita, CO₂, temperatura dhe furnizimi me ujë ndikojnë te fotosinteza. Kur një faktor kufizon procesin, shtimi i një tjetri mund të mos e rritë ritmin.", "Në laboratorin virtual, drita është 80% dhe CO₂ 30%. Modeli e kufizon aktivitetin në 30%; kjo shkallë është ilustruese.", Question("Në modelin me dritë 80% dhe CO₂ 30%, cilin faktor duhet të shtosh si fillim?", ["Dritën", "CO₂", "Të ulësh të dy"], 1, "CO₂ është faktori më i pakët në këtë model.")),
    Lesson(.biology, "Enzimat dhe kushtet", "Enzimat përshpejtojnë reaksionet biologjike. Forma dhe aktiviteti i tyre varen nga kushtet. Temperatura dhe pH optimal ndryshojnë nga një enzimë te tjetra.", "Laboratori ynë përdor një enzimë hipotetike me maksimum në 37°C dhe pH 7; këto vlera nuk vlejnë për çdo enzimë.", Question("A kanë të gjitha enzimat të njëjtin pH optimal?", ["Jo, ai ndryshon", "Po, gjithmonë 7", "Po, gjithmonë 1"], 0, "Enzimat punojnë në mjedise të ndryshme dhe kanë përshtatje të ndryshme.")),
    Lesson(.biology, "Osmoza në qelizë", "Uji kalon përmes një membrane që e lejon, por që mund të mos lejojë substancat e tretura. Me presion fillestar të njëjtë, lëvizja neto e ujit është drejt anës më të përqendruar me lëndë të tretur që nuk kalon membranën.", "Një copë patateje në tretësirë kripe mjaft të përqendruar mund të humbë ujë dhe masë.", Question("Nëse jashtë qelizës ka më shumë lëndë të tretur që nuk kalon membranën, uji priret…", ["Të hyjë në qelizë", "Të mos lëvizë kurrë", "Të dalë nga qeliza"], 2, "Në kushtet e modelit, ana e jashtme ka potencial më të ulët të ujit."))
]

struct Activity: Identifiable {
    let subject: Subject
    let title: String
    let materials: String
    let steps: [String]
    let discuss: String
    var id: String { title }
}
let activities = [
    Activity(subject: .physics, title: "Mat shpejtësinë e një lodre", materials: "Makinë lodër, metër, kronometër, shirit letre.", steps: ["Shëno dy pika 2 m larg në dysheme.", "Njëri vë në lëvizje lodrën. Tjetri mat kohën ndërmjet pikave.", "Përsëriteni tri herë dhe llogaritni 2 / t për çdo provë."], discuss: "Sa ndryshojnë rezultatet? Si ndikon koha e reagimit te matja?"),
    Activity(subject: .math, title: "Nga matja te grafiku", materials: "Letër me katrorë, vizore, laps.", steps: ["Përdorni matjet e një lodre: në çastet 0, 1, 2 dhe 3 s, rruga është përkatësisht 0, 2, 4 dhe 6 m.", "Njëri shënon kohën në boshtin horizontal dhe rrugën në atë vertikal. Tjetri vendos pikat.", "Bashkojini pikat. Krahasoni pjerrësinë me simulimin e lëvizjes."], discuss: "Si do të ndryshonte grafiku po të dyfishohej shpejtësia?"),
    Activity(subject: .chemistry, title: "Gjurmo acidet me ngjyra", materials: "Letër treguese pH me shkallë ngjyrash, gota, ujë, lëng limoni, sodë buke.", steps: ["Hidhni ujë në tri gota. Lërini njërën si provë krahasuese, shtoni limon në të dytën dhe pak sodë buke në të tretën.", "Parashikoni cila gotë ka pH më të ulët. Përdorni nga një shirit të ri për çdo gotë.", "Lexoni ngjyrat sipas udhëzimit të shiritit. Shënoni vlerat e përafërta. Mos i shijoni tretësirat."], discuss: "A u përputh renditja me parashikimin? Çfarë kufizimi ka shkalla e ngjyrave?"),
    Activity(subject: .biology, title: "Nga etiketa te racioni", materials: "Dy etiketa ushqimore, letër dhe laps.", steps: ["Gjeni gramët e proteinave për 100 g në të dyja etiketat.", "Zgjidhni një racion prej 60 g dhe llogaritni sasinë për secilin produkt.", "Këmbeni llogaritjet me një shok dhe vizatoni dy shtylla për krahasim."], discuss: "Pse krahasimi bëhet më i qartë kur përdoret e njëjta masë?")
] + extraActivities
let discoveries = [
    (Subject.physics, "Pse anohesh përpara kur frenon autobusi?", "Këmbët ngadalësohen bashkë me dyshemenë, ndërsa pjesa e sipërme e trupit priret të ruajë shpejtësinë e mëparshme për shkak të inercisë."),
    (.math, "A e zhbën një rritje prej 20% një ulje prej 20%?", "Një bluzë prej 1 000 lekësh zbret në 800 lekë. Rritja pasuese prej 20% llogaritet mbi 800 lekë dhe e çon çmimin në 960 lekë."),
    (.chemistry, "Pse ndryshket më shpejt hekuri pranë detit?", "Kripërat e tretura e bëjnë ujin përçues më të mirë. Kjo lehtëson proceset elektrokimike të korrozionit kur ka ujë dhe oksigjen."),
    (.biology, "Si futet ajri kur merr frymë?", "Diafragma tkurret dhe ulet. Vëllimi i kraharorit rritet, presioni në mushkëri bie nën presionin atmosferik dhe ajri hyn.")
]
