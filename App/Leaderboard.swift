import SwiftUI

// Sfida e ditës dhe Renditja javore me XP (Juri).
// Serveri: Supabase/migrations/20261114_1310_juri_renditja.sql (api_xpReport, api_leaderboard, api_dailyAnswer, api_dailyStats).
// Renditja tregon vetëm nxënës të pranuar në klasë (si te shokët): username, emri, avatari dhe XP. Asnjë email.

/// Sfida e ditës: e njëjta pyetje për të gjithë nxënësit e të njëjtit nivel, e re çdo ditë (ora e Shqipërisë).
enum DailyChallenge {
    static let storageKey = "daily.v1"   // "2026-11-14:1|2026-11-15:0"

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Tirane") ?? .current
        return calendar
    }
    static func dayKey(_ date: Date = Date()) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 2026, parts.month ?? 1, parts.day ?? 1)
    }
    static func question(level: Int?, date: Date = Date()) -> Exercise? {
        let pool = Exercise.all
            .filter { $0.kind == "select" && $0.choices.count >= 2 && (level == nil || $0.level == level) }
            .sorted { $0.id < $1.id }
        guard !pool.isEmpty else { return nil }
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        // Hap i madh (numër i thjeshtë) që ditët e njëpasnjëshme të mos japin pyetje fqinje.
        return pool[(day &* 7919) % pool.count]
    }
    static func result(_ log: String, day: String) -> Bool? {
        for item in log.split(separator: "|") {
            let parts = item.split(separator: ":")
            if parts.count == 2, parts[0] == Substring(day) { return parts[1] == "1" }
        }
        return nil
    }
    static func recording(_ log: String, day: String, correct: Bool) -> String {
        guard result(log, day: day) == nil else { return log }
        let items = log.split(separator: "|").map(String.init).suffix(400)
        return (items + ["\(day):\(correct ? 1 : 0)"]).joined(separator: "|")
    }
    static func correctCount(_ log: String) -> Int { log.split(separator: "|").filter { $0.hasSuffix(":1") }.count }
    static func answeredCount(_ log: String) -> Int { log.split(separator: "|").filter { !$0.isEmpty }.count }
    /// Ditë radhazi me sfidën e ditës të zgjidhur saktë (deri sot ose dje).
    static func streak(_ log: String, today: Date = Date()) -> Int {
        let correctDays = Set(log.split(separator: "|").compactMap { item -> String? in
            let parts = item.split(separator: ":"); return parts.count == 2 && parts[1] == "1" ? String(parts[0]) : nil })
        var date = today, count = 0
        if !correctDays.contains(dayKey(date)) { date = calendar.date(byAdding: .day, value: -1, to: date) ?? date }
        while correctDays.contains(dayKey(date)) {
            count += 1
            date = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        }
        return count
    }
}

struct LeaderRow: Decodable, Identifiable, Equatable {
    let rank: Int
    let username: String
    let displayName: String
    let avatarEmoji: String
    let avatarColor: Int
    let xp: Int
    let me: Bool
    var id: String { username }
    var color: Color { AvatarStore.colors[min(max(avatarColor, 0), AvatarStore.colors.count - 1)] }
}
private struct LeaderReply: Decodable {
    struct Me: Decodable { let rank: Int; let xp: Int }
    let rows: [LeaderRow]
    let me: Me?
}
struct DailyStats: Decodable { let answered: Int; let correctPercent: Int; let mine: Bool? }

@MainActor
final class LeaderboardModel: ObservableObject {
    @Published var rows: [LeaderRow] = []
    @Published var myRank: Int?
    @Published var myXP = 0
    @Published var loaded = false
    @Published var message = ""
    @Published var daily: DailyStats?

    func report(_ xp: Int) async { let _: OKReply? = try? await SchoolAPI.call("xpReport", body: ["xp": xp]) }

