import SwiftUI

// «Sot» (#1, Matia): kartat e ditës sipas rolit, në krye të faqes Krye.
// Përdor vetëm të dhëna reale nga shërbimi i shkollës (snapshot, orari, projektet), pa demo. Çdo kartë hap veprimin e vet.
// Nuk shton thirrje të reja në server: përdor api_snapshot, api_scheduleGet dhe api_projects që ekzistojnë.

@MainActor
final class TodayModel: ObservableObject {
    @Published var snapshot: SchoolSnapshot?
    @Published var slots: [ScheduleSlot] = []
    @Published var projects: [SchoolProject] = []
    @Published var loading = false
    @Published var failed = false

    func load(token: String) async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        do {
            let snap: SchoolSnapshot = try await SchoolAPI.call("snapshot", token: token)
            snapshot = snap
            failed = false
        } catch { failed = snapshot == nil }
        // Orari dhe projektet janë shtesë: nëse dështojnë, «Sot» shfaqet pa to.
        if let reply: ScheduleReply = try? await SchoolAPI.call("scheduleGet") { slots = reply.slots }
        if let reply: ProjectsReply = try? await SchoolAPI.call("projects") { projects = reply.projects }
    }
}

/// Një kartë e «Sot».
struct TodayItem: Identifiable {
    enum Target { case school, schedule, projects, calendar, plan(PlanTarget) }
    let id: String
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    var urgent = false
    let target: Target
    /// Rezultatet që shënohen si të para kur hapet karta.
    var seen: [String] = []
}

struct TodaySection: View {
    let role: SchoolRole
    @EnvironmentObject private var account: Account
    @StateObject private var model = TodayModel()
    @AppStorage("today.seenResults.v1") private var seenResults = ""
    @AppStorage("studyReadIDs.v1") private var readIDs = ""

