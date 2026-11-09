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

// MARK: - Biseda me asistentin

extension StudyLesson {
    var tutorLesson: TutorLesson {
        TutorLesson(id: id, subject: subject, title: title, introduction: introduction,
                    sections: sections.map { (title: $0.title, text: $0.text) }, problem: example.problem, steps: example.steps,
                    conclusion: example.conclusion, pitfall: pitfall, recap: recap, checkPrompt: check.prompt,
                    checkOptions: check.options, checkCorrect: check.correct, checkWhy: check.why, exerciseIDs: exerciseIDs)
    }
}

extension Exercise {
    var tutorExercise: TutorExercise {
        TutorExercise(id: id, kind: kind, prompt: prompt, unit: unit, why: why, accuracy: accuracy, answers: answers, choices: choices, tolerance: tolerance)
    }
}

extension SchoolRole {
    var tutorRole: TutorRole {
        switch self {
        case .teacher: return .teacher
        case .parent: return .parent
        case .student: return .student
        }
    }
}

private struct ChatLine: Identifiable {
    let id = UUID()
    let fromStudent: Bool
    let reply: TutorReply
}

/// "Dija": faqja e bisedës me asistenten e mësimeve. Hapet nga menyja anësore, nga faqja kryesore dhe nga çdo mësim.
struct TutorChat: View {
    /// Kur hapet nga një mësim, biseda nis me atë temë.
    var startingLesson: StudyLesson? = nil
    @State private var tutor: LessonTutor
    @State private var lines: [ChatLine] = []
    @State private var draft = ""

    init(startingLesson: StudyLesson? = nil, role: SchoolRole = .student) {
        self.startingLesson = startingLesson
        _tutor = State(initialValue: LessonTutor(search: LessonAssistantIndex.shared, lessons: StudyLesson.all.map(\.tutorLesson),
                                                 exercises: Exercise.all.map(\.tutorExercise), role: role.tutorRole))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ChatIntro()
                        ForEach(lines) { line in ChatBubble(line: line).id(line.id) }
                    }
                    .frame(maxWidth: 720, alignment: .leading).padding(16).frame(maxWidth: .infinity)
                }
                .onChange(of: lines.count) { _ in
                    if let last = lines.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            ChatSuggestions(items: lines.last(where: { !$0.fromStudent })?.reply.suggestions ?? LessonAssistantIndex.examples.prefix(3).map { $0 }) { send($0) }
            HStack {
                TextField("Shkruaj këtu…", text: $draft, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...4).onSubmit { send(draft) }
                Button { send(draft) } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Dërgo")
            }.padding(12).background(.white)
        }
        .background(Color.paper)
        .navigationTitle(LessonTutor.name)
        .onAppear {
            guard lines.isEmpty else { return }
            if let lesson = startingLesson, let first = tutor.start(with: lesson.id) {
                lines.append(ChatLine(fromStudent: false, reply: first))
            } else {
                lines.append(ChatLine(fromStudent: false, reply: tutor.welcome()))
            }
        }
    }

    private func send(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        draft = ""
        lines.append(ChatLine(fromStudent: true, reply: TutorReply(text: clean)))
        lines.append(ChatLine(fromStudent: false, reply: tutor.reply(to: clean)))
    }
}

private struct ChatIntro: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(LessonTutor.name + " · asistentja e mësimeve", systemImage: "sparkles").font(.title2.bold())
            Text("Pyet për një temë dhe vazhdo bisedën: \"më thjesht\", \"shembull\", \"pse?\", \"më jep një ushtrim\", \"kam test nesër\". Llogarit edhe shprehje. Punon në pajisjen tënde, pa internet; shpjegimet vijnë nga mësimet e aplikacionit.")
                .font(.footnote).foregroundStyle(.secondary)
            NavigationLink("Kërko temat si listë") { LessonAssistant() }.font(.footnote)
        }
    }
}

private struct ChatBubble: View {
    let line: ChatLine
    var body: some View {
        HStack {
            if line.fromStudent { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 8) {
                if let title = line.reply.title { Text(title).font(.headline) }
                Text(line.reply.text).fixedSize(horizontal: false, vertical: true)
                if !line.fromStudent, let id = line.reply.lessonID, let lesson = LessonAssistantIndex.byID[id] {
                    NavigationLink { StudyReader(lesson: lesson) } label: {
                        Label("Burimi: " + lesson.title, systemImage: "book").font(.caption.bold())
                    }.buttonStyle(.plain).foregroundStyle(Color.lagoon)
                }
            }
            .padding(12)
            .foregroundStyle(line.fromStudent ? Color.white : Color.black.opacity(0.86))
            .background(line.fromStudent ? Color.lagoon : Color.white, in: RoundedRectangle(cornerRadius: 16))
            if !line.fromStudent { Spacer(minLength: 40) }
        }
    }
}

private struct ChatSuggestions: View {
    let items: [String]
    let choose: (String) -> Void
    var body: some View {
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(items, id: \.self) { item in Button(item) { choose(item) }.buttonStyle(.bordered) }
                }.padding(.horizontal, 12).padding(.vertical, 6)
            }
        }
    }
}
