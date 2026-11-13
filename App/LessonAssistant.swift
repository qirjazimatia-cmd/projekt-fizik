import SwiftUI
import PhotosUI
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
        .padding(16).background(Color.card, in: RoundedRectangle(cornerRadius: 18))
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
    /// Emri i fotos së ruajtur në pajisje (BoskoAI/foto/...), nëse mesazhi kishte foto.
    var imageName: String? = nil
    /// Përgjigje nga Bosko AI me internet (jo nga asistenti lokal).
    var online: Bool? = nil
}

/// Një bisedë e ruajtur me Bosko AI.
private struct ChatConversation: Identifiable, Codable {
    var id = UUID()
    var title = "Bisedë e re"
    var updated = Date()
    var lines: [ChatLine] = []
    var hasQuestions: Bool { lines.contains(where: { $0.fromStudent }) }
    var lastLessonID: String? { lines.last(where: { !$0.fromStudent && $0.reply.lessonID != nil })?.reply.lessonID }
}

/// Ruan bisedat dhe fotot në pajisje (një listë për çdo rol). Fshihen vetëm kur përdoruesi i fshin vetë.
private enum ChatHistory {
    static var folder: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = base.appendingPathComponent("BoskoAI", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder.appendingPathComponent("foto", isDirectory: true), withIntermediateDirectories: true)
        return folder
    }
    private static func url(_ role: TutorRole) -> URL? { folder?.appendingPathComponent("bisedat-\(role).json") }
    static func imageURL(_ name: String) -> URL? { folder?.appendingPathComponent("foto", isDirectory: true).appendingPathComponent(name) }

    static func load(_ role: TutorRole) -> [ChatConversation] {
        var list: [ChatConversation] = []
        if let url = url(role), let data = try? Data(contentsOf: url) {
            list = (try? JSONDecoder().decode([ChatConversation].self, from: data)) ?? []
        }
        // Biseda e vetme e versionit të mëparshëm ("Dija") bëhet bisedë e parë e listës.
        if let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let old = base.appendingPathComponent("Dija/biseda-\(role).json")
            if let data = try? Data(contentsOf: old), let lines = try? JSONDecoder().decode([ChatLine].self, from: data),
               lines.contains(where: { $0.fromStudent }) {
                list.append(ChatConversation(title: title(for: lines), lines: lines))
                save(list, role)
                try? FileManager.default.removeItem(at: old)
            }
        }
        return list.sorted { $0.updated > $1.updated }
    }
    static func save(_ list: [ChatConversation], _ role: TutorRole) {
        let kept = list.filter { $0.hasQuestions }.prefix(100).map { conversation -> ChatConversation in
            var copy = conversation
            copy.lines = Array(copy.lines.suffix(400))
            return copy
        }
        guard let url = url(role), let data = try? JSONEncoder().encode(Array(kept)) else { return }
        try? data.write(to: url, options: .atomic)
    }
    static func saveImage(_ data: Data) -> String? {
        let name = UUID().uuidString + ".jpg"
        guard let url = imageURL(name), (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return name
    }
    static func deleteImages(of conversation: ChatConversation) {
        for name in conversation.lines.compactMap({ $0.imageName }) {
            if let url = imageURL(name) { try? FileManager.default.removeItem(at: url) }
        }
    }
    static func title(for lines: [ChatLine]) -> String {
        guard let first = lines.first(where: { $0.fromStudent }) else { return "Bisedë e re" }
        let text = first.reply.text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return first.imageName != nil ? "📷 Foto" : "Bisedë e re" }
        return text.count > 42 ? String(text.prefix(40)) + "…" : text
    }
}

