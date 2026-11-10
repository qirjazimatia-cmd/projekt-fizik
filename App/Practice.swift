import SwiftUI

struct Exercise: Decodable, Identifiable {
    let id, subject, kind, prompt, why, unit: String
    let answers, choices: [String]
    let level: Int
    let tolerance: Double
    let accuracy: String
    static let all: [Self] = {
        guard let file = Bundle.main.url(forResource: "Exercises", withExtension: "json"),
              let data = try? Data(contentsOf: file),
              let bank = try? JSONDecoder().decode([Exercise].self, from: data) else { return [] }
        return bank
    }()
    var format: String {
        switch kind {
        case "select": return "Zgjedhje e shumëfishtë"
        case "order": return "Renditje"
        case "dial": return "Shkallë matëse"
        default: return "Llogaritje"
        }
    }
}

struct PracticeMenu: View {
    @Environment(\.learnerLevel) private var learnerLevel
    @State private var level = SchoolLevel.basic
    @State private var subject = Subject.physics
    @State private var code = ""
    var body: some View {
        Page {
            Text("Punishtja e ushtrimeve").font(.largeTitle.bold())
            Picker("Lënda", selection: $subject) {
                ForEach(Subject.allCases) { Text($0.rawValue).tag($0) }
            }
            if let learnerLevel { Text(learnerLevel.name).font(.headline) } else { LevelPicker(level: $level) }
            TextField("Kërko kodin e detyrës, p.sh. F5-01", text: $code)
                .textFieldStyle(.roundedBorder).autocorrectionDisabled()
            let query = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let items = Exercise.all.filter { item in
                if let learnerLevel, item.level != learnerLevel.rawValue { return false }
                return query.isEmpty ? item.subject == subject.rawValue && item.level == (learnerLevel ?? level).rawValue : item.id.hasPrefix(query)
            }
            if items.isEmpty { Text("Nuk u gjet ushtrim me këtë kod.") }
            ForEach(items.sorted { $0.kind == $1.kind ? $0.id < $1.id : $0.kind < $1.kind }) { item in
                NavigationLink { ExercisePlayer(item: item) } label: {
                    Tile(icon: "pencil.and.ruler", title: item.prompt, detail: "\(item.id) · \(item.format)")
                }
            }
        }.buttonStyle(.plain).navigationTitle("Ushtrime")
    }
}

