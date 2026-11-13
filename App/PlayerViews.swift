import SwiftUI
#if os(iOS)
import UIKit
#endif

// Pjesët e UI-së personale (Juri): krye me përshëndetje dhe avatar, «Vazhdo ku e le», nivelet dhe medaljet,
// redaktori i avatarit, kërkimi global, ngjyra dhe ikona e app-it, ikonat që lëvizin dhe kalimi me zmadhim.

// MARK: - Ikona që lëvizin (iOS 17+ / macOS 14+); në versionet e vjetra mbeten të qeta.

extension View {
    /// Ikona kërcen sa herë ndryshon `value`.
    @ViewBuilder func bounceSymbol<V: Equatable>(on value: V) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) { self.symbolEffect(.bounce, value: value) } else { self }
    }
    /// Ikona pulson butë pa ndalur (p.sh. flaka, zilja).
    @ViewBuilder func pulsingSymbol(_ active: Bool = true) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) { self.symbolEffect(.pulse, options: .repeating, isActive: active) } else { self }
    }
    /// Ikona tundet herë pas here (zilja e njoftimeve). iOS 18+/macOS 15+.
    @ViewBuilder func wigglingSymbol() -> some View {
        if #available(iOS 18.0, macOS 15.0, *) { self.symbolEffect(.wiggle, options: .repeat(.periodic(delay: 3))) } else { self }
    }
}

// MARK: - Kalimi me zmadhim: karta zmadhohet dhe bëhet faqja (iOS 18+). Gjetkë mbetet kalimi i zakonshëm.

extension View {
    @ViewBuilder func zoomSource<ID: Hashable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *) { self.matchedTransitionSource(id: id, in: namespace) } else { self }
        #else
        self
        #endif
    }
    @ViewBuilder func zoomDestination<ID: Hashable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *) { self.navigationTransition(.zoom(sourceID: id, in: namespace)) } else { self }
        #else
        self
        #endif
    }
}

// MARK: - Krye: përshëndetje, avatar, nivel, seri

struct HomeHeader: View {
    let role: SchoolRole
    @EnvironmentObject private var account: Account
    private var stats = PlayerStats()
    private var avatar = AvatarStore()
    @State private var editing = false
    @State private var showBadges = false
    @State private var ring: Double = 0

    init(role: SchoolRole) { self.role = role }

    private var greeting: (String, String) {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return ("Mirëmëngjes", "sun.max.fill")
        case 12..<18: return ("Mirëdita", "sun.haze.fill")
        case 18..<22: return ("Mirëmbrëma", "sunset.fill")
        default: return ("Natën e mirë", "moon.stars.fill")
        }
    }
    private var name: String {
        if !avatar.nickname.isEmpty { return avatar.nickname }
        let local = account.email.split(separator: "@").first.map(String.init) ?? ""
        let first = local.split(whereSeparator: { $0 == "." || $0 == "_" || $0.isNumber }).first.map(String.init) ?? local
        return first.isEmpty ? "" : first.prefix(1).uppercased() + first.dropFirst()
    }

    var body: some View {
        let level = stats.level
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Button { editing = true } label: {
                    ZStack {
                        Circle().stroke(Color.lagoon.opacity(0.18), lineWidth: 5)
                        Circle().trim(from: 0, to: ring)
                            .stroke(AngularGradient(colors: [.lagoon, .pink, .sun, .lagoon], center: .center), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        AvatarBadge(emoji: avatar.emoji, color: avatar.color, size: 54)
                    }.frame(width: 68, height: 68)
                }
                .buttonStyle(.springy)
                .accessibilityLabel("Ndrysho avatarin")
                VStack(alignment: .leading, spacing: 3) {
                    Label(greeting.0 + (name.isEmpty ? "" : ", " + name), systemImage: greeting.1)
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .symbolRenderingMode(.multicolor)
                    Text(role == .student ? "Gati për të mësuar diçka të re sot?" : "Mirë se erdhe në BrainSpark")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if role == .student {
                Button { showBadges = true } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Niveli \(level.number)").font(.headline)
                                Text("· " + level.title).font(.subheadline).foregroundStyle(.secondary)
                                Spacer()
                                CountingText(stats.xp, format: { "\($0) XP" }).font(.subheadline.bold()).foregroundStyle(Color.lagoon)
                            }
                            ProgressView(value: ring, total: 1)
                                .tint(Color.lagoon)
                            Text("\(level.xpForLevel - level.xpIntoLevel) XP deri te niveli \(level.number + 1)").font(.caption).foregroundStyle(.secondary)
                        }
                        Divider().frame(height: 50)
                        VStack(spacing: 2) {
                            Image(systemName: "flame.fill").font(.title2)
                                .foregroundStyle(stats.streak > 0 ? AnyShapeStyle(LinearGradient(colors: [.yellow, .orange, .red], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.secondary))
                                .pulsingSymbol(stats.streak > 0)
                            Text("\(stats.streak)").font(.headline.monospacedDigit())
                            Text("ditë").font(.caption2).foregroundStyle(.secondary)
                        }
                        VStack(spacing: 2) {
                            Image(systemName: "medal.fill").font(.title2).foregroundStyle(Color.sun)
                                .bounceSymbol(on: stats.badges.filter(\.earned).count)
                            Text("\(stats.badges.filter(\.earned).count)").font(.headline.monospacedDigit())
                            Text("medalje").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(14).glass(cornerRadius: 22, interactive: true)
                }
                .buttonStyle(.springy)
            }
        }
        .onAppear { withAnimation(.spring(response: 1.0, dampingFraction: 0.8).delay(0.2)) { ring = max(0.02, level.progress) } }
        .onChange(of: stats.xp) { _ in withAnimation(.spring()) { ring = max(0.02, stats.level.progress) } }
        .sheet(isPresented: $editing) { AvatarEditor().frame(minWidth: 420, minHeight: 560) }
        .sheet(isPresented: $showBadges) { NavigationStack { BadgeShelf() }.frame(minWidth: 420, minHeight: 560) }
        .modifier(LevelUpWatcher(level: level.number, earned: stats.badges.filter(\.earned)))
    }
}

