import Foundation

enum NumericAnswer {
    static func parse(_ raw: String) -> Double? {
        let value = raw.trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:",",with:".").replacingOccurrences(of:"−",with:"-")
        let parts = value.split(separator:"/",omittingEmptySubsequences:false)
        guard (1...2).contains(parts.count), let n = Double(parts[0].trimmingCharacters(in:.whitespaces)), n.isFinite else { return nil }
        if parts.count == 1 { return n }
        guard let d = Double(parts[1].trimmingCharacters(in:.whitespaces)), d.isFinite, d != 0 else { return nil }
        let result = n/d
        return result.isFinite ? result : nil
    }
    static func accepts(_ value: Double, expected: Double, tolerance: Double) -> Bool {
        guard value.isFinite, expected.isFinite, tolerance.isFinite, tolerance >= 0 else { return false }
        return abs(value-expected) <= tolerance + max(abs(expected),1) * Double.ulpOfOne * 4
    }
}

/// Leximi i sigurt i fletoreve lokale. Kthen nil kur ka bajte të ruajtur që nuk lexohen,
/// që thirrësi të mos i mbishkruajë me një listë bosh (humbje e heshtur e të dhënave).
enum NotebookCodec {
    static func load<T: Decodable>(_ type: T.Type, from data: Data) -> [T]? {
        if data.isEmpty { return [] }
        return try? JSONDecoder().decode([T].self, from: data)
    }
    static let blockedMessage = "Fletorja e ruajtur nuk u lexua, prandaj nuk u mbishkrua. Mos fshi aplikacionin; ruaj një kopje të të dhënave dhe provo përsëri pas përditësimit."
}