struct ExercisePlayer: View {
    let item: Exercise
    var advance: ((Bool) -> Void)? = nil
    var recordAnswer: ((Bool) -> Void)? = nil
    @State private var number = ""
    @State private var dial = 0.0
    @State private var picks: [String] = []
    @State private var options: [String] = []
    @State private var result: Bool?
    @AppStorage("mastered") private var mastered = ""
    var body: some View {
        Page {
            Text("\(item.subject) · \(item.format)").foregroundStyle(Color.lagoon)
            Text(item.prompt).font(.title2.bold())
            if item.kind == "number" {
                Text(item.accuracy).font(.footnote)
                HStack { TextField("Përgjigjja", text: $number).textFieldStyle(.roundedBorder); Text(item.unit) }
                    .disabled(result != nil)
            } else if item.kind == "dial" {
                Text("\(Int(dial)) \(item.unit)").font(.largeTitle.monospacedDigit())
                Slider(value: $dial, in: 0...100, step: 1).disabled(result != nil).accessibilityLabel(item.unit)
            } else {
                Text(item.kind == "order" ? "Preki sipas radhës. Për ta hequr një zgjedhje, preke sërish." : "Prek të gjitha përgjigjet e sakta.")
                ForEach(options, id: \.self) { option in
                    Button {
                        if picks.contains(option) { picks.removeAll { $0 == option } } else { picks.append(option) }
                    } label: {
                        HStack {
                            Text(option); Spacer()
                            if let i = picks.firstIndex(of: option) {
                                Text(item.kind == "order" ? "\(i + 1)" : "✓").bold()
                            }
                        }.padding().background(picks.contains(option) ? Color.lagoon.opacity(0.15) : .white, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).disabled(result != nil)
                }
            }
            if let result {
                SectionText(heading: result ? "Saktë!" : "Shiko zgjidhjen", text: item.why + "\nPërgjigjja: " + item.answers.joined(separator: ", ") + " " + item.unit)
                if let advance { Button("Vazhdo") { advance(result) }.buttonStyle(.borderedProminent) }
                else if !result { Button("Riprovo") { self.result = nil }.buttonStyle(.bordered) }
            } else {
                Button("Kontrollo përgjigjen") { check() }.buttonStyle(.borderedProminent)
            }
        }.navigationTitle(item.id).onAppear {
            if options.isEmpty {
                options = item.choices.shuffled()
                if item.kind == "order", options == item.answers, let first = options.first {
                    options.removeFirst(); options.append(first)
                }
            }
        }
    }
    private static func numeric(_ raw: String) -> Double? { NumericAnswer.parse(raw) }
    private func check() {
        let right: Bool
        switch item.kind {
        case "order": right = picks == item.answers
        case "select": right = Set(picks) == Set(item.answers)
        case "dial": right = String(Int(dial)) == item.answers.first
        default:
            let cleaned = number.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
            if let actual = Self.numeric(cleaned), let expected = Self.numeric(item.answers[0]) {
                right = NumericAnswer.accepts(actual, expected:expected, tolerance:item.tolerance)
            } else { right = false }
        }
        result = right
        recordAnswer?(right)
        if right && !mastered.components(separatedBy: "|").contains(item.id) { mastered += "|" + item.id }
    }
}

enum SchoolRole: String, CaseIterable, Identifiable {
    case student = "Nxënës", teacher = "Mësues", parent = "Prind"
    var id: Self { self }
    var title: String {
        switch self {
        case .student: return "Këndi i nxënësit"
        case .teacher: return "Këndi i mësuesit"
        case .parent: return "Këndi i prindit"
        }
    }
}

struct RoleDesk: View {
    let role: SchoolRole
    @AppStorage("mastered") private var mastered = ""
    @AppStorage("homeActivity") private var homeActivity = ""
    @AppStorage("goal") private var goal = 5
    @Environment(\.learnerLevel) private var learnerLevel
    private var report: String {
        Subject.allCases.map { subject in
            let group = Exercise.all.filter { $0.subject == subject.rawValue && $0.level == learnerLevel?.rawValue }
            let solved = group.filter { mastered.components(separatedBy: "|").contains($0.id) }
            return "\(subject.rawValue): \(solved.count)/\(group.count)"
        }.joined(separator: "\n")
    }
    var body: some View {
        if role == .teacher {
            Page { SchoolHub(); AccountControls() }
        } else {
        Page {
            Text(role.title).font(.largeTitle.bold())
            if role == .student {
                if let learnerLevel {
                    DisclosureGroup("Ndrysho klasën · " + learnerLevel.name) { StudentClassChooser() }
                    SchoolHub()
                    StudentToday(level: learnerLevel)
                }
                SectionText(heading: "Përparimi im në këtë pajisje", text: report)
                Stepper("Synimi im: \(goal) ushtrime", value: $goal, in: 1...max(1, Exercise.all.filter { $0.level == learnerLevel?.rawValue }.count))
                let count = Exercise.all.filter { $0.level == learnerLevel?.rawValue && mastered.components(separatedBy: "|").contains($0.id) }.count
                ProgressView(value: Double(min(count, goal)), total: Double(goal))
                Text(count >= goal ? "E arrite synimin!" : "Edhe \(goal - count) ushtrime për të arritur synimin.")
                NavigationLink("Mësimet dhe kapitujt e klasës sime") { StudySubjects() }
                NavigationLink("Zgjidh një ushtrim ose kërko kodin e mësuesit") { PracticeMenu() }
                ShareLink(item: "BrainSpark · Raporti im\n" + report) { Label("Ndaje raportin me prindin ose mësuesin", systemImage: "square.and.arrow.up") }
            } else {
                SchoolHub()
                FamilyReport()
                Text("Zgjidhni një veprimtari që mund ta bëni së bashku në shtëpi. Fëmija mund të të dërgojë rezultatet nga këndi i vet me butonin e ndarjes së raportit.")
                ForEach(activities) { activity in
                    DisclosureGroup(activity.title) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(activity.materials)
                            ForEach(activity.steps, id: \.self) { Text($0) }
                            Text(activity.discuss).bold()
                            Button(homeActivity.components(separatedBy: "|").contains(activity.id) ? "Përfunduar ✓" : "E bëmë së bashku") {
                                var ids = Set(homeActivity.split(separator: "|").map(String.init))
                                if ids.contains(activity.id) { ids.remove(activity.id) } else { ids.insert(activity.id) }
                                homeActivity = ids.sorted().joined(separator: "|")
                            }.buttonStyle(.bordered)
                        }.padding(.top, 10)
                    }.padding().background(.white, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }.navigationTitle(role.rawValue)
        }
    }
}

// A parent imports only the report the learner explicitly shared.
struct FamilyReport: View {
    @AppStorage("familyReport") private var saved = ""
    @State private var draft = ""
    @State private var message = ""
    private func scores(_ input: String) -> [(count: Int, total: Int)]? {
        let lines = input.components(separatedBy: .newlines)
        var result: [(count: Int, total: Int)] = []
        for subject in Subject.allCases {
            let prefix = subject.rawValue + ":"
            let matches = lines.filter { $0.hasPrefix(prefix) }
            guard matches.count == 1 else { return nil }
            let parts = matches[0].dropFirst(prefix.count).trimmingCharacters(in: .whitespaces).split(separator: "/")
            let subjectBank = Exercise.all.filter { $0.subject == subject.rawValue }
            let levelTotals = SchoolLevel.allCases.map { level in subjectBank.filter { $0.level == level.rawValue }.count }
            let supportedTotals = Set([9, 10, 14, 17, 33, 45, 50, 70, subjectBank.count] + levelTotals).filter { $0 > 0 }
            guard parts.count == 2, let historicalTotal = Int(parts[1]), supportedTotals.contains(historicalTotal),
                  let count = Int(parts[0]), (0...historicalTotal).contains(count) else { return nil }
            result.append((count, historicalTotal))
        }
        return result
    }
    var body: some View {
        DisclosureGroup("Raporti që më dërgoi fëmija") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ngjit këtu raportin nga këndi i nxënësit. Ruhet vetëm raporti i fundit në këtë profil.")
                TextEditor(text: $draft).frame(minHeight: 85).border(.secondary)
                    .accessibilityLabel("Teksti i raportit")
                Button("Ruaj raportin") {
                    if let values = scores(draft) {
                        saved = zip(Subject.allCases, values).map { subject, count in
                            "\(subject.rawValue): \(count.count)/\(count.total)"
                        }.joined(separator: "\n")
                        draft = ""; message = "Raporti u ruajt."
                    } else { message = "Ngjit raportin e plotë me rezultatet e të katër lëndëve." }
                }.buttonStyle(.bordered)
                if !message.isEmpty { Text(message) }
                if let values = scores(saved) {
                    ForEach(Subject.allCases.indices, id: \.self) { index in
                        let subject = Subject.allCases[index]
                        let total = values[index].total
                        ProgressView(value: Double(values[index].count), total: Double(total)) {
                            Text("\(subject.rawValue) · \(values[index].count) nga \(total)")
                        }
                    }
                }
            }.padding(.top)
        }
    }
}

