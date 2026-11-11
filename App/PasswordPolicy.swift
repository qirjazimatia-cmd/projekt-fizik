import Foundation

/// Kërkesat për fjalëkalimin e ri (regjistrim dhe rikuperim). Hyrja me fjalëkalim ekzistues nuk kontrollohet,
/// që llogaritë e vjetra të mund të hyjnë. Serveri (Supabase Auth) mbetet kontrolli përfundimtar.
enum PasswordPolicy {
    struct Rule: Identifiable, Equatable {
        let id: String
        let text: String
        let passes: (String) -> Bool
        static func == (a: Rule, b: Rule) -> Bool { a.id == b.id }
    }

    static let minimumLength = 10

    static let rules: [Rule] = [
        Rule(id: "length", text: "Të paktën \(minimumLength) karaktere") { $0.count >= minimumLength },
        Rule(id: "upper", text: "Një shkronjë e madhe (A–Z)") { $0.contains(where: { $0.isUppercase }) },
        Rule(id: "lower", text: "Një shkronjë e vogël (a–z)") { $0.contains(where: { $0.isLowercase }) },
        Rule(id: "digit", text: "Një numër (0–9)") { $0.contains(where: { $0.isNumber }) },
        Rule(id: "symbol", text: "Një simbol (p.sh. ! ? @ # . -)") { $0.contains(where: { !$0.isLetter && !$0.isNumber && !$0.isWhitespace }) },
        Rule(id: "spaces", text: "Pa hapësira në fillim ose në fund") { $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) },
    ]

    /// Kërkesat që nuk plotësohen ende.
    static func missing(_ password: String) -> [Rule] { rules.filter { !$0.passes(password) } }
    static func isValid(_ password: String) -> Bool { missing(password).isEmpty }

    /// Mesazhi i gabimit për regjistrim/rikuperim, ose nil kur fjalëkalimi është në rregull.
    static func problem(_ password: String, email: String = "") -> String? {
        let lacking = missing(password)
        if !lacking.isEmpty { return "Fjalëkalimit i mungon: " + lacking.map { $0.text.lowercased() }.joined(separator: ", ") + "." }
        let name = email.split(separator: "@").first.map { String($0).lowercased() } ?? ""
        if name.count >= 4 && password.lowercased().contains(name) { return "Fjalëkalimi nuk duhet të përmbajë emailin tënd." }
        return nil
    }
}
