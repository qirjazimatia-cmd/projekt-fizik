import SwiftUI

@main
struct ScienceQuestApp: App {
    @StateObject private var account = Account()
    @AppStorage(AppAppearance.schemeKey) private var appearance = 0
    @AppStorage(AppAppearance.textSizeKey) private var textSize = 2
    @AppStorage(Onboarding.doneKey) private var onboardingDone = false
    @AppStorage(AppAccent.key) private var accent = 0
    var body: some Scene {
        WindowGroup {
            Group {
                if let role = account.role {
                    Dashboard(role: role).defaultAppStorage(account.storage).id("\(account.identity)|\(accent)")
                } else if account.restoring {
                    // Hapja e llogarisë së ruajtur: pa ekranin e hyrjes.
                    VStack(spacing: 16) {
                        Image(systemName: "atom").font(.system(size: 64, weight: .bold)).foregroundStyle(Color.lagoon)
                        ProgressView("Po hapet llogaria…")
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.paper.ignoresSafeArea())
                } else { AccessScreen() }
            }.environmentObject(account)
            .tint(Color.lagoon)
            .preferredColorScheme(AppAppearance.scheme(appearance))
            .dynamicTypeSize(AppAppearance.textSize(textSize))
            .task { await account.restore() }
            .modifier(FirstLaunch(done: $onboardingDone))
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
                    Button("E ruajta kodin") { account.recoveryNotice = "" }.buttonStyle(.liquidProminent)
                }.interactiveDismissDisabled()
            }
        }
    }
}

extension Color {
    static let midnight = Color(red: 0.08, green: 0.07, blue: 0.19)
    static let sun = Color(red: 1.0, green: 0.84, blue: 0.27)
    /// Ngjyra kryesore; në modalitetin e errët pak më e çelët, që të lexohet mbi sfond të errët.
    /// Ngjyra kryesore: ajo që zgjedh përdoruesi te Pamja (Progression.swift → AppAccent); parazgjedhja vjollcë.
    static var lagoon: Color { AppAccent.color }
    /// Sfondi i faqeve.
    static let paper = Color(light: Color(red: 0.95, green: 0.94, blue: 0.99), dark: Color(red: 0.07, green: 0.07, blue: 0.11))
    /// Sfondi i kartave (ishte e bardhë).
    static let card = Color(light: .white, dark: Color(red: 0.14, green: 0.13, blue: 0.20))
    /// Teksti kryesor.
    static let ink = Color(light: Color.black.opacity(0.86), dark: Color.white.opacity(0.92))

    /// Ngjyrë që ndryshon vetë sipas modalitetit të çelët/të errët të sistemit.
    init(light: Color, dark: Color) {
        #if os(iOS)
        self = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
        #elseif os(macOS)
        self = Color(NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light) })
        #else
        self = light
        #endif
    }
}

/// Pamja e app-it: modaliteti (sistemi/i çelët/i errët) dhe madhësia e tekstit, nga Profili.
enum AppAppearance {
    static let schemeKey = "appearance.scheme.v1"
    static let textSizeKey = "appearance.textSize.v1"
    static func scheme(_ value: Int) -> ColorScheme? { value == 1 ? .light : value == 2 ? .dark : nil }
    static let sizes: [DynamicTypeSize] = [.xSmall, .medium, .large, .xLarge, .xxLarge, .xxxLarge, .accessibility1, .accessibility2]
    static let sizeNames = ["Shumë i vogël", "I vogël", "Normal", "I madh", "Më i madh", "Shumë i madh", "Maksimal", "Maksimal+"]
    static func textSize(_ index: Int) -> DynamicTypeSize { sizes[min(max(index, 0), sizes.count - 1)] }
}

/// Cilësimet e pamjes te Profili.
struct AppearanceSettings: View {
    @AppStorage(AppAppearance.schemeKey, store: .standard) private var appearance = 0
    @AppStorage(AppAppearance.textSizeKey, store: .standard) private var textSize = 2
    @AppStorage(Haptics.enabledKey, store: .standard) private var haptics = true
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pamja").font(.headline)
            Picker("Modaliteti", selection: $appearance) {
                Text("Si sistemi").tag(0); Text("I çelët").tag(1); Text("I errët").tag(2)
            }.pickerStyle(.segmented)
            HStack {
                Text("Madhësia e tekstit")
                Spacer()
                Text(AppAppearance.sizeNames[min(max(textSize, 0), AppAppearance.sizeNames.count - 1)]).foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { Double(textSize) }, set: { textSize = Int($0.rounded()) }), in: 0...Double(AppAppearance.sizes.count - 1), step: 1) {
                Text("Madhësia e tekstit")
            } minimumValueLabel: { Text("A").font(.caption) } maximumValueLabel: { Text("A").font(.title2) }
            Toggle("Dridhje të lehta kur përgjigjesh", isOn: $haptics)
            PersonalizeSettings().padding(.top, 6)
        }
    }
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
        .background { PageBackground().ignoresSafeArea() }.foregroundStyle(Color.ink)
    }
}

