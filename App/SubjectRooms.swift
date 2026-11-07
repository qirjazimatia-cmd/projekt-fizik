import SwiftUI

extension Subject {
    var color: Color {
        switch self {
        case .physics: return Color(red: 0.15, green: 0.25, blue: 0.77)
        case .math: return Color(red: 0.58, green: 0.13, blue: 0.43)
        case .chemistry: return Color(red: 0.66, green: 0.21, blue: 0.07)
        case .biology: return Color(red: 0.14, green: 0.41, blue: 0.18)
        }
    }
    var short: String {
        switch self {
        case .physics: return "Fiz."
        case .math: return "Mat."
        case .chemistry: return "Kimi"
        case .biology: return "Bio."
        }
    }

}

private enum Destination: Hashable {
    case home, lab, events, desk, subject(Subject)
}

struct Dashboard: View {
    @EnvironmentObject private var account: Account
    let role: SchoolRole
    @AppStorage("studentLevel4") private var selectedLevel = 0
    @State private var destination: Destination
    init(role: SchoolRole) {
        self.role = role
        _destination = State(initialValue: role == .parent ? .home : .desk)
    }
    @State private var drawer = false
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 760
            if role == .student && SchoolLevel(rawValue: selectedLevel) == nil {
                Page {
                    Text("Këndi i nxënësit").font(.largeTitle.bold())
                    StudentClassChooser()
                    AccountControls()
                }
            } else {
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    rail(expanded: wide, canToggle: !wide)
                    NavigationStack {
                        switch destination {
                        case .home: HomePage(role: role) { select(.subject($0)) }
                        case .desk: RoleDesk(role: role)
                        case .events: if account.isOnline { SharedSchoolCalendar() } else { SchoolEventsView() }
                        case .lab: Lab()
                        case .subject(let subject): SubjectRoom(subject: subject)
                        }
                    }.environment(\.learnerLevel, role == .student ? SchoolLevel(rawValue: selectedLevel) : nil)
                    .id(destination).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if drawer && !wide {
                    Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { drawer = false }
                    rail(expanded: true, canToggle: true)
                }
            }
            }
        }.tint(.lagoon)
    }
    private func select(_ value: Destination) { destination = value; drawer = false }
    private func rail(expanded: Bool, canToggle: Bool) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                if canToggle {
                    Button { drawer.toggle() } label: {
                        Image(systemName: drawer ? "xmark" : "sidebar.left").font(.title2).frame(width: 44, height: 44)
                    }.accessibilityLabel(drawer ? "Mbyll menunë" : "Hap menunë")
                }
                if expanded { Text("Science\nQuest").font(.system(size: 30, weight: .black, design: .rounded)).padding(.bottom, 16) }
                tab(.home, "Krye", "Krye", "house.fill", expanded)
                ForEach([Subject.math, .physics, .chemistry, .biology]) { subject in
                    tab(.subject(subject), subject.rawValue, subject.short, subject.icon, expanded)
                }
                Divider().background(.white.opacity(0.6)).padding(.vertical, 6)
                tab(.lab, "Laboratori", "Lab", "flask.fill", expanded)
                tab(.events, "Eventet", "Eventet", "calendar", expanded)
                tab(.desk, role.title, "Profili", "person.fill", expanded)
            }.padding(.horizontal, expanded ? 12 : 4).padding(.vertical, 12)
        }.frame(width: expanded ? 198 : 58).frame(maxHeight: .infinity)
        .foregroundStyle(.white).background(Color.midnight).buttonStyle(.plain)
    }
    private func tab(_ value: Destination, _ label: String, _ short: String, _ symbol: String, _ expanded: Bool) -> some View {
        Button { select(value) } label: {
            Group {
                if expanded { Label(label, systemImage: symbol).font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 9) }
                else { VStack(spacing: 4) { Image(systemName: symbol); Text(short).font(.caption2.bold()) } }
            }.frame(maxWidth: .infinity, minHeight: expanded ? 43 : 49)
            .foregroundStyle(destination == value ? Color.midnight : .white)
            .background(destination == value ? Color.sun : Color.clear, in: RoundedRectangle(cornerRadius: 9))
        }.accessibilityLabel(label).accessibilityAddTraits(destination == value ? .isSelected : [])
    }
}

