import SwiftUI
import AVFoundation

// MARK: - Leximi me zë (në pajisje, falas)

/// Lexon me zë përgjigjet e Bosko AI. Përdor zërin shqip nëse pajisja e ka; përndryshe zërin e parazgjedhur.
@MainActor
final class SpeechReader: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var speakingID: UUID?
    private let synthesizer = AVSpeechSynthesizer()

    override init() { super.init(); synthesizer.delegate = self }

    static var albanianVoice: AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix("sq") }
    }

    func toggle(_ text: String, id: UUID) {
        if speakingID == id { stop(); return }
        stop()
        let clean = text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "·", with: ",")
        let utterance = AVSpeechUtterance(string: clean)
        utterance.voice = Self.albanianVoice ?? AVSpeechSynthesisVoice(language: "sq-AL") ?? AVSpeechSynthesisVoice(language: "it-IT")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        speakingID = id
        synthesizer.speak(utterance)
    }
    func stop() { synthesizer.stopSpeaking(at: .immediate); speakingID = nil }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speakingID = nil }
    }
}

// MARK: - Pyetje me zë

/// Regjistron pyetjen me zë (m4a). Bosko AI online e kupton zërin në shqip dhe përgjigjet.
@MainActor
final class VoiceRecorder: ObservableObject {
    @Published private(set) var recording = false
    @Published var message = ""
    private var recorder: AVAudioRecorder?
    private var url: URL { FileManager.default.temporaryDirectory.appendingPathComponent("bosko-pyetja.m4a") }

    func start() async {
        guard await Self.permission() else { message = "Lejo mikrofonin te Cilësimet që të pyesësh me zë."; return }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let settings: [String: Any] = [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1,
                                       AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue]
        do {
            try? FileManager.default.removeItem(at: url)
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.record(forDuration: 60)
            recording = true; message = ""
        } catch { message = "Mikrofoni nuk u hap: " + error.localizedDescription }
    }

    /// Ndalon dhe kthen zërin (ose nil nëse ishte shumë i shkurtër).
    func stop() -> Data? {
        guard let recorder else { return nil }
        let duration = recorder.currentTime
        recorder.stop(); self.recorder = nil; recording = false
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        guard duration > 0.6, let data = try? Data(contentsOf: url) else { message = "Mbaje pak më gjatë dhe fol qartë."; return nil }
        return data
    }

    static func permission() async -> Bool {
        #if os(iOS)
        if #available(iOS 17.0, *) { return await AVAudioApplication.requestRecordPermission() }
        return await withCheckedContinuation { c in AVAudioSession.sharedInstance().requestRecordPermission { c.resume(returning: $0) } }
        #else
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
        #endif
    }
}

// MARK: - Test prove nga kapitujt

/// Nxënësi zgjedh lëndën dhe kapitujt; testi ndërtohet nga ushtrimet e atyre kapitujve (pa internet).
struct MockTestView: View {
    @Environment(\.learnerLevel) private var learnerLevel
    @State private var subject = Subject.physics
    @State private var chosen: Set<String> = []
    @State private var count = 10
    @State private var items: [Exercise] = []
    @State private var index = 0
    @State private var correct = 0
    @State private var wrong: [Exercise] = []
    @State private var started = false

    private var level: Int { learnerLevel?.rawValue ?? 1 }
    private var chapters: [(id: String, title: String)] {
        var seen = Set<String>(); var list: [(String, String)] = []
        for lesson in StudyLesson.all where lesson.subject == subject.rawValue && lesson.level == level && !seen.contains(lesson.chapterID) {
            seen.insert(lesson.chapterID); list.append((lesson.chapterID, lesson.chapterTitle))
        }
        return list.map { (id: $0.0, title: $0.1) }
    }

    var body: some View {
        if !started { setup } else if index < items.count {
            ExercisePlayer(item: items[index], advance: { right in
                if right { correct += 1 } else { wrong.append(items[index]) }
                withAnimation(.easeInOut) { index += 1 }
                if index == items.count && correct * 10 >= items.count * 8 { Haptics.celebrate() }
            }).id(items[index].id + "-\(index)")
            .safeAreaInset(edge: .top) {
                ProgressView(value: Double(index), total: Double(items.count)).padding(.horizontal).tint(subject.color)
            }
        } else { results }
    }

    private var setup: some View {
        Page {
            Text("Test prove").font(.largeTitle.bold())
            Text("Zgjidh lëndën dhe kapitujt. Testi merr ushtrime nga ato kapituj dhe në fund të tregon ku duhet të përsëritësh.").font(.callout)
            Picker("Lënda", selection: $subject) { ForEach(Subject.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented)
                .onChange(of: subject) { _ in chosen = [] }
            ForEach(chapters, id: \.id) { chapter in
                Toggle(chapter.title, isOn: Binding(get: { chosen.contains(chapter.id) },
                                                    set: { if $0 { chosen.insert(chapter.id) } else { chosen.remove(chapter.id) } }))
            }
            Stepper("Pyetje: \(count)", value: $count, in: 5...20, step: 5)
            Button("Fillo testin") { start() }.buttonStyle(.borderedProminent).disabled(chosen.isEmpty)
        }.navigationTitle("Test prove")
    }

    private var results: some View {
        Page {
            Text("Rezultati").font(.largeTitle.bold())
            Text("\(correct) nga \(items.count) të sakta").font(.title2.bold())
            ProgressView(value: Double(correct), total: Double(max(items.count, 1))).tint(correct * 2 >= items.count ? .green : .orange)
            Text(feedback).font(.callout)
            if !wrong.isEmpty {
                Text("Përsërit këto").font(.headline)
                ForEach(lessonsToReview, id: \.id) { lesson in
                    NavigationLink { StudyReader(lesson: lesson) } label: { Label(lesson.title, systemImage: "book") }
                }
            }
            Button("Test i ri") { started = false; index = 0; correct = 0; wrong = [] }.buttonStyle(.bordered)
        }.navigationTitle("Rezultati")
        .confetti(correct * 10 >= items.count * 8, colors: [subject.color, .sun, subject.deep, .white])
    }

    private var feedback: String {
        let ratio = Double(correct) / Double(max(items.count, 1))
        if ratio >= 0.9 { return "Shkëlqyeshëm! Je gati për testin." }
        if ratio >= 0.6 { return "Mirë! Përsërit mësimet më poshtë dhe provo përsëri." }
        return "Mos u shqetëso: lexo mësimet më poshtë, pastaj bëj një test të ri."
    }
    private var lessonsToReview: [StudyLesson] {
        let wrongIDs = Set(wrong.map(\.id))
        return StudyLesson.all.filter { lesson in !wrongIDs.isDisjoint(with: lesson.exerciseIDs) }
    }
    private func start() {
        let lessons = StudyLesson.all.filter { chosen.contains($0.chapterID) && $0.level == level }
        let ids = Set(lessons.flatMap(\.exerciseIDs))
        items = Array(Exercise.all.filter { ids.contains($0.id) }.shuffled().prefix(count))
        index = 0; correct = 0; wrong = []; started = !items.isEmpty
    }
}
