import SwiftUI

// MARK: - Asistenti i mësimeve
// Shpjegon temat duke kërkuar te 600 mësimet e aplikacionit. Punon në pajisje: pa internet, pa shërbim me pagesë,
// pa dërguar pyetjet gjëkundi. Nuk është AI gjeneruese: çdo përgjigje vjen nga një mësim i aplikacionit dhe tregon burimin.

extension StudyLesson {
    var searchDocument: SearchDocument {
        .lesson(id: id, subject: subject, level: level, title: title, chapterTitle: chapterTitle, objectives: objectives,
                introduction: introduction, sections: sections.map { $0.title + " " + $0.text },
                example: example.problem + " " + example.steps.joined(separator: " "), recap: recap)
    }
}

enum LessonAssistantIndex {
    /// Ndërtohet një herë, kur hapet asistenti për herë të parë.
    static let shared = LessonSearch(StudyLesson.all.map(\.searchDocument))
    static let byID: [String: StudyLesson] = Dictionary(uniqueKeysWithValues: StudyLesson.all.map { ($0.id, $0) })
    static let examples = ["Si llogaritet shpejtësia mesatare?", "Çfarë është fotosinteza?", "Teorema e Pitagorës",
                           "Barazimi i reaksionit kimik", "Ligji i dytë i Njutonit", "Si funksionon osmoza?"]
}

struct LessonAssistant: View {
    /// Kur hapet nga një mësim, asistenti nis me atë temë.
    var startingLesson: StudyLesson? = nil
    @Environment(\.learnerLevel) private var learnerLevel
    @State private var question = ""
    @State private var subjectFilter: Subject?
    @State private var onlyMyLevel = true
    @State private var results: [StudyLesson] = []
    @State private var selected: StudyLesson?
    @State private var searched = false

    var body: some View {
        Page {
            AssistantHeader()
            TextField("Çfarë nuk kupton? P.sh. \"si llogaritet nxitimi\"", text: $question, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(1...3).onSubmit(ask)
            AssistantFilters(subject: $subjectFilter, onlyMyLevel: $onlyMyLevel, hasLevel: learnerLevel != nil)
            Button("Shpjegoje") { ask() }.buttonStyle(.borderedProminent)
                .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !searched && selected == nil {
                AssistantExamples { example in question = example; ask() }
            } else if searched && results.isEmpty {
                Text("Nuk gjeta temë që përputhet. Provo fjalë të tjera: emrin e ligjit, të formulës ose të procesit, p.sh. \"energjia kinetike\" ose \"mitoza\". Mund të heqësh edhe filtrin e lëndës ose të nivelit.")
            }
            if let lesson = selected {
                AssistantAnswer(lesson: lesson)
                let others = results.filter { $0.id != lesson.id }
                if !others.isEmpty {
                    Text("Tema të lidhura").font(.headline)
                    ForEach(others) { other in
                        Button { selected = other } label: {
                            Tile(icon: Subject(rawValue: other.subject)?.icon ?? "book",
                                 title: other.title, detail: other.subject + " · " + other.schoolLevel.name)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Asistenti")
        .onAppear {
            if selected == nil, let start = startingLesson {
                selected = start; question = start.title; results = [start]; searched = true
            }
        }
    }

    private func ask() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let level = onlyMyLevel ? learnerLevel?.rawValue : nil
        let hits = LessonAssistantIndex.shared.search(text, subject: subjectFilter?.rawValue, level: level, limit: 5)
        results = hits.compactMap { LessonAssistantIndex.byID[$0.id] }
        selected = results.first
        searched = true
    }
}

private struct AssistantHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Asistenti i mësimeve", systemImage: "questionmark.bubble.fill").font(.largeTitle.bold())
            Text("Shkruaj çfarë nuk kupton dhe asistenti gjen temën te 600 mësimet, pastaj ta shpjegon hap pas hapi.")
            Text("Punon në pajisjen tënde, edhe pa internet. Pyetjet nuk dërgohen gjëkundi. Nuk është AI që shpik përgjigje: çdo shpjegim vjen nga një mësim i aplikacionit.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

private struct AssistantFilters: View {
    @Binding var subject: Subject?
    @Binding var onlyMyLevel: Bool
    let hasLevel: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Lënda", selection: $subject) {
                Text("Të gjitha lëndët").tag(Subject?.none)
                ForEach(Subject.allCases) { item in Text(item.rawValue).tag(Subject?.some(item)) }
            }.pickerStyle(.menu)
            if hasLevel { Toggle("Vetëm temat e klasës sime", isOn: $onlyMyLevel) }
        }
    }
}

private struct AssistantExamples: View {
    let choose: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Provo për shembull").font(.headline)
            ForEach(LessonAssistantIndex.examples, id: \.self) { example in
                Button(example) { choose(example) }.buttonStyle(.bordered)
            }
        }
    }
}

/// Shpjegimi i një teme: ideja, pikat kryesore, shembulli hap pas hapi, gabimi i zakonshëm dhe vetëkontrolli.
private struct AssistantAnswer: View {
    let lesson: StudyLesson
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(lesson.subject + " · " + lesson.schoolLevel.name + " · " + lesson.chapterTitle).font(.caption.bold())
                    .foregroundStyle(lesson.schoolSubject.color)
                Text(lesson.title).font(.title.bold())
            }
            SectionText(heading: "Me pak fjalë", text: lesson.introduction)
            if !lesson.recap.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ideja kryesore").font(.headline).foregroundStyle(Color.lagoon)
                    ForEach(Array(lesson.recap.prefix(3).enumerated()), id: \.offset) { item in
                        Label(item.element, systemImage: "checkmark.circle").fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            StepByStep(example: lesson.example).id(lesson.id)
            SectionText(heading: "Kujdes nga ky gabim", text: lesson.pitfall)
            SelfCheck(check: lesson.check).id(lesson.id + ".check")
            DisclosureGroup("Shpjegimi i plotë") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(lesson.sections.enumerated()), id: \.offset) { item in
                        SectionText(heading: item.element.title, text: item.element.text)
                    }
                }.padding(.top, 8)
            }
            NavigationLink { StudyReader(lesson: lesson) } label: {
                Tile(icon: "book.fill", title: "Hap mësimin e plotë", detail: "Burimi: mësimi " + lesson.id + " · \(lesson.readingMinutes) min")
            }.buttonStyle(.plain)
        }
        .padding(16).background(.white, in: RoundedRectangle(cornerRadius: 18))
    }
}