    func load(all: Bool) async {
        do {
            let reply: LeaderReply = try await SchoolAPI.call("leaderboard", body: ["scope": all ? "all" : "week"])
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                rows = reply.rows; myRank = reply.me?.rank; myXP = reply.me?.xp ?? 0; loaded = true
            }
            message = ""
        } catch { message = error.localizedDescription; loaded = true }
    }

    func answerDaily(day: String, correct: Bool) async {
        daily = try? await SchoolAPI.call("dailyAnswer", body: ["day": day, "correct": correct])
    }
    func loadDaily(day: String) async {
        daily = try? await SchoolAPI.call("dailyStats", body: ["day": day])
    }

    /// Ditët deri në fund të javës (e hëna e re), për «Java mbyllet pas …».
    static var daysLeftInWeek: Int {
        let calendar = DailyChallenge.calendar
        let weekday = calendar.component(.weekday, from: Date())   // 1 = e diel
        return weekday == 1 ? 1 : 9 - weekday
    }
}

// MARK: - Sfida e ditës

struct DailyChallengeCard: View {
    @Environment(\.learnerLevel) private var learnerLevel
    @AppStorage(DailyChallenge.storageKey) private var log = ""
    @State private var open = false
    var body: some View {
        let day = DailyChallenge.dayKey()
        let done = DailyChallenge.result(log, day: day)
        if let item = DailyChallenge.question(level: learnerLevel?.rawValue) {
            let subject = Subject(rawValue: item.subject) ?? .math
            Button { open = true } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(.white.opacity(0.22))
                        Image(systemName: done == nil ? "bolt.fill" : (done == true ? "checkmark" : "xmark"))
                            .font(.title2.bold())
                            .bounceSymbol(on: done)
                    }.frame(width: 54, height: 54)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("Sfida e ditës").font(.caption.bold()).opacity(0.9)
                            if DailyChallenge.streak(log) > 1 {
                                Text("🔥 \(DailyChallenge.streak(log))").font(.caption.bold())
                                    .padding(.horizontal, 6).padding(.vertical, 1).background(.white.opacity(0.25), in: Capsule())
                            }
                        }
                        Text(done == nil ? item.prompt : (done == true ? "E zgjidhe! +40 XP" : "Nesër një pyetje e re. +10 XP"))
                            .font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                        Text(subject.rawValue + " · e njëjta pyetje për të gjithë sot").font(.caption).opacity(0.85)
                    }
                    Spacer(minLength: 0)
                    if done == nil { Image(systemName: "chevron.right").font(.headline) }
                }
                .foregroundStyle(.white).padding(16)
                .background {
                    ZStack { subject.gradient; GlyphField(subject: subject, opacity: 0.14, tint: .white) }
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .shadow(color: subject.color.opacity(0.35), radius: 12, y: 6)
            }
            .buttonStyle(.springy)
            .sheet(isPresented: $open) {
                NavigationStack { DailyChallengeView(item: item, day: day) }
                    .macSheetFrame(minWidth: 460, minHeight: 600)
            }
        }
    }
}

