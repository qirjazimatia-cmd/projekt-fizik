import Foundation

/// Orari javor i klasës (pa UI dhe pa rrjet), që të provohet në teste.
struct ScheduleSlot: Decodable, Identifiable, Equatable {
    let id: String
    let classID: String
    let className: String
    let weekday: Int          // 1 = e hënë ... 7 = e diel (ISO)
    let starts: String        // "08:00"
    let ends: String
    let subject: String
    let room: String
    let mine: Bool

    var startMinutes: Int { ScheduleWeek.minutes(starts) ?? 0 }
    var endMinutes: Int { ScheduleWeek.minutes(ends) ?? 0 }
}
struct ScheduleReply: Decodable { let slots: [ScheduleSlot] }

enum ScheduleWeek {
    static let dayNames = ["E hënë", "E martë", "E mërkurë", "E enjte", "E premte", "E shtunë", "E diel"]

    static func minutes(_ text: String) -> Int? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return parts[0] * 60 + parts[1]
    }
    /// Dita ISO (1 = e hënë) e një date.
    static func isoWeekday(_ date: Date, calendar: Calendar = .current) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7 + 1
    }
    /// Dita e Calendar-it (1 = e diel) nga dita ISO.
    static func calendarWeekday(_ iso: Int) -> Int { iso % 7 + 1 }

    /// Ora që po zhvillohet tani dhe ora e radhës sot.
    static func now(_ slots: [ScheduleSlot], at date: Date, calendar: Calendar = .current) -> (current: ScheduleSlot?, next: ScheduleSlot?) {
        let day = isoWeekday(date, calendar: calendar)
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let today = slots.filter { $0.weekday == day }.sorted { $0.startMinutes < $1.startMinutes }
        return (today.first { $0.startMinutes <= m && m < $0.endMinutes }, today.first { $0.startMinutes > m })
    }

    /// Njoftimi javor `minutesBefore` minuta para orës: (dita e Calendar-it, ora, minuta).
    static func reminderTime(_ slot: ScheduleSlot, minutesBefore: Int) -> (weekday: Int, hour: Int, minute: Int) {
        var total = slot.startMinutes - minutesBefore
        var iso = slot.weekday
        if total < 0 { total += 24 * 60; iso = iso == 1 ? 7 : iso - 1 }
        return (calendarWeekday(iso), total / 60, total % 60)
    }
}