/// Prezantimi i hapjes së parë (AppFeel.swift): ekran i plotë në iPhone/iPad, dritare në Mac.
private struct FirstLaunch: ViewModifier {
    @Binding var done: Bool
    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(isPresented: Binding(get: { !done }, set: { if !$0 { done = true } })) {
            Onboarding { done = true }
        }
        #else
        content.sheet(isPresented: Binding(get: { !done }, set: { if !$0 { done = true } })) {
            Onboarding { done = true }.frame(minWidth: 560, minHeight: 620)
        }
        #endif
    }
}

struct Tile: View {
    let icon: String
    let title: String
    let detail: String
    @Environment(\.subjectTheme) private var subject
    @State private var shown = false
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon).font(.headline).foregroundStyle(.white)
                .bounceSymbol(on: shown)
                .frame(width: 48, height: 48)
                .background(subject.map { AnyShapeStyle($0.gradient) } ?? AnyShapeStyle(Color.lagoon), in: RoundedRectangle(cornerRadius: subject == nil ? 8 : 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
        }
        .padding(15).glass(cornerRadius: 22, tint: subject?.color, interactive: true).contentShape(Rectangle())
        .modifier(ScrollFade())
        .liquidRipple(subject?.color ?? .lagoon)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { shown = true } }
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
        .accessibilityElement(children: .ignore).accessibilityLabel("BrainSpark")
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
            HomeHeader(role: role).appearIn(0)
            TodaySection(role: role)
            if role == .student {
                DailyChallengeCard().appearIn(1)
                LeaderboardCard().appearIn(2)
                FocusTimerCard().appearIn(3)
            }
            GlobalSearchField().appearIn(1)
            if let last = StudyLesson.all.first(where: { $0.id == lastID && (learnerLevel == nil || $0.level == learnerLevel?.rawValue) }) {
                ContinueCard(lesson: last, readIDs: readIDs).appearIn(2)
            }
            QuestCover()
            Text("BrainSpark · versioni " + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")).font(.caption.bold()).foregroundStyle(Color.lagoon)
            Text("Zgjidh lëndën").font(.system(.title, design: .rounded).weight(.black))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 12) {
                ForEach(Array([Subject.math, .physics, .chemistry, .biology].enumerated()), id: \.element) { index, subject in
                    Button { open(subject) } label: { HomeSubjectCard(subject: subject) }
                        .buttonStyle(.springy)
                        .appearIn(index)
                }
            }
            let readingPool = StudyLesson.all.filter { learnerLevel == nil || $0.level == learnerLevel?.rawValue }
            let count = readingPool.filter { readIDs.split(separator: "|").contains(Substring($0.id)) }.count
            ProgressView(value: Double(count), total: Double(max(1, readingPool.count))) {
                Text("Mësime të lexuara · \(count)/\(readingPool.count)").font(.subheadline.bold())
            }
            Group {
                NavigationLink { StudySubjects() } label: { Tile(icon: "books.vertical.fill", title: "Mësime sipas kapitujve", detail: "\(StudyLesson.all.count) mësime · Pesë nivele") }
                NavigationLink { TutorChat(role: role) } label: { Tile(icon: "sparkles", title: "Bisedo me " + LessonTutor.name, detail: "Asistenti i mësimeve · edhe me foto, pa internet") }
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

/// Karta e lëndës në faqen Krye: gradient, simbole që lëvizin dhe ikonë që noton.
private struct HomeSubjectCard: View {
    let subject: Subject
    @State private var float = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: subject.icon).font(.system(size: 30, weight: .semibold))
                    .offset(y: float ? -3 : 3).rotationEffect(.degrees(float ? 6 : -6))
                Spacer()
                Image(systemName: "arrow.up.right").font(.headline)
            }
            Text(subject.rawValue).font(.title2.bold())
            Text(subject.motto).font(.caption).opacity(0.9).lineLimit(2)
        }
        .padding(16).frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .foregroundStyle(.white)
        .background { ZStack { subject.gradient; GlyphField(subject: subject, opacity: 0.14, tint: .white) }.clipShape(RoundedRectangle(cornerRadius: 20)) }
        .shadow(color: subject.color.opacity(0.35), radius: 10, y: 6)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.2 + Double(subject.rawValue.count % 4) * 0.3).repeatForever(autoreverses: true)) { float = true }
        }
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
                    }.padding().glass(cornerRadius: 12)
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
                Button("Provo përsëri") { self.choice = nil }.buttonStyle(.liquid)
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
                }.padding().glass(cornerRadius: 15)
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
            }.padding().glass(cornerRadius: 16)
            SectionText(heading: "Sfida", text: "Gjej dy mënyra për të përshkuar 24 m. Cila vijë ka pjerrësi më të madhe?")
        }.navigationTitle("Simulimi")
    }
}
