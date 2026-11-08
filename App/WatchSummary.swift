import Foundation

/// Përmbledhja që iPhone-i i dërgon Apple Watch-it (issue #17).
/// Përmban vetëm tekst për t'u lexuar: pa çelësa, pa seancë, pa skedarë. Ora nuk thërret dot serverin.
/// Ky skedar përfshihet në të dy target-et (iOS/macOS dhe watchOS).
struct WatchSummary: Codable, Equatable {
    struct Item: Codable, Equatable, Identifiable {
        enum Kind: String, Codable { case event, project, feedback }
        let id: String
        let kind: Kind
        let title: String
        let detail: String
        let date: Double?
    }
    var updated: Double
    var signedIn: Bool
    var items: [Item]

    static let contextKey = "summary"
    static let empty = WatchSummary(updated: 0, signedIn: false, items: [])

    func encoded() -> Data? { try? JSONEncoder().encode(self) }
    static func decode(_ data: Data) -> WatchSummary? { try? JSONDecoder().decode(WatchSummary.self, from: data) }
}
