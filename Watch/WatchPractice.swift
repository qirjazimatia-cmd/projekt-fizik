import SwiftUI

/// Ushtrimet e orës vijnë nga i njëjti `Exercises.json` si në iPhone (600 ushtrime: zgjedhje dhe numra).
enum WatchSubject: String, CaseIterable, Identifiable {
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

struct WatchExercise: Decodable, Identifiable {
    let id, subject, kind, prompt, why, unit: String
    let answers, choices: [String]
    let level: Int
    let tolerance: Double
    static let all: [WatchExercise] = {
        guard let file = Bundle.main.url(forResource: "Exercises", withExtension: "json"),
              let data = try? Data(contentsOf: file),
              let bank = try? JSONDecoder().decode([WatchExercise].self, from: data) else { return [] }
        return bank.filter { $0.kind == "select" || $0.kind == "number" }
    }()
    static let levelNames = [1: "9-vjeçare", 2: "Gjimnaz I", 3: "Gjimnaz II", 4: "Gjimnaz III", 5: "Olimpiadë"]
}

struct WatchLevelList: View {
    let subject: WatchSubject
    var body: some View {
        List {
            ForEach(1...5, id: \.self) { level in
                let count = WatchExercise.all.filter { $0.subject == subject.rawValue && $0.level == level }.count
                if count > 0 {
                    NavigationLink { WatchQuiz(subject: subject, level: level) } label: {
                        VStack(alignment: .leading) {
                            Text(WatchExercise.levelNames[level] ?? "Niveli \(level)")
                            Text("\(count) ushtrime").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(subject.rawValue)
    }
}

struct WatchQuiz: View {
    let subject: WatchSubject
    let level: Int
    @AppStorage("watchMastered") private var mastered = ""
    @State private var queue: [WatchExercise] = []
    @State private var index = 0
    @State private var picks: Set<String> = []
    @State private var number = ""
    @State private var result: Bool?
    @State private var right = 0
    @State private var answered = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if queue.isEmpty {
                    Text("Nuk ka ushtrime për këtë nivel.")
                } else {
                    let item = queue[index % queue.count]
                    Text("\(right)/\(answered) të sakta").font(.footnote).foregroundStyle(.secondary)
                    Text(item.prompt).font(.body).fixedSize(horizontal: false, vertical: true)
                    if item.kind == "select" { choices(item) } else { numberInput(item) }
                    if let result {
                        Label(result ? "Saktë!" : "Jo ende", systemImage: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result ? Color.green : Color.orange)
                        if !result { Text("Përgjigja: " + item.answers.joined(separator: "; ") + (item.unit.isEmpty ? "" : " " + item.unit)).font(.footnote) }
                        Text(item.why).font(.footnote).fixedSize(horizontal: false, vertical: true)
                        Button("Tjetri") { next() }.buttonStyle(.borderedProminent)
                    } else {
                        Button("Kontrollo") { check(item) }
                            .buttonStyle(.borderedProminent)
                            .disabled(item.kind == "select" ? picks.isEmpty : number.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .navigationTitle(WatchExercise.levelNames[level] ?? subject.rawValue)
        .onAppear {
            if queue.isEmpty {
                let done = Set(mastered.split(separator: "|").map(String.init))
                let items = WatchExercise.all.filter { $0.subject == subject.rawValue && $0.level == level }.shuffled()
                // Fillimisht ato që nuk janë zgjidhur ende saktë në këtë orë.
                queue = items.filter { !done.contains($0.id) } + items.filter { done.contains($0.id) }
            }
        }
    }

    @ViewBuilder private func choices(_ item: WatchExercise) -> some View {
        if item.answers.count > 1 { Text("Zgjidh të gjitha të saktat.").font(.footnote).foregroundStyle(.secondary) }
        ForEach(item.choices, id: \.self) { choice in
            Button {
                guard result == nil else { return }
                if item.answers.count > 1 {
                    if picks.contains(choice) { picks.remove(choice) } else { picks.insert(choice) }
                } else { picks = [choice] }
            } label: {
                HStack {
                    Image(systemName: picks.contains(choice) ? "checkmark.circle.fill" : "circle")
                    Text(choice).font(.footnote).multilineTextAlignment(.leading)
                }
            }
            .tint(tint(for: choice, item))
        }
    }

    private func tint(for choice: String, _ item: WatchExercise) -> Color? {
        guard result != nil else { return nil }
        if item.answers.contains(choice) { return Color.green }
        return picks.contains(choice) ? Color.orange : nil
    }

    @ViewBuilder private func numberInput(_ item: WatchExercise) -> some View {
        TextField(item.unit.isEmpty ? "Përgjigja" : "Përgjigja në " + item.unit, text: $number)
            .disabled(result != nil)
        Text("Mund të shkruash edhe thyesë, p.sh. 3/4.").font(.footnote).foregroundStyle(.secondary)
    }

    private func check(_ item: WatchExercise) {
        let ok: Bool
        if item.kind == "select" {
            ok = picks == Set(item.answers)
        } else if let actual = NumericAnswer.parse(number), let expected = NumericAnswer.parse(item.answers.first ?? "") {
            ok = NumericAnswer.accepts(actual, expected: expected, tolerance: item.tolerance)
        } else { ok = false }
        result = ok
        answered += 1
        if ok {
            right += 1
            if !mastered.split(separator: "|").contains(Substring(item.id)) { mastered += "|" + item.id }
        }
    }

    private func next() {
        index += 1; picks = []; number = ""; result = nil
    }
}
