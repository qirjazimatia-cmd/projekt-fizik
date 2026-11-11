import SwiftUI
import Charts

/// Pamja vizuale e progresit të nxënësit: seria e ditëve, grafiku i 7 ditëve, saktësia dhe progresi sipas lëndëve.
struct ProgressDashboard: View {
    let level: SchoolLevel?
    @AppStorage(ActivityLog.storageKey) private var activity = ""
    @AppStorage("mastered") private var mastered = ""

    private var days: [String: ActivityDay] { ActivityLog.decode(activity) }
    private var week: [ActivityEntry] { ActivityLog.lastDays(7, days) }
    private var weekAnswers: Int { week.reduce(0) { $0 + $1.day.answers } }
    private var weekCorrect: Int { week.reduce(0) { $0 + $1.day.correct } }
    private var weekLessons: Int { week.reduce(0) { $0 + $1.day.lessons } }
    private var solvedIDs: Set<String> { Set(mastered.split(separator: "|").map(String.init)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Përparimi im").font(.title2.bold())
            HStack(spacing: 10) {
                stat(value: "\(ActivityLog.streak(days))", label: "ditë radhazi", icon: "flame.fill", color: .orange)
                stat(value: "\(weekAnswers)", label: "ushtrime këtë javë", icon: "checkmark.seal.fill", color: .lagoon)
                stat(value: weekAnswers == 0 ? "–" : "\(Int((Double(weekCorrect) / Double(weekAnswers) * 100).rounded()))%", label: "saktësia", icon: "target", color: .green)
                stat(value: "\(weekLessons)", label: "mësime të lexuara", icon: "book.fill", color: .purple)
            }
            Chart {
                ForEach(week) { entry in
                    BarMark(x: .value("Dita", entry.date, unit: .day), y: .value("Ushtrime", entry.day.correct))
                        .foregroundStyle(by: .value("Lloji", "Të sakta"))
                    BarMark(x: .value("Dita", entry.date, unit: .day), y: .value("Ushtrime", entry.day.answers - entry.day.correct))
                        .foregroundStyle(by: .value("Lloji", "Të gabuara"))
                    BarMark(x: .value("Dita", entry.date, unit: .day), y: .value("Ushtrime", entry.day.lessons))
                        .foregroundStyle(by: .value("Lloji", "Mësime"))
                }
            }
            .chartForegroundStyleScale(["Të sakta": Color.green, "Të gabuara": Color.orange.opacity(0.75), "Mësime": Color.purple.opacity(0.7)])
            .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
            .frame(height: 160)
            .accessibilityLabel("Aktiviteti i 7 ditëve të fundit: \(weekAnswers) ushtrime dhe \(weekLessons) mësime.")
            if let level {
                ForEach(Subject.allCases) { subject in
                    let group = Exercise.all.filter { $0.subject == subject.rawValue && $0.level == level.rawValue }
                    let done = group.filter { solvedIDs.contains($0.id) }.count
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(subject.rawValue, systemImage: subject.icon).font(.subheadline.bold())
                            Spacer()
                            Text("\(done)/\(group.count)").font(.caption).foregroundStyle(.secondary)
                        }
                        ProgressView(value: Double(done), total: Double(max(group.count, 1))).tint(.lagoon)
                    }
                }
            }
            Text(motivation).font(.footnote).foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private var motivation: String {
        let streak = ActivityLog.streak(days)
        if streak == 0 { return "Fillo sot një seri të re: mjafton një ushtrim ose një mësim." }
        if (days[ActivityLog.dayKey(Date())]?.total ?? 0) == 0 { return "Seria jote prej \(streak) ditësh pret: bëj një ushtrim sot që të mos ndërpritet." }
        return "Bravo! \(streak) ditë radhazi. Vazhdo kështu."
    }

    private func stat(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).foregroundStyle(color)
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}