private enum RoomTab: String, CaseIterable {
    case lessons = "Mësime", quiz = "Kuize sipas nivelit", practice = "Ushtrime", lab = "Laborator", games = "Lojëra"
    var icon: String {
        switch self {
        case .lessons: return "books.vertical.fill"
        case .quiz: return "bolt.fill"
        case .practice: return "pencil.and.ruler"
        case .lab: return "slider.horizontal.3"
        case .games: return "gamecontroller.fill"
        }
    }
}
private struct SubjectRoom: View {
    let subject: Subject
    var body: some View {
        Page {
            SubjectBanner(subject: subject)
            ForEach(RoomTab.allCases, id: \.self) { tab in
                NavigationLink {
                    if tab == .lessons { StudyLibrary(subject: subject) }
                    else { SubjectShelf(subject: subject, tab: tab) }
                } label: {
                    HStack {
                        Image(systemName: tab.icon).font(.title2).foregroundStyle(subject.color).frame(width: 40)
                        Text(tab.rawValue).font(.title3.bold())
                        Spacer()
                        Image(systemName: "arrow.up.right").foregroundStyle(subject.color)
                    }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .leading) { Rectangle().fill(subject.color).frame(width: 4) }
                }
            }
        }.buttonStyle(.plain)
    }
}

private struct SubjectShelf: View {
    @Environment(\.learnerLevel) private var learnerLevel
    @State private var level = SchoolLevel.basic
    let subject: Subject
    let tab: RoomTab
    var body: some View {
        Page {
            Text(subject.rawValue.uppercased()).font(.caption.bold()).tracking(2).foregroundStyle(subject.color)
            Text(tab.rawValue).font(.largeTitle.bold())
            switch tab {
            case .lessons:
                NavigationLink("Hap kapitujt e mësimeve") { StudyLibrary(subject: subject) }
            case .quiz:
                ForEach(learnerLevel.map { [$0] } ?? SchoolLevel.allCases) { level in
                    NavigationLink { SubjectQuiz(subject: subject, level: level) } label: {
                        Tile(icon: "bolt.fill", title: level.name, detail: "Sfida, seri përgjigjesh të sakta dhe riprovim i gabimeve")
                    }
                }
            case .practice:
                if let learnerLevel { Text(learnerLevel.name).font(.headline) } else { LevelPicker(level: $level) }
                ForEach(Exercise.all.filter { $0.subject == subject.rawValue && $0.level == (learnerLevel ?? level).rawValue }) { item in
                    NavigationLink { ExercisePlayer(item: item) } label: {
                        Tile(icon: "pencil", title: item.prompt, detail: item.id + " · " + item.format)
                    }
                }
            case .lab:
                LabExperiments(subject: subject)
                if subject == .physics {
                    NavigationLink { SpringLaboratory() } label: {
                        Tile(icon: "arrow.up.and.down", title: "Punishtja e sustave", detail: "7 eksperimente · Huku · EPG ↔ EK ↔ Eel")
                    }
                    NavigationLink { MotionLab() } label: { Tile(icon: "bicycle", title: "Laboratori i lëvizjes", detail: "Ndërto grafikun rrugë–kohë") }
                }
                ForEach(activities.filter { $0.subject == subject }) { activity in
                    NavigationLink { PracticalActivityView(activity:activity) } label: {
                        Tile(icon:"leaf",title:activity.title,detail:"Veprimtari praktike me fletore")
                    }
                }
            case .games:
                LabGameLinks(subject: subject)
                NavigationLink { PairGame(subject: subject) } label: { Tile(icon: "square.grid.2x2.fill", title: "Gjej çiftin", detail: "Pyetje dhe përgjigje sipas nivelit") }
                NavigationLink { SortGame(subject: subject) } label: { Tile(icon: "tray.2.fill", title: "Ndaji në grupe", detail: "Dallo përgjigjet e sakta nga gabimet") }
            }
        }.buttonStyle(.plain)
    }
}
struct SubjectQuiz: View {
    let subject: Subject
    let level: SchoolLevel
    @State private var deck: [Exercise] = []
    @State private var index = 0
    @State private var score = 0
    @State private var streak = 0
    @State private var longest = 0
    @State private var missed: [Exercise] = []
    @State private var count = 5
    @State private var started = false
    @AppStorage("quizStars") private var stars = 0
    var body: some View {
        VStack(alignment: .leading) {
            if !started {
                Page {
                    SubjectBanner(subject: subject)
                    Text("Sfido veten").font(.largeTitle.bold())
                    Text(level.name)
                    Text("⭐ \(stars) yje të fituar")
                    Picker("Gjatësia", selection: $count) {
                        Text("5 pyetje").tag(5)
                        Text("10 pyetje").tag(10)
                    }.pickerStyle(.segmented)
                    Text("Një përgjigje e saktë sjell një yll. Çdo tri përgjigje të sakta radhazi sjellin edhe dy yje bonus.")
                    Button("Nis sfidën") {
                        start(Array(Exercise.all.filter { $0.subject == subject.rawValue && $0.level == level.rawValue }.shuffled().prefix(count)))
                    }.buttonStyle(.borderedProminent)
                }
            } else if index < deck.count {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pyetja \(index + 1)/\(deck.count) · ⭐ \(score) · 🔥 \(streak) radhazi").font(.headline)
                    ProgressView(value: Double(index), total: Double(deck.count)).tint(subject.color)
                }.padding()
                let item = deck[index]
                ExercisePlayer(item: item, advance: { correct in
                    guard index < deck.count, deck[index].id == item.id else { return }
                    if correct {
                        streak += 1
                        longest = max(longest, streak)
                        let earned = streak % 3 == 0 ? 3 : 1
                        score += earned
                        stars += earned
                    } else { streak = 0; missed.append(item) }
                    index += 1
                }).id(item.id)
            } else {
                Page {
                    Text(missed.isEmpty ? "🏆 Sfidë perfekte!" : "🌟 Sfida përfundoi").font(.largeTitle.bold())
                    Text("\(deck.count - missed.count)/\(deck.count) përgjigje të sakta · \(score) yje")
                    Text("Seria më e gjatë · \(longest) përgjigje të sakta")
                    if !missed.isEmpty {
                        Text("Përforco ato që të ngatërruan.")
                        ForEach(missed) { item in Text("• " + item.prompt) }
                        Button("Riprovo pyetjet e humbura") { start(missed.shuffled()) }.buttonStyle(.borderedProminent)
                    }
                    Button("Sfida të tjera") { started = false }
                }
            }
        }.navigationTitle("Kuizi · " + level.name)
    }
    private func start(_ items: [Exercise]) {
        deck = items; index = 0; score = 0; streak = 0; longest = 0; missed = []; started = true
    }
}