/// «Vazhdo ku e le»: mësimi i fundit, me sa të ka mbetur nga kapitulli.
struct ContinueCard: View {
    let lesson: StudyLesson
    let readIDs: String
    @Namespace private var zoom
    var body: some View {
        let chapter = StudyLesson.all.filter { $0.chapterID == lesson.chapterID && $0.level == lesson.level && $0.subject == lesson.subject }
        let read = chapter.filter { readIDs.split(separator: "|").contains(Substring($0.id)) }.count
        let progress = Double(read) / Double(max(chapter.count, 1))
        NavigationLink {
            StudyReader(lesson: lesson).zoomDestination("continue", in: zoom)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(.white.opacity(0.3), lineWidth: 5)
                    Circle().trim(from: 0, to: progress).stroke(.white, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                    Image(systemName: "play.fill").font(.title3)
                }.frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Vazhdo ku e le").font(.caption.bold()).opacity(0.85)
                    Text(lesson.title).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                    Text("\(lesson.chapterTitle) · \(read)/\(chapter.count) në kapitull").font(.caption).opacity(0.85).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.headline)
            }
            .foregroundStyle(.white).padding(16)
            .background { ZStack { lesson.schoolSubject.gradient; GlyphField(subject: lesson.schoolSubject, opacity: 0.12, tint: .white) }.clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)) }
            .shadow(color: lesson.schoolSubject.color.opacity(0.35), radius: 12, y: 6)
            .zoomSource("continue", in: zoom)
        }
        .buttonStyle(.springy)
    }
}

// MARK: - Medaljet dhe nivelet