    var body: some View {
        if account.isOnline {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Sot").font(.system(.title, design: .rounded).weight(.black))
                    Text(Self.dateText(Date())).font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    if model.loading && model.snapshot != nil { ProgressView().controlSize(.small).accessibilityLabel("Po rifreskohet") }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                if model.snapshot == nil && !model.failed {
                    TodayPlaceholder()
                } else if model.snapshot == nil {
                    Button { Task { await model.load(token: account.token) } } label: {
                        Label("«Sot» nuk u ngarkua. Kontrollo internetin dhe prek për ta provuar përsëri.", systemImage: "arrow.clockwise")
                            .font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16).glass(cornerRadius: 18)
                    }
                    .buttonStyle(.plain)
                } else if items.isEmpty {
                    HStack(spacing: 14) {
                        Text("🎉").font(.largeTitle).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Asgjë urgjente sot").font(.headline)
                            Text(emptyDetail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16).glass(cornerRadius: 18)
                    .accessibilityElement(children: .combine)
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        NavigationLink { destination(item) } label: { TodayCard(item: item) }
                            .buttonStyle(.springy)
                            .appearIn(index)
                    }
                }
            }
            .task(id: account.token) { await model.load(token: account.token) }
        }
    }

    // MARK: Destinacionet

    @ViewBuilder private func destination(_ item: TodayItem) -> some View {
        Group {
            switch item.target {
            case .school:
                Page { SchoolHub() }.navigationTitle("Shkolla")
            case .schedule:
                ClassScheduleView(classes: role == .teacher ? (model.snapshot?.classes ?? []) : [], canEdit: role == .teacher)
            case .projects:
                ProjectsScreen(ownedClasses: (model.snapshot?.classes ?? []).filter { $0.owner == account.identity.replacingOccurrences(of: "school-", with: "") })
            case .calendar:
                SharedSchoolCalendar()
            case .plan(let target):
                StudyPlanView(target: target)
            }
        }
        .onAppear { markSeen(item.seen) }
        .onDisappear { Task { await model.load(token: account.token) } }
    }

    private func markSeen(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        var set = Set(seenResults.split(separator: "|").map(String.init))
        ids.forEach { set.insert($0) }
        seenResults = set.sorted().suffix(300).joined(separator: "|")
    }

    private var emptyDetail: String {
        switch role {
        case .teacher: return "Nuk ka dorëzime për korrigjim, kërkesa ose ora të tjera sot."
        case .parent: return "Nuk ka nota të reja ose evente për sot dhe nesër."
        case .student: return "Nuk ke teste, afate ose ora të tjera sot. Vazhdo me një mësim ose provo një laborator."
        }
    }

    // MARK: Kartat sipas rolit

    private var items: [TodayItem] {
        guard let snap = model.snapshot else { return [] }
        let now = Date()
        var list: [TodayItem] = []
        let seen = Set(seenResults.split(separator: "|").map(String.init))

        // Orari: ora tani dhe ora e radhës (mësuesi sheh vetëm orët e veta).
        let slots = role == .teacher ? model.slots.filter(\.mine) : model.slots
        let (current, next) = ScheduleWeek.now(slots, at: now)
        if let current {
            list.append(TodayItem(id: "now-" + current.id, icon: "clock.fill", tint: Self.tint(current.subject),
                                  title: "Tani: " + current.subject, detail: Self.place(current) + " · deri në " + current.ends, urgent: true, target: .schedule))
        }
        if let next {
            list.append(TodayItem(id: "next-" + next.id, icon: "clock.arrow.circlepath", tint: Self.tint(next.subject),
                                  title: "Ora e radhës: " + next.subject, detail: next.starts + "–" + next.ends + " · " + Self.place(next), target: .schedule))
        }

        switch role {
        case .student:
            for attempt in snap.results where !attempt.submitted && attempt.deadline > attempt.serverNow {
                let minutes = Int((attempt.deadline - attempt.serverNow) / 60)
                list.append(TodayItem(id: "run-" + attempt.id, icon: "timer", tint: .red, title: "Vazhdo testin: " + attempt.title,
                                      detail: "Të kanë mbetur rreth \(max(minutes, 1)) min", urgent: true, target: .school))
            }
            let started = Set(snap.results.map(\.exam))
            let open = snap.tests.filter { $0.status == "published" && !started.contains($0.id) }
            for test in open.prefix(3) {
                list.append(TodayItem(id: "test-" + test.id, icon: "pencil.and.list.clipboard", tint: Self.tint(test.subject),
                                      title: "Test i hapur: " + test.title, detail: "\(test.minutes) min · \(test.count) pyetje", urgent: true, target: .school))
            }
            if open.count > 3 {
                list.append(TodayItem(id: "tests-more", icon: "tray.full.fill", tint: .lagoon, title: "Edhe \(open.count - 3) teste të hapura", detail: "Shiko të gjitha te Shkolla", target: .school))
            }
            list += newResults(snap, seen: seen)
            // Plani i përgatitjes (#3): për testet e 14 ditëve të ardhshme, detyrat e sotme.
            let read = Set(readIDs.split(separator: "|").map(String.init))
            for target in PlanTarget.upcoming(snap, now: now).prefix(2) {
                let todayTasks = target.plan(readIDs: read, now: now).first { Calendar.current.isDateInToday($0.date) }?.tasks ?? []
                let left = StudyPlanner.daysLeft(until: target.date, now: now)
                let when = left == 0 ? "sot" : left == 1 ? "nesër" : "pas \(left) ditësh"
                list.append(TodayItem(id: "plan-" + target.id, icon: "list.bullet.clipboard.fill", tint: target.subject?.color ?? .lagoon,
                                      title: "Përgatitu: " + target.title + " (" + when + ")",
                                      detail: todayTasks.isEmpty ? "Shiko planin ditë pas dite" : "Sot: " + todayTasks.prefix(2).map(\.title).joined(separator: " · "),
                                      urgent: left <= 1, target: .plan(target)))
            }
            for project in model.projects where project.isOpen && !project.mine {
                guard let due = project.due else { continue }
                let left = due - now.timeIntervalSince1970
                let delivered = project.teams.contains { team in team.versions.contains { !$0.isDraft } }
                guard left > -86_400, left < 7 * 86_400, !delivered else { continue }
                list.append(TodayItem(id: "proj-" + project.id, icon: "folder.fill.badge.person.crop", tint: .orange, title: "Afat: " + project.title,
                                      detail: Self.relative(due, now: now) + " · " + project.kindText, urgent: left < 2 * 86_400, target: .projects))
            }
        case .teacher:
            let toGrade = snap.results.filter { $0.submitted && $0.status == "në korrigjim" }
            if !toGrade.isEmpty {
                list.append(TodayItem(id: "grade", icon: "checkmark.seal.fill", tint: .orange, title: toGrade.count == 1 ? "1 dorëzim për korrigjim" : "\(toGrade.count) dorëzime për korrigjim",
                                      detail: Set(toGrade.map(\.title)).sorted().prefix(2).joined(separator: " · "), urgent: true, target: .school))
            }
            let waiting = snap.members.filter { !$0.approved }
            if !waiting.isEmpty {
                let names = Set(waiting.compactMap { member in snap.classes.first { $0.id == member.classID }?.name }).sorted()
                list.append(TodayItem(id: "join", icon: "person.badge.clock.fill", tint: .lagoon, title: waiting.count == 1 ? "1 kërkesë për t'u bashkuar" : "\(waiting.count) kërkesa për t'u bashkuar",
                                      detail: names.isEmpty ? "Prano ose refuzo" : "Klasa: " + names.joined(separator: ", "), target: .school))
            }
            let review = model.projects.filter(\.mine).flatMap(\.teams).flatMap(\.versions).filter { $0.submitted != nil && $0.reviewed == nil }
            if !review.isEmpty {
                list.append(TodayItem(id: "proj-review", icon: "text.bubble.fill", tint: .orange, title: review.count == 1 ? "1 version projekti pret komentin" : "\(review.count) versione projekti presin komentin",
                                      detail: "Jep feedback", target: .projects))
            }
        case .parent:
            if (snap.children ?? []).isEmpty {
                list.append(TodayItem(id: "link-child", icon: "figure.and.child.holdinghands", tint: .lagoon, title: "Lidhu me fëmijën tënd",
                                      detail: "Fut kodin e familjes që gjeneron fëmija në llogarinë e vet", target: .school))
            }
            list += newResults(snap, seen: seen)
        }

        // Eventet e sotme dhe të nesërme.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let limit = calendar.date(byAdding: .day, value: 2, to: today) ?? now
        for event in snap.events.sorted(by: { $0.date < $1.date }) {
            let date = Date(timeIntervalSince1970: event.date)
            guard date >= today, date < limit else { continue }
            let isToday = calendar.isDate(date, inSameDayAs: now)
            let time = date.formatted(date: .omitted, time: .shortened)
            list.append(TodayItem(id: "ev-" + event.id, icon: event.examID == nil ? "calendar" : "calendar.badge.exclamationmark",
                                  tint: Self.tint(event.subject), title: (isToday ? "Sot: " : "Nesër: ") + event.title,
                                  detail: event.note.isEmpty ? time : time + " · " + event.note, urgent: isToday && event.examID != nil, target: .calendar))
        }

        // Më të ngutshmet sipër; jo më shumë se 8 karta.
        let sorted = list.filter(\.urgent) + list.filter { !$0.urgent }
        return Array(sorted.prefix(8))
    }

    private func newResults(_ snap: SchoolSnapshot, seen: Set<String>) -> [TodayItem] {
        snap.results.filter { $0.submitted && $0.status == "vlerësuar" && !seen.contains($0.id) }.prefix(3).map { attempt in
            let score = attempt.score.map { "\($0)/\(attempt.maximum) pikë" } ?? "Rezultati u publikua"
            let who = role == .parent ? (attempt.student.map { $0.split(separator: "@").first.map(String.init) ?? $0 } ?? "") : ""
            return TodayItem(id: "res-" + attempt.id, icon: "star.circle.fill", tint: .green, title: "Rezultat i ri: " + attempt.title,
                             detail: who.isEmpty ? score : who + " · " + score, target: .school, seen: [attempt.id])
        }
    }

    // MARK: Ndihmës

    static func tint(_ subject: String?) -> Color {
        let s = (subject ?? "").lowercased()
        if s.contains("fiz") { return Subject.physics.color }
        if s.contains("mat") { return Subject.math.color }
        if s.contains("kim") { return Subject.chemistry.color }
        if s.contains("bio") { return Subject.biology.color }
        return .lagoon
    }
    static func place(_ slot: ScheduleSlot) -> String { slot.room.isEmpty ? slot.className : slot.className + " · salla " + slot.room }
    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sq_AL")
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return formatter.string(from: date)
    }
    static func relative(_ seconds: Double, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "sq_AL")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: Date(timeIntervalSince1970: seconds), relativeTo: now)
    }
}

