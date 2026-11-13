import Foundation

// Plani i përgatitjes për testin (#3, Matia). Rregulla të thjeshta e të kuptueshme, pa AI (kërkesat §7):
//  • Ditët e punës janë nga sot deri në ditën para testit.
//  • Mësimet e temës (më të përshtatshmet sipër, të palexuarat para të lexuarave) ndahen njëlloj në ditët e punës, deri 3 në ditë.
//  • Dita e fundit para testit lihet për përsëritje dhe test prove (kur ka të paktën 2 ditë).
//  • Testi nesër: përsëritje e mësimeve kryesore + test prove sot. Testi sot: vetëm përsëritje e shkurtër.
// Pa UI dhe pa rrjet, që të provohet në teste (si ScheduleWeek).

struct PlanLesson: Equatable {
    let id: String
    let title: String
    let read: Bool
}

struct PlanTask: Identifiable, Equatable {
    enum Kind: Equatable { case lesson(String), review, mockTest, practice }
    let id: String
    let kind: Kind
    let title: String
}

struct PlanDay: Identifiable, Equatable {
    let date: Date
    let tasks: [PlanTask]
    var id: Date { date }
}

enum StudyPlanner {
    static let maxLessonsPerDay = 3

    /// Ditët e plota nga sot deri në ditën e testit (0 = testi është sot).
    static func daysLeft(until exam: Date, now: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: now), end = calendar.startOfDay(for: exam)
        return max(calendar.dateComponents([.day], from: start, to: end).day ?? 0, 0)
    }

    static func plan(exam: Date, now: Date, lessons: [PlanLesson], subjectName: String, calendar: Calendar = .current) -> [PlanDay] {
        let today = calendar.startOfDay(for: now)
        let days = daysLeft(until: exam, now: now, calendar: calendar)
        let ordered = lessons.filter { !$0.read } + lessons.filter(\.read)
        let topic = subjectName.isEmpty ? "temës" : subjectName

        if days == 0 {
            return [PlanDay(date: today, tasks: [PlanTask(id: "review", kind: .review, title: "Përsërit shkurt përmbledhjet e \(topic) (10–15 min) dhe pusho")])]
        }
        if days == 1 {
            var tasks = ordered.prefix(2).map { PlanTask(id: "lesson-" + $0.id, kind: .lesson($0.id), title: "Përsërit «\($0.title)»") }
            if tasks.isEmpty { tasks.append(PlanTask(id: "review", kind: .review, title: "Përsërit mësimet e fundit të \(topic)")) }
            tasks.append(PlanTask(id: "mock", kind: .mockTest, title: "Bëj një test prove"))
            return [PlanDay(date: today, tasks: tasks)]
        }

        // Të paktën 2 ditë: ditët e leximit + dita e fundit për përsëritje.
        let readingDays = days - 1
        let chosen = Array(ordered.prefix(readingDays * maxLessonsPerDay))
        var result: [PlanDay] = []
        for index in 0..<readingDays {
            guard let date = calendar.date(byAdding: .day, value: index, to: today) else { continue }
            // Ndarje e barabartë: dita `index` merr pjesën e saj të listës.
            let from = chosen.count * index / readingDays, to = chosen.count * (index + 1) / readingDays
            var tasks = chosen[from..<to].map { PlanTask(id: "lesson-" + $0.id, kind: .lesson($0.id), title: ($0.read ? "Përsërit «" : "Lexo «") + $0.title + "» dhe bëj ushtrimin") }
            if tasks.isEmpty { tasks.append(PlanTask(id: "practice-\(index)", kind: .practice, title: "Ushtrime në \(topic) (20 min)")) }
            result.append(PlanDay(date: date, tasks: tasks))
        }
        if let last = calendar.date(byAdding: .day, value: readingDays, to: today) {
            result.append(PlanDay(date: last, tasks: [
                PlanTask(id: "review", kind: .review, title: "Përsërit përmbledhjet dhe gabimet e zakonshme"),
                PlanTask(id: "mock", kind: .mockTest, title: "Bëj një test prove dhe shiko ku gabove"),
            ]))
        }
        return result
    }

    /// A duket ky event si test/provim (kur mësuesi s'e ka lidhur me një test në app)?
    static func looksLikeExam(_ title: String) -> Bool {
        let t = title.lowercased()
        return ["test", "provim", "kontroll", "kuiz", "detyrë klase", "pyetësor"].contains { t.contains($0) }
    }
}