/// Fotot: i zvogëlon në JPEG (deri 1600 px), pa UIKit/AppKit, që të shkojnë shpejt dhe të zënë pak vend.
private enum ChatImage {
    static func jpeg(from data: Data, maxPixels: Int = 1600) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: maxPixels]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
    static func cgImage(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

/// Lidhja me Bosko AI me internet (Edge Function `bosko-ai` te Supabase, që pyet Gemini). Çelësi nuk është në aplikacion.
private enum BoskoOnline {
    struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } }
    private struct Answer: Decodable { let text: String?; let error: String? }

    @MainActor
    static func ask(history: [ChatLine], image: Data?, role: TutorRole, lesson: String?, audio: Data? = nil, mode: String? = nil) async throws -> String {
        SupabaseAuth.shared.loadStored()
        guard SupabaseConfig.enabled, SupabaseAuth.shared.session != nil else {
            throw Failure(message: "Për Bosko AI me internet duhet të jesh i kyçur në llogari.")
        }
        let token = try await SupabaseAuth.shared.accessToken()
        var base = SupabaseConfig.url
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/functions/v1/bosko-ai") else { throw Failure(message: "Adresa e shërbimit nuk është e vlefshme.") }
        let messages: [[String: String]] = history.suffix(16).compactMap { line -> [String: String]? in
            var text = line.reply.text
            if let title = line.reply.title, !line.fromStudent { text = title + "\n" + text }
            if line.imageName != nil && line.fromStudent && text.isEmpty { text = "(foto)" }
            if line.fromStudent && text == "🎤 Pyetje me zë" { text = "(pyetje me zë)" }
            return text.isEmpty ? nil : ["role": line.fromStudent ? "user" : "model", "text": text]
        }
        var body: [String: Any] = ["messages": messages, "role": "\(role)"]
        if let lesson { body["lesson"] = lesson }
        if let image { body["image"] = ["mime": "image/jpeg", "data": image.base64EncodedString()] }
        if let audio { body["audio"] = ["mime": "audio/mp4", "data": audio.base64EncodedString()] }
        if let mode { body["mode"] = mode }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.timeoutInterval = 90
        request.setValue(SupabaseConfig.key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let answer = try? JSONDecoder().decode(Answer.self, from: data)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let text = answer?.text, !text.isEmpty else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw Failure(message: answer?.error ?? (code == 404 ? "Bosko AI me internet nuk është aktivizuar ende te Supabase." : "Bosko AI nuk u përgjigj (\(code))."))
        }
        return text
    }
}

/// "Bosko AI": biseda me asistentin e mësimeve, me listë bisedash anash (si te Claude). Me internet përgjigjet vijnë nga
/// Bosko AI online (kupton edhe foto); pa internet përgjigjet asistenti lokal nga mësimet e aplikacionit.
struct TutorChat: View {
    /// Kur hapet nga një mësim, nis një bisedë e re me atë temë.
    var startingLesson: StudyLesson? = nil
    private let role: TutorRole
    @State private var tutor: LessonTutor
    @State private var conversations: [ChatConversation] = []
    @State private var currentID: UUID?
    @State private var draft = ""
    @State private var pendingImage: Data?
    @State private var loaded = false
    @State private var showList = true
    @State private var showListSheet = false
    @State private var toDelete: ChatConversation?
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var showCamera = false
    /// Bisedat që po presin përgjigje nga Bosko AI online (secila bisedë e vetën).
    @State private var waitingIDs: Set<UUID> = []
    /// "Mos ma thuaj përgjigjen": Bosko jep vetëm sugjerime hap pas hapi.
    @AppStorage("bosko.hints.v1", store: .standard) private var hintMode = false
    @StateObject private var reader = SpeechReader()
    @StateObject private var recorder = VoiceRecorder()
    @State private var showMockTest = false
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
    private var saved: [ChatConversation] { conversations.filter { $0.hasQuestions } }
    private var thinking: Bool { currentID.map { waitingIDs.contains($0) } ?? false }
    private var canSend: Bool { !thinking && (pendingImage != nil || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }

    var body: some View {
        HStack(spacing: 0) {
            if showList && !compact {
                ConversationList(conversations: saved, currentID: currentID,
                                 choose: { open($0) }, delete: { toDelete = $0 }, newChat: { newConversation() })
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
                } label: { Label("Bisedat", systemImage: "sidebar.left") }
                Button { newConversation() } label: { Label("Bisedë e re", systemImage: "square.and.pencil") }
                Toggle(isOn: $hintMode) { Label("Vetëm sugjerime", systemImage: hintMode ? "lightbulb.fill" : "lightbulb") }
                    .help("Mos ma thuaj përgjigjen: vetëm sugjerime hap pas hapi")
                Menu {
                    Button { showMockTest = true } label: { Label("Test prove nga kapitujt", systemImage: "checklist") }
                    if role == .teacher {
                        Button { draft = "Krijo 10 pyetje testi (me alternativa dhe përgjigjet e sakta në fund) për temën: " } label: { Label("Pyetje testi për një temë", systemImage: "list.number") }
                        Button { draft = "Bëj një plan mësimi 45-minutësh (objektivat, hyrja, aktivitetet, kontrolli, detyra) për temën: " } label: { Label("Plan mësimi për një temë", systemImage: "doc.text") }
                    }
                } label: { Label("Më shumë", systemImage: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showListSheet) {
            NavigationStack {
                ConversationList(conversations: saved, currentID: currentID,
                                 choose: { open($0); showListSheet = false }, delete: { toDelete = $0 },
                                 newChat: { newConversation(); showListSheet = false })
                    .navigationTitle("Bisedat")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Mbyll") { showListSheet = false } } }
            }
        }
        .confirmationDialog("Ta fshij këtë bisedë?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Fshi bisedën", role: .destructive) { if let c = toDelete { delete(c) } }
            Button("Anulo", role: .cancel) { toDelete = nil }
        } message: {
            Text("«\(toDelete?.title ?? "")» fshihet bashkë me fotot e saj. Bisedat e tjera mbeten.")
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { item in
            guard let item else { return }
            photoItem = nil
            Task { @MainActor in
                if let data = try? await item.loadTransferable(type: Data.self) { attach(data) }
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            let data = try? Data(contentsOf: url)
            if access { url.stopAccessingSecurityScopedResource() }
            if let data { attach(data) }
        }
        #if os(iOS)
        .sheet(isPresented: $showCamera) {
            CameraPicker(done: { attach($0) }, close: { showCamera = false }).ignoresSafeArea()
        }
        #endif
        .onAppear { load() }
        .environmentObject(reader)
        .onDisappear { reader.stop() }
        .sheet(isPresented: $showMockTest) {
            NavigationStack {
                MockTestView()
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Mbyll") { showMockTest = false } } }
            }
            .frame(minWidth: 420, minHeight: 520)
        }
    }

    private var chatColumn: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ChatIntro()
                        ForEach(lines) { line in ChatBubble(line: line).id(line.id) }
                        if thinking {
                            HStack(spacing: 8) { ProgressView(); Text("Bosko po mendon…").foregroundStyle(.secondary) }
                                .padding(.vertical, 6).id("thinking")
                        }
                    }
                    .frame(maxWidth: 720, alignment: .leading).padding(16).frame(maxWidth: .infinity)
                }
                .onChange(of: lines.count) { _ in
                    if let last = lines.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
                .onChange(of: thinking) { now in
                    if now { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
                }
            }
            ChatSuggestions(items: lines.last(where: { !$0.fromStudent })?.reply.suggestions ?? LessonAssistantIndex.examples.prefix(3).map { $0 }) { send($0) }
            if !recorder.message.isEmpty { Text(recorder.message).font(.footnote).foregroundStyle(.orange).padding(.horizontal, 12) }
            if hintMode { Label("Mënyra «vetëm sugjerime»: Bosko nuk e jep përgjigjen, të çon hap pas hapi.", systemImage: "lightbulb.fill").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12) }
            composer
        }
    }

