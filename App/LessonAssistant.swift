import SwiftUI
import PhotosUI
import Vision
import ImageIO
import UniformTypeIdentifiers

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

private struct ChatLine: Identifiable, Codable {
    var id = UUID()
    let fromStudent: Bool
    let reply: TutorReply
    var fromPhoto: Bool? = nil
}

/// Një bisedë e ruajtur me Bosko AI.
private struct ChatConversation: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = "Bisedë e re"
    var updated = Date()
    var lines: [ChatLine] = []
    var hasQuestions: Bool { lines.contains(where: \.fromStudent) }
    var lastLessonID: String? { lines.last(where: { !$0.fromStudent && $0.reply.lessonID != nil })?.reply.lessonID }
    static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.updated == b.updated && a.lines.count == b.lines.count && a.title == b.title }
}

/// Ruan bisedat në pajisje (një listë për çdo rol). Fshihen vetëm kur përdoruesi i fshin vetë.
private enum ChatHistory {
    private static var folder: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = base.appendingPathComponent("BoskoAI", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
    private static func url(_ role: TutorRole) -> URL? { folder?.appendingPathComponent("bisedat-\(role).json") }

    static func load(_ role: TutorRole) -> [ChatConversation] {
        var list: [ChatConversation] = []
        if let url = url(role), let data = try? Data(contentsOf: url) {
            list = (try? JSONDecoder().decode([ChatConversation].self, from: data)) ?? []
        }
        // Biseda e vetme e versionit të mëparshëm ("Dija") bëhet bisedë e parë e listës.
        if let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let old = base.appendingPathComponent("Dija/biseda-\(role).json")
            if let data = try? Data(contentsOf: old), let lines = try? JSONDecoder().decode([ChatLine].self, from: data), lines.contains(where: \.fromStudent) {
                var conversation = ChatConversation(lines: lines)
                conversation.title = title(for: lines)
                list.append(conversation)
                save(list, role)
                try? FileManager.default.removeItem(at: old)
            }
        }
        return list.sorted { $0.updated > $1.updated }
    }
    static func save(_ list: [ChatConversation], _ role: TutorRole) {
        let trimmed = list.filter(\.hasQuestions).map { conversation -> ChatConversation in
            var c = conversation; c.lines = Array(c.lines.suffix(400)); return c
        }
        guard let url = url(role), let data = try? JSONEncoder().encode(Array(trimmed.prefix(100))) else { return }
        try? data.write(to: url, options: .atomic)
    }
    static func title(for lines: [ChatLine]) -> String {
        guard let first = lines.first(where: \.fromStudent) else { return "Bisedë e re" }
        let text = first.reply.text.replacingOccurrences(of: "\n", with: " ")
        return text.count > 42 ? String(text.prefix(40)) + "…" : text
    }
}

/// "Bosko AI": biseda me asistentin e mësimeve, me listë bisedash anash (si te Claude). Hapet nga menyja anësore,
/// nga faqja kryesore dhe nga çdo mësim.
struct TutorChat: View {
    /// Kur hapet nga një mësim, nis një bisedë e re me atë temë.
    var startingLesson: StudyLesson? = nil
    private let role: TutorRole
    @State private var tutor: LessonTutor
    @State private var conversations: [ChatConversation] = []
    @State private var currentID: UUID?
    @State private var draft = ""
    @State private var loaded = false
    @State private var showList = true
    @State private var showListSheet = false
    @State private var toDelete: ChatConversation?
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var showCamera = false
    @State private var reading = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    init(startingLesson: StudyLesson? = nil, role: SchoolRole = .student) {
        self.startingLesson = startingLesson
        self.role = role.tutorRole
        _tutor = State(initialValue: Self.makeTutor(role.tutorRole))
    }

    private static func makeTutor(_ role: TutorRole) -> LessonTutor {
        LessonTutor(search: LessonAssistantIndex.shared, lessons: StudyLesson.all.map(\.tutorLesson),
                    exercises: Exercise.all.map(\.tutorExercise), role: role)
    }

    private var compact: Bool {
        #if os(iOS)
        return sizeClass == .compact
        #else
        return false
        #endif
    }
    private var lines: [ChatLine] { conversations.first(where: { $0.id == currentID })?.lines ?? [] }

