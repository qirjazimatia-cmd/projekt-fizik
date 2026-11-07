import SwiftUI

enum GameKind: String, CaseIterable, Identifiable {
    case quiz = "Kuiz", logic = "Sfida e logjikës", battle = "Science Battle", escape = "Science Escape Room"
    var id: Self { self }
    var detail: String {
        switch self {
        case .quiz: return "Gjashtë pyetje nga katër lëndët"
        case .logic: return "Zbulo rregullin dhe nxirr përfundimin"
        case .battle: return "Dy skuadra, një pajisje, nga katër pyetje sipas nivelit"
        case .escape: return "Zgjidh katër enigma për të hapur laboratorin"
        }
    }
}

let logicQuestions = [
    Question("Një kulturë bakteresh dyfishohet çdo orë. Ena mbushet në orën 8. Kur ishte gjysmë e mbushur?", ["Në orën 4", "Në orën 6", "Në orën 7"], 2, "Një dyfishim e çon sasinë nga gjysma në të plotë."),
    Question("Ke 8 sfera. Njëra është më e rëndë, të tjerat janë identike. Peshon 3 kundrejt 3 dhe peshorja qëndron në ekuilibër. Ç’bën tani?", ["Pesho dy sferat e mbetura kundrejt njëra-tjetrës", "Pesho sërish të njëjtat grupe", "Zgjidh një nga gjashtë sferat"], 0, "Ekuilibri përjashton të gjashta sferat e peshuara. Nga dy të tjerat, më e rënda e ul pjatën e peshores."),
    Question("Një robot bën 2 hapa përpara dhe 1 prapa në çdo cikël. Sa hapa larg nisjes është pas 5 cikleve të plota?", ["10", "5", "15"], 1, "Në çdo cikël zhvendosja është 2 − 1 = 1 hap përpara.")
]

struct Arcade: View {
    @Environment(\.learnerLevel) private var learnerLevel
    var body: some View {
        Page {
            ForEach(GameKind.allCases) { kind in
                NavigationLink {
                    if kind == .quiz, let learnerLevel {
                        Page {
                            Text(learnerLevel.name).font(.title.bold())
                            ForEach(Subject.allCases) { subject in
                                NavigationLink(subject.rawValue) { SubjectQuiz(subject: subject, level: learnerLevel) }
                            }
                        }
                    } else if kind == .escape { EscapeRoom() } else { QuizGame(kind: kind) }
                } label: { Tile(icon: kind == .escape ? "lock.fill" : "gamecontroller.fill", title: kind.rawValue, detail: kind == .quiz ? (learnerLevel?.name ?? kind.detail) : kind.detail) }
            }
            ForEach(Subject.allCases) { subject in
                Text(subject.rawValue).font(.title2.bold())
                LabGameLinks(subject:subject)
            }
        }.navigationTitle("Luaj").buttonStyle(.plain)
    }
}

struct QuizGame: View {
    @Environment(\.learnerLevel) private var learnerLevel
    @State private var level = SchoolLevel.basic
    @AppStorage("gameRecent.v7") private var recent = ""
    let kind: GameKind
    @State private var questions: [Question] = []
    @State private var round = 0
    @State private var selection: Int?
    @State private var scores = [0, 0]
    @State private var handoff = false
    private var team: Int { kind == .battle ? round % 2 : 0 }

    private func restart() {
        let selectedLevel = learnerLevel ?? level
        let pool = StudyLesson.matching(level:selectedLevel)
        let previous = Set(recent.split(separator:"|").map(String.init))
        var deck: [StudyLesson] = []
        // Equal subject coverage for each of the two teams, shuffled inside each round.
        for _ in 0..<2 {
            for subject in Subject.allCases.shuffled() {
                let candidates = pool.filter { item in item.schoolSubject == subject && !deck.contains { $0.id == item.id } }
                if let pick = candidates.filter({ !previous.contains($0.id) }).randomElement() ?? candidates.randomElement() { deck.append(pick) }
            }
        }
        if kind == .battle {
            var fair: [StudyLesson] = []
            for subject in Subject.allCases.shuffled() { fair += deck.filter { $0.schoolSubject == subject } }
            deck = fair
        }
        if kind == .logic {
            deck = Array(pool.filter { $0.chapterTitle.contains("logji") || $0.chapterTitle.contains("prov") || $0.chapterTitle.contains("num") || $0.schoolSubject == .math }.shuffled().prefix(8))
        }
        questions = deck.map { $0.check.question.shuffledOptions() }
        recent = deck.map(\.id).joined(separator:"|")
        round = 0
        scores = [0, 0]
        selection = nil
        handoff = kind == .battle
    }

    var body: some View {
        Page {
            if questions.isEmpty {
                Text(kind.rawValue).font(.largeTitle.bold())
                Text(kind.detail)
                if let learnerLevel { Text(learnerLevel.name) } else { LevelPicker(level:$level) }
                Button("Fillo lojën", action: restart).buttonStyle(.borderedProminent)
            } else if round == questions.count {
                Text("Loja përfundoi").font(.largeTitle.bold())
                if kind == .battle {
                    Text(scores[0] == scores[1] ? "Barazim!" : "Fiton skuadra \(scores[0] > scores[1] ? 1 : 2)!")
                    Text("Skuadra 1: \(scores[0]) / 4   •   Skuadra 2: \(scores[1]) / 4")
                } else { Text("Përgjigje të sakta: \(scores[0]) nga \(questions.count)") }
                Button("Luaj përsëri", action: restart).buttonStyle(.borderedProminent)
            } else if handoff {
                Text("Radha e skuadrës \(team + 1)").font(.largeTitle.bold())
                Text("Kalojani pajisjen skuadrës që ka radhën. Çdo përgjigje e saktë vlen një pikë.")
                Button("Jemi gati") { handoff = false }.buttonStyle(.borderedProminent)
            } else {
                Text("Pyetja \(round + 1) nga \(questions.count)").font(.headline)
                if kind == .battle { Text("Skuadra \(team + 1)") }
                Answers(question: questions[round], selection: selection) { index in
                    guard selection == nil else { return }
                    selection = index
                    if index == questions[round].correct { scores[team] += 1 }
                }
                if selection != nil {
                    Button(round + 1 == questions.count ? "Shiko rezultatin" : "Vazhdo") {
                        round += 1
                        selection = nil
                        handoff = kind == .battle
                    }.buttonStyle(.borderedProminent)
                }
            }
        }.navigationTitle(kind.rawValue)
    }
}