enum SchoolLevel: Int, CaseIterable, Identifiable {
    case basic = 1, first, second, third, olympiad
    var id: Self { self }
    var name: String {
        switch self {
        case .basic: return "Shkollë 9-vjeçare"
        case .first: return "Gjimnaz · Viti I"
        case .second: return "Gjimnaz · Viti II"
        case .third: return "Gjimnaz · Viti III"
        case .olympiad: return "Olimpiadë"
        }
    }
}
struct LevelPicker: View {
    @Binding var level: SchoolLevel
    var body: some View {
        Picker("Niveli", selection: $level) {
            ForEach(SchoolLevel.allCases) { Text($0.name).tag($0) }
        }.pickerStyle(.menu)
    }
}

private struct LearnerLevelKey: EnvironmentKey {
    static let defaultValue: SchoolLevel? = nil
}
extension EnvironmentValues {
    var learnerLevel: SchoolLevel? {
        get { self[LearnerLevelKey.self] }
        set { self[LearnerLevelKey.self] = newValue }
    }
}
struct StudentClassChooser: View {
    @AppStorage("studentLevel4") private var chosen = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Zgjidh klasën tënde").font(.title2.bold())
            Text("Kjo zgjedhje përcakton ushtrimet dhe kuizet në të katër lëndët.")
            ForEach(SchoolLevel.allCases) { level in
                Button { chosen = level.rawValue } label: {
                    HStack {
                        Text(level.name).bold()
                        Spacer()
                        Image(systemName: chosen == level.rawValue ? "checkmark.circle.fill" : "chevron.right")
                    }.padding().foregroundStyle(chosen == level.rawValue ? Color.white : Color.midnight)
                    .background(chosen == level.rawValue ? Color.lagoon : Color.white, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
            }
        }
    }
}
private struct StudentToday: View {
    let level: SchoolLevel
    @AppStorage("mastered") private var solved = ""
    @State private var subject = Subject.math
    private var items: [Exercise] { Exercise.all.filter { $0.subject == subject.rawValue && $0.level == level.rawValue } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(level.name, systemImage: "graduationcap.fill").foregroundStyle(.white).padding(10).background(Color.lagoon, in: Capsule())
            Text("Ushtrimet e mia").font(.title2.bold())
            Picker("Lënda", selection: $subject) { ForEach(Subject.allCases) { Text($0.rawValue).tag($0) } }
            NavigationLink { SubjectQuiz(subject: subject, level: level) } label: {
                Tile(icon: "bolt.fill", title: "Fillo kuizin tim", detail: subject.rawValue + " · " + level.name)
            }
            let done = Set(solved.split(separator: "|").map(String.init))
            ForEach(items.sorted { first, second in
                if done.contains(first.id) != done.contains(second.id) { return !done.contains(first.id) }
                return first.id > second.id
            }) { item in
                NavigationLink { ExercisePlayer(item: item) } label: {
                    Tile(icon: done.contains(item.id) ? "checkmark.circle.fill" : "pencil", title: item.prompt, detail: item.id + " · " + level.name)
                }
            }
        }.buttonStyle(.plain)
    }
}