    var body: some View {
        HStack(spacing: 0) {
            if showList && !compact {
                ConversationList(conversations: conversations.filter(\.hasQuestions), currentID: currentID,
                                 choose: open, delete: { toDelete = $0 }, newChat: newConversation)
                    .frame(width: 250)
                Divider()
            }
            chatColumn
        }
        .background(Color.paper)
        .navigationTitle(LessonTutor.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    if compact { showListSheet = true } else { withAnimation { showList.toggle() } }
                } label: {
                    Label("Bisedat", systemImage: "sidebar.left")
                }
                Button(action: newConversation) { Label("Bisedë e re", systemImage: "square.and.pencil") }
            }
        }
        .sheet(isPresented: $showListSheet) {
            NavigationStack {
                ConversationList(conversations: conversations.filter(\.hasQuestions), currentID: currentID,
                                 choose: { open($0); showListSheet = false }, delete: { toDelete = $0 },
                                 newChat: { newConversation(); showListSheet = false })
                    .navigationTitle("Bisedat")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Mbyll") { showListSheet = false } } }
            }
        }
        .confirmationDialog("Ta fshij bisedën «\(toDelete?.title ?? "")»?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Fshi bisedën", role: .destructive) { if let c = toDelete { delete(c) } }
            Button("Anulo", role: .cancel) { toDelete = nil }
        } message: {
            Text("Bisedat e tjera mbeten. Kjo bisedë nuk kthehet më pasi ta fshish.")
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { item in
            guard let item else { return }
            photoItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { await readPhoto(data) }
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            let data = try? Data(contentsOf: url)
            if access { url.stopAccessingSecurityScopedResource() }
            if let data { Task { await readPhoto(data) } }
        }
        #if os(iOS)
        .sheet(isPresented: $showCamera) {
            CameraPicker(done: { data in Task { await readPhoto(data) } }, close: { showCamera = false }).ignoresSafeArea()
        }
        #endif
        .onAppear(perform: load)
    }

    private var chatColumn: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ChatIntro()
                        ForEach(lines) { line in ChatBubble(line: line).id(line.id) }
                        if reading { ProgressView("Po lexoj foton…").padding(.vertical, 8) }
                    }
                    .frame(maxWidth: 720, alignment: .leading).padding(16).frame(maxWidth: .infinity)
                }
                .onChange(of: lines.count) { _ in
                    if let last = lines.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            ChatSuggestions(items: lines.last(where: { !$0.fromStudent })?.reply.suggestions ?? LessonAssistantIndex.examples.prefix(3).map { $0 }) { send($0) }
            HStack {
                Menu {
                    Button { showPhotoPicker = true } label: { Label("Nga fotot", systemImage: "photo") }
                    #if os(iOS)
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showCamera = true } label: { Label("Bëj foto", systemImage: "camera") }
                    }
                    #endif
                    Button { showFileImporter = true } label: { Label("Nga një skedar", systemImage: "folder") }
                } label: {
                    Image(systemName: "camera.fill").font(.title3)
                }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("Dërgo një foto të ushtrimit")
                .disabled(reading)
                TextField("Shkruaj këtu…", text: $draft, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...4).onSubmit { send(draft) }
                Button { send(draft) } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Dërgo")
            }.padding(12).background(.white)
        }
    }

    // MARK: Bisedat

    private func load() {
        guard !loaded else { return }
        loaded = true
        conversations = ChatHistory.load(role)
        if let lesson = startingLesson, let first = tutor.start(with: lesson.id) {
            let conversation = ChatConversation(lines: [ChatLine(fromStudent: false, reply: first)])
            conversations.insert(conversation, at: 0)
            currentID = conversation.id
        } else if let latest = conversations.first {
            open(latest)
        } else {
            newConversation()
        }
    }

    private func open(_ conversation: ChatConversation) {
        currentID = conversation.id
        tutor = Self.makeTutor(role)
        tutor.resume(lessonID: conversation.lastLessonID)
    }

    private func newConversation() {
        // Një bisedë bosh nuk dyfishohet: thjesht e hapim atë.
        conversations.removeAll { !$0.hasQuestions && $0.id != currentID }
        if let current = conversations.first(where: { $0.id == currentID }), !current.hasQuestions { return }
        tutor = Self.makeTutor(role)
        let conversation = ChatConversation(lines: [ChatLine(fromStudent: false, reply: tutor.welcome())])
        conversations.insert(conversation, at: 0)
        currentID = conversation.id
    }

    private func delete(_ conversation: ChatConversation) {
        conversations.removeAll { $0.id == conversation.id }
        toDelete = nil
        ChatHistory.save(conversations, role)
        if currentID == conversation.id {
            if let next = conversations.first(where: \.hasQuestions) { open(next) } else { currentID = nil; newConversation() }
        }
    }

    private func append(_ newLines: [ChatLine]) {
        guard let index = conversations.firstIndex(where: { $0.id == currentID }) else { return }
        conversations[index].lines.append(contentsOf: newLines)
        conversations[index].updated = Date()
        conversations[index].title = ChatHistory.title(for: conversations[index].lines)
        let conversation = conversations.remove(at: index)
        conversations.insert(conversation, at: 0)
        ChatHistory.save(conversations, role)
    }

    private func send(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        draft = ""
        append([ChatLine(fromStudent: true, reply: TutorReply(text: clean)),
                ChatLine(fromStudent: false, reply: tutor.reply(to: clean))])
    }

    @MainActor
    private func readPhoto(_ data: Data) async {
        reading = true
        let recognized = await PhotoText.read(data)
        reading = false
        let shown = recognized.isEmpty ? "📷 Foto" : "📷 " + recognized.joined(separator: "\n")
        append([ChatLine(fromStudent: true, reply: TutorReply(text: shown), fromPhoto: true),
                ChatLine(fromStudent: false, reply: tutor.reply(toPhotoLines: recognized))])
    }
}

