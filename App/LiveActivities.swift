import SwiftUI
#if os(iOS)
import ActivityKit
#endif

// Live Activity (Juri): ora e mësimit që po zhvillohet (ose fillon brenda 15 minutave) dhe kohëmatësi i fokusit,
// në ekranin e kyçur dhe te Dynamic Island. Të dhënat i jep vetë app-i, kështu që nuk nevojitet llogari me pagesë.
// Pamja e Live Activity është te Widgets/BrainSparkWidgets.swift.

enum LiveActivities {
    static func colorIndex(for subject: String) -> Int {
        let lower = subject.lowercased()
        if lower.contains("mat") { return 1 }
        if lower.contains("fiz") { return 2 }
        if lower.contains("kim") { return 3 }
        if lower.contains("bio") { return 4 }
        return 0
    }

    /// Ora e sotme që po zhvillohet, ose që fillon brenda 15 minutave.
    static func relevantSlot(_ slots: [ScheduleSlot], now: Date = Date(), calendar: Calendar = .current) -> (ScheduleSlot, Date, Date)? {
        let weekday = ScheduleWeek.isoWeekday(now, calendar: calendar)
        let startOfDay = calendar.startOfDay(for: now)
        for slot in slots.filter({ $0.weekday == weekday }).sorted(by: { $0.startMinutes < $1.startMinutes }) {
            guard let start = calendar.date(byAdding: .minute, value: slot.startMinutes, to: startOfDay),
                  let end = calendar.date(byAdding: .minute, value: slot.endMinutes, to: startOfDay) else { continue }
            if now < end && now >= start.addingTimeInterval(-15 * 60) { return (slot, start, end) }
        }
        return nil
    }

    #if os(iOS)
    @available(iOS 16.2, *)
    private static func activities(_ kind: String) -> [ActivityKit.Activity<BrainSparkActivity>] {
        ActivityKit.Activity<BrainSparkActivity>.activities.filter { $0.attributes.kind == kind }
    }

    /// Fillon, përditëson ose mbyll Live Activity e orës së mësimit sipas orarit.
    static func syncClass(_ slots: [ScheduleSlot]) async {
        guard #available(iOS 16.2, *), ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let (slot, start, end) = relevantSlot(slots) else {
            for activity in activities("class") { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }
        let room = slot.room.isEmpty ? "" : " · salla \(slot.room)"
        let state = BrainSparkActivity.ContentState(title: slot.subject, subtitle: slot.className + room,
                                                    start: start, end: end, symbol: "graduationcap.fill",
                                                    colorIndex: colorIndex(for: slot.subject))
        let content = ActivityContent(state: state, staleDate: end)
        if let current = activities("class").first {
            if current.content.state != state { await current.update(content) }
        } else {
            _ = try? ActivityKit.Activity.request(attributes: BrainSparkActivity(kind: "class"), content: content, pushType: nil)
        }
    }

    static var focusRunning: Bool {
        guard #available(iOS 16.2, *) else { return false }
        return activities("focus").contains { $0.activityState == .active }
    }

    static func startFocus(minutes: Int) {
        guard #available(iOS 16.2, *), ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let now = Date()
        let state = BrainSparkActivity.ContentState(title: "Fokus", subtitle: "Mëso pa shpërqendrime · \(minutes) min",
                                                    start: now, end: now.addingTimeInterval(Double(minutes) * 60),
                                                    symbol: "brain.head.profile", colorIndex: 5)
        _ = try? ActivityKit.Activity.request(attributes: BrainSparkActivity(kind: "focus"),
                                  content: ActivityContent(state: state, staleDate: state.end), pushType: nil)
    }

    static func stopFocus() async {
        guard #available(iOS 16.2, *) else { return }
        for activity in activities("focus") { await activity.end(nil, dismissalPolicy: .immediate) }
    }
    #else
    static func syncClass(_ slots: [ScheduleSlot]) async {}
    static var focusRunning: Bool { false }
    static func startFocus(minutes: Int) {}
    static func stopFocus() async {}
    #endif
}

/// E vendosur te Dashboard: kur app-i hapet ose kthehet në plan të parë, rifreskon Live Activity e orës së mësimit.
struct LiveActivitySync: ViewModifier {
    @EnvironmentObject private var account: Account
    @Environment(\.scenePhase) private var phase
    func body(content: Content) -> some View {
        content
            .task(id: account.isOnline) { await refresh() }
            .onChange(of: phase) { value in if value == .active { Task { await refresh() } } }
    }
    private func refresh() async {
        guard account.isOnline else { return }
        guard let reply: ScheduleReply = try? await SchoolAPI.call("scheduleGet") else { return }
        await LiveActivities.syncClass(reply.slots)
    }
}

/// Kohëmatësi i fokusit te Krye: 25 minuta mësim; numërimi shfaqet edhe në ekranin e kyçur / Dynamic Island.
struct FocusTimerCard: View {
    @AppStorage("focus.endsAt.v1", store: .standard) private var endsAt: Double = 0
    @State private var minutes = 25
    var body: some View {
        let running = endsAt > Date().timeIntervalSince1970
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.lagoon.opacity(0.15))
                Image(systemName: running ? "timer" : "brain.head.profile").font(.title2).foregroundStyle(Color.lagoon)
                    .pulsingSymbol(running)
            }.frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 2) {
                Text(running ? "Fokus" : "Kohëmatësi i fokusit").font(.headline)
                if running {
                    Text(timerInterval: Date()...Date(timeIntervalSince1970: endsAt), countsDown: true)
                        .font(.title3.monospacedDigit().bold()).foregroundStyle(Color.lagoon)
                } else {
                    Text("\(minutes) min mësim pa shpërqendrime. Numërimi del edhe në ekranin e kyçur.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if running {
                Button("Ndalo") {
                    withAnimation(.spring()) { endsAt = 0 }
                    Task { await LiveActivities.stopFocus() }
                }.buttonStyle(.liquid)
            } else {
                Menu {
                    ForEach([15, 25, 45], id: \.self) { value in
                        Button("\(value) minuta") { start(value) }
                    }
                } label: { Text("Fillo").font(.headline) } primaryAction: { start(minutes) }
                .menuStyle(.button).buttonStyle(.liquidProminent)
            }
        }
        .padding(14).glass(cornerRadius: 22)
    }
    private func start(_ value: Int) {
        minutes = value
        Haptics.success()
        withAnimation(.spring()) { endsAt = Date().addingTimeInterval(Double(value) * 60).timeIntervalSince1970 }
        Task { await LiveActivities.stopFocus(); LiveActivities.startFocus(minutes: value) }
    }
}
