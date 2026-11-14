import SwiftUI

// XP, nivelet, medaljet, avatari dhe ngjyra e preferuar (kërkesa e Juri-t).
// XP-të llogariten nga ajo që app-i ruan tashmë (mësime të lexuara, ushtrime, laboratorë, ditë radhazi),
// prandaj nuk ka mënyrë për t'i «fryrë» dy herë dhe nuk duhet server. Ruhen në këtë pajisje, për çdo llogari.

/// Të dhënat e nxënësit që nevojiten për XP dhe medaljet (lexohen direkt nga ruajtja e app-it).
struct PlayerStats: DynamicProperty {
    @AppStorage("studyReadIDs.v1") var readIDs = ""
    @AppStorage("studyPassedIDs.v1") var passedIDs = ""
    @AppStorage("mastered") var mastered = ""
    @AppStorage("labMissions") var labMissions = ""
    @AppStorage("labStars.v1") var labStars = ""
    @AppStorage("labPredictions.v1") var predictions = 0
    @AppStorage("studyActivity.v1") var activity = ""
    @AppStorage("daily.v1") var daily = ""

    private func count(_ list: String) -> Int { Set(list.split(separator: "|").filter { !$0.isEmpty }).count }
    var lessonsRead: Int { count(readIDs) }
    var checksPassed: Int { count(passedIDs) }
    var exercisesMastered: Int { count(mastered) }
    var labsDone: Int { count(labMissions) }
    var labStarTotal: Int { labStars.split(separator: "|").compactMap { $0.split(separator: ":").last.flatMap { Int($0) } }.reduce(0, +) }
    var streak: Int { ActivityLog.streak(ActivityLog.decode(activity)) }
    var activeDays: Int { ActivityLog.decode(activity).count }
    var answers: Int { ActivityLog.decode(activity).values.reduce(0) { $0 + $1.answers } }

    var xp: Int {
        lessonsRead * 20 + checksPassed * 15 + exercisesMastered * 10 + labsDone * 30 + labStarTotal * 10
            + predictions * 5 + activeDays * 25 + min(answers, 2000) * 2
            + DailyChallenge.correctCount(daily) * 40 + (DailyChallenge.answeredCount(daily) - DailyChallenge.correctCount(daily)) * 10
    }
    var level: PlayerLevel { PlayerLevel(xp: xp) }
}

/// Niveli: çdo nivel kërkon 100 XP më shumë se i mëparshmi (100, 200, 300...).
struct PlayerLevel: Equatable {
    let number: Int
    let xpIntoLevel: Int
    let xpForLevel: Int
    init(xp: Int) {
        var level = 1, need = 100, left = max(0, xp)
        while left >= need { left -= need; level += 1; need = level * 100 }
        number = level; xpIntoLevel = left; xpForLevel = need
    }
    var progress: Double { Double(xpIntoLevel) / Double(xpForLevel) }
    var title: String {
        switch number {
        case 1...2: return "Fillestar"
        case 3...4: return "Kureshtar"
        case 5...7: return "Eksplorues"
        case 8...11: return "Shkencëtar"
        case 12...16: return "Ekspert"
        default: return "Gjeni ✨"
        }
    }
}

struct Badge: Identifiable, Equatable {
    let id: String
    let emoji: String
    let title: String
    let detail: String
    let earned: Bool
}

extension PlayerStats {
    var badges: [Badge] {
        [
            Badge(id: "first-lesson", emoji: "📖", title: "Hapi i parë", detail: "Lexo mësimin e parë", earned: lessonsRead >= 1),
            Badge(id: "reader-25", emoji: "📚", title: "Lexues i zellshëm", detail: "Lexo 25 mësime", earned: lessonsRead >= 25),
            Badge(id: "reader-100", emoji: "🏛️", title: "Biblioteka ime", detail: "Lexo 100 mësime", earned: lessonsRead >= 100),
            Badge(id: "exercise-10", emoji: "✏️", title: "Zgjidhës", detail: "Zgjidh saktë 10 ushtrime", earned: exercisesMastered >= 10),
            Badge(id: "exercise-50", emoji: "🧮", title: "Makinë ushtrimesh", detail: "Zgjidh saktë 50 ushtrime", earned: exercisesMastered >= 50),
            Badge(id: "lab-1", emoji: "🧪", title: "Laboranti", detail: "Përfundo misionin e parë në laborator", earned: labsDone >= 1),
            Badge(id: "lab-10", emoji: "🔬", title: "10 laboratorë", detail: "Përfundo 10 misione laboratori", earned: labsDone >= 10),
            Badge(id: "stars-30", emoji: "🌟", title: "Yjet e laboratorit", detail: "Mblidh 30 yje në laboratorë", earned: labStarTotal >= 30),
            Badge(id: "prophet", emoji: "🔮", title: "Parashikuesi", detail: "Bëj 10 parashikime të sakta", earned: predictions >= 10),
            Badge(id: "streak-3", emoji: "🔥", title: "3 ditë radhazi", detail: "Mëso 3 ditë pa ndërprerje", earned: streak >= 3),
            Badge(id: "streak-7", emoji: "⚡️", title: "Java e plotë", detail: "Mëso 7 ditë radhazi", earned: streak >= 7),
            Badge(id: "level-5", emoji: "🚀", title: "Niveli 5", detail: "Arrij nivelin 5", earned: level.number >= 5),
            Badge(id: "daily-7", emoji: "⚡", title: "7 sfida të ditës", detail: "Zgjidh saktë 7 sfida të ditës", earned: DailyChallenge.correctCount(daily) >= 7),
        ]
    }
}