struct BadgeShelf: View {
    private var stats = PlayerStats()
    @Environment(\.dismiss) private var dismiss
    init() {}
    var body: some View {
        let level = stats.level
        Page {
            VStack(spacing: 10) {
                Text("Niveli \(level.number)").font(.system(size: 44, weight: .black, design: .rounded)).foregroundStyle(Color.lagoon)
                Text(level.title).font(.title3.bold())
                ProgressView(value: level.progress).tint(Color.lagoon).frame(maxWidth: 320)
                Text("\(stats.xp) XP gjithsej · \(level.xpForLevel - level.xpIntoLevel) XP deri te niveli tjetër").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).padding().glass(cornerRadius: 24)
            Text("Si fiton XP").font(.headline)
            Text("Mësim i lexuar +20 · Pyetje kontrolli +15 · Ushtrim i saktë +10 · Mision laboratori +30 · Çdo yll +10 · Parashikim i saktë +5 · Çdo ditë që mëson +25")
                .font(.callout).foregroundStyle(.secondary)
            Text("Medaljet").font(.title2.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                ForEach(Array(stats.badges.enumerated()), id: \.element.id) { index, badge in
                    VStack(spacing: 6) {
                        Text(badge.emoji).font(.system(size: 44))
                            .grayscale(badge.earned ? 0 : 1).opacity(badge.earned ? 1 : 0.35)
                        Text(badge.title).font(.subheadline.bold()).multilineTextAlignment(.center)
                        Text(badge.detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        if badge.earned { Label("Fituar", systemImage: "checkmark.seal.fill").font(.caption2.bold()).foregroundStyle(.green) }
                    }
                    .padding(12).frame(maxWidth: .infinity, minHeight: 150)
                    .glass(cornerRadius: 20, tint: badge.earned ? Color.sun : nil, strength: badge.earned ? 0.15 : 0.0)
                    .appearIn(index)
                }
            }
        }
        .navigationTitle("Përparimi im")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Mbyll") { dismiss() } } }
    }
}

/// Kur ngjitesh nivel ose fiton një medalje të re, del një festë (një herë për secilën).
private struct LevelUpWatcher: ViewModifier {
    let level: Int
    let earned: [Badge]
    @AppStorage("celebrated.level.v1") private var celebratedLevel = 0
    @AppStorage("celebrated.badges.v1") private var celebratedBadges = ""
    @State private var showing: (title: String, emoji: String, detail: String)?

    func body(content: Content) -> some View {
        content
            .overlay {
                if let showing {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { close() }
                        VStack(spacing: 12) {
                            Text(showing.emoji).font(.system(size: 80))
                            Text(showing.title).font(.system(.title, design: .rounded).weight(.black)).multilineTextAlignment(.center)
                            Text(showing.detail).multilineTextAlignment(.center).foregroundStyle(.secondary)
                            Button("Bukur!") { close() }.buttonStyle(.liquidProminent)
                        }
                        .padding(28).frame(maxWidth: 340)
                        .glass(cornerRadius: 30, tint: .sun, strength: 0.12)
                        .confetti(true)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                    .zIndex(10)
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: showing?.title)
            .task(id: "\(level)|\(earned.map(\.id).joined())") { check() }
    }

    private func check() {
        guard showing == nil else { return }
        if celebratedLevel == 0 { celebratedLevel = level }   // herën e parë nuk festojmë nivelet e vjetra
        let seen = Set(celebratedBadges.split(separator: "|").map(String.init))
        if celebratedBadges.isEmpty && !earned.isEmpty {
            celebratedBadges = earned.map(\.id).joined(separator: "|"); return
        }
        if level > celebratedLevel {
            celebratedLevel = level
            Haptics.celebrate()
            showing = ("Niveli \(level)!", "🚀", "U ngjite nivel: " + PlayerLevel(xp: 0).titleFor(level) + ". Vazhdo kështu!")
        } else if let badge = earned.first(where: { !seen.contains($0.id) }) {
            celebratedBadges = (seen.union([badge.id])).sorted().joined(separator: "|")
            Haptics.celebrate()
            showing = ("Medalje e re: " + badge.title, badge.emoji, badge.detail)
        }
    }
    private func close() { showing = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { check() } }
}

extension PlayerLevel {
    func titleFor(_ number: Int) -> String {
        var xp = 0
        for n in 1..<max(number, 1) { xp += n * 100 }
        return PlayerLevel(xp: xp).title
    }
}

// MARK: - Redaktori i avatarit

struct AvatarEditor: View {
    private var avatar = AvatarStore()
    @Environment(\.dismiss) private var dismiss
    init() {}
    var body: some View {
        NavigationStack {
            Page {
                AvatarBadge(emoji: avatar.emoji, color: avatar.color, size: 120)
                    .frame(maxWidth: .infinity)
                    .id(avatar.emoji + "\(avatar.colorIndex)")
                    .transition(.scale.combined(with: .opacity))
                TextField("Si të thërrasim? (p.sh. Juri)", text: avatar.$nickname)
                    .textFieldStyle(.plain).padding(14).glass(cornerRadius: 16)
                Text("Personazhi").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 10)], spacing: 10) {
                    ForEach(AvatarStore.emojis, id: \.self) { emoji in
                        Button {
                            Haptics.tap()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { avatar.emoji = emoji }
                        } label: {
                            Text(emoji).font(.system(size: 30)).frame(width: 56, height: 56)
                                .glass(cornerRadius: 16, tint: avatar.emoji == emoji ? avatar.color : nil, strength: avatar.emoji == emoji ? 0.4 : 0)
                                .scaleEffect(avatar.emoji == emoji ? 1.08 : 1)
                        }.buttonStyle(.springy)
                    }
                }
                Text("Ngjyra").font(.headline)
                HStack(spacing: 12) {
                    ForEach(AvatarStore.colors.indices, id: \.self) { index in
                        Button {
                            Haptics.tap()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { avatar.colorIndex = index }
                        } label: {
                            Circle().fill(AvatarStore.colors[index]).frame(width: 34, height: 34)
                                .overlay(Circle().strokeBorder(.white, lineWidth: avatar.colorIndex == index ? 3 : 0))
                                .shadow(color: AvatarStore.colors[index].opacity(0.5), radius: avatar.colorIndex == index ? 6 : 0)
                                .scaleEffect(avatar.colorIndex == index ? 1.15 : 1)
                        }.buttonStyle(.plain)
                        .accessibilityLabel("Ngjyra \(index + 1)")
                    }
                }
                Text("Avatari shfaqet te Krye dhe te bisedat me Bosko AI, në këtë pajisje.").font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Avatari im")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Gati") { dismiss() } } }
        }
    }
}