struct DailyChallengeView: View {
    let item: Exercise
    let day: String
    @EnvironmentObject private var account: Account
    @AppStorage(DailyChallenge.storageKey) private var log = ""
    @StateObject private var model = LeaderboardModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let done = DailyChallenge.result(log, day: day)
        Page {
            HStack {
                Label("Sfida e ditës", systemImage: "bolt.fill").font(.title2.bold()).foregroundStyle(Color.lagoon)
                Spacer()
                Text(day).font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 4).glassCapsule()
            }
            if let done {
                GameOverCard(title: done ? "Saktë! 🎉" : "Jo këtë herë", score: done ? 40 : 10, unit: "XP",
                             celebrate: done, color: done ? .green : .orange) {
                    if let stats = model.daily, stats.answered > 0 {
                        Text("\(stats.correctPercent)% e \(stats.answered) nxënësve u përgjigjën saktë sot.").font(.headline).multilineTextAlignment(.center)
                    }
                    Text("🔥 \(DailyChallenge.streak(log)) ditë radhazi · \(DailyChallenge.correctCount(log)) sfida të zgjidhura").foregroundStyle(.secondary)
                    Button("Mbyll") { dismiss() }.buttonStyle(.liquidProminent)
                }
                SectionText(heading: "Shpjegimi", text: item.why + "\nPërgjigjja: " + item.answers.joined(separator: ", "))
            } else {
                Text("Një pyetje, një provë. E njëjta për të gjithë nxënësit sot.").foregroundStyle(.secondary)
                ExercisePlayer(item: item, advance: { correct in
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        log = DailyChallenge.recording(log, day: day, correct: correct)
                    }
                    if account.isOnline { Task { await model.answerDaily(day: day, correct: correct) } }
                })
            }
        }
        .navigationTitle("Sfida e ditës")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Mbyll") { dismiss() } } }
        .task { if account.isOnline && DailyChallenge.result(log, day: day) != nil { await model.loadDaily(day: day) } }
    }
}

// MARK: - Renditja

/// Karta te Krye: podiumi i javës dhe vendi yt.
struct LeaderboardCard: View {
    @EnvironmentObject private var account: Account
    @StateObject private var model = LeaderboardModel()
    private var stats = PlayerStats()
    @State private var open = false
    init() {}

    var body: some View {
        Button { open = true } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Renditja e javës", systemImage: "trophy.fill").font(.headline).foregroundStyle(Color.sun)
                        .symbolRenderingMode(.hierarchical)
                    Spacer()
                    Text("mbyllet pas \(LeaderboardModel.daysLeftInWeek) ditësh").font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
                if !account.isOnline {
                    Text("Renditja shfaqet kur je me llogari online.").font(.callout).foregroundStyle(.secondary)
                } else if !model.loaded {
                    HStack(spacing: 10) { ForEach(0..<3, id: \.self) { _ in Capsule().fill(Color.secondary.opacity(0.15)).frame(height: 54) } }
                        .redacted(reason: .placeholder)
                } else if model.rows.isEmpty {
                    Text("Bëhu i pari këtë javë! Mëso, zgjidh ushtrime dhe laboratorë për të fituar XP.").font(.callout).foregroundStyle(.secondary)
                } else {
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(model.rows.prefix(3)) { row in
                            VStack(spacing: 4) {
                                AvatarBadge(emoji: row.avatarEmoji, color: row.color, size: row.rank == 1 ? 46 : 38)
                                Text(row.displayName).font(.caption.bold()).lineLimit(1)
                                Text("\(row.xp) XP").font(.caption2).foregroundStyle(.secondary)
                                Text(["🥇", "🥈", "🥉"][min(row.rank, 3) - 1]).font(.title3)
                            }.frame(maxWidth: .infinity)
                        }
                    }
                    if let rank = model.myRank {
                        HStack {
                            Text("Ti je i \(rank)-ti").font(.subheadline.bold())
                            Spacer()
                            Text("\(model.myXP) XP këtë javë").font(.subheadline).foregroundStyle(Color.lagoon)
                        }
                        .padding(10).glass(cornerRadius: 14, tint: .lagoon, strength: 0.1)
                    }
                }
            }
            .padding(16).glass(cornerRadius: 24, interactive: true)
        }
        .buttonStyle(.springy)
        .task(id: account.isOnline) {
            guard account.isOnline else { return }
            await model.report(stats.xp)
            await model.load(all: false)
        }
        .sheet(isPresented: $open) {
            NavigationStack { LeaderboardView() }.macSheetFrame(minWidth: 460, minHeight: 640)
        }
    }
}

struct LeaderboardView: View {
    @EnvironmentObject private var account: Account
    @StateObject private var model = LeaderboardModel()
    private var stats = PlayerStats()
    @State private var allTime = false
    @Environment(\.dismiss) private var dismiss
    init() {}