struct EscapeRoom: View {
    @Environment(\.learnerLevel) private var learnerLevel
    @State private var level = SchoolLevel.basic
    @State private var deck: [Exercise] = []
    @State private var stage = 0
    @State private var misses = 0
    @State private var run = UUID()
    @AppStorage("gameEscapeRecent.v7") private var recent = ""
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            if deck.isEmpty {
                Page {
                    Text("Science Escape Room").font(.largeTitle.bold())
                    Text("Hap katër dyer: një për çdo lëndë. Çdo lojë sjell enigma të tjera të nivelit tënd.")
                    if let learnerLevel { Text(learnerLevel.name) } else { LevelPicker(level:$level) }
                    Button("Nis ekspeditën",action:restart).buttonStyle(.borderedProminent)
                }
            } else if stage == deck.count {
                Page {
                    Text("Laboratori u hap!").font(.largeTitle.bold())
                    Text("Katër lëndë · \(misses) riprovime")
                    Button("Ekspeditë e re") { deck = [] }.buttonStyle(.borderedProminent)
                }
            } else {
                Text("Dera \(stage+1)/\(deck.count) · " + deck[stage].subject).font(.headline).padding()
                ProgressView(value:Double(stage),total:Double(deck.count)).padding(.horizontal)
                ExercisePlayer(item:deck[stage],advance:{ right in
                    if right { stage += 1 } else { misses += 1 }
                    run = UUID()
                }).id(run)
            }
        }
    }
    private func restart() {
        let seen = Set(recent.split(separator:"|").map(String.init))
        deck = Subject.allCases.shuffled().compactMap { subject in
            let pool = Exercise.all.filter { $0.subject == subject.rawValue && $0.level == (learnerLevel ?? level).rawValue }
            return pool.filter { !seen.contains($0.id) }.randomElement() ?? pool.randomElement()
        }
        recent = deck.map(\.id).joined(separator:"|"); stage = 0; misses = 0; run = UUID()
    }
}

extension Question {
    func shuffledOptions() -> Question {
        let indices = options.indices.shuffled()
        return Question(prompt,indices.map { options[$0] },indices.firstIndex(of:correct) ?? 0,why)
    }
}