    /// Kutia e shkrimit: foto (opsionale) + tekst (opsional), dërgohen bashkë me një shtypje.
    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let pendingImage, let image = ChatImage.cgImage(pendingImage) {
                ZStack(alignment: .topTrailing) {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                        .frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 10))
                    Button { self.pendingImage = nil } label: {
                        Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.white, .black.opacity(0.6))
                    }
                    .buttonStyle(.plain).padding(4).accessibilityLabel("Hiq foton")
                }
            }
            HStack(alignment: .bottom) {
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
                .fixedSize()
                .accessibilityLabel("Shto një foto")
                Button {
                    if recorder.recording { if let audio = recorder.stop() { sendVoice(audio) } }
                    else { Task { await recorder.start() } }
                } label: {
                    Image(systemName: recorder.recording ? "stop.circle.fill" : "mic.fill").font(.title3)
                        .foregroundStyle(recorder.recording ? Color.red : Color.lagoon)
                }
                .buttonStyle(.plain).disabled(thinking)
                .accessibilityLabel(recorder.recording ? "Ndalo dhe dërgo pyetjen me zë" : "Pyet me zë")
                TextField(recorder.recording ? "Po dëgjoj… shtyp ⏹ kur të mbarosh" : (pendingImage == nil ? "Shkruaj këtu…" : "Shto një pyetje për foton (s'është e detyrueshme)…"), text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...5)
                    .onSubmit { if canSend { send(draft) } }
                Button { send(draft) } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                    .buttonStyle(.plain).foregroundStyle(canSend ? Color.lagoon : Color.secondary)
                    .disabled(!canSend)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityLabel("Dërgo")
            }
        }
        .padding(12).background(Color.card)
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
        // Një bisedë bosh nuk dyfishohet: thjesht mbetemi te ajo.
        conversations.removeAll { !$0.hasQuestions && $0.id != currentID }
        if let current = conversations.first(where: { $0.id == currentID }), !current.hasQuestions { return }
        tutor = Self.makeTutor(role)
        let conversation = ChatConversation(lines: [ChatLine(fromStudent: false, reply: tutor.welcome())])
        conversations.insert(conversation, at: 0)
        currentID = conversation.id
    }

    private func delete(_ conversation: ChatConversation) {
        ChatHistory.deleteImages(of: conversation)
        conversations.removeAll { $0.id == conversation.id }
        toDelete = nil
        ChatHistory.save(conversations, role)
        if currentID == conversation.id {
            currentID = nil
            if let next = conversations.first(where: { $0.hasQuestions }) { open(next) } else { newConversation() }
        }
    }

    private func append(_ newLines: [ChatLine], to id: UUID?) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].lines.append(contentsOf: newLines)
        conversations[index].updated = Date()
        conversations[index].title = ChatHistory.title(for: conversations[index].lines)
        let conversation = conversations.remove(at: index)
        conversations.insert(conversation, at: 0)
        ChatHistory.save(conversations, role)
    }

    // MARK: Dërgimi

    private func attach(_ data: Data) {
        if let jpeg = ChatImage.jpeg(from: data) { pendingImage = jpeg }
    }

    /// Materiali nga 600 mësimet e aplikacionit që i jepet Bosko AI: tema e bisedës dhe mësimet që i përshtaten pyetjes.
    /// Kështu përgjigjet ndjekin programin dhe fjalorin e shkollës.
    private func lessonContext(_ conversation: ChatConversation?, question: String) -> String? {
        var ids: [String] = []
        if let id = conversation?.lastLessonID { ids.append(id) }
        if !question.isEmpty {
            for hit in LessonAssistantIndex.shared.search(question, limit: 3) where !ids.contains(hit.id) { ids.append(hit.id) }
        }
        let parts = ids.prefix(3).compactMap { id -> String? in
            guard let lesson = LessonAssistantIndex.byID[id] else { return nil }
            let sections = lesson.sections.prefix(3).map { $0.title + ": " + $0.text }.joined(separator: "\n")
            return "• " + lesson.title + "\n" + lesson.introduction + "\n" + sections + "\nPërmbledhje: " + lesson.recap.joined(separator: " ")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    /// Pyetja me zë: dërgohet te Bosko AI online, që e kupton shqipen e folur.
    private func sendVoice(_ audio: Data) {
        guard !thinking, let id = currentID else { return }
        append([ChatLine(fromStudent: true, reply: TutorReply(text: "🎤 Pyetje me zë"))], to: id)
        let history = conversations.first(where: { $0.id == id })?.lines ?? []
        waitingIDs.insert(id)
        Task { @MainActor in
            do {
                let answer = try await BoskoOnline.ask(history: history, image: nil, role: role, lesson: lessonContext(conversations.first(where: { $0.id == id }), question: ""),
                                                       audio: audio, mode: hintMode ? "hints" : nil)
                append([ChatLine(fromStudent: false, reply: TutorReply(text: answer, suggestions: ["Shpjegoje më thjesht", "Më jep një shembull"]), online: true)], to: id)
            } catch {
                let reason = (error as? LocalizedError)?.errorDescription ?? "Nuk ka lidhje me internetin."
                append([ChatLine(fromStudent: false, reply: TutorReply(title: "Pyetja me zë nuk u dërgua", text: reason + "\n\nPyetjet me zë i kupton vetëm Bosko AI me internet. Provo përsëri ose shkruaje pyetjen."))], to: id)
            }
            waitingIDs.remove(id)
        }
    }

    private func send(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let image = pendingImage
        guard !thinking, !clean.isEmpty || image != nil, let id = currentID else { return }
        draft = ""; pendingImage = nil
        let imageName = image.flatMap { ChatHistory.saveImage($0) }
        append([ChatLine(fromStudent: true, reply: TutorReply(text: clean), imageName: imageName)], to: id)

        // Ushtrimet e aplikacionit (dhe kontrolli i përgjigjeve) mbeten te asistenti lokal.
        if image == nil && !hintMode && tutor.prefersLocal(clean) {
            append([ChatLine(fromStudent: false, reply: tutor.reply(to: clean))], to: id)
            return
        }
        let history = conversations.first(where: { $0.id == id })?.lines ?? []
        let context = lessonContext(conversations.first(where: { $0.id == id }), question: clean)
        waitingIDs.insert(id)
        Task { @MainActor in
            do {
                let answer = try await BoskoOnline.ask(history: history, image: image, role: role, lesson: context, mode: hintMode ? "hints" : nil)
                append([ChatLine(fromStudent: false, reply: TutorReply(text: answer, suggestions: ["Shpjegoje më thjesht", "Më jep një shembull", "Më jep një ushtrim"]), online: true)], to: id)
            } catch {
                let reason = (error as? LocalizedError)?.errorDescription ?? "Nuk ka lidhje me internetin."
                if image != nil || clean.isEmpty {
                    append([ChatLine(fromStudent: false, reply: TutorReply(title: "Fotoja nuk u dërgua",
                        text: reason + "\n\nFotot i kupton vetëm Bosko AI me internet. Provo përsëri pas pak, ose shkruaje ushtrimin këtu."))], to: id)
                } else {
                    var local = tutor.reply(to: clean)
                    local.text = "(Pa internet tani: " + reason + " Po të përgjigjem nga mësimet e aplikacionit.)\n\n" + local.text
                    append([ChatLine(fromStudent: false, reply: local)], to: id)
                }
            }
            waitingIDs.remove(id)
        }
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
                        HStack {
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
                            Button { delete(conversation) } label: { Image(systemName: "trash").font(.caption) }
                                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Fshi bisedën")
                        }
                        .listRowBackground(conversation.id == currentID ? Color.lagoon.opacity(0.14) : Color.clear)
                        // Rrëshqit majtas ose mbaj shtypur bisedën për ta fshirë.
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { delete(conversation) } label: { Label("Fshi", systemImage: "trash") }
                        }
                        .contextMenu {
                            Button { choose(conversation) } label: { Label("Hap bisedën", systemImage: "bubble.left") }
                            Button(role: .destructive) { delete(conversation) } label: { Label("Fshi bisedën", systemImage: "trash") }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color.paper)
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
    func makeCoordinator() -> Coordinator { Coordinator(done: done, close: close) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (Data) -> Void
        let close: () -> Void
        init(done: @escaping (Data) -> Void, close: @escaping () -> Void) { self.done = done; self.close = close }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) { done(data) }
            close()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { close() }
    }
}
#endif