    var body: some View {
        Page {
            Picker("Periudha", selection: $allTime) {
                Text("Këtë javë").tag(false)
                Text("Gjithë kohës").tag(true)
            }.pickerStyle(.segmented)
            if !allTime {
                Label("Java mbyllet pas \(LeaderboardModel.daysLeftInWeek) ditësh. E hëna nis nga zero.", systemImage: "clock")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !model.message.isEmpty { Text(model.message).foregroundStyle(.red) }
            if model.rows.count >= 1 { podium }
            ForEach(Array(model.rows.dropFirst(min(3, model.rows.count)).enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 12) {
                    Text("\(row.rank)").font(.headline.monospacedDigit()).frame(width: 32)
                    AvatarBadge(emoji: row.avatarEmoji, color: row.color, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.displayName + (row.me ? " (ti)" : "")).font(.headline)
                        Text("@" + row.username).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    CountingText(row.xp, format: { "\($0) XP" }).font(.subheadline.bold()).foregroundStyle(Color.lagoon)
                }
                .padding(12)
                .glass(cornerRadius: 18, tint: row.me ? .lagoon : nil, strength: row.me ? 0.18 : 0.18)
                .appearIn(index + 3)
            }
            if let rank = model.myRank, !model.rows.contains(where: { $0.me }) {
                HStack {
                    Text("Ti je i \(rank)-ti").font(.headline)
                    Spacer()
                    Text("\(model.myXP) XP").foregroundStyle(Color.lagoon)
                }.padding(12).glass(cornerRadius: 18, tint: .lagoon, strength: 0.18)
            }
            Text("Shfaqen vetëm nxënësit e pranuar në klasë, me username, emër dhe avatar. XP fitohen nga mësimet, ushtrimet, laboratorët dhe sfida e ditës.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .navigationTitle("Renditja")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Mbyll") { dismiss() } } }
        .refreshable { await model.report(stats.xp); await model.load(all: allTime) }
        .task(id: allTime) {
            guard account.isOnline else { return }
            await model.report(stats.xp)
            await model.load(all: allTime)
        }
    }

    /// Podiumi: i pari në mes, më i lartë; shtyllat ngrihen me animacion.
    private var podium: some View {
        let top = Array(model.rows.prefix(3))
        let order = top.count == 3 ? [top[1], top[0], top[2]] : top
        return HStack(alignment: .bottom, spacing: 10) {
            ForEach(order) { row in PodiumColumn(row: row) }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

private struct PodiumColumn: View {
    let row: LeaderRow
    @State private var raised = false
    var body: some View {
        let height: CGFloat = row.rank == 1 ? 120 : row.rank == 2 ? 90 : 70
        VStack(spacing: 6) {
            if row.rank == 1 { Image(systemName: "crown.fill").foregroundStyle(Color.sun).font(.title2).bounceSymbol(on: raised) }
            AvatarBadge(emoji: row.avatarEmoji, color: row.color, size: row.rank == 1 ? 64 : 52)
            Text(row.displayName + (row.me ? " (ti)" : "")).font(.caption.bold()).lineLimit(1)
            CountingText(raised ? row.xp : 0, format: { "\($0) XP" }).font(.caption2.bold()).foregroundStyle(Color.lagoon)
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [podiumColor, podiumColor.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                Text(["🥇", "🥈", "🥉"][min(row.rank, 3) - 1]).font(.title).padding(.top, 6)
            }
            .frame(height: raised ? height : 12)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(Double(3 - min(row.rank, 3)) * 0.12)) { raised = true }
        }
    }
    private var podiumColor: Color {
        switch row.rank {
        case 1: return Color.sun
        case 2: return Color(red: 0.75, green: 0.78, blue: 0.85)
        default: return Color(red: 0.85, green: 0.55, blue: 0.30)
        }
    }
}