// Interactive laboratory models. Each model has two controls and a measurable mission.
enum LabExperiment: String, CaseIterable, Identifiable {
    case flight, pendulum, circuit, fraction, curve, chance, population, membrane, genes, acidity, gas, dilution
    case energy, forces, springEnergy, waves, refraction, buoyancy, unitCircle, pythagoras, linear, polygon, dice, exponential, photosynthesis, enzyme, lungs, heart, foodEnergy, microscope, neutralization, ions, reaction, equilibrium, crystals, halfLife
    var id: String { rawValue }
    var extended: Bool {
        switch self {
        case .energy, .forces, .springEnergy, .waves, .refraction, .buoyancy, .unitCircle, .pythagoras, .linear, .polygon, .dice, .exponential, .photosynthesis, .enzyme, .lungs, .heart, .foodEnergy, .microscope, .neutralization, .ions, .reaction, .equilibrium, .crystals, .halfLife: return true
        default: return false
        }
    }
    var requiresTrial: Bool { self == .chance || self == .dice }
    var subject: Subject {
        switch self {
        case .flight, .pendulum, .circuit: return .physics
        case .fraction, .curve, .chance: return .math
        case .population, .membrane, .genes: return .biology
        case .energy: return .physics
        case .forces: return .physics
        case .springEnergy: return .physics
        case .waves: return .physics
        case .refraction: return .physics
        case .buoyancy: return .physics
        case .unitCircle: return .math
        case .pythagoras: return .math
        case .linear: return .math
        case .polygon: return .math
        case .dice: return .math
        case .exponential: return .math
        case .photosynthesis: return .biology
        case .enzyme: return .biology
        case .lungs: return .biology
        case .heart: return .biology
        case .foodEnergy: return .biology
        case .microscope: return .biology
        case .neutralization: return .chemistry
        case .ions: return .chemistry
        case .reaction: return .chemistry
        case .equilibrium: return .chemistry
        case .crystals: return .chemistry
        case .halfLife: return .chemistry
        case .acidity, .gas, .dilution: return .chemistry
        }
    }
    var title: String {
        switch self {
        case .flight: return "🚀 Hedhja e raketës"
        case .pendulum: return "⏱ Lavjerrësi në planetë"
        case .circuit: return "💡 Ndize qarkun"
        case .fraction: return "🍕 Punishtja e thyesave"
        case .curve: return "🎢 Ndërto parabolën"
        case .chance: return "🎯 Rrota e probabilitetit"
        case .population: return "🦠 Kolonia që rritet"
        case .membrane: return "💧 Uji dhe membrana"
        case .genes: return "🧬 Kryqëzimi i bizeleve"
        case .acidity: return "🧪 Detektivi i pH-së"
        case .gas: return "🎈 Gazi nën presion"
        case .energy: return "🛝 Nga EPG-ja në EK"
        case .forces: return "🛒 Ligji i dytë i Njutonit"
        case .springEnergy: return "🌀 Bateria e sustës"
        case .waves: return "🌊 Valët në litar"
        case .refraction: return "🔦 Drita mes dy mjediseve"
        case .buoyancy: return "⛵ Pluskon apo fundoset?"
        case .unitCircle: return "🧭 Rrethi dhe sinusi"
        case .pythagoras: return "📐 Ndërto trekëndëshin"
        case .linear: return "📈 Drejtëza që lëviz"
        case .polygon: return "🔷 Arkitekti i shumëkëndëshave"
        case .dice: return "🎲 Laboratori i dy zareve"
        case .exponential: return "🌱 Makina e fuqive"
        case .photosynthesis: return "🌿 Faktorët e fotosintezës"
        case .enzyme: return "🧩 Forma dhe puna e enzimës"
        case .lungs: return "🫁 Ritmi i mushkërive"
        case .heart: return "🫀 Pompa e gjakut"
        case .foodEnergy: return "🦊 Piramida e energjisë"
        case .microscope: return "🔬 Mikroskopi virtual"
        case .neutralization: return "⚖️ Acidi takon bazën"
        case .ions: return "⚛️ Ndërto atomin dhe jonin"
        case .reaction: return "💧 Fabrika e molekulave"
        case .equilibrium: return "🔄 Ekuilibri A ⇌ B"
        case .crystals: return "💎 Kristale nga tretësira"
        case .halfLife: return "⌛ Ora e gjysmëjetës"
        case .dilution: return "⚗️ Ngjyrat e përqendrimit"
        }
    }
    var first: (label: String, range: ClosedRange<Double>, step: Double, initial: Double) {
        switch self {
        case .flight: return ("Shpejtësia fillestare (m/s)", 5...30, 1, 10)
        case .pendulum: return ("Gjatësia (m)", 0.2...3, 0.1, 1)
        case .circuit: return ("Tensioni (V)", 1...24, 1, 6)
        case .fraction: return ("Feta të zgjedhura", 0...12, 1, 3)
        case .curve: return ("Koeficienti a", -3...3, 0.5, 1)
        case .chance: return ("Sektorë portokalli", 0...10, 1, 3)
        case .population: return ("Koha (orë)", 0...8, 1, 2)
        case .membrane: return ("Përqendrimi majtas (njësi relative)", 0...10, 1, 3)
        case .genes: return ("Prindi 1 · 0 = aa, 1 = Aa, 2 = AA", 0...2, 1, 1)
        case .acidity: return ("pH", 0...14, 1, 7)
        case .gas: return ("Vëllimi (L)", 1...10, 0.5, 5)
        case .energy: return ("Lartësia fillestare (m)", 1...20, 1, 10)
        case .forces: return ("Forca rezultante (N)", 0...40, 1, 10)
        case .springEnergy: return ("Konstantja elastike (N/m)", 10...200, 10, 50)
        case .waves: return ("Frekuenca (Hz)", 1...10, 1, 2)
        case .refraction: return ("Këndi i rënies (gradë)", 0...80, 5, 40)
        case .buoyancy: return ("Dendësia e trupit (kg/m³)", 200...1400, 100, 600)
        case .unitCircle: return ("Këndi (gradë)", 0...360, 15, 45)
        case .pythagoras: return ("Kateti a", 1...12, 1, 3)
        case .linear: return ("Pjerrësia m", -4...4, 0.5, 1)
        case .polygon: return ("Numri i brinjëve", 3...10, 1, 5)
        case .dice: return ("Shuma që kërkon", 2...12, 1, 7)
        case .exponential: return ("Baza", 2...4, 1, 2)
        case .photosynthesis: return ("Drita e disponueshme (%)", 0...100, 5, 60)
        case .enzyme: return ("Temperatura (°C)", 0...70, 1, 25)
        case .lungs: return ("Frymëmarrje në minutë", 6...30, 1, 12)
        case .heart: return ("Rrahje në minutë", 40...150, 5, 70)
        case .foodEnergy: return ("Energjia e prodhuesve (kJ)", 1000...10000, 1000, 5000)
        case .microscope: return ("Zmadhimi i okularit", 5...20, 5, 10)
        case .neutralization: return ("Acid i fortë 0,1 mol/L (mL)", 5...100, 5, 30)
        case .ions: return ("Protone", 1...18, 1, 11)
        case .reaction: return ("Molekula H₂", 0...12, 1, 6)
        case .equilibrium: return ("Konstantja K = [B]/[A]", 0.5...5, 0.5, 1)
        case .crystals: return ("Temperatura (°C)", 0...80, 5, 40)
        case .halfLife: return ("Koha e kaluar (min)", 0...60, 5, 20)
        case .dilution: return ("Sasia e substancës (mol)", 0.1...2, 0.1, 0.5)
        }
    }
    var second: (label: String, range: ClosedRange<Double>, step: Double, initial: Double) {
        switch self {
        case .flight: return ("Këndi (gradë)", 10...80, 5, 30)
        case .pendulum: return ("Nxitimi i rëndesës (m/s²)", 1...20, 0.1, 9.8)
        case .circuit: return ("Rezistenca (Ω)", 1...20, 1, 10)
        case .fraction: return ("Numri i fetave të barabarta", 1...12, 1, 8)
        case .curve: return ("Zhvendosja vertikale b", -4...4, 1, 0)
        case .chance: return ("Numri i rrotullimeve", 10...100, 10, 20)
        case .population: return ("Koha e dyfishimit (orë)", 1...4, 1, 2)
        case .membrane: return ("Përqendrimi djathtas (njësi relative)", 0...10, 1, 7)
        case .genes: return ("Prindi 2 · 0 = aa, 1 = Aa, 2 = AA", 0...2, 1, 1)
        case .acidity: return ("pH i mostrës së dytë", 0...14, 1, 5)
        case .gas: return ("Temperatura absolute (K)", 200...400, 10, 300)
        case .energy: return ("Pjesa e zbritjes (%)", 0...100, 5, 0)
        case .forces: return ("Masa (kg)", 1...10, 1, 5)
        case .springEnergy: return ("Zgjatja (cm)", 0...30, 1, 10)
        case .waves: return ("Gjatësia valore (m)", 0.5...5, 0.5, 2)
        case .refraction: return ("Treguesi i mjedisit të dytë", 1...2, 0.1, 1.5)
        case .buoyancy: return ("Dendësia e lëngut (kg/m³)", 800...1400, 100, 1000)
        case .unitCircle: return ("Rrezja", 1...5, 1, 2)
        case .pythagoras: return ("Kateti b", 1...12, 1, 4)
        case .linear: return ("Prerja b", -4...4, 1, 0)
        case .polygon: return ("Rrezja e rrethit rrethshkrues", 1...10, 1, 4)
        case .dice: return ("Numri i hedhjeve", 10...100, 10, 30)
        case .exponential: return ("Eksponenti", 0...5, 1, 3)
        case .photosynthesis: return ("CO₂ i disponueshëm (%)", 0...100, 5, 40)
        case .enzyme: return ("pH", 1...13, 0.5, 6)
        case .lungs: return ("Vëllimi i një frymëmarrjeje (mL)", 200...1000, 50, 500)
        case .heart: return ("Vëllimi për rrahje (mL)", 30...120, 5, 70)
        case .foodEnergy: return ("Kalimi mes niveleve (%)", 5...20, 1, 10)
        case .microscope: return ("Zmadhimi i objektivit", 10...100, 10, 40)
        case .neutralization: return ("Bazë e fortë 0,1 mol/L (mL)", 5...100, 5, 50)
        case .ions: return ("Elektrone", 0...20, 1, 10)
        case .reaction: return ("Molekula O₂", 0...6, 1, 2)
        case .equilibrium: return ("Përqendrimi total (mol/L)", 1...10, 1, 4)
        case .crystals: return ("Lënda e shtuar në 100 g ujë (g)", 0...80, 5, 50)
        case .halfLife: return ("Gjysmëjeta (min)", 5...30, 5, 10)
        case .dilution: return ("Vëllimi i tretësirës (L)", 0.2...4, 0.1, 1)
        }
    }
    var explanation: String {
        switch self {
        case .flight: return "Model pa rezistencë ajri, me nisje e ulje në të njëjtën lartësi. R = v² sin(2θ)/g, ku g = 9,8 m/s²."
        case .pendulum: return "Për lëkundje të vogla, T = 2π√(L/g). Masa e trupit nuk e ndryshon periodën në këtë model."
        case .circuit: return "Për një rezistencë ideale, I = U/R. Drita ilustron fuqinë P = U²/R. Ndriçimi është ilustrues."
        case .fraction: return "Emëruesi tregon sa feta të barabarta ka pica. Numëruesi tregon sa prej tyre zgjedh. Përqindja = 100 × numëruesi/emëruesi."
        case .curve: return "Grafiku është y = ax² + b. Koeficienti a ndryshon hapjen dhe drejtimin. b lëviz kulmin lart ose poshtë."
        case .chance: return "Rrota ka 10 sektorë të barabartë. P(portokalli) = sektorët portokalli/10. Frekuenca e vrojtuar ndryshon nga një provë te tjetra."
        case .population: return "Kolonia nis me 10 qeliza. N = 10 × 2^(t/d). Modeli supozon ushqim të pakufizuar dhe kushte të pandryshuara."
        case .membrane: return "Membrana lejon kalimin e ujit. Me presion fillestar të njëjtë dhe substancë të tretur që nuk kalon membranën, uji lëviz neto drejt anës më të përqendruar."
        case .genes: return "Model me një gjen dhe dominancë të plotë. A është aleli dominant, a recesiv. Ngjyra e verdhë shfaqet te AA dhe Aa, e gjelbra te aa."
        case .acidity: return "pH = −log₁₀[H⁺] në modelin e tretësirave ideale të holluara. Në 25°C, pH 7 është neutral. Çdo ulje me një njësi e shumëfishon [H⁺] me 10."
        case .gas: return "Ligji i gazit ideal, P = nRT/V. Sasia fikse është n = 0,1 mol dhe R = 8,314 kPa·L/(mol·K)."
        case .energy: return "Trupi 2 kg niset nga qetësia dhe rrëshqet pa fërkim. Me g = 10 m/s², EPG = mgh, EK = mgh₀ − mgh dhe v = √(2gΔh). Shuma EPG + EK ruhet."
        case .forces: return "Karroca nis nga qetësia dhe mbi të vepron forcë rezultante konstante. a = F/m. Pamja e animuar paraqet një interval që përsëritet."
        case .springEnergy: return "Për një sustë ideale brenda kufirit elastik, E = kx²/2. Zgjatja nga centimetra kthehet në metra. Nëse x dyfishohet, energjia katërfishohet."
        case .waves: return "Për një valë periodike, v = fλ. Ngjyra shënon formën e valës. Grimcat lëkunden rreth pozicionit të tyre, ndërsa shqetësimi përhapet."
        case .refraction: return "Drita kalon nga ajri, me n₁ = 1, në një mjedis me n₂. Këndet maten nga normalja. Ligji i Snellit jep sin(r) = sin(i)/n₂."
        case .buoyancy: return "Në ekuilibër pluskimi, pjesa e zhytur është ρtrup/ρlëng. Nëse trupi është më i dendur se lëngu, ai fundoset. Ne supozojmë trup homogjen dhe lëng të qetë."
        case .unitCircle: return "Në një rreth me rreze r, koordinatat janë x = r cos θ dhe y = r sin θ. Ndryshimi i rrezes shkallëzon koordinatat."
        case .pythagoras: return "Për trekëndëshin kënddrejtë, c² = a² + b². Hipotenuza është përballë këndit të drejtë."
        case .linear: return "Grafiku y = mx + b pret boshtin y te b. Për çdo rritje të x me një, y ndryshon me m."
        case .polygon: return "Në shumëkëndëshin e rregullt me n brinjë dhe rreze r të rrethit rrethshkrues, brinja është 2r sin(π/n). Perimetri është n herë brinja."
        case .dice: return "Dy zare të paanshme japin 36 çifte të renditura njësoj të mundshme. Numri i çifteve për shumën s është 6 − |7 − s|. Frekuenca nga provat ndryshon rastësisht."
        case .exponential: return "aⁿ do të thotë shumëzim i n faktorëve të barabartë me a. Për a ≠ 0, a⁰ = 1. Grafiku tregon rritjen për eksponentë nga 0 deri në 5."
        case .photosynthesis: return "Në këtë model krahasues, temperatura dhe uji janë të përshtatshëm. Aktivitetin e kufizon faktori më i pakët midis dritës dhe CO₂. Shkalla është ilustruese."
        case .enzyme: return "Model për një enzimë hipotetike me optimum 37°C dhe pH 7. Kur kushtet largohen nga optimumi, aktiviteti bie. Enzimat reale kanë kurba të ndryshme."
        case .lungs: return "Ventilimi minutë = frekuenca × vëllimi i një frymëmarrjeje. Ky model tregon vëllimin total të ajrit, përfshirë ajrin në rrugët përçuese."
        case .heart: return "Debiti kardiak është frekuenca e rrahjeve shumëzuar me vëllimin sistolik. Vlerat janë për një model mësimor."
        case .foodEnergy: return "Model me të njëjtën përqindje kalimi në dy nivele radhazi. Energjia te konsumatorët dytësorë është E₀(p/100)². Përqindjet reale ndryshojnë."
        case .microscope: return "Zmadhimi i përgjithshëm është okulari × objektivi. Në pamje modeli tregon një qelizë me membranë, citoplazmë dhe bërthamë. Madhësia reale mbetet e njëjtë."
        case .neutralization: return "Model virtual i një acidi të fortë monoprotik dhe baze të fortë, në 25°C. H⁺ + OH⁻ → H₂O. Teprica përcakton pH. Kur sasitë janë të barabarta, pH = 7."
        case .ions: return "Ngarkesa në njësi elementare është numri i protoneve minus numrin e elektroneve. Ndryshimi i elektroneve formon jon, ndërsa ndryshimi i protoneve ndryshon elementin."
        case .reaction: return "Në reaksionin 2H₂ + O₂ → 2H₂O, çdo grup reaksioni përdor 2 molekula H₂ dhe 1 molekulë O₂. Reaktanti që mbaron i pari kufizon produktin."
        case .equilibrium: return "Për A ⇌ B, me koeficientë 1 me 1, K = [B]/[A]. Në këtë model [A] + [B] ruhet. Në ekuilibër [B] = ctotal K/(1 + K)."
        case .crystals: return "Përdorim substancë hipotetike me tretshmëri S = 20 + 0,5T gramë për 100 g ujë. Masa mbi këtë kufi mbetet e ngurtë ose kristalizon gjatë ftohjes."
        case .halfLife: return "Model mesatar i zbërthimit me 1000 bërthama fillestare. N = N₀ × (1/2)^(t/T½). Zbërthimet individuale janë rastësore."
        case .dilution: return "Përqendrimi molar c = n/V. Shtimi i ujit, me sasi të pandryshuar substance, e ul përqendrimin. Ngjyra është ilustrim."
        }
    }
    var mission: String {
        switch self {
        case .flight: return "Dërgo raketën 35–45 metra larg."
        case .pendulum: return "Krijo një periodë nga 1,9 deri në 2,1 sekonda."
        case .circuit: return "Arrij rrymë 1 A me tension të paktën 10 V."
        case .fraction: return "Zgjidh saktësisht 75% të picës."
        case .curve: return "Ndërto parabolë që hapet poshtë dhe ka kulmin në (0, 2)."
        case .chance: return "Vendos probabilitetin 70%, pastaj kryej një provë."
        case .population: return "Rrite koloninë në 80 qeliza."
        case .membrane: return "Bëj që uji të lëvizë neto drejt anës së majtë."
        case .genes: return "Krijo kryqëzim ku 25% e pasardhësve priten të jenë aa."
        case .acidity: return "Bëj mostrën e parë 100 herë më të pasur në H⁺ se mostra e dytë."
        case .gas: return "Arrij presion 49–51 kPa."
        case .energy: return "Arrij pikën ku EPG-ja dhe EK-ja janë të barabarta."
        case .forces: return "Vendos forcën dhe masën që nxitimi të jetë 2 m/s²."
        case .springEnergy: return "Ruaj 4 J në sustë."
        case .waves: return "Krijo valë me shpejtësi përhapjeje 10 m/s."
        case .refraction: return "Me kënd rënieje të paktën 30°, ul këndin e përthyerjes nën 20°."
        case .buoyancy: return "Bëj që gjysma e vëllimit të trupit të jetë e zhytur."
        case .unitCircle: return "Vendos pikën në lartësinë y = 1 me kënd 30°."
        case .pythagoras: return "Ndërto një trekëndësh me hipotenuzë 13."
        case .linear: return "Kaloje drejtëzën nga pika (2, 7)."
        case .polygon: return "Ndërto gjashtëkëndësh të rregullt me perimetër 24."
        case .dice: return "Zgjidh shumën me probabilitet më të lartë dhe kryej një provë."
        case .exponential: return "Gjej një fuqi që jep 64."
        case .photosynthesis: return "Siguro të paktën 80% aktivitet në model."
        case .enzyme: return "Arrij të paktën 95% aktivitet të enzimës."
        case .lungs: return "Vendos ventilim total 6 L/min."
        case .heart: return "Vendos debit kardiak 5 L/min."
        case .foodEnergy: return "Siguro 100 kJ te konsumatorët dytësorë."
        case .microscope: return "Zgjidh zmadhim të përgjithshëm 600×."
        case .neutralization: return "Arrij neutralizim të plotë me dy vëllime jo më të vogla se 40 mL."
        case .ions: return "Ndërto jonin Na⁺ me 11 protone."
        case .reaction: return "Formo 8 molekula H₂O pa mbetje të reaktantëve."
        case .equilibrium: return "Arrij [B] = 3 mol/L kur K = 3."
        case .crystals: return "Lër 20 g lëndë të ngurtë në fund."
        case .halfLife: return "Lër 125 bërthama sipas vlerës mesatare të modelit."
        case .dilution: return "Përgatit tretësirë me përqendrim 0,5 mol/L."
        }
    }
    func value(_ a: Double, _ b: Double) -> Double {
        switch self {
        case .flight: return a * a * sin(2 * b * .pi / 180) / 9.8
        case .pendulum: return 2 * .pi * sqrt(a / b)
        case .circuit: return a / b
        case .fraction: return min(a, b) / b * 100
        case .curve: return a * 4 + b
        case .chance: return a * 10
        case .population: return 10 * pow(2, a / b)
        case .membrane: return a - b
        case .genes: return (1 - a / 2) * (1 - b / 2) * 100
        case .acidity: return pow(10, b - a)
        case .gas: return 0.1 * 8.314 * b / a
        case .energy: return 20 * a * b / 100
        case .forces: return a / b
        case .springEnergy: return 0.5 * a * pow(b / 100, 2)
        case .waves: return a * b
        case .refraction: return asin(sin(a * .pi / 180) / b) * 180 / .pi
        case .buoyancy: return a / b * 100
        case .unitCircle: return b * sin(a * .pi / 180)
        case .pythagoras: return sqrt(a * a + b * b)
        case .linear: return 2 * a + b
        case .polygon: return 2 * a * b * sin(.pi / a)
        case .dice: return (6 - abs(7 - a)) / 36 * 100
        case .exponential: return pow(a, b)
        case .photosynthesis: return min(a, b)
        case .enzyme: return 100 * exp(-pow((a - 37) / 14, 2) - pow((b - 7) / 2, 2))
        case .lungs: return a * b / 1000
        case .heart: return a * b / 1000
        case .foodEnergy: return a * pow(b / 100, 2)
        case .microscope: return a * b
        case .neutralization: return a == b ? 7 : (a > b ? -log10(0.1 * (a - b) / (a + b)) : 14 + log10(0.1 * (b - a) / (a + b)))
        case .ions: return a - b
        case .reaction: return 2 * min(floor(a / 2), b)
        case .equilibrium: return b * a / (1 + a)
        case .crystals: return max(0, b - (20 + 0.5 * a))
        case .halfLife: return 1000 * pow(0.5, a / b)
        case .dilution: return a / b
        }
    }
    func achieved(_ a: Double, _ b: Double) -> Bool {
        let v = value(a, b)
        switch self {
        case .flight: return (35...45).contains(v)
        case .pendulum: return (1.9...2.1).contains(v)
        case .circuit: return abs(v - 1) < 0.001 && a >= 10
        case .fraction: return abs(v - 75) < 0.001
        case .curve: return a < 0 && b == 2
        case .chance: return a == 7
        case .population: return abs(v - 80) < 0.001
        case .membrane: return a > b
        case .genes: return abs(v - 25) < 0.001
        case .acidity: return abs(v - 100) < 0.001
        case .gas: return (49...51).contains(v)
        case .energy: return b == 50
        case .forces: return abs(v - 2) < 0.001
        case .springEnergy: return abs(v - 4) < 0.001
        case .waves: return abs(v - 10) < 0.001
        case .refraction: return a >= 30 && v < 20
        case .buoyancy: return abs(v - 50) < 0.001
        case .unitCircle: return a == 30 && abs(v - 1) < 0.001
        case .pythagoras: return abs(v - 13) < 0.001
        case .linear: return abs(v - 7) < 0.001
        case .polygon: return a == 6 && abs(v - 24) < 0.001
        case .dice: return a == 7
        case .exponential: return abs(v - 64) < 0.001
        case .photosynthesis: return v >= 80
        case .enzyme: return v >= 95
        case .lungs: return abs(v - 6) < 0.001
        case .heart: return abs(v - 5) < 0.001
        case .foodEnergy: return abs(v - 100) < 0.001
        case .microscope: return abs(v - 600) < 0.001
        case .neutralization: return a == b && a >= 40
        case .ions: return a == 11 && b == 10
        case .reaction: return a == 8 && b == 4
        case .equilibrium: return a == 3 && abs(v - 3) < 0.001
        case .crystals: return abs(v - 20) < 0.001
        case .halfLife: return abs(v - 125) < 0.001
        case .dilution: return abs(v - 0.5) < 0.001
        }
    }
}