/// Shembulli zbulohet një hap në një kohë, që nxënësi të mendojë vetë para se të shohë hapin tjetër.
private struct StepByStep: View {
    let example: WorkedExample
    @State private var shown = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hap pas hapi").font(.headline).foregroundStyle(Color.lagoon)
            Text(example.problem).bold().fixedSize(horizontal: false, vertical: true)
            ForEach(Array(example.steps.prefix(shown).enumerated()), id: \.offset) { item in
                Text("\(item.offset + 1). " + item.element).fixedSize(horizontal: false, vertical: true)
            }
            if shown < example.steps.count {
                Text("Mendo vetë hapin \(shown + 1), pastaj krahasoje.").font(.footnote).foregroundStyle(.secondary)
                HStack {
                    Button("Shfaq hapin \(shown + 1)") { shown += 1 }.buttonStyle(.bordered)
                    Button("Shfaq të gjithë") { shown = example.steps.count }
                }
            } else {
                Text(example.conclusion).italic().fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SelfCheck: View {
    let check: StudyCheck
    @State private var picked: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Provo veten").font(.headline).foregroundStyle(Color.lagoon)
            Text(check.prompt).fixedSize(horizontal: false, vertical: true)
            ForEach(Array(check.options.enumerated()), id: \.offset) { item in
                Button { picked = item.offset } label: {
                    Label(item.element, systemImage: icon(item.offset))
                }.buttonStyle(.plain).disabled(picked != nil)
            }
            if let picked {
                Text(picked == check.correct ? "Saktë!" : "Jo tamam. Përgjigjja e saktë: " + check.options[check.correct])
                    .bold().foregroundStyle(picked == check.correct ? Color.green : Color.red)
                Text(check.why).font(.callout).fixedSize(horizontal: false, vertical: true)
                Button("Provo përsëri") { self.picked = nil }
            }
        }
    }
    private func icon(_ index: Int) -> String {
        guard let picked else { return "circle" }
        if index == check.correct { return "checkmark.circle.fill" }
        return index == picked ? "xmark.circle.fill" : "circle"
    }
}