struct PairClue {
    let left: String
    let right: String
    init(_ left: String, _ right: String) { self.left = left; self.right = right }
}
struct SortClue {
    let name: String
    let first: Bool
    let why: String
    init(_ name: String, _ first: Bool, _ why: String) { self.name = name; self.first = first; self.why = why }
}
extension Subject {
    var pairTask: String {
        switch self {
        case .physics: return "Lidh madhësinë fizike me njësinë."
        case .math: return "Lidh thyesën me përqindjen."
        case .chemistry: return "Lidh emrin e substancës me formulën."
        case .biology: return "Lidh organin me funksionin."
        }
    }
    var pairs: [PairClue] {
        switch self {
        case .physics: return [.init("Forca", "N"), .init("Fuqia", "W"), .init("Energjia", "J"), .init("Presioni", "Pa"), .init("Frekuenca", "Hz"), .init("Rezistenca", "Ω")]
        case .math: return [.init("1/8", "12,5%"), .init("3/5", "60%"), .init("7/10", "70%"), .init("3/4", "75%"), .init("1/5", "20%"), .init("9/10", "90%")]
        case .chemistry: return [.init("Uji", "H₂O"), .init("Dioksidi i karbonit", "CO₂"), .init("Kloruri i natriumit", "NaCl"), .init("Metani", "CH₄"), .init("Oksigjeni molekular", "O₂"), .init("Amoniaku", "NH₃")]
        case .biology: return [.init("Zemra", "Pompon gjakun"), .init("Veshkat", "Filtrojnë gjakun dhe formojnë urinën"), .init("Mushkëritë", "Shkëmbejnë gaze"), .init("Zorra e hollë", "Përthith shumicën e lëndëve ushqyese"), .init("Truri", "Përpunon informacionin nervor"), .init("Stomaku", "Përzien ushqimin me lëngun gastrik")]
        }
    }
    var groups: [String] {
        switch self {
        case .physics: return ["Skalare","Vektoriale"]
        case .math: return ["Numër i thjeshtë","Numër i përbërë"]
        case .chemistry: return ["Ndryshim fizik","Ndryshim kimik"]
        case .biology: return ["Sistemi tretës","Sistemi i frymëmarrjes"]
        }
    }
    var sortTask: String { "Ndaj kartat në dy grupe: " + groups.joined(separator: " / ") + "." }
    var cards: [SortClue] {
        switch self {
        case .physics: return [.init("Koha",true,"Intervali kohor ka vlerë dhe njësi."),.init("Masa",true,"Masa shprehet me një numër dhe njësi."),.init("Temperatura",true,"Temperatura nuk ka drejtim."),.init("Nxitimi",false,"Nxitimi ka edhe drejtim dhe kah."),.init("Forca",false,"Për forcën duhen edhe drejtimi dhe kahu."),.init("Zhvendosja",false,"Zhvendosja drejtohet nga pika fillestare te pika fundore.")]
        case .math: return [.init("2",true,"Pjesëtohet vetëm me 1 dhe 2."),.init("17",true,"Ka vetëm dy pjesëtues natyrorë."),.init("29",true,"Ka vetëm dy pjesëtues natyrorë."),.init("21",false,"21 = 3 × 7."),.init("49",false,"49 = 7 × 7."),.init("15",false,"15 = 3 × 5.")]
        case .chemistry: return [.init("Shkrirja e akullit",true,"Uji ndryshon gjendje."),.init("Thyerja e xhamit",true,"Ndryshon forma e xhamit."),.init("Avullimi i ujit",true,"Uji kalon në gjendje të gaztë."),.init("Ndryshkja e hekurit",false,"Formohen substanca të reja."),.init("Djegia e drurit",false,"Formohen gaze dhe mbetje me përbërje të re."),.init("Thartimi i qumështit",false,"Bakteret prodhojnë acid laktik.")]
        case .biology: return [.init("Ezofagu",true,"Përcjell ushqimin në stomak."),.init("Stomaku",true,"Përzien ushqimin me lëngun gastrik."),.init("Zorra e hollë",true,"Këtu përthithen shumica e lëndëve ushqyese."),.init("Trakeja",false,"Përcjell ajrin drejt bronkeve."),.init("Bronket",false,"Shpërndajnë ajrin në mushkëri."),.init("Alveolat",false,"Mundësojnë shkëmbimin e gazeve me gjakun.")]
        }
    }
}

