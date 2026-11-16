import Foundation

// MARK: - Regjistri (CSV)

struct RosterInput: Equatable {
    var amza, firstName, lastName, className: String
    var birthYear: String
    var json: [String: Any] { ["amza": amza, "firstName": firstName, "lastName": lastName, "className": className, "birthYear": birthYear] }
}

/// Lexon regjistrin: Amza; Emri; Mbiemri; Klasa; Viti i lindjes (opsional). Ndarësi: `;`, `,` ose tab.
/// Rreshti i parë anashkalohet nëse duket si titull. Kthen rreshtat e mirë dhe numrat e rreshtave me gabim.
enum RosterCSV {
    static func parse(_ text: String) -> (rows: [RosterInput], bad: [Int]) {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return ([], []) }
        let separator: Character = first.contains("\t") ? "\t" : first.contains(";") ? ";" : ","
        var rows: [RosterInput] = []; var bad: [Int] = []
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let cells = split(trimmed, by: separator)
            let lower = trimmed.lowercased()
            if rows.isEmpty && bad.isEmpty && (lower.contains("amz") || lower.contains("emri") || lower.contains("klasa")) { continue }
            guard cells.count >= 4, !cells[0].isEmpty, !cells[1].isEmpty, !cells[2].isEmpty, !cells[3].isEmpty,
                  cells[0].count <= 20, cells[1].count <= 40, cells[2].count <= 40, cells[3].count <= 12 else { bad.append(index + 1); continue }
            let year = cells.count > 4 ? cells[4] : ""
            if !year.isEmpty && !(year.count == 4 && year.allSatisfy(\.isNumber)) { bad.append(index + 1); continue }
            rows.append(RosterInput(amza: cells[0], firstName: cells[1], lastName: cells[2], className: cells[3].uppercased(), birthYear: year))
        }
        return (rows, bad)
    }
    /// Ndarje që respekton thonjëzat ("Kola, Ana").
    static func split(_ line: String, by separator: Character) -> [String] {
        let chars = Array(line)
        var cells: [String] = []; var current = ""; var quoted = false; var i = 0
        while i < chars.count {
            let char = chars[i]
            if char == "\"" {
                if quoted && i + 1 < chars.count && chars[i + 1] == "\"" { current.append("\""); i += 1 }
                else { quoted.toggle() }
            } else if char == separator && !quoted {
                cells.append(current); current = ""
            } else { current.append(char) }
            i += 1
        }
        cells.append(current)
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
