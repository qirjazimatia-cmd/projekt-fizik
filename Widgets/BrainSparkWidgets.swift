import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// BrainSpark · Widget-et (Juri)
// 1. «Sfida e ditës»: e njëjta pyetje si te app-i (e njëjta zgjedhje sipas datës dhe klasës), në ekranin kryesor dhe të kyçur.
//    Widget-i lexon pyetjet nga Exercises.json brenda vetes; nuk ka nevojë për App Groups (që kërkojnë llogari me pagesë).
// 2. Live Activity: ora e mësimit dhe kohëmatësi i fokusit (te Dynamic Island dhe ekrani i kyçur).

@main
struct BrainSparkWidgets: WidgetBundle {
    var body: some Widget {
        DailyChallengeWidget()
        BrainSparkLiveActivity()
    }
}

// MARK: - Ngjyrat (si te app-i)

private enum Palette {
    static func colors(_ index: Int) -> [Color] {
        switch index {
        case 1: return [Color(red: 0.62, green: 0.12, blue: 0.47), Color(red: 0.33, green: 0.05, blue: 0.42)]
        case 2: return [Color(red: 0.13, green: 0.32, blue: 0.86), Color(red: 0.05, green: 0.10, blue: 0.40)]
        case 3: return [Color(red: 0.78, green: 0.29, blue: 0.05), Color(red: 0.55, green: 0.08, blue: 0.10)]
        case 4: return [Color(red: 0.11, green: 0.50, blue: 0.24), Color(red: 0.02, green: 0.30, blue: 0.30)]
        case 5: return [Color(red: 0.55, green: 0.30, blue: 0.95), Color(red: 0.85, green: 0.25, blue: 0.60)]
        default: return [Color(red: 0.32, green: 0.22, blue: 0.74), Color(red: 0.08, green: 0.07, blue: 0.19)]
        }
    }
    static func index(subject: String) -> Int {
        let lower = subject.lowercased()
        if lower.contains("mat") { return 1 }
        if lower.contains("fiz") { return 2 }
        if lower.contains("kim") { return 3 }
        if lower.contains("bio") { return 4 }
        return 0
    }
    static func symbol(subject: String) -> String {
        switch index(subject: subject) {
        case 1: return "function"
        case 2: return "atom"
        case 3: return "testtube.2"
        case 4: return "leaf.fill"
        default: return "bolt.fill"
        }
    }
}

// MARK: - Sfida e ditës

/// Klasa e nxënësit (widget-i s'mund ta lexojë nga app-i pa App Groups, prandaj zgjidhet te «Ndrysho widget-in»).
enum WidgetLevel: Int, AppEnum {
    case basic = 1, first, second, third, olympiad
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Klasa"
    static var caseDisplayRepresentations: [WidgetLevel: DisplayRepresentation] = [
        .basic: "Shkollë 9-vjeçare", .first: "Gjimnaz · Viti I", .second: "Gjimnaz · Viti II",
        .third: "Gjimnaz · Viti III", .olympiad: "Olimpiadë",
    ]
}

struct DailyChallengeIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Sfida e ditës"
    static var description = IntentDescription("Pyetja e ditës nga BrainSpark, e njëjta për të gjithë nxënësit e klasës.")
    @Parameter(title: "Klasa", default: .basic) var level: WidgetLevel
}

private struct WidgetExercise: Decodable {
    let id: String
    let subject: String
    let kind: String
    let prompt: String
    let choices: [String]
    let level: Int

    static let all: [WidgetExercise] = {
        guard let url = Bundle.main.url(forResource: "Exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([WidgetExercise].self, from: data) else { return [] }
        return items
    }()

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Tirane") ?? .current
        return calendar
    }
    /// E njëjta zgjedhje si `DailyChallenge.question` te app-i.
    static func question(level: Int, date: Date) -> WidgetExercise? {
        let pool = all.filter { $0.kind == "select" && $0.choices.count >= 2 && $0.level == level }.sorted { $0.id < $1.id }
        guard !pool.isEmpty else { return nil }
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return pool[(day &* 7919) % pool.count]
    }
}

struct DailyEntry: TimelineEntry {
    let date: Date
    let subject: String
    let prompt: String
    let choices: [String]
}