// MARK: - Kërkimi global

struct GlobalSearchField: View {
    @State private var open = false
    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.headline)
                Text("Kërko mësime, ushtrime, laboratorë…").foregroundStyle(.secondary)
                Spacer()
                #if os(macOS)
                Text("⌘K").font(.caption.bold()).padding(.horizontal, 6).padding(.vertical, 2).glassCapsule()
                #endif
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .glassCapsule(interactive: true)
        }
        .buttonStyle(.springy)
        .keyboardShortcut("k", modifiers: .command)
        .accessibilityLabel("Kërko")
        .sheet(isPresented: $open) { GlobalSearch().frame(minWidth: 520, minHeight: 620) }
    }
}

struct GlobalSearch: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.learnerLevel) private var learnerLevel
    @State private var query = ""
    @Namespace private var zoom

    private var tokens: [String] { LessonSearch.tokens(query) }
    private func matches(_ text: String) -> Bool {
        let normalized = LessonSearch.normalize(text)
        return !tokens.isEmpty && tokens.allSatisfy { normalized.contains($0) }
    }
    private var lessons: [StudyLesson] {
        Array(StudyLesson.all.filter { (learnerLevel == nil || $0.level == learnerLevel?.rawValue) && (matches($0.title) || matches($0.chapterTitle)) }.prefix(20))
    }
    private var exercises: [Exercise] {
        Array(Exercise.all.filter { (learnerLevel == nil || $0.level == learnerLevel?.rawValue) && matches($0.prompt) }.prefix(12))
    }
    private var labs: [LabExperiment] { LabExperiment.allCases.filter { matches($0.title) || matches($0.mission) } }

    var body: some View {
        NavigationStack {
            Page {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.headline).foregroundStyle(Color.lagoon)
                    TextField("Shkruaj p.sh. «fotosinteza», «forca», «ekuacion»", text: $query)
                        .textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button { withAnimation { query = "" } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 13).glassCapsule()
                if tokens.isEmpty {
                    Text("Provo:").font(.headline)
                    HStack {
                        ForEach(["qeliza", "shpejtësia", "acid", "thyesa"], id: \.self) { word in
                            Button(word) { withAnimation(.spring()) { query = word } }.buttonStyle(.liquid)
                        }
                    }
                } else if lessons.isEmpty && exercises.isEmpty && labs.isEmpty {
                    Label("Nuk gjeta asgjë për «\(query)». Provo një fjalë tjetër.", systemImage: "questionmark.circle").foregroundStyle(.secondary)
                } else {
                    if !lessons.isEmpty {
                        section("Mësime", count: lessons.count)
                        ForEach(lessons) { lesson in
                            NavigationLink { StudyReader(lesson: lesson).zoomDestination(lesson.id, in: zoom) } label: {
                                Tile(icon: lesson.schoolSubject.icon, title: lesson.title, detail: "\(lesson.subject) · \(lesson.chapterTitle)")
                                    .environment(\.subjectTheme, lesson.schoolSubject)
                                    .zoomSource(lesson.id, in: zoom)
                            }.buttonStyle(.springy)
                        }
                    }
                    if !labs.isEmpty {
                        section("Laboratorë", count: labs.count)
                        ForEach(labs) { experiment in
                            NavigationLink { InteractiveExperiment(experiment: experiment) } label: {
                                Tile(icon: "flask.fill", title: experiment.title, detail: experiment.mission)
                                    .environment(\.subjectTheme, experiment.subject)
                            }.buttonStyle(.springy)
                        }
                    }
                    if !exercises.isEmpty {
                        section("Ushtrime", count: exercises.count)
                        ForEach(exercises) { item in
                            NavigationLink { Page { ExercisePlayer(item: item) } } label: {
                                Tile(icon: "pencil.circle.fill", title: item.prompt, detail: item.subject + " · klasa \(item.level)")
                                    .environment(\.subjectTheme, Subject(rawValue: item.subject))
                            }.buttonStyle(.springy)
                        }
                    }
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: query)
            .navigationTitle("Kërko")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Mbyll") { dismiss() } } }
        }
    }
    private func section(_ title: String, count: Int) -> some View {
        HStack { Text(title).font(.title3.bold()); Text("\(count)").font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 2).glassCapsule() }
            .padding(.top, 6)
    }
}

