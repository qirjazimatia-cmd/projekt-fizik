import SwiftUI

@main
struct ScienceQuestApp: App {
    @StateObject private var account = Account()
    var body: some Scene {
        WindowGroup {
            Group {
                if let role = account.role {
                    Dashboard(role: role).defaultAppStorage(account.storage).id(account.identity)
                } else { AccessScreen() }
            }.environmentObject(account).preferredColorScheme(.light)
            .task { await account.restore() }
            .task(id:account.identity) {
                guard account.isOnline else { return }
                while !Task.isCancelled {
                    do { try await Task.sleep(nanoseconds:30_000_000_000) } catch { return }
                    await account.synchronize()
                }
            }
            .sheet(isPresented:Binding(get:{ !account.recoveryNotice.isEmpty },set:{ if !$0 { account.recoveryNotice = "" } })) {
                Page {
                    Text("Ruaj kodin personal të rikuperimit").font(.title.bold())
                    Text("Ky kod ndryshon fjalëkalimin kur e harron. Mbaje privat dhe ruaje jashtë aplikacionit. Nuk është kod 2FA dhe nuk kërkohet në hyrjet e zakonshme.")
                    Text(account.recoveryNotice).font(.headline.monospaced()).textSelection(.enabled)
                    ShareLink(item:"ScienceQuest · " + account.email + "\nKodi privat i rikuperimit: " + account.recoveryNotice) { Text("Ruaj kodin") }
                    Button("E ruajta kodin") { account.recoveryNotice = "" }.buttonStyle(.borderedProminent)
                }.interactiveDismissDisabled()
            }
        }
    }
}

extension Color {
    static let midnight = Color(red: 0.08, green: 0.07, blue: 0.19)
    static let sun = Color(red: 1.0, green: 0.84, blue: 0.27)
    static let lagoon = Color(red: 0.32, green: 0.22, blue: 0.74)
    static let paper = Color(red: 0.95, green: 0.94, blue: 0.99)
}

struct Page<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) { content }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(20).frame(maxWidth: .infinity)
        }
        .background(Color.paper).foregroundStyle(Color.black.opacity(0.86))
    }
}

struct Tile: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon).font(.headline).foregroundStyle(.white)
                .frame(width: 48, height: 48).background(Color.lagoon, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
        }
        .padding(15).background(.white, in: RoundedRectangle(cornerRadius: 18)).contentShape(Rectangle())
    }
}

struct QuestCover: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: -6) {
                Text("SCIENCE").foregroundStyle(.white)
                Text("QUEST").foregroundStyle(Color.sun)
            }.font(.system(size: 40, weight: .black, design: .rounded))
            Spacer(minLength: 4)
            Canvas { context, size in
                let box = CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8)
                context.stroke(Path(ellipseIn: box), with: .color(.white), lineWidth: 2)
                let center = CGPoint(x: box.midX, y: box.midY)
                for i in 0..<8 {
                    let a = Double(i) * .pi / 4
                    var spoke = Path()
                    spoke.move(to: center)
                    spoke.addLine(to: CGPoint(x: center.x + cos(a) * box.width / 2, y: center.y + sin(a) * box.height / 2))
                    context.stroke(spoke, with: .color(.white.opacity(0.45)), lineWidth: 1)
                }
                context.fill(Path(ellipseIn: CGRect(x: box.midX - 13, y: box.minY, width: 26, height: 26)), with: .color(.sun))
                context.fill(Path(ellipseIn: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)), with: .color(.pink))
            }.frame(maxWidth: 110, maxHeight: 100).accessibilityHidden(true)
        }.padding(20).frame(maxWidth: .infinity, minHeight: 124)
        .background(LinearGradient(colors: [.midnight, Color(red: 0.26, green: 0.17, blue: 0.63)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore).accessibilityLabel("Science Quest")
    }
}