struct DailyProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DailyEntry {
        DailyEntry(date: Date(), subject: "Fizikë", prompt: "Cila është njësia e forcës?", choices: ["Njuton", "Xhaul", "Vat"])
    }
    func snapshot(for configuration: DailyChallengeIntent, in context: Context) async -> DailyEntry {
        entry(for: configuration, date: Date())
    }
    func timeline(for configuration: DailyChallengeIntent, in context: Context) async -> Timeline<DailyEntry> {
        let now = Date()
        let calendar = WidgetExercise.calendar
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        return Timeline(entries: [entry(for: configuration, date: now), entry(for: configuration, date: tomorrow)], policy: .atEnd)
    }
    private func entry(for configuration: DailyChallengeIntent, date: Date) -> DailyEntry {
        guard let item = WidgetExercise.question(level: configuration.level.rawValue, date: date) else {
            return DailyEntry(date: date, subject: "BrainSpark", prompt: "Hap app-in për sfidën e ditës.", choices: [])
        }
        return DailyEntry(date: date, subject: item.subject, prompt: item.prompt, choices: Array(item.choices.prefix(3)))
    }
}

struct DailyChallengeView: View {
    let entry: DailyEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let index = Palette.index(subject: entry.subject)
        switch family {
        case .accessoryInline:
            Label("Sfida e ditës: " + entry.subject, systemImage: "bolt.fill")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("Sfida e ditës", systemImage: "bolt.fill").font(.caption2.bold())
                Text(entry.prompt).font(.caption).lineLimit(3)
            }
            .containerBackground(for: .widget) { Color.clear }
        default:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: Palette.symbol(subject: entry.subject))
                    Text("Sfida e ditës").font(.caption.bold())
                    Spacer()
                    Image(systemName: "bolt.fill").foregroundStyle(.yellow)
                }
                Text(entry.prompt)
                    .font(family == .systemSmall ? .footnote.bold() : .headline)
                    .lineLimit(family == .systemSmall ? 4 : 3)
                    .minimumScaleFactor(0.8)
                if family != .systemSmall {
                    HStack(spacing: 6) {
                        ForEach(entry.choices, id: \.self) { choice in
                            Text(choice).font(.caption.bold()).lineLimit(1)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(.white.opacity(0.22), in: Capsule())
                        }
                    }
                }
                Spacer(minLength: 0)
                Text(entry.subject + " · prek për t'u përgjigjur").font(.caption2).opacity(0.85)
            }
            .foregroundStyle(.white)
            .containerBackground(for: .widget) {
                ZStack {
                    LinearGradient(colors: Palette.colors(index), startPoint: .topLeading, endPoint: .bottomTrailing)
                    // Shkëlqim xhami lart.
                    LinearGradient(colors: [.white.opacity(0.25), .clear], startPoint: .top, endPoint: .center)
                }
            }
        }
    }
}

struct DailyChallengeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "BrainSparkDailyChallenge", intent: DailyChallengeIntent.self, provider: DailyProvider()) { entry in
            DailyChallengeView(entry: entry)
        }
        .configurationDisplayName("Sfida e ditës")
        .description("Një pyetje e re çdo ditë nga BrainSpark. Zgjidh klasën te «Ndrysho widget-in».")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Live Activity

struct BrainSparkLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BrainSparkActivity.self) { context in
            LockScreenActivity(state: context.state)
                .activityBackgroundTint(Palette.colors(context.state.colorIndex)[1].opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            let tint = Palette.colors(state.colorIndex)[0]
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: state.symbol).font(.title2).foregroundStyle(tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: state.start...state.end, countsDown: true)
                        .font(.title3.monospacedDigit().bold()).foregroundStyle(tint)
                        .frame(maxWidth: 80).multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.title).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(state.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        ProgressView(timerInterval: state.start...state.end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                            .tint(tint)
                    }
                }
            } compactLeading: {
                Image(systemName: state.symbol).foregroundStyle(tint)
            } compactTrailing: {
                Text(timerInterval: state.start...state.end, countsDown: true)
                    .monospacedDigit().frame(maxWidth: 46).foregroundStyle(tint)
            } minimal: {
                Image(systemName: state.symbol).foregroundStyle(tint)
            }
        }
    }
}

private struct LockScreenActivity: View {
    let state: BrainSparkActivity.ContentState
    var body: some View {
        let colors = Palette.colors(state.colorIndex)
        HStack(spacing: 14) {
            Image(systemName: state.symbol)
                .font(.title2.bold()).foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(state.title).font(.headline).foregroundStyle(.white)
                    Spacer()
                    Text(timerInterval: state.start...state.end, countsDown: true)
                        .font(.headline.monospacedDigit()).foregroundStyle(.white)
                        .multilineTextAlignment(.trailing)
                }
                Text(state.subtitle).font(.caption).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                ProgressView(timerInterval: state.start...state.end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .tint(.white)
            }
        }
        .padding(16)
    }
}