private struct PairGame: View {
    let subject: Subject
    @Environment(\.learnerLevel) private var learnerLevel
    @State private var level = SchoolLevel.basic
    @State private var pairs: [PairClue] = []
    @State private var left: [Int] = []
    @State private var right: [Int] = []
    @State private var chosen: Int?
    @State private var solved: Set<Int> = []
    @State private var attempts = 0
    @State private var feedback = ""
    var body: some View {
        Page {
            Text("Gjej çiftin e nivelit tënd").font(.title2.bold())
            if let learnerLevel { Text(learnerLevel.name) } else { LevelPicker(level:$level).onChange(of:level) { _ in restart() } }
            Text("Prek një kartë majtas, pastaj çiftin e saj djathtas.")
            Text("Çifte: \(solved.count) / \(pairs.count) · Përpjekje: \(attempts)")
            ForEach(left.indices, id: \.self) { i in
                HStack {
                    card(left[i], isLeft: true)
                    card(right[i], isLeft: false)
                }
            }
            Text(feedback).font(.headline)
            if solved.count == pairs.count {
                Button("Përziej kartat dhe luaj përsëri", action: restart).buttonStyle(.borderedProminent)
            }
        }.navigationTitle("Gjej çiftin").onAppear { if left.isEmpty { restart() } }
    }
    private func card(_ id: Int, isLeft: Bool) -> some View {
        let pair = pairs[id]
        return Button {
            if isLeft { chosen = id; feedback = "Tani zgjidh kartën djathtas." }
            else if let source = chosen {
                attempts += 1
                if source == id {
                    solved.insert(id)
                    feedback = "Saktë! " + pair.left + " → " + pair.right
                } else { feedback = "Ky çift nuk përputhet. Zgjidh përsëri." }
                chosen = nil
            }
        } label: {
            Text((solved.contains(id) ? "✓ " : "") + (isLeft ? pair.left : pair.right))
                .frame(maxWidth: .infinity, minHeight: 60).padding(6)
                .foregroundStyle(isLeft && chosen == id ? Color.white : Color.primary)
                .background(isLeft && chosen == id ? subject.color : Color.white, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).disabled(solved.contains(id) || (!isLeft && chosen == nil))
    }
    private func restart() {
        pairs = LevelGameBank.pairs(subject:subject,level:learnerLevel ?? level)
        left = pairs.indices.shuffled()
        right = pairs.indices.shuffled()
        if right == left, let first = right.first { right.removeFirst(); right.append(first) }
        chosen = nil; solved = []; attempts = 0; feedback = ""
    }
}

private struct SortGame: View {
    let subject: Subject
    @Environment(\.learnerLevel) private var learnerLevel
    @State private var level = SchoolLevel.basic
    private let labels = ["Përgjigje e saktë","Përgjigje e gabuar"]
    @State private var cards: [SortClue] = []
    @State private var index = 0
    @State private var score = 0
    @State private var correct: Bool?
    var body: some View {
        Page {
            if let learnerLevel { Text(learnerLevel.name) } else { LevelPicker(level:$level).onChange(of:level) { _ in restart() } }
            if index < cards.count {
                let card = cards[index]
                Text("Karta \(index + 1) nga \(cards.count) · Pikë: \(score)")
                Text(card.name).font(.largeTitle.bold()).padding().frame(maxWidth: .infinity)
                    .background(subject.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                Text("Në cilin grup bën pjesë?")
                ForEach(labels.indices, id: \.self) { group in
                    Button(labels[group]) {
                        guard correct == nil else { return }
                        let hit = (group == 0) == card.first
                        correct = hit
                        if hit { score += 1 }
                    }.buttonStyle(.bordered).disabled(correct != nil)
                }
                if let correct {
                    SectionText(heading: correct ? "Saktë!" : labels[card.first ? 0 : 1], text: card.why)
                    Button(index + 1 == cards.count ? "Shiko rezultatin" : "Karta tjetër") {
                        index += 1; self.correct = nil
                    }.buttonStyle(.borderedProminent)
                }
            } else if !cards.isEmpty {
                Text("Loja përfundoi").font(.largeTitle.bold())
                Text("Klasifikove saktë \(score) nga \(cards.count) karta.")
                Button("Luaj përsëri", action: restart).buttonStyle(.borderedProminent)
            }
        }.navigationTitle("Ndaji në grupe").onAppear { if cards.isEmpty { restart() } }
    }
    private func restart() { cards = LevelGameBank.classifications(subject:subject,level:learnerLevel ?? level); index = 0; score = 0; correct = nil }
}

struct SubjectBanner: View {
    let subject: Subject
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(subject.rawValue).font(.system(.largeTitle, design: .rounded).weight(.black))
                Text("\(lessons.filter { $0.subject == subject }.count) mësime · \(Exercise.all.filter { $0.subject == subject.rawValue }.count) ushtrime").font(.subheadline.bold())
            }
            Spacer()
            Image(systemName: subject.icon).font(.system(size: 44, weight: .light)).accessibilityHidden(true)
        }.padding(17).frame(maxWidth: .infinity, minHeight: 110)
        .foregroundStyle(.white).background(subject.color, in: RoundedRectangle(cornerRadius: 12))
    }
}

