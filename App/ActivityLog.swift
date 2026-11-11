import Foundation

/// Ditari i aktivitetit të nxënësit, ditë pas dite (për grafikët dhe serinë e ditëve).
/// Ruhet si JSON te çelësi "studyActivity.v1" i llogarisë (sinkronizohet bashkë me progresin "study…").
struct ActivityDay: Codable, Equatable {
    var answers = 0
    var correct = 0
    var lessons = 0
    var total: Int { answers + lessons }
}

struct ActivityEntry: Identifiable, Equatable {
    let date: Date
    let day: ActivityDay
    var id: Date { date }
}

enum ActivityLog {
    static let storageKey = "studyActivity.v1"

    static func decode(_ raw: String) -> [String: ActivityDay] {
        guard let data = raw.data(using: .utf8), let days = try? JSONDecoder().decode([String: ActivityDay].self, from: data) else { return [:] }
        return days
    }
    static func encode(_ days: [String: ActivityDay]) -> String {
        // Mbajmë vetëm 400 ditët e fundit, që vlera të mbetet e vogël.
        let kept = Dictionary(uniqueKeysWithValues: days.sorted { $0.key > $1.key }.prefix(400).map { ($0.key, $0.value) })
        guard let data = try? JSONEncoder().encode(kept) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func recordingAnswer(_ raw: String, correct: Bool, at date: Date = Date(), calendar: Calendar = .current) -> String {
        var days = decode(raw); let key = dayKey(date, calendar: calendar)
        days[key, default: ActivityDay()].answers += 1
        if correct { days[key, default: ActivityDay()].correct += 1 }
        return encode(days)
    }
    static func recordingLesson(_ raw: String, at date: Date = Date(), calendar: Calendar = .current) -> String {
        var days = decode(raw)
        days[dayKey(date, calendar: calendar), default: ActivityDay()].lessons += 1
        return encode(days)
    }

    /// Ditët radhazi me aktivitet, që mbarojnë sot (ose dje, nëse sot s'ka ende aktivitet).
    static func streak(_ days: [String: ActivityDay], today: Date = Date(), calendar: Calendar = .current) -> Int {
        var day = calendar.startOfDay(for: today)
        if (days[dayKey(day, calendar: calendar)]?.total ?? 0) == 0 {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while (days[dayKey(day, calendar: calendar)]?.total ?? 0) > 0 {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    /// N ditët e fundit (më e vjetra e para), me ditë bosh kur s'ka aktivitet.
    static func lastDays(_ n: Int, _ days: [String: ActivityDay], today: Date = Date(), calendar: Calendar = .current) -> [ActivityEntry] {
        let start = calendar.startOfDay(for: today)
        return (0..<n).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: start) else { return nil }
            return ActivityEntry(date: date, day: days[dayKey(date, calendar: calendar)] ?? ActivityDay())
        }
    }
}