struct HomePage: View {
    let role: SchoolRole
    let open: (Subject) -> Void
    @AppStorage("studyReadIDs.v1") private var readIDs = ""
    @AppStorage("studyLastID.v1") private var lastID = ""
    @Environment(\.learnerLevel) private var learnerLevel
    var body: some View {
        Page {
            QuestCover()
            Text("Versioni i fundit · Klasa dhe vlerësim 7.0").font(.caption.bold()).foregroundStyle(Color.lagoon)
            Text("Zgjidh lëndën").font(.system(.title, design: .rounded).weight(.black))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 12) {
                ForEach([Subject.math, .physics, .chemistry, .biology]) { subject in
                    Button { open(subject) } label: {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack { Image(systemName: subject.icon).font(.title); Spacer(); Image(systemName: "arrow.up.right") }
                            Text(subject.rawValue).font(.title2.bold())
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.white).background(subject.color, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            let readingPool = StudyLesson.all.filter { learnerLevel == nil || $0.level == learnerLevel?.rawValue }
            let count = readingPool.filter { readIDs.split(separator: "|").contains(Substring($0.id)) }.count
            ProgressView(value: Double(count), total: Double(max(1, readingPool.count))) {
                Text("Mësime të lexuara · \(count)/\(readingPool.count)").font(.subheadline.bold())
            }
            if let last = readingPool.first(where: { $0.id == lastID }) {
                NavigationLink { StudyReader(lesson: last) } label: {
                    Tile(icon: "bookmark.fill", title: "Rihap temën e fundit", detail: last.title)
                }
            }
            Group {
                NavigationLink { StudySubjects() } label: { Tile(icon: "books.vertical.fill", title: "Mësime sipas kapitujve", detail: "600 mësime · 120 kapituj · Pesë nivele") }
                NavigationLink { RoleDesk(role: role) } label: { Tile(icon: "person.fill", title: role.title, detail: "Detyrat dhe aktivitetet e profilit") }
                NavigationLink { PracticeMenu() } label: { Tile(icon: "magnifyingglass", title: role == .student ? "Ushtrimet e mia" : "Gjej detyrën", detail: role == .student ? "Ushtrime dhe detyra për klasën time" : "Kërko ushtrimin me kodin e mësuesit") }
                NavigationLink { Lab() } label: { Tile(icon: "slider.horizontal.3", title: "Eksperimento", detail: "43 simulime, përzierje të lira, lojëra dhe prova praktike") }
                NavigationLink { Discover() } label: { Tile(icon: "sparkles", title: "Zbulo", detail: "Pse ndodh kjo?") }
                NavigationLink { Arcade() } label: { Tile(icon: "gamecontroller.fill", title: "Luaj", detail: "Science Battle dhe Science Escape Room") }
                AccountControls()
            }
        }.buttonStyle(.plain)
    }
}

struct SectionText: View {
    let heading: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading).font(.headline).foregroundStyle(Color.lagoon)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct Answers: View {
    let question: Question
    let selection: Int?
    let choose: (Int) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(question.prompt).font(.title3.bold())
            ForEach(question.options.indices, id: \.self) { index in
                Button { choose(index) } label: {
                    HStack {
                        Text(question.options[index])
                        Spacer()
                        if selection == index {
                            Image(systemName: index == question.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                        }
                    }.padding().background(.white, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).disabled(selection != nil)
            }
            if let selection {
                SectionText(heading: selection == question.correct ? "Saktë!" : "Përgjigjja: \(question.options[question.correct])", text: question.why)
            }
        }
    }
}

struct LessonDetail: View {
    let lesson: Lesson
    @State private var choice: Int?
    @AppStorage("solvedTopics") private var solved = ""
    var body: some View {
        Page {
            Text(lesson.title).font(.largeTitle.bold())
            Text(lesson.explanation)
            SectionText(heading: "Në jetën e përditshme", text: lesson.example)
            Divider()
            Answers(question: lesson.question, selection: choice) { index in
                choice = index
                if index == lesson.question.correct && !solved.components(separatedBy: "|").contains(lesson.id) {
                    solved += "|" + lesson.id
                }
            }
            if let choice, choice != lesson.question.correct {
                Button("Provo përsëri") { self.choice = nil }.buttonStyle(.bordered)
            }
        }.navigationTitle(lesson.subject.rawValue)
    }
}

struct Discover: View {
    var body: some View {
        Page {
            ForEach(discoveries.indices, id: \.self) { index in
                let item = discoveries[index]
                DisclosureGroup {
                    Text(item.2).padding(.top, 8).frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(item.0.rawValue, systemImage: item.0.icon).font(.caption.bold()).foregroundStyle(Color.lagoon)
                        Text(item.1).font(.headline)
                    }
                }.padding().background(.white, in: RoundedRectangle(cornerRadius: 15))
            }
        }.navigationTitle("Zbulo")
    }
}

struct Lab: View {
    @State private var subject = Subject.chemistry
    @State private var section = 0
    var body: some View {
        Page {
            Text("Laboratori i lirë").font(.largeTitle.bold())
            Text("Ndrysho kushtet, provo ide dhe ruaj vëzhgimet.")
            Picker("Lënda", selection: $subject) {
                ForEach(Subject.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.menu)
            Picker("Përmbajtja", selection: $section) {
                Text("Simulime").tag(0)
                Text("Lojëra").tag(1)
                Text("Prova praktike").tag(2)
            }.pickerStyle(.segmented)
            if section == 0 {
                LabExperiments(subject: subject)
                if subject == .physics {
                    NavigationLink { SpringLaboratory() } label: {
                        Tile(icon: "arrow.up.and.down", title: "Punishtja e sustave", detail: "7 eksperimente · Masa, ngurtësia dhe energjia")
                    }
                    NavigationLink { MotionLab() } label: {
                        Tile(icon:"bicycle",title:"Laboratori i lëvizjes",detail:"Ndërto grafikun rrugë–kohë")
                    }
                }
            } else if section == 1 {
                LabGameLinks(subject:subject)
            } else {
                ForEach(activities.filter { $0.subject == subject }) { activity in
                    NavigationLink { PracticalActivityView(activity:activity) } label: {
                        Tile(icon:subject.icon,title:activity.title,detail:"Hapa, matje dhe fletore vëzhgimesh")
                    }
                }
            }
        }.buttonStyle(.plain).navigationTitle("Laboratori")
    }
}

struct MotionLab: View {
    @State private var speed = 3.0
    @State private var time = 5.0
    var body: some View {
        Page {
            Text("Sa larg arrin biçikleta?").font(.largeTitle.bold())
            Text("Modeli nis nga 0 m dhe ruan shpejtësi konstante. Ndrysho kohën ose shpejtësinë dhe ndiq pikën në grafik.")
            Text("Shpejtësia: \(Int(speed)) m/s").font(.headline)
            Slider(value: $speed, in: 1...10, step: 1).accessibilityLabel("Shpejtësia në metra për sekondë")
            Text("Koha: \(Int(time)) s").font(.headline)
            Slider(value: $time, in: 1...10, step: 1).accessibilityLabel("Koha në sekonda")
            Text("Rruga = \(Int(speed)) × \(Int(time)) = \(Int(speed * time)) m").font(.title2.bold())
            VStack(alignment: .leading) {
                Text("Rruga (m)").font(.caption.bold())
                HStack(spacing: 5) {
                    VStack { Text("100"); Spacer(); Text("50"); Spacer(); Text("0") }.font(.caption.monospacedDigit())
                    Canvas { context, size in
                        for tick in 0...4 {
                            let fraction = CGFloat(tick) / 4
                            var grid = Path()
                            grid.move(to: CGPoint(x: 0, y: size.height * fraction))
                            grid.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                            grid.move(to: CGPoint(x: size.width * fraction, y: 0))
                            grid.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
                            context.stroke(grid, with: .color(.gray.opacity(0.35)))
                        }
                        let end = CGPoint(x: size.width * time / 10, y: size.height * (1 - speed * time / 100))
                        var line = Path()
                        line.move(to: CGPoint(x: 0, y: size.height))
                        line.addLine(to: end)
                        context.stroke(line, with: .color(.lagoon), lineWidth: 4)
                        context.fill(Path(ellipseIn: CGRect(x: end.x - 5, y: end.y - 5, width: 10, height: 10)), with: .color(.lagoon))
                    }
                }.frame(height: 170)
                HStack { Text("0"); Spacer(); Text("5"); Spacer(); Text("10 s") }.font(.caption).padding(.leading, 26)
            }.padding().background(.white, in: RoundedRectangle(cornerRadius: 16))
            SectionText(heading: "Sfida", text: "Gjej dy mënyra për të përshkuar 24 m. Cila vijë ka pjerrësi më të madhe?")
        }.navigationTitle("Simulimi")
    }
}