private struct ConversationList: View {
    let conversations: [ChatConversation]
    let currentID: UUID?
    let choose: (ChatConversation) -> Void
    let delete: (ChatConversation) -> Void
    let newChat: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: newChat) {
                Label("Bisedë e re", systemImage: "square.and.pencil").frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered).padding(12)
            if conversations.isEmpty {
                Text("Bisedat e tua do shfaqen këtu. Ruhen në këtë pajisje derisa t'i fshish.")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 12)
                Spacer()
            } else {
                List {
                    ForEach(conversations) { conversation in
                        Button { choose(conversation) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(conversation.title).lineLimit(1)
                                    .fontWeight(conversation.id == currentID ? .semibold : .regular)
                                Text(conversation.updated, format: .dateTime.day().month().hour().minute())
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(conversation.id == currentID ? Color.lagoon.opacity(0.14) : Color.clear)
                        .contextMenu { Button(role: .destructive) { delete(conversation) } label: { Label("Fshi bisedën", systemImage: "trash") } }
                        .swipeActions { Button(role: .destructive) { delete(conversation) } label: { Label("Fshi", systemImage: "trash") } }
                    }
                }
                .listStyle(.plain)
                Text("Për ta fshirë një bisedë: kliko me të djathtën mbi të (ose rrëshqite majtas).")
                    .font(.caption2).foregroundStyle(.secondary).padding(12)
            }
        }
        .background(Color.paper)
    }
}

/// Lexon tekstin e një fotoje në pajisje (Apple Vision): pa internet dhe pa pagesë.
private enum PhotoText {
    static func read(_ data: Data) async -> [String] {
        await Task.detached(priority: .userInitiated) { () -> [String] in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldAllowFloat: true] as CFDictionary) else { return [] }
            let orientation: CGImagePropertyOrientation = {
                let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
                let raw = props?[kCGImagePropertyOrientation] as? UInt32 ?? 1
                return CGImagePropertyOrientation(rawValue: raw) ?? .up
            }()
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
            guard (try? handler.perform([request])) != nil else { return [] }
            let observations = (request.results ?? []).sorted { $0.boundingBox.minY > $1.boundingBox.minY }
            return observations.compactMap { $0.topCandidates(1).first?.string }
        }.value
    }
}

#if os(iOS)
/// Kamera e iPhone/iPad për të fotografuar ushtrimin.
private struct CameraPicker: UIViewControllerRepresentable {
    let done: (Data) -> Void
    let close: () -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) { parent.done(data) }
            parent.close()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.close() }
    }
}
#endif

private struct ChatIntro: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(LessonTutor.name + " · asistenti i mësimeve", systemImage: "sparkles").font(.title2.bold())
            Text("Pyet për një temë dhe vazhdo bisedën: \"më thjesht\", \"shembull\", \"pse?\", \"më jep një ushtrim\", \"kam test nesër\". Llogarit shprehje, zgjidh ekuacione (p.sh. 2x + 3 = 11) dhe lexon ushtrimin nga një foto 📷. Punon në pajisjen tënde, pa internet; shpjegimet vijnë nga mësimet e aplikacionit.")
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
