import Foundation

/// Kërkimi i asistentit të mësimeve. Punon plotësisht në pajisje (pa internet, pa shërbim me pagesë)
/// mbi 600 mësimet e aplikacionit. Algoritmi: BM25 me fusha të peshuara, rrënjë e thjeshtë shqipe
/// (5 shkronjat e para të fjalës), bonus kur fjala është në titull dhe kur pyetja përmend lëndën.
/// Nuk varet nga SwiftUI, që testet ta provojnë drejtpërdrejt.
struct SearchDocument {
    let id: String
    let subject: String
    let level: Int
    /// Teksti i çdo fushe me peshën e saj (titulli peshon më shumë se shembulli).
    let fields: [(text: String, weight: Double)]
    let title: String

    static func lesson(id: String, subject: String, level: Int, title: String, chapterTitle: String, objectives: [String],
                       introduction: String, sections: [String], example: String, recap: [String]) -> SearchDocument {
        SearchDocument(id: id, subject: subject, level: level, fields: [
            (title, 4.0), (chapterTitle, 1.5), (objectives.joined(separator: " "), 1.2), (introduction, 1.0),
            (sections.joined(separator: " "), 0.8), (example, 0.6), (recap.joined(separator: " "), 0.8)
        ], title: title)
    }
}

struct SearchHit: Equatable {
    let id: String
    let score: Double
}

final class LessonSearch {
    /// Fjalë që nuk ndihmojnë në gjetjen e temës (pas heqjes së ë/ç dhe shkronjave të mëdha).
    static let stopWords: Set<String> = Set("""
    a apo ato ai ajo atij asaj ata ate cfare cila cili cilat cilet ci do dhe dmth e edhe eshte jane jam je ka kane kam ke kjo ky \
    keto ku kur me mund nga nje nuk o per pse po qe sa se si shpjego shpjegoje shpjegom shpjegohet ta te ti tek une u ve vetem \
    por pra ose ne mi mos kete ketij kesaj ndihme ndihmo kuptoj kuptoni dua the
    """.split(separator: " ").map(String.init))
    /// Kur pyetja përmend lëndën, temat e asaj lënde marrin përparësi.
    static let subjectHints: [String: String] = ["kimi": "Kimi", "kimik": "Kimi", "fizik": "Fizikë", "matem": "Matematikë", "biolo": "Biologji"]

    static func normalize(_ text: String) -> String {
        let folded = text.lowercased().replacingOccurrences(of: "ë", with: "e").replacingOccurrences(of: "ç", with: "c")
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
        return String(folded.unicodeScalars.map { scalar -> Character in
            let v = scalar.value
            return (v >= 97 && v <= 122) || (v >= 48 && v <= 57) ? Character(scalar) : " "
        })
    }
    static func stem(_ token: String) -> String { token.count > 5 ? String(token.prefix(5)) : token }
    static func tokens(_ text: String) -> [String] {
        normalize(text).split(separator: " ").map(String.init)
            .filter { $0.count > 1 && !stopWords.contains($0) }.map(stem)
    }

    private struct Entry { let document: SearchDocument; let frequencies: [String: Double]; let length: Double; let titleTokens: Set<String> }
    private let entries: [Entry]
    private let documentFrequency: [String: Int]
    private let averageLength: Double

    init(_ documents: [SearchDocument]) {
        var built: [Entry] = []
        var frequency: [String: Int] = [:]
        for document in documents {
            var counts: [String: Double] = [:]
            var length = 0.0
            for field in document.fields {
                for token in Self.tokens(field.text) { counts[token, default: 0] += field.weight; length += field.weight }
            }
            for token in counts.keys { frequency[token, default: 0] += 1 }
            built.append(Entry(document: document, frequencies: counts, length: length, titleTokens: Set(Self.tokens(document.title))))
        }
        entries = built
        documentFrequency = frequency
        averageLength = built.isEmpty ? 1 : max(1, built.map(\.length).reduce(0, +) / Double(built.count))
    }

    private func idf(_ token: String) -> Double {
        let n = Double(entries.count), df = Double(documentFrequency[token] ?? 0)
        return log(1 + (n - df + 0.5) / (df + 0.5))
    }

    /// Temat më të përshtatshme për pyetjen, nga më e mira. `subject` dhe `level` kufizojnë kërkimin.
    func search(_ query: String, subject: String? = nil, level: Int? = nil, limit: Int = 5) -> [SearchHit] {
        var seen = Set<String>()
        let queryTokens = Self.tokens(query).filter { seen.insert($0).inserted }
        guard !queryTokens.isEmpty else { return [] }
        let hinted = Set(queryTokens.compactMap { Self.subjectHints[$0] })
        let k = 1.2, b = 0.75
        var hits: [SearchHit] = []
        for entry in entries {
            if let subject, entry.document.subject != subject { continue }
            if let level, entry.document.level != level { continue }
            var score = 0.0
            for token in queryTokens {
                guard let f = entry.frequencies[token], f > 0 else { continue }
                score += idf(token) * f * (k + 1) / (f + k * (1 - b + b * entry.length / averageLength))
            }
            score += queryTokens.filter { entry.titleTokens.contains($0) }.map(idf).reduce(0, +)
            if score > 0 && hinted.contains(entry.document.subject) { score *= 1.6 }
            if score > 0 { hits.append(SearchHit(id: entry.document.id, score: score)) }
        }
        return Array(hits.sorted { $0.score != $1.score ? $0.score > $1.score : $0.id < $1.id }.prefix(limit))
    }
}