struct LabExperiments: View {
    let subject: Subject
    var body: some View {
        if subject == .chemistry {
            NavigationLink { ChemistryMixer() } label: {
                Tile(icon:"testtube.2",title:"🧪 Tavolina e përzierjeve",detail:"Zgjidh substancat dhe zbulo çfarë ndodh")
            }
        }
        ForEach(LabExperiment.allCases.filter { $0.subject == subject }) { experiment in
            NavigationLink { InteractiveExperiment(experiment: experiment) } label: {
                Tile(icon: subject.icon, title: experiment.title, detail: experiment.mission)
            }
        }
    }
}

private struct LabObservation: Codable, Identifiable {
    var id = UUID()
    let experiment: String
    let first, second: Double
    let result: String
}

private struct InteractiveExperiment: View {
    let experiment: LabExperiment
    @State private var a: Double
    @State private var b: Double
    @State private var running = false
    @State private var startTime = Date()
    @State private var checked = false
    @State private var hits: Int?
    @State private var freePlay = true
    @AppStorage("labMissions") private var completed = ""
    @AppStorage("labObservations") private var observations = Data()
    @State private var notebookBlocked = false

    init(experiment: LabExperiment) {
        self.experiment = experiment
        _a = State(initialValue: experiment.first.initial)
        _b = State(initialValue: experiment.second.initial)
    }
    private var result: String {
        let value = experiment.value(a, b)
        let number = String(format: "%.2f", value)
        switch experiment {
        case .flight: return "Largësia horizontale · " + number + " m"
        case .pendulum: return "Perioda · " + number + " s"
        case .circuit: return "Rryma · " + number + " A"
        case .fraction: return "\(Int(min(a,b)))/\(Int(b)) = " + number + "%"
        case .curve: return "y = \(a)x² + \(b) · Kur x = 2, y = " + number
        case .chance: return "Probabiliteti teorik · " + number + "%"
        case .population: return "Popullata sipas modelit · " + number + " qeliza"
        case .membrane: return a == b ? "Ekuilibër · pa rrjedhje neto" : (a > b ? "← Uji lëviz neto majtas" : "Uji lëviz neto djathtas →")
        case .genes: return "Pasardhës aa · " + number + "%"
        case .acidity: return "[H⁺] e mostrës 1 / [H⁺] e mostrës 2 = " + String(format: "%.3g", value)
        case .gas: return "Presioni · " + number + " kPa"
        case .energy: return "Energjia kinetike · \(number) J"
        case .forces: return "Nxitimi · \(number) m/s²"
        case .springEnergy: return "Energjia elastike · \(number) J"
        case .waves: return "Shpejtësia e valës · \(number) m/s"
        case .refraction: return "Këndi i përthyerjes · \(number)°"
        case .buoyancy: return "Raporti i dendësive · \(number)%"
        case .unitCircle: return "Koordinata y · \(number)"
        case .pythagoras: return "Hipotenuza · \(number)"
        case .linear: return "Vlera y kur x = 2 · \(number)"
        case .polygon: return "Perimetri · \(number)"
        case .dice: return "Probabiliteti teorik · \(number)%"
        case .exponential: return "Vlera e fuqisë · \(number)"
        case .photosynthesis: return "Aktiviteti në model · \(number)%"
        case .enzyme: return "Aktiviteti në model · \(number)%"
        case .lungs: return "Ventilimi minutë · \(number) L/min"
        case .heart: return "Debiti kardiak · \(number) L/min"
        case .foodEnergy: return "Energjia në nivelin e tretë · \(number) kJ"
        case .microscope: return "Zmadhimi i përgjithshëm · \(number)×"
        case .neutralization: return "pH pas përzierjes · \(number)"
        case .ions: return "Ngarkesa në njësi e · \(number)"
        case .reaction: return "Molekula H₂O të formuara · \(number)"
        case .equilibrium: return "Përqendrimi i B në ekuilibër · \(number) mol/L"
        case .crystals: return "Lënda e ngurtë · \(number) g"
        case .halfLife: return "Bërthama të pazbërthyera · \(number)"
        case .dilution: return "Përqendrimi · " + number + " mol/L"
        }
    }
    private var records: [LabObservation] {
        ((try? JSONDecoder().decode([LabObservation].self, from: observations)) ?? []).filter { $0.experiment == experiment.rawValue }
    }
    var body: some View {
        Page {
            VStack(alignment: .leading, spacing: 10) {
                Text(experiment.title).font(.largeTitle.bold())
                Picker("Mënyra", selection: $freePlay) {
                    Text("Eksperimento lirshëm").tag(true)
                    Text("Provo misionin").tag(false)
                }.pickerStyle(.segmented)
                if !freePlay { Text(experiment.mission).font(.headline) }
                Text("Parashiko çfarë do të ndodhë, ndrysho vlerat dhe vëzhgo modelin.")
            }
            TimelineView(.animation(minimumInterval: 0.04, paused: !running)) { timeline in
                let elapsed = running ? timeline.date.timeIntervalSince(startTime) : 0
                let percent = experiment == .energy && running ? energyProgress(elapsed) : b
                VStack(spacing: 0) {
                    LabScene(experiment: experiment, a: a, b: percent, time: elapsed)
                        .frame(height: 235)
                        .background(Color.midnight, in: RoundedRectangle(cornerRadius: 24))
                    if experiment == .energy { EnergyReadout(height: a, percent: percent) }
                }
            }
            controls
            if experiment != .energy { Text(result).font(.title3.bold()).foregroundStyle(experiment.subject.color) }
            if experiment.requiresTrial, let hits {
                Text("Prova · \(hits) rezultate të kërkuara nga \(Int(b)) · \(Int(Double(hits) / b * 100))%")
            }
            actions
            if checked && !freePlay {
                let success = experiment.achieved(a, b) && (!experiment.requiresTrial || hits != nil)
                Label(success ? "Misioni u arrit!" : "Vazhdo eksperimentin. Krahaso rezultatin me synimin.",
                      systemImage: success ? "star.circle.fill" : "lightbulb")
                    .foregroundStyle(success ? Color.green : Color.primary)
            }
            DisclosureGroup("Pse ndodh kjo?") { Text(experiment.explanation).padding(.top) }
            notebook
        }.navigationTitle("Laboratori")
        .onChange(of: a) { _ in changed() }
        .onChange(of: b) { _ in
            if experiment == .fraction { a = min(a, b) }
            changed()
        }
        .onDisappear { running = false }
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(experiment.first.label + " · " + String(format: "%.1f", a)).bold()
            Slider(value: $a, in: experiment == .fraction ? 0...b : experiment.first.range, step: experiment.first.step)
                .accessibilityLabel(experiment.first.label)
            if experiment == .energy && running {
                Text("Pozicioni dhe energjitë ndiqen te pamja sipër. Ndalo për ta vendosur pozicionin vetë.").font(.callout)
            } else {
                Text(experiment.second.label + " · " + String(format: "%.1f", b)).bold()
                Slider(value: $b, in: experiment.second.range, step: experiment.second.step)
                    .accessibilityLabel(experiment.second.label)
            }
        }
    }
    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(running ? "Ndalo animacionin" : "Nis animacionin") {
                    if running && experiment == .energy {
                        b = energyProgress(Date().timeIntervalSince(startTime))
                    }
                    running.toggle()
                    startTime = Date()
                }.buttonStyle(.bordered)
                Button("Rivendos") {
                    a = experiment.first.initial; b = experiment.second.initial
                    running = false; hits = nil; checked = false
                }
            }
            if freePlay {
                Button("Provo një kombinim të ri") {
                    let first = experiment.first
                    let second = experiment.second
                    let aCount = Int(((first.range.upperBound - first.range.lowerBound) / first.step).rounded())
                    let bCount = Int(((second.range.upperBound - second.range.lowerBound) / second.step).rounded())
                    b = second.range.lowerBound + Double(Int.random(in: 0...bCount)) * second.step
                    a = first.range.lowerBound + Double(Int.random(in: 0...aCount)) * first.step
                    if experiment == .fraction { a = min(a, b) }
                }
            }
            if experiment.requiresTrial {
                Button("Kryej \(Int(b)) prova") {
                    hits = (0..<Int(b)).filter { _ in
                        if experiment == .dice { return Int.random(in: 1...6) + Int.random(in: 1...6) == Int(a) }
                        return Int.random(in: 0..<10) < Int(a)
                    }.count
                    checked = false
                }.buttonStyle(.borderedProminent)
            }
            if !freePlay {
            Button("Kontrollo misionin") {
                checked = true
                if experiment.achieved(a, b) && (!experiment.requiresTrial || hits != nil) {
                    var ids = Set(completed.split(separator: "|").map(String.init))
                    ids.insert(experiment.rawValue); completed = ids.sorted().joined(separator: "|")
                }
            }.buttonStyle(.borderedProminent).disabled(experiment == .energy && running)
            Text("🏅 \(Set(completed.split(separator: "|")).count)/\(LabExperiment.allCases.count) misione të arritura").font(.caption.bold())
            }
        }
    }
    private var notebook: some View {
        DisclosureGroup("Fletorja e eksperimentit · \(records.count) matje") {
            VStack(alignment: .leading, spacing: 12) {
                Button("Ruaj këtë matje") {
                    guard var all = NotebookCodec.load(LabObservation.self, from: observations) else { notebookBlocked = true; return }
                    notebookBlocked = false
                    all.insert(LabObservation(experiment: experiment.rawValue, first: a, second: b, result: result), at: 0)
                    observations = (try? JSONEncoder().encode(Array(all.prefix(360)))) ?? observations
                }.disabled(experiment == .energy && running)
                if experiment == .energy && running { Text("Ndalo animacionin për të ruajtur matjen.").font(.caption) }
                if notebookBlocked { Text(NotebookCodec.blockedMessage).font(.caption).foregroundStyle(Color.red) }
                ForEach(records) { record in
                    VStack(alignment: .leading) {
                        Text(record.result).bold()
                        Text(experiment.first.label + " = \(record.first)")
                        Text(experiment.second.label + " = \(record.second)")
                    }.font(.caption)
                    Divider()
                }
            }.padding(.top)
        }
    }
    private func changed() { checked = false; hits = nil; startTime = Date() }
    private func energyProgress(_ elapsed: Double) -> Double {
        // Constant acceleration down the incline: distance is proportional to t².
        // Slow playback provides time to compare the two forms of energy.
        let phase = max(0, elapsed).truncatingRemainder(dividingBy: 6) / 6
        return phase * phase * 100
    }
}

