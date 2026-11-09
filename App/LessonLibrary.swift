import SwiftUI

struct StudySection: Decodable {
    let title, text: String
}
struct WorkedExample: Decodable {
    let problem: String
    let steps: [String]
    let conclusion: String
}
struct StudyCheck: Decodable {
    let prompt: String
    let options: [String]
    let correct: Int
    let why: String
    var question: Question { Question(prompt, options, correct, why) }
}
struct StudyLesson: Decodable, Identifiable {
    let id, subject, title, introduction: String
    let level, order, chapterOrder: Int
    let chapterID, chapterTitle: String
    let objectives: [String]
    let chapterIntroduction: String
    let diagram: StudyDiagram
    let sections: [StudySection]
    let example: WorkedExample
    let pitfall: String
    let recap: [String]
    let check: StudyCheck
    let exerciseIDs: [String]
    var schoolSubject: Subject { Subject(rawValue: subject) ?? .math }
    var schoolLevel: SchoolLevel { SchoolLevel(rawValue: level) ?? .basic }
    var readingMinutes: Int {
        let words = ([introduction, example.problem, example.conclusion, pitfall] + sections.map(\.text) + example.steps + recap)
            .joined(separator: " ").split(whereSeparator: { $0.isWhitespace }).count
        return max(3, Int(ceil(Double(words) / 130)))
    }
    var searchableText: String {
        ([title, chapterTitle, introduction] + sections.map(\.title) + sections.map(\.text)).joined(separator: " ")
    }
    static let all: [StudyLesson] = {
        guard let url = Bundle.main.url(forResource: "Lessons", withExtension: "json"),
              let bytes = try? Data(contentsOf: url),
              let content = try? JSONDecoder().decode([StudyLesson].self, from: bytes) else { return [] }
        return content.sorted { $0.id < $1.id }
    }()
    static func matching(subject: Subject? = nil, level: SchoolLevel? = nil) -> [StudyLesson] {
        all.filter { (subject == nil || $0.subject == subject?.rawValue) && (level == nil || $0.level == level?.rawValue) }
            .sorted { $0.order < $1.order }
    }
}

private enum ReadingFilter: String, CaseIterable {
    case all = "Të gjitha", saved = "Të ruajtura", unread = "Pa lexuar"
}

