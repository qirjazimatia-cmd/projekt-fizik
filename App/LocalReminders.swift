import SwiftUI
import UserNotifications

/// Njoftimet në pajisje për testet, detyrat dhe eventet e klasës (#5). Nuk kërkojnë llogari me pagesë te Apple
/// as server: planifikohen nga kalendari i shkollës sa herë rifreskohet. Njoftimet push nga serveri vijnë më vonë.
@MainActor
enum LocalReminders {
    static let enabledKey = "reminders.enabled.v1"
    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    /// Kërkon lejen (vetëm herën e parë) dhe rindërton njoftimet nga eventet e reja.
    static func sync(_ snapshot: SchoolSnapshot) async {
        let center = UNUserNotificationCenter.current()
        let existing = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("brainspark.") && !$0.hasPrefix(ScheduleReminders.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: existing)
        guard enabled else { return }
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            guard (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true else { return }
        } else if settings.authorizationStatus == .denied {
            return
        }
        let events = snapshot.events.map {
            ReminderEvent(id: $0.id, title: $0.title, note: $0.note, date: Date(timeIntervalSince1970: $0.date),
                          isExam: $0.examID != nil, subject: $0.subject)
        }
        for reminder in ReminderPlanner.plan(events, now: Date()) {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.threadIdentifier = reminder.kind.thread
            content.relevanceScore = reminder.kind.relevance
            content.sound = reminder.kind == .info ? nil : .default
            #if os(iOS)
            content.interruptionLevel = reminder.kind == .info ? .passive : .active
            #endif
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fire)
            let request = UNNotificationRequest(identifier: "brainspark." + reminder.id, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
            try? await center.add(request)
        }
    }

    static func disable() async {
        UserDefaults.standard.set(false, forKey: enabledKey)
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("brainspark.") && !$0.hasPrefix(ScheduleReminders.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}

/// Çelësi i njoftimeve te Profili.
struct ReminderSettings: View {
    @AppStorage(LocalReminders.enabledKey) private var enabled = true
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Njoftimet për testet, detyrat dhe eventet", isOn: $enabled)
                .onChange(of: enabled) { on in if !on { Task { await LocalReminders.disable() } } }
            Text("Testet: 3 ditë para, një ditë para dhe në mëngjes. Detyrat: një ditë para dhe në mëngjes. Njoftimet e tjera: në mëngjes, pa zë. Grupohen sipas llojit.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