/// Karta: ikonë me ngjyrën e lëndës, titull, hollësi. Me tekst shumë të madh (aksesueshmëri) ikona kalon sipër tekstit.
private struct TodayCard: View {
    let item: TodayItem
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 14))
        layout {
            Image(systemName: item.icon).font(.headline).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(LinearGradient(colors: [item.tint, item.tint.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                Text(item.detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if !typeSize.isAccessibilitySize {
                Spacer(minLength: 0)
                if item.urgent { Circle().fill(.red).frame(width: 8, height: 8).accessibilityHidden(true) }
                Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glass(cornerRadius: 18, tint: item.tint, strength: 0.12)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityLabel((item.urgent ? "E rëndësishme. " : "") + item.title + ". " + item.detail)
        .accessibilityHint("Prek dy herë për ta hapur.")
    }
}

/// Skeleti gjatë ngarkimit të parë (në vend të ekranit bosh).
private struct TodayPlaceholder: View {
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 12).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4).frame(width: 180, height: 12)
                        RoundedRectangle(cornerRadius: 4).frame(width: 120, height: 10)
                    }
                    Spacer()
                }
                .foregroundStyle(Color.secondary.opacity(pulse ? 0.12 : 0.25))
                .padding(14).glass(cornerRadius: 18)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Po ngarkohet «Sot»…")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

// MARK: - Plani i përgatitjes (#3)

/// Një test i ardhshëm (14 ditët e ardhshme) për të cilin ndërtohet plani.
struct PlanTarget: Identifiable, Equatable {
    let id: String
    let title: String
    let date: Date
    let subject: Subject?
    let level: Int?

    /// Testet e ardhshme nga kalendari i klasës: eventet e lidhura me një test, ose që duken si test («Test», «Provim», «Kontroll»…).
    static func upcoming(_ snap: SchoolSnapshot, now: Date, calendar: Calendar = .current) -> [PlanTarget] {
        let today = calendar.startOfDay(for: now)
        let limit = calendar.date(byAdding: .day, value: 15, to: today) ?? now
        return snap.events.sorted { $0.date < $1.date }.compactMap { event in
            let date = Date(timeIntervalSince1970: event.date)
            guard date >= today, date < limit, event.examID != nil || StudyPlanner.looksLikeExam(event.title) else { return nil }
            let examSubject = snap.tests.first { $0.id == event.examID }?.subject
            let subject = [event.subject, examSubject, event.title].compactMap { $0 }.lazy.compactMap(Self.subject).first
            return PlanTarget(id: event.id, title: event.title, date: date, subject: subject,
                              level: snap.classes.first { $0.id == event.classID }?.level)
        }
    }

    static func subject(_ text: String) -> Subject? {
        let s = text.lowercased()
        if s.contains("fiz") { return .physics }
        if s.contains("mat") || s.contains("algjeb") || s.contains("gjeometri") { return .math }
        if s.contains("kim") { return .chemistry }
        if s.contains("bio") { return .biology }
        return nil
    }

    /// Mësimet e temës: kërkimi te mësimet e app-it me titullin e testit, lëndën dhe nivelin e klasës.
    func lessons(readIDs: Set<String>) -> [PlanLesson] {
        let query = [title, subject?.rawValue ?? ""].joined(separator: " ")
        var hits = LessonAssistantIndex.shared.search(query, subject: subject?.rawValue, level: level, limit: 9)
        if hits.isEmpty { hits = LessonAssistantIndex.shared.search(query, subject: subject?.rawValue, limit: 9) }
        return hits.compactMap { LessonAssistantIndex.byID[$0.id] }.map { PlanLesson(id: $0.id, title: $0.title, read: readIDs.contains($0.id)) }
    }

    func plan(readIDs: Set<String>, now: Date = Date()) -> [PlanDay] {
        StudyPlanner.plan(exam: date, now: now, lessons: lessons(readIDs: readIDs), subjectName: subject?.rawValue ?? "")
    }
}

/// Plani ditë pas dite, me shenja ✓ (mësimet shënohen vetë kur lexohen).
struct StudyPlanView: View {
    let target: PlanTarget
    @AppStorage("studyReadIDs.v1") private var readIDs = ""
    @AppStorage("plan.done.v1") private var doneIDs = ""

    private var read: Set<String> { Set(readIDs.split(separator: "|").map(String.init)) }
    private var done: Set<String> { Set(doneIDs.split(separator: "|").map(String.init)) }

    var body: some View {
        let days = target.plan(readIDs: read)
        let left = StudyPlanner.daysLeft(until: target.date, now: Date())
        Page {
            VStack(alignment: .leading, spacing: 6) {
                Text(target.title).font(.system(.largeTitle, design: .rounded).weight(.black))
                Label(TodaySection.dateText(target.date) + " · " + (left == 0 ? "sot" : left == 1 ? "nesër" : "pas \(left) ditësh"),
                      systemImage: "calendar").font(.headline).foregroundStyle(target.subject?.color ?? .lagoon)
            }
            .accessibilityElement(children: .combine)
            ProgressView(value: Double(completed(days)), total: Double(max(days.flatMap(\.tasks).count, 1))) {
                Text("Kryer \(completed(days)) nga \(days.flatMap(\.tasks).count)").font(.subheadline.bold())
            }
            ForEach(days) { day in
                VStack(alignment: .leading, spacing: 10) {
                    Text(dayTitle(day.date)).font(.title3.bold()).accessibilityAddTraits(.isHeader)
                    ForEach(day.tasks) { task in row(task) }
                }
                .padding(16).glass(cornerRadius: 20, tint: Calendar.current.isDateInToday(day.date) ? (target.subject?.color ?? .lagoon) : nil, strength: 0.10)
            }
            Label("Si u ndërtua: mësimet e temës ndahen 2–3 në ditë deri një ditë para testit; dita e fundit është për përsëritje dhe test prove. Ndrysho ritmin si të duash; ky është vetëm një sugjerim.",
                  systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("Plani i përgatitjes")
    }

    private func key(_ task: PlanTask) -> String { target.id + ":" + task.id }
    private func isDone(_ task: PlanTask) -> Bool {
        if case .lesson(let id) = task.kind, read.contains(id) { return true }
        return done.contains(key(task))
    }
    private func completed(_ days: [PlanDay]) -> Int { days.flatMap(\.tasks).filter(isDone).count }
    private func toggle(_ task: PlanTask) {
        var set = done
        if set.contains(key(task)) { set.remove(key(task)) } else { set.insert(key(task)); Haptics.success() }
        doneIDs = set.sorted().suffix(400).joined(separator: "|")
    }
    private func dayTitle(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Sot" }
        if Calendar.current.isDateInTomorrow(date) { return "Nesër" }
        return TodaySection.dateText(date).capitalized
    }

    @ViewBuilder private func row(_ task: PlanTask) -> some View {
        let finished = isDone(task)
        HStack(spacing: 12) {
            Button { toggle(task) } label: {
                Image(systemName: finished ? "checkmark.circle.fill" : "circle").font(.title2)
                    .foregroundStyle(finished ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.title)
            .accessibilityValue(finished ? "Kryer" : "Pa kryer")
            .accessibilityHint("Prek dy herë për ta shënuar.")
            NavigationLink { destination(task) } label: {
                HStack {
                    Text(task.title).strikethrough(finished).foregroundStyle(finished ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary).accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Hap detyrën.")
        }
    }

    @ViewBuilder private func destination(_ task: PlanTask) -> some View {
        switch task.kind {
        case .lesson(let id):
            if let lesson = LessonAssistantIndex.byID[id] { StudyReader(lesson: lesson) } else { StudySubjects() }
        case .mockTest: MockTestView()
        case .practice: PracticeMenu()
        case .review: StudySubjects()
        }
    }
}