// Open SubjectRooms.swift with the Xcode canvas to preview without signing in.
struct StudioNavigation_Previews: PreviewProvider {
    static var previews: some View {
        Dashboard(role: .student)
            .environmentObject(Account())
            .preferredColorScheme(.light)
    }
}

struct SchoolEvent: Codable, Identifiable {
    var id = UUID()
    let owner: String
    var title: String
    var subject: String
    var level: Int
    var date: Date
    var note: String
}

@MainActor
enum SchoolEventStore {
    static let key = "schoolEvents.v1"
    static func read(_ data: Data) throws -> [SchoolEvent] {
        if data.isEmpty { return [] }
        return try JSONDecoder().decode([SchoolEvent].self, from: data)
    }
    static func save(_ event: SchoolEvent, account: Account) throws {
        guard account.role == .teacher, event.owner == account.identity else {
            throw AuthFailure(message: "Vetëm mësuesi mund ta ruajë këtë event.")
        }
        guard !event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              SchoolLevel(rawValue: event.level) != nil,
              Subject.allCases.contains(where: { $0.rawValue == event.subject }) else {
            throw AuthFailure(message: "Plotëso titullin, lëndën dhe klasën.")
        }
        var events = try read(UserDefaults.standard.data(forKey: key) ?? Data())
        if let old = events.first(where: { $0.id == event.id }), old.owner != account.identity {
            throw AuthFailure(message: "Ky event i përket një mësuesi tjetër.")
        }
        events.removeAll { $0.id == event.id }
        events.append(event)
        UserDefaults.standard.set(try JSONEncoder().encode(events), forKey: key)
    }
    static func delete(_ event: SchoolEvent, account: Account) throws {
        guard account.role == .teacher, event.owner == account.identity else {
            throw AuthFailure(message: "Vetëm krijuesi i eventit mund ta fshijë.")
        }
        var events = try read(UserDefaults.standard.data(forKey: key) ?? Data())
        events.removeAll { $0.id == event.id && $0.owner == account.identity }
        UserDefaults.standard.set(try JSONEncoder().encode(events), forKey: key)
    }
    static func removeAccount(_ identity: String) {
        guard var events = try? read(UserDefaults.standard.data(forKey: key) ?? Data()) else { return }
        events.removeAll { $0.owner == identity }
        if let data = try? JSONEncoder().encode(events) { UserDefaults.standard.set(data, forKey: key) }
    }
}

