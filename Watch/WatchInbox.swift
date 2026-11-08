import Foundation
import WatchConnectivity

/// Merr përmbledhjen nga iPhone-i dhe e ruan në orë që të shfaqet edhe pa lidhje.
final class WatchInbox: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var summary: WatchSummary
    private static let storeKey = "watchSummary.v1"

    override init() {
        if let data = UserDefaults.standard.data(forKey: Self.storeKey), let saved = WatchSummary.decode(data) { summary = saved }
        else { summary = .empty }
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    var badge: String {
        guard summary.signedIn else { return "Hyr nga iPhone-i" }
        let upcoming = summary.items.filter { $0.kind != .feedback }.count
        let feedback = summary.items.filter { $0.kind == .feedback }.count
        var parts = ["\(upcoming) afate"]
        if feedback > 0 { parts.append("\(feedback) komente") }
        return parts.joined(separator: " · ")
    }

    private func accept(_ context: [String: Any]) {
        guard let data = context[WatchSummary.contextKey] as? Data, let incoming = WatchSummary.decode(data) else { return }
        DispatchQueue.main.async {
            guard incoming.updated >= self.summary.updated else { return }
            self.summary = incoming
            // Pas daljes nga llogaria në iPhone nuk ruhet asgjë në orë.
            if incoming.signedIn { UserDefaults.standard.set(data, forKey: Self.storeKey) }
            else { UserDefaults.standard.removeObject(forKey: Self.storeKey) }
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        accept(session.receivedApplicationContext)
    }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        accept(applicationContext)
    }
}