struct StudyLibrary: View {
    let subject: Subject
    @Environment(\.learnerLevel) private var learnerLevel
    @State private var level = SchoolLevel.basic
    @State private var query = ""
    @State private var filter = ReadingFilter.all
    @AppStorage("studyReadIDs.v1") private var readIDs = ""
    @AppStorage("studyBookmarks.v1") private var bookmarks = ""
    @AppStorage("studyLastID.v1") private var lastID = ""
    private var chosenLevel: SchoolLevel { learnerLevel ?? level }
    private var pool: [StudyLesson] { StudyLesson.matching(subject: subject, level: chosenLevel) }
    private var visible: [StudyLesson] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return pool.filter { lesson in
            (search.isEmpty || lesson.searchableText.range(of: search, options: [.caseInsensitive, .diacriticInsensitive]) != nil)
            && (filter != .saved || contains(bookmarks, lesson.id))
            && (filter != .unread || !contains(readIDs, lesson.id))
        }
    }
    private var chapters: [StudyLesson] {
        pool.filter { $0.order % 5 == 1 }.sorted { $0.chapterOrder < $1.chapterOrder }
    }
    var body: some View {
        Page {
            VStack(alignment: .leading, spacing: 10) {
                Label(subject.rawValue, systemImage: subject.icon).foregroundStyle(subject.color).font(.headline)
                Text("Mëso hap pas hapi").font(.largeTitle.bold())
                if let learnerLevel {
                    Text(learnerLevel.name).font(.title3.bold())
                    Text("Temat ndjekin klasën tënde. Nivelin mund ta ndryshosh te këndi i nxënësit.").font(.footnote)
                } else { LevelPicker(level: $level) }
                Text("6 kapituj · 30 mësime në këtë nivel. Hap kapitullin dhe zgjidh temën që të duhet.")
                let read = pool.filter { contains(readIDs, $0.id) }.count
                ProgressView(value: Double(read), total: Double(max(1, pool.count))) {
                    Text("\(read)/\(pool.count) tema të shënuara si të lexuara")
                }.tint(subject.color)
            }
            if let last = pool.first(where: { $0.id == lastID }) {
                NavigationLink { StudyReader(lesson: last) } label: {
                    Tile(icon: "book.fill", title: "Rihap temën e fundit", detail: last.title)
                }
            }
            TextField("Kërko një temë ose fjalë në këtë nivel", text: $query).textFieldStyle(.roundedBorder)
            Picker("Shfaq", selection: $filter) {
                ForEach(ReadingFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            if StudyLesson.all.isEmpty {
                Text("Mësimet nuk u ngarkuan. Kontrollo që Lessons.json të jetë pjesë e projektit.")
            } else if visible.isEmpty {
                Text("Nuk ka tema që përputhen me kërkimin dhe filtrin. Provo një fjalë tjetër ose zgjidh Të gjitha.")
            }
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && filter == .all {
                ForEach(chapters) { chapter in
                    let topics = pool.filter { $0.chapterID == chapter.chapterID }
                    let completed = topics.filter { contains(readIDs, $0.id) }.count
                    NavigationLink {
                        StudyChapter(subject: subject, level: chosenLevel, chapterID: chapter.chapterID)
                    } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("KAPITULLI \(chapter.chapterOrder)").font(.caption.bold()).tracking(1)
                                Spacer()
                                Image(systemName: "arrow.right.circle.fill").font(.title2)
                            }.foregroundStyle(subject.color)
                            Text(chapter.chapterTitle).font(.title2.bold())
                            Text(topics.map(\.title).joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
                            ProgressView(value: Double(completed), total: Double(topics.count)) {
                                Text("\(completed)/\(topics.count) mësime të lexuara").font(.caption)
                            }.tint(subject.color)
                        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(alignment: .leading) { Capsule().fill(subject.color).frame(width: 4).padding(.vertical, 18) }
                    }
                }
            } else {
                ForEach(visible) { lesson in
                    NavigationLink { StudyReader(lesson: lesson) } label: {
                        Tile(icon: contains(readIDs, lesson.id) ? "checkmark.circle.fill" : "book.closed",
                             title: lesson.title, detail: lesson.chapterTitle + " · \(lesson.readingMinutes) min")
                    }
                }
            }
            let refreshers = lessons.filter { $0.subject == subject && $0.level == chosenLevel }
            if !refreshers.isEmpty {
                DisclosureGroup("Rikujtime të shkurtra · \(refreshers.count)") {
                    ForEach(refreshers) { lesson in
                        NavigationLink { LessonDetail(lesson: lesson) } label: {
                            Tile(icon: "lightbulb", title: lesson.title, detail: "Përmbledhja e versionit të mëparshëm")
                        }
                    }
                }
            }
        }.navigationTitle("Mësime").buttonStyle(.plain)
    }
    private func contains(_ list: String, _ id: String) -> Bool { list.split(separator: "|").contains(Substring(id)) }
}

struct StudyChapter: View {
    let subject: Subject
    let level: SchoolLevel
    let chapterID: String
    @AppStorage("studyReadIDs.v1") private var readIDs = ""
    private var pool: [StudyLesson] {
        StudyLesson.matching(subject: subject, level: level).filter { $0.chapterID == chapterID }
    }
    var body: some View {
        Page {
            Text(subject.rawValue + " · " + level.name).font(.caption.bold()).foregroundStyle(subject.color)
            Text(pool.first?.chapterTitle ?? "Kapitulli").font(.largeTitle.bold())
            Text("Pesë tema me shpjegime, shembuj të zgjidhur dhe vetëkontroll. Shënimet dhe temat e lexuara ruhen në llogarinë tënde.")
            if let overview = pool.first?.chapterIntroduction { SectionText(heading:"Hyrje në kapitull",text:overview) }
            ForEach(pool) { lesson in
                NavigationLink { StudyReader(lesson: lesson) } label: {
                    Tile(icon: readIDs.split(separator: "|").contains(Substring(lesson.id)) ? "checkmark.circle.fill" : "book.closed",
                         title: lesson.title, detail: "\(lesson.readingMinutes) min · Shembull · Pyetje kontrolli")
                }
            }
        }.buttonStyle(.plain).navigationTitle("Kapitulli")
    }
}