private struct LabScene: View {
    let experiment: LabExperiment
    let a, b, time: Double

    var body: some View {
        if experiment.extended {
            ExtendedLabScene(experiment: experiment, a: a, b: b, time: time)
        } else {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let center = CGPoint(x: w / 2, y: h / 2)
            func line(_ points: [CGPoint], color: Color = .white, width: CGFloat = 2) {
                guard let first = points.first else { return }
                var path = Path()
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
                context.stroke(path, with: .color(color), lineWidth: width)
            }
            func dot(_ point: CGPoint, radius: CGFloat, color: Color) {
                context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
            }
            func label(_ text: String, _ point: CGPoint, color: Color = .white) {
                context.draw(Text(text).font(.system(size: 14, weight: .bold)).foregroundColor(color), at: point)
            }
            func beaker(_ x: CGFloat, color: Color, fill: Double) {
                let box = CGRect(x: x - 42, y: 65, width: 84, height: 130)
                let fluid = CGRect(x: box.minX + 3, y: box.maxY - 122 * fill, width: 78, height: 122 * fill)
                context.fill(Path(roundedRect: fluid, cornerRadius: 8), with: .color(color))
                line([CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.minX, y: box.maxY),
                      CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.maxX, y: box.minY)], width: 3)
            }
            switch experiment {
            case .flight:
                let angle = b * .pi / 180
                let duration = 2 * a * sin(angle) / 9.8
                // Fixed 100 m horizontal and 50 m vertical scene scales.
                let xScale = (w - 55) / 100
                let yScale = (h - 50) / 50
                let points = (0...80).map { i -> CGPoint in
                    let t = duration * Double(i) / 80
                    return CGPoint(x: 25 + a * cos(angle) * t * xScale,
                                   y: h - 25 - (a * sin(angle) * t - 4.9 * t * t) * yScale)
                }
                line([CGPoint(x: 20, y: h - 25), CGPoint(x: w - 15, y: h - 25)], color: .green)
                line(points, color: .cyan, width: 3)
                let progress = time == 0 ? 0.0 : time.truncatingRemainder(dividingBy: 4) / 4
                let index = min(80, Int(progress * 80))
                label("🚀", points[index])
                label("0 m", CGPoint(x: 25, y: h - 10))
                label("100 m", CGPoint(x: w - 30, y: h - 10))
            case .pendulum:
                let period = experiment.value(a, b)
                let angle = 0.2 * cos(2 * .pi * time / period)
                let length = 45 + a * 37
                let anchor = CGPoint(x: w / 2, y: 30)
                let bob = CGPoint(x: anchor.x + sin(angle) * length, y: anchor.y + cos(angle) * length)
                line([CGPoint(x: w / 2 - 45, y: 30), CGPoint(x: w / 2 + 45, y: 30)], color: .gray, width: 7)
                line([anchor, bob], width: 3)
                dot(bob, radius: 17, color: .orange)
                label("T = " + String(format: "%.2f s", period), CGPoint(x: w / 2, y: h - 18))
            case .circuit:
                let left: CGFloat = 40
                let right = w - 40
                line([CGPoint(x: left, y: 65), CGPoint(x: right, y: 65), CGPoint(x: right, y: 180),
                      CGPoint(x: left, y: 180), CGPoint(x: left, y: 65)], color: .cyan, width: 4)
                let power = a * a / b
                for i in (1...4).reversed() {
                    dot(CGPoint(x: right, y: 115), radius: CGFloat(12 + i * 7),
                        color: .yellow.opacity(min(0.6, power / 80) / Double(i)))
                }
                dot(CGPoint(x: right, y: 115), radius: 16, color: .yellow)
                label("💡", CGPoint(x: right, y: 115))
                label("\(Int(a)) V", CGPoint(x: left + 15, y: 115))
                label("\(Int(b)) Ω", CGPoint(x: w / 2, y: 155))
                for i in 0..<6 {
                    let f = (Double(i) / 6 + time * min(1, a / b / 5)).truncatingRemainder(dividingBy: 1)
                    dot(CGPoint(x: left + f * (right - left), y: 65), radius: 4, color: .white)
                }
                label("P = " + String(format: "%.1f W", power), CGPoint(x: w / 2, y: 210))
            case .fraction, .chance:
                let count = experiment == .fraction ? Int(b) : 10
                let radius: CGFloat = 85
                let rotation = experiment == .chance ? time * 60 : -90
                for i in 0..<count {
                    let start = Double(i) / Double(count) * 360 + rotation
                    let end = Double(i + 1) / Double(count) * 360 + rotation
                    var wedge = Path()
                    wedge.move(to: center)
                    wedge.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
                    wedge.closeSubpath()
                    context.fill(wedge, with: .color(i < Int(a) ? .orange : .cyan.opacity(0.35)))
                    context.stroke(wedge, with: .color(.white), lineWidth: 2)
                    if experiment == .fraction && i < Int(a) {
                        let angle = (start + end) / 2 * .pi / 180
                        dot(CGPoint(x: center.x + cos(angle) * 50, y: center.y + sin(angle) * 50), radius: 7, color: .red)
                    }
                }
                if experiment == .chance { label("▼", CGPoint(x: center.x, y: 18), color: .orange) }
            case .curve:
                let scaleX = (w - 40) / 8
                let scaleY = (h - 35) / 12
                line([CGPoint(x: 15, y: center.y), CGPoint(x: w - 15, y: center.y)], color: .gray)
                line([CGPoint(x: center.x, y: 10), CGPoint(x: center.x, y: h - 10)], color: .gray)
                var segment: [CGPoint] = []
                for i in 0...160 {
                    let x = -4 + Double(i) / 20
                    let y = a * x * x + b
                    if abs(y) <= 6 {
                        segment.append(CGPoint(x: center.x + x * scaleX, y: center.y - y * scaleY))
                    } else if !segment.isEmpty { line(segment, color: .pink, width: 3); segment = [] }
                }
                line(segment, color: .pink, width: 3)
                dot(CGPoint(x: center.x, y: center.y - b * scaleY), radius: 6, color: .yellow)
                label("x", CGPoint(x: w - 12, y: center.y + 15))
                label("y", CGPoint(x: center.x + 15, y: 12))
                label("−4", CGPoint(x: 25, y: center.y + 15))
                label("4", CGPoint(x: w - 25, y: center.y + 15))
            case .population:
                let count = min(100, Int(experiment.value(a, b)))
                for i in 0..<count {
                    let x = 20 + Double((i * 67 + 13) % 101) / 101 * (w - 40)
                    let y = 20 + Double((i * 37 + 23) % 97) / 97 * (h - 70)
                    dot(CGPoint(x: x + sin(time * 2 + Double(i)) * 3, y: y), radius: 5, color: i % 2 == 0 ? .mint : .cyan)
                }
                label(count == 100 ? "Pamja tregon deri në 100 qeliza" : "\(count) qeliza", CGPoint(x: center.x, y: h - 20))
            case .membrane:
                line([CGPoint(x: center.x, y: 25), CGPoint(x: center.x, y: 195)], color: .pink, width: 5)
                for side in 0..<2 {
                    let count = Int(side == 0 ? a : b)
                    for i in 0..<count {
                        let x = side == 0 ? w * 0.22 : w * 0.72
                        dot(CGPoint(x: x + Double(i % 3) * 12 - 12, y: 55 + Double(i / 3) * 28), radius: 5, color: .orange)
                    }
                }
                label(a == b ? "↔" : (a > b ? "← H₂O" : "H₂O →"),
                      CGPoint(x: center.x + sin(time * 2) * 8, y: h - 30), color: .cyan)
                label("Majtas", CGPoint(x: w * 0.25, y: 20))
                label("Djathtas", CGPoint(x: w * 0.75, y: 20))
            case .genes:
                let alleles = [["a", "a"], ["A", "a"], ["A", "A"]]
                let first = alleles[Int(a)]
                let second = alleles[Int(b)]
                for row in 0..<2 {
                    for column in 0..<2 {
                        let pair = first[row] + second[column]
                        let recessive = pair == "aa"
                        let point = CGPoint(x: w * (column == 0 ? 0.35 : 0.65), y: CGFloat(75 + row * 85))
                        dot(point, radius: 31, color: recessive ? .green : .yellow)
                        label(pair == "aA" ? "Aa" : pair, point, color: .black)
                    }
                }
                label("Çdo kombinim ka probabilitet 25%", CGPoint(x: center.x, y: 215))
            case .acidity:
                let color1 = Color(hue: a / 20, saturation: 0.85, brightness: 0.95)
                let color2 = Color(hue: b / 20, saturation: 0.85, brightness: 0.95)
                beaker(w * 0.3, color: color1, fill: 0.8)
                beaker(w * 0.7, color: color2, fill: 0.8)
                label("pH \(Int(a))", CGPoint(x: w * 0.3, y: 40))
                label("pH \(Int(b))", CGPoint(x: w * 0.7, y: 40))
                label("Ngjyra ilustron shkallën e pH-së", CGPoint(x: center.x, y: 215))
            case .gas:
                let height = 40 + a * 12
                let top = h - 25 - height
                line([CGPoint(x: 40, y: 30), CGPoint(x: 40, y: h - 25), CGPoint(x: w - 40, y: h - 25), CGPoint(x: w - 40, y: 30)], width: 3)
                line([CGPoint(x: 40, y: top), CGPoint(x: w - 40, y: top)], color: .orange, width: 9)
                for i in 0..<24 {
                    let f = (Double(i) * 0.137 + time * b / 1300).truncatingRemainder(dividingBy: 1)
                    let g = (Double(i) * 0.231 + time * b / 1800).truncatingRemainder(dividingBy: 1)
                    dot(CGPoint(x: 48 + f * (w - 96), y: top + 12 + g * (height - 24)), radius: 4, color: .cyan)
                }
            case .dilution:
                let concentration = min(1, experiment.value(a, b) / 3)
                beaker(center.x, color: .purple.opacity(0.15 + 0.85 * concentration), fill: min(1, b / 4))
                for i in 0..<Int(a * 15) {
                    let x = center.x - 30 + Double((i * 13) % 61)
                    let fillHeight = min(118, b / 4 * 118)
                    let y = 192 - Double((i * 17) % 101) / 101 * fillHeight
                    dot(CGPoint(x: x, y: y + sin(time + Double(i)) * 2), radius: 2, color: .pink)
                }
                label(String(format: "%.1f L", b), CGPoint(x: center.x, y: 215))
            default: break
            }
        }.accessibilityLabel(experiment.title + ". Modeli ndryshon sipas vlerave të zgjedhura.")
    }
    }
}
