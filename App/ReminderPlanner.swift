import Foundation

/// Njoftimet e grupuara sipas rëndësisë (#5). Kjo pjesë vetëm planifikon (pa UserNotifications), që të provohet në teste.
enum ReminderKind: String, CaseIterable {
    case test, task, info

    /// Grupi në Qendrën e Njoftimeve: njoftimet e të njëjtit lloj mblidhen bashkë.
    var thread: String { "brainspark." + rawValue }
    var label: String {
        switch self {
        case .test: return "Test"
        case .task: return "Detyrë"
        case .info: return "Njoftim"
        }
    }
    /// 1 = më e rëndësishmja; sistemi i rendit njoftimet sipas këtij numri.
    var relevance: Double {
        switch self {
        case .test: return 1.0
        case .task: return 0.7
        case .info: return 0.3
        }
    }
}

struct ReminderEvent {
    let id: String
    let title: String
    let note: String
    let date: Date
    let isExam: Bool
    let subject: String?

    var kind: ReminderKind {
        if isExam { return .test }
        let text = (title + " " + note).lowercased()
        if ["test", "provim", "kontroll", "kuiz"].contains(where: { text.contains($0) }) { return .test }
        if ["detyr", "projekt", "dorëzim", "dorezim", "ese", "raport"].contains(where: { text.contains($0) }) { return .task }
        return .info
    }
}

struct PlannedReminder: Equatable {
    let id: String
    let kind: ReminderKind
    let title: String
    let body: String
    let fire: Date
}

enum ReminderPlanner {
    /// Sa njoftime planifikohen për çdo lloj ngjarjeje:
    /// test: 3 ditë para (18:00), një ditë para (18:00) dhe në mëngjes (07:30);
    /// detyrë: një ditë para (18:00) dhe në mëngjes (07:30); njoftim: vetëm në mëngjes (07:30).
    static func plan(_ events: [ReminderEvent], now: Date, calendar: Calendar = .current, limit: Int = 60) -> [PlannedReminder] {
        var result: [PlannedReminder] = []
        for event in events where event.date > now {
            let kind = event.kind
            let day = calendar.startOfDay(for: event.date)
            func at(_ daysBefore: Int, _ hour: Int, _ minute: Int) -> Date? {
                guard let base = calendar.date(byAdding: .day, value: -daysBefore, to: day) else { return nil }
                return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base)
            }
            let subject = event.subject.map { " · " + $0 } ?? ""
            var slots: [(String, Date?, String)] = []
            switch kind {
            case .test:
                slots = [("3d", at(3, 18, 0), "Pas 3 ditësh: " + event.title + subject + ". Fillo përsëritjen sot, pak nga pak."),
                         ("1d", at(1, 18, 0), "Nesër: " + event.title + subject + ". Një përsëritje e shkurtër dhe gjumë i mirë."),
                         ("0d", at(0, 7, 30), "Sot: " + event.title + subject + ". Suksese!")]
            case .task:
                slots = [("1d", at(1, 18, 0), "Nesër dorëzohet: " + event.title + subject + "."),
                         ("0d", at(0, 7, 30), "Sot: " + event.title + subject + ".")]
            case .info:
                slots = [("0d", at(0, 7, 30), event.title + subject + (event.note.isEmpty ? "" : " — " + event.note))]
            }
            for (tag, date, body) in slots {
                guard let date, date > now, date < event.date.addingTimeInterval(60) else { continue }
                result.append(PlannedReminder(id: "\(event.id)-\(tag)", kind: kind, title: kind.label, body: body, fire: date))
            }
        }
        // iOS lejon deri në 64 njoftime të planifikuara: mbajmë më të rëndësishmet dhe më të afërtat.
        return Array(result.sorted { ($0.fire, -$0.kind.relevance) < ($1.fire, -$1.kind.relevance) }.prefix(limit))
    }
}