// MARK: - Ngjyra dhe ikona e app-it

struct PersonalizeSettings: View {
    @AppStorage(AppAccent.key, store: .standard) private var accent = 0
    @AppStorage("appIcon.choice.v1", store: .standard) private var iconChoice = AppIconChoice.standard.rawValue
    @State private var iconMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ngjyra e app-it").font(.headline)
            HStack(spacing: 12) {
                ForEach(AppAccent.choices.indices, id: \.self) { index in
                    Button {
                        Haptics.tap()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { accent = index }
                    } label: {
                        Circle().fill(Color(light: AppAccent.choices[index].light, dark: AppAccent.choices[index].dark))
                            .frame(width: 34, height: 34)
                            .overlay(Circle().strokeBorder(.white, lineWidth: accent == index ? 3 : 0))
                            .overlay { if accent == index { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) } }
                            .scaleEffect(accent == index ? 1.15 : 1)
                            .shadow(color: AppAccent.choices[index].light.opacity(0.5), radius: accent == index ? 6 : 0)
                    }.buttonStyle(.plain)
                    .accessibilityLabel(AppAccent.choices[index].name)
                }
            }
            #if os(iOS)
            Text("Ikona e app-it").font(.headline).padding(.top, 6)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(AppIconChoice.allCases) { choice in
                        Button { setIcon(choice) } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(LinearGradient(colors: [choice.colors[0], choice.colors[0].opacity(0.8)], startPoint: .top, endPoint: .bottom))
                                    Image(systemName: "atom").font(.system(size: 30, weight: .bold)).foregroundStyle(choice.colors[1])
                                }
                                .frame(width: 64, height: 64)
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.lagoon, lineWidth: iconChoice == choice.rawValue ? 3 : 0))
                                .scaleEffect(iconChoice == choice.rawValue ? 1.06 : 1)
                                Text(choice.title).font(.caption)
                            }
                        }.buttonStyle(.springy)
                    }
                }.padding(.vertical, 4)
            }
            if !iconMessage.isEmpty { Text(iconMessage).font(.caption).foregroundStyle(.secondary) }
            #endif
        }
    }

    #if os(iOS)
    private func setIcon(_ choice: AppIconChoice) {
        guard UIApplication.shared.supportsAlternateIcons else { iconMessage = "Kjo pajisje nuk lejon ndryshimin e ikonës."; return }
        UIApplication.shared.setAlternateIconName(choice.assetName) { error in
            DispatchQueue.main.async {
                if error == nil {
                    withAnimation(.spring()) { iconChoice = choice.rawValue }
                    iconMessage = ""
                    Haptics.success()
                } else { iconMessage = "Ikona nuk u ndryshua. Provo përsëri." }
            }
        }
    }
    #endif
}