/// Avatari i profilit (emoji + ngjyrë + emër i shkurtër), për çdo llogari.
struct AvatarStore: DynamicProperty {
    @AppStorage("avatar.emoji.v1") var emoji = "🦊"
    @AppStorage("avatar.color.v1") var colorIndex = 0
    @AppStorage("avatar.name.v1") var nickname = ""
    static let emojis = ["🦊", "🐼", "🦉", "🐯", "🐸", "🐙", "🦄", "🐧", "🦁", "🐨", "🤖", "👩‍🔬", "👨‍🔬", "🧑‍🚀", "🧙", "⚡️", "🌟", "🔭", "🧬", "⚛️"]
    static let colors: [Color] = [Color(red: 0.32, green: 0.22, blue: 0.74), .blue, .teal, .green, .orange, .pink, .red, .indigo]
    var color: Color { Self.colors[min(max(colorIndex, 0), Self.colors.count - 1)] }
}

/// Avatari i rrumbullakët.
struct AvatarBadge: View {
    let emoji: String
    let color: Color
    var size: CGFloat = 48
    var body: some View {
        Text(emoji).font(.system(size: size * 0.55))
            .frame(width: size, height: size)
            .background(Circle().fill(LinearGradient(colors: [color.opacity(0.95), color.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 2))
            .shadow(color: color.opacity(0.4), radius: 6, y: 3)
            .accessibilityHidden(true)
    }
}

/// Ngjyra kryesore e app-it që zgjedh përdoruesi (Pamja → Ngjyra). Ruhet në pajisje.
enum AppAccent {
    static let key = "accent.choice.v1"
    static let choices: [(name: String, light: Color, dark: Color)] = [
        ("Vjollcë", Color(red: 0.32, green: 0.22, blue: 0.74), Color(red: 0.62, green: 0.55, blue: 1.0)),
        ("Oqean", Color(red: 0.05, green: 0.40, blue: 0.80), Color(red: 0.40, green: 0.70, blue: 1.0)),
        ("Smerald", Color(red: 0.02, green: 0.52, blue: 0.40), Color(red: 0.30, green: 0.85, blue: 0.65)),
        ("Perëndim", Color(red: 0.85, green: 0.35, blue: 0.10), Color(red: 1.0, green: 0.62, blue: 0.35)),
        ("Rozë", Color(red: 0.80, green: 0.15, blue: 0.45), Color(red: 1.0, green: 0.50, blue: 0.72)),
        ("Natë", Color(red: 0.15, green: 0.18, blue: 0.35), Color(red: 0.65, green: 0.70, blue: 0.90)),
    ]
    static var index: Int { min(max(UserDefaults.standard.integer(forKey: key), 0), choices.count - 1) }
    static var color: Color { Color(light: choices[index].light, dark: choices[index].dark) }
}

/// Ikonat alternative të app-it (vetëm iPhone/iPad).
enum AppIconChoice: String, CaseIterable, Identifiable {
    case standard, ocean, sunset, forest, light
    var id: String { rawValue }
    /// Emri i grupit të ikonës në Assets (nil = ikona kryesore).
    var assetName: String? {
        switch self {
        case .standard: return nil
        case .ocean: return "AppIconOcean"
        case .sunset: return "AppIconSunset"
        case .forest: return "AppIconForest"
        case .light: return "AppIconLight"
        }
    }
    var title: String {
        switch self {
        case .standard: return "Klasike"
        case .ocean: return "Oqean"
        case .sunset: return "Perëndim"
        case .forest: return "Pyll"
        case .light: return "E çelët"
        }
    }
    var colors: [Color] {
        switch self {
        case .standard: return [Color(red: 0.55, green: 0.30, blue: 0.95), .white]
        case .ocean: return [Color(red: 0.10, green: 0.55, blue: 1.0), .white]
        case .sunset: return [Color(red: 1.0, green: 0.42, blue: 0.30), .white]
        case .forest: return [Color(red: 0.12, green: 0.78, blue: 0.50), .white]
        case .light: return [Color(red: 0.96, green: 0.95, blue: 1.0), Color(red: 0.42, green: 0.30, blue: 0.85)]
        }
    }
}