@MainActor
private struct SchoolEventsView: View {
    @EnvironmentObject private var account: Account
    @Environment(\.learnerLevel) private var learnerLevel
    @AppStorage(SchoolEventStore.key, store: .standard) private var data = Data()
    @AppStorage("eventsFamilyLevel") private var familyLevel = 1
    @State private var selectedDate = Date()
    @State private var month = Date()
    @State private var teacherLevel = SchoolLevel.basic
    @State private var editing: SchoolEvent?
    @State private var deleting: SchoolEvent?
    @State private var error = ""

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.firstWeekday = 2
        value.locale = Locale(identifier: "sq_AL")
        return value
    }
    private var level: SchoolLevel {
        if account.role == .student { return learnerLevel ?? .basic }
        if account.role == .parent { return SchoolLevel(rawValue: familyLevel) ?? .basic }
        return teacherLevel
    }
    private var events: [SchoolEvent] {
        ((try? SchoolEventStore.read(data)) ?? []).filter { $0.level == level.rawValue }.sorted {
            $0.date == $1.date ? $0.title < $1.title : $0.date < $1.date
        }
    }
    private var monthEvents: [SchoolEvent] {
        events.filter { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
    }
    private var monthStart: Date {
        calendar.dateInterval(of: .month, for: month)!.start
    }

    var body: some View {
        Page {
            Text("Eventet").font(.largeTitle.bold())
            if account.role == .student {
                Text(level.name).font(.headline)
            } else if account.role == .parent {
                Picker("Klasa e fëmijës", selection: $familyLevel) {
                    ForEach(SchoolLevel.allCases) { Text($0.name).tag($0.rawValue) }
                }
            } else {
                LevelPicker(level: $teacherLevel)
                Button {
                    editing = SchoolEvent(owner: account.identity, title: "", subject: Subject.biology.rawValue,
                                          level: level.rawValue, date: selectedDate, note: "")
                } label: { Label("Shto event", systemImage: "plus.circle.fill") }
                .buttonStyle(.borderedProminent)
            }
            calendarView
            VStack(alignment: .leading, spacing: 12) {
                Text(selectedDate.formatted(date: .complete, time: .omitted)).font(.headline)
                let dayEvents = events.filter { calendar.isDate($0.date, inSameDayAs: selectedDate) }
                if dayEvents.isEmpty { Text("Kjo ditë është pa evente për klasën tënde.") }
                ForEach(dayEvents) { event in eventCard(event) }
            }
            DisclosureGroup("Të gjitha eventet e muajit · \(monthEvents.count)") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(monthEvents) { event in eventCard(event) }
                }.padding(.top)
            }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            if (try? SchoolEventStore.read(data)) == nil {
                Text("Eventet e ruajtura nuk u lexuan. Provo ta rihapësh aplikacionin.")
            }
        }
        .environment(\.locale, Locale(identifier: "sq_AL"))
        .navigationTitle("Kalendari i testeve")
        .sheet(item: $editing) { event in
            SchoolEventEditor(event: event).environmentObject(account)
        }
        .alert("Ta fshish eventin?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Anulo", role: .cancel) { deleting = nil }
            Button("Fshije", role: .destructive) {
                guard let event = deleting else { return }
                do { try SchoolEventStore.delete(event, account: account); error = "" }
                catch { self.error = error.localizedDescription }
                deleting = nil
            }
        }
    }

    private var calendarView: some View {
        VStack(spacing: 14) {
            HStack {
                Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Muaji i mëparshëm")
                Text(month.formatted(.dateTime.month(.wide).year())).font(.title2.bold()).frame(maxWidth: .infinity)
                Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Muaji pasardhës")
            }
            HStack {
                Stepper("Viti \(calendar.component(.year, from: month))", onIncrement: { moveMonth(12) }, onDecrement: { moveMonth(-12) })
                Button("Sot") { month = Date(); selectedDate = Date() }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(["Hën", "Mar", "Mër", "Enj", "Pre", "Sht", "Die"], id: \.self) {
                    Text($0).font(.caption.bold())
                }
                let offset = (calendar.component(.weekday, from: monthStart) + 5) % 7
                let days = calendar.range(of: .day, in: .month, for: month)!.count
                ForEach(0..<(offset + days), id: \.self) { index in
                    if index < offset { Color.clear.frame(height: 46) }
                    else {
                        let date = calendar.date(byAdding: .day, value: index - offset, to: monthStart)!
                        let count = events.filter { calendar.isDate($0.date, inSameDayAs: date) }.count
                        let selected = calendar.isDate(date, inSameDayAs: selectedDate)
                        Button { selectedDate = date } label: {
                            VStack(spacing: 3) {
                                Text("\(index - offset + 1)").font(.body.bold())
                                Circle().fill(count > 0 ? Color.orange : Color.clear).frame(width: 6, height: 6)
                            }.frame(maxWidth: .infinity, minHeight: 46)
                            .foregroundStyle(selected ? .white : Color.midnight)
                            .background(selected ? Color.lagoon : .white, in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain)
                        .accessibilityLabel(date.formatted(date: .complete, time: .omitted) + ", \(count) evente")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
    }

    private func moveMonth(_ amount: Int) {
        guard let next = calendar.date(byAdding: .month, value: amount, to: monthStart) else { return }
        month = next
        selectedDate = next
    }

    private func eventCard(_ event: SchoolEvent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(event.title).font(.headline)
            Text(event.subject + " · " + level.name)
            Text(event.date.formatted(date: .abbreviated, time: .omitted)).font(.subheadline)
            if !event.note.isEmpty { Text(event.note) }
            if account.role == .teacher && event.owner == account.identity {
                HStack {
                    Button("Ndrysho") { editing = event }
                    Button("Fshi", role: .destructive) { deleting = event }
                }.buttonStyle(.bordered)
            }
        }.padding().frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
    }
}

@MainActor
private struct SchoolEventEditor: View {
    @EnvironmentObject private var account: Account
    @Environment(\.dismiss) private var dismiss
    @State private var event: SchoolEvent
    @State private var error = ""

    init(event: SchoolEvent) { _event = State(initialValue: event) }

    var body: some View {
        NavigationStack {
            Page {
                Text("Event për klasën").font(.title.bold())
                TextField("Titulli, p.sh. Test biologjie", text: $event.title).textFieldStyle(.roundedBorder)
                Picker("Lënda", selection: $event.subject) {
                    ForEach(Subject.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                Picker("Klasa", selection: $event.level) {
                    ForEach(SchoolLevel.allCases) { Text($0.name).tag($0.rawValue) }
                }
                DatePicker("Data e testit", selection: $event.date, displayedComponents: .date)
                TextField("Temat ose udhëzimet për nxënësit", text: $event.note, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                Text("Eventi shfaqet në kalendarin e nxënësve dhe prindërve të kësaj klase.")
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
                HStack {
                    Button("Anulo") { dismiss() }
                    Button("Ruaj eventin") {
                        event.title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        do { try SchoolEventStore.save(event, account: account); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.buttonStyle(.borderedProminent)
                    .disabled(event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }.environment(\.locale, Locale(identifier: "sq_AL"))
        .frame(minWidth: 300, minHeight: 460)
    }
}

// These decks use the same explicit level as lessons and practice. Distinct
// answers avoid ambiguous pairs when two numerical questions share an answer.
enum LevelGameBank {
    static func pairs(subject: Subject, level: SchoolLevel) -> [PairClue] {
        var answers = Set<String>()
        var result: [PairClue] = []
        for item in StudyLesson.matching(subject:subject,level:level).shuffled() {
            let answer = item.check.options[item.check.correct]
            guard answers.insert(answer).inserted else { continue }
            result.append(PairClue(item.check.prompt,answer))
            if result.count == 6 { break }
        }
        return result
    }
    static func classifications(subject: Subject, level: SchoolLevel) -> [SortClue] {
        StudyLesson.matching(subject:subject,level:level).shuffled().prefix(10).map { lesson in
            let right = Bool.random()
            let alternatives = lesson.check.options.indices.filter { $0 != lesson.check.correct }
            let index = right ? lesson.check.correct : (alternatives.randomElement() ?? lesson.check.correct)
            return SortClue(lesson.check.prompt + "\nPërgjigjja e propozuar: " + lesson.check.options[index],right,lesson.check.why)
        }
    }
}