private struct ChatIntro: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(LessonTutor.name + " · asistenti i mësimeve", systemImage: "sparkles").font(.title2.bold())
            Text("Pyet çfarë të duash për mësimet, ose dërgo foton e ushtrimit 📷 (me ose pa pyetje). Me internet përgjigjet Bosko AI online; pa internet të ndihmon nga mësimet e aplikacionit. Bisedat ruhen në këtë pajisje.")
                .font(.footnote).foregroundStyle(.secondary)
            NavigationLink("Kërko temat si listë") { LessonAssistant() }.font(.footnote)
        }
    }
}

private struct ChatBubble: View {
    let line: ChatLine
    @EnvironmentObject private var reader: SpeechReader
    private var formatted: AttributedString {
        (try? AttributedString(markdown: line.reply.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(line.reply.text)
    }
    var body: some View {
        HStack {
            if line.fromStudent { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 8) {
                if let name = line.imageName, let url = ChatHistory.imageURL(name), let data = try? Data(contentsOf: url),
                   let image = ChatImage.cgImage(data) {
                    Image(decorative: image, scale: 1).resizable().scaledToFit()
                        .frame(maxWidth: 260, maxHeight: 260).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                if let title = line.reply.title { Text(title).font(.headline) }
                if !line.reply.text.isEmpty { Text(formatted).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                if !line.fromStudent, let id = line.reply.lessonID, let lesson = LessonAssistantIndex.byID[id] {
                    NavigationLink { StudyReader(lesson: lesson) } label: {
                        Label("Burimi: " + lesson.title, systemImage: "book").font(.caption.bold())
                    }.buttonStyle(.plain).foregroundStyle(Color.lagoon)
                }
                if !line.fromStudent && !line.reply.text.isEmpty {
                    Button { reader.toggle(line.reply.text, id: line.id) } label: {
                        Label(reader.speakingID == line.id ? "Ndalo leximin" : "Lexoje me zë", systemImage: reader.speakingID == line.id ? "stop.fill" : "speaker.wave.2")
                            .font(.caption)
                    }.buttonStyle(.plain).foregroundStyle(Color.lagoon)
                }
                if line.online == true {
                    Label("Bosko AI online · kontrolloje me mësuesin kur ke dyshime", systemImage: "sparkles").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .foregroundStyle(line.fromStudent ? Color.white : Color.ink)
            .background(line.fromStudent ? Color.lagoon : Color.card, in: RoundedRectangle(cornerRadius: 16))
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