struct StudySubjects: View {
    var body: some View {
        Page {
            Text("Biblioteka e mësimeve").font(.largeTitle.bold())
            Text("Zgjidh lëndën, pastaj kapitullin. Nxënësi sheh nivelin e profilit; mësuesi dhe prindi mund të shfletojnë pesë nivelet.")
            ForEach(Subject.allCases) { subject in
                NavigationLink { StudyLibrary(subject: subject) } label: {
                    Tile(icon: subject.icon, title: subject.rawValue, detail: "150 mësime · 30 kapituj · 5 nivele")
                }
            }
        }.buttonStyle(.plain).navigationTitle("Mësimet")
    }
}

struct StudyReader: View {
    let lesson: StudyLesson
    @AppStorage("studyReadIDs.v1") private var readIDs = ""
    @AppStorage("studyBookmarks.v1") private var bookmarks = ""
    @AppStorage("studyLastID.v1") private var lastID = ""
    @AppStorage("studyPassedIDs.v1") private var passedIDs = ""
    @AppStorage("studyReadingSize.v1") private var textSize = 17.0
    @AppStorage private var notes: String
    @State private var choice: Int?
    init(lesson: StudyLesson) {
        self.lesson = lesson
        _notes = AppStorage(wrappedValue: "", "studyNotes." + lesson.id)
    }
    private var bookmarked: Bool { includes(bookmarks) }
    private var read: Bool { includes(readIDs) }
    private var next: StudyLesson? {
        StudyLesson.matching(subject: lesson.schoolSubject, level: lesson.schoolLevel).first { $0.order > lesson.order }
    }
    var body: some View {
        ScrollViewReader { proxy in
            Page {
                header.id(0)
                HStack {
                    Label("Madhësia e shkrimit", systemImage: "textformat.size")
                    Spacer()
                    Button("A−") { textSize = max(15, textSize - 2) }.accessibilityLabel("Zvogëlo shkrimin")
                    Button("A+") { textSize = min(25, textSize + 2) }.accessibilityLabel("Zmadho shkrimin")
                }.buttonStyle(.bordered)
                DisclosureGroup("Përmbajtja e mësimit") {
                    VStack(alignment: .leading, spacing: 12) {
                        Button("Hyrja dhe synimet") { jump(0, proxy) }
                        ForEach(lesson.sections.indices, id: \.self) { i in
                            Button(lesson.sections[i].title) { jump(i + 1, proxy) }
                        }
                        Button("Shembulli i zgjidhur") { jump(100, proxy) }
                        Button("Përmbledhje dhe vetëkontroll") { jump(200, proxy) }
                    }
                }
                NavigationLink { TutorChat(startingLesson: lesson) } label: {
                    Label("Bisedo me asistentin për këtë temë", systemImage: "bubble.left.and.bubble.right")
                }.buttonStyle(.bordered)
                introduction
                LessonDiagramView(lesson:lesson)
                ForEach(lesson.sections.indices, id: \.self) { index in
                    readingSection(lesson.sections[index]).id(index + 1)
                }
                workedExample.id(100)
                review.id(200)
                practiceLinks
                notesSection
                footer
            }.onAppear {
                lastID = lesson.id

            }
        }.navigationTitle(lesson.title).id(lesson.id)
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(lesson.subject + " · " + lesson.schoolLevel.name).font(.caption.bold()).foregroundStyle(lesson.schoolSubject.color)
            Text(lesson.title).font(.largeTitle.bold())
            Text(lesson.chapterTitle + " · \(lesson.readingMinutes) min lexim").font(.subheadline)
            Button {
                bookmarks = toggling(bookmarks)
            } label: {
                Label(bookmarked ? "Hiqe nga të ruajturat" : "Ruaje për më vonë", systemImage: bookmarked ? "bookmark.fill" : "bookmark")
            }.buttonStyle(.bordered)
        }
    }
    private var introduction: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(lesson.introduction).font(.system(size: textSize)).lineSpacing(6)
            Text("Pas këtij mësimi do të mundesh:").font(.headline)
            ForEach(lesson.objectives, id: \.self) { Text("• " + $0).font(.system(size: textSize)) }
        }.textSelection(.enabled)
    }
    private func readingSection(_ section: StudySection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title).font(.title2.bold()).foregroundStyle(lesson.schoolSubject.color)
            Text(section.text).font(.system(size: textSize)).lineSpacing(7).fixedSize(horizontal: false, vertical: true)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16)).textSelection(.enabled)
    }
    private var workedExample: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("Shembull i zgjidhur hap pas hapi", systemImage: "pencil.and.outline").font(.title2.bold())
            Text(lesson.example.problem).font(.system(size: textSize, weight: .semibold))
            ForEach(lesson.example.steps.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(i+1)").bold().frame(width: 30, height: 30)
                        .background(lesson.schoolSubject.color.opacity(0.12), in: Circle())
                    Text(lesson.example.steps[i]).font(.system(size: textSize)).lineSpacing(6)
                }
            }
            Text(lesson.example.conclusion).font(.system(size: textSize, weight: .semibold))
        }.padding(18).background(lesson.schoolSubject.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        .textSelection(.enabled)
    }
    private var review: some View {
        VStack(alignment: .leading, spacing: 18) {
            readingSection(StudySection(title: "Gabimi që duhet shmangur", text: lesson.pitfall))
            Text("Mbaje mend").font(.title2.bold())
            ForEach(lesson.recap, id: \.self) { Text("• " + $0).font(.system(size: textSize)).lineSpacing(5) }
            Divider()
            Text("Kontrollo kuptimin").font(.title2.bold())
            Answers(question: lesson.check.question, selection: choice) { selected in
                choice = selected
                if selected == lesson.check.correct { passedIDs = inserting(passedIDs) }
            }
            if choice != nil {
                Button("Provoje pyetjen përsëri") { choice = nil }.buttonStyle(.bordered)
            } else if includes(passedIDs) {
                Text("Këtë pyetje e ke zgjidhur saktë më parë.").font(.caption)
            }
        }
    }
    private var practiceLinks: some View {
        VStack(alignment: .leading, spacing: 12) {
            let matching = lesson.exerciseIDs.compactMap { id in Exercise.all.first { $0.id == id && $0.level == lesson.level && $0.subject == lesson.subject } }
            if !matching.isEmpty {
                Text("Ushtrohu në këtë nivel").font(.title2.bold())
                ForEach(matching) { exercise in
                    NavigationLink { ExercisePlayer(item: exercise) } label: {
                        Tile(icon: "pencil", title: exercise.prompt, detail: exercise.id)
                    }
                }
            }
            NavigationLink { SubjectQuiz(subject: lesson.schoolSubject, level: lesson.schoolLevel) } label: {
                Tile(icon: "bolt", title: "Kuizi i lëndës për këtë nivel", detail: lesson.schoolLevel.name)
            }
        }.buttonStyle(.plain)
    }
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shënimet e mia").font(.title2.bold())
            Text("Shpjegoje idenë me fjalët e tua ose shëno çfarë do të pyesësh në klasë.").font(.callout)
            TextEditor(text: $notes).frame(minHeight: 140).font(.system(size: textSize)).padding(6)
                .background(.white, in: RoundedRectangle(cornerRadius: 12)).accessibilityLabel("Shënimet për " + lesson.title)
            Text("Ruhen automatikisht në këtë llogari.").font(.caption)
        }
    }
    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(read ? "Shënoje si të palexuar" : "E lexova këtë mësim") { readIDs = toggling(readIDs) }
                .buttonStyle(.borderedProminent)
            if let next {
                NavigationLink { StudyReader(lesson: next) } label: {
                    Tile(icon: "arrow.right.circle", title: "Tema pasuese", detail: next.title)
                }.buttonStyle(.plain)
            }
        }
    }
    private func includes(_ value: String) -> Bool { value.split(separator: "|").contains(Substring(lesson.id)) }
    private func inserting(_ value: String) -> String {
        var ids = Set(value.split(separator: "|").map(String.init)); ids.insert(lesson.id)
        return ids.sorted().joined(separator: "|")
    }
    private func toggling(_ value: String) -> String {
        var ids = Set(value.split(separator: "|").map(String.init))
        if ids.contains(lesson.id) { ids.remove(lesson.id) } else { ids.insert(lesson.id) }
        return ids.sorted().joined(separator: "|")
    }
    private func jump(_ section: Int, _ proxy: ScrollViewProxy) {
        withAnimation { proxy.scrollTo(section, anchor: .top) }
    }
}
