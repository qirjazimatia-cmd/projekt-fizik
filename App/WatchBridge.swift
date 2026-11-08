import Foundation
#if os(iOS)
import WatchConnectivity
#endif

/// iPhone → Apple Watch (issue #17). Pas çdo rifreskimi të "Shkolla ime", iPhone-i ndërton një përmbledhje të shkurtër
/// (ngjarjet e 3 javëve të ardhshme, afatet e projekteve, komentet e reja të mësuesit) dhe ia dërgon orës.
/// Në Mac nuk bën asgjë. Kur llogaria del, ora merr një përmbledhje bosh, që të mos mbeten të dhëna aty.
@MainActor
enum WatchPublisher {
    static func publish(_ snapshot: SchoolSnapshot) async {
        #if os(iOS)
        guard WCSession.isSupported() else { return }
        WatchLink.shared.send(await build(snapshot))
        #endif
    }

    static func clear() {
        #if os(iOS)
        guard WCSession.isSupported() else { return }
        WatchLink.shared.send(WatchSummary(updated: Date().timeIntervalSince1970, signedIn: false, items: []))
        #endif
    }

    static func build(_ snapshot: SchoolSnapshot) async -> WatchSummary {
        let now = Date().timeIntervalSince1970
        let horizon = now + 21 * 86_400
        let classNames = Dictionary(snapshot.classes.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        var items: [WatchSummary.Item] = snapshot.events
            .filter { $0.date >= now - 3_600 && $0.date <= horizon }
            .sorted { $0.date < $1.date }
            .prefix(15)
            .map { e in
                let kind = e.examID == nil ? "Ngjarje" : "Test"
                let parts = [kind, e.subject, classNames[e.classID]].compactMap { $0 }.filter { !$0.isEmpty }
                return .init(id: "e-" + e.id, kind: .event, title: e.title, detail: parts.joined(separator: " · "), date: e.date)
            }
        if SupabaseConfig.enabled, let reply: ProjectsReply = try? await SchoolAPI.call("projects") {
            for p in reply.projects where p.isOpen {
                if let due = p.due, due >= now - 86_400 {
                    let submitted = p.teams.contains { $0.versions.contains { !$0.isDraft } }
                    let state = p.mine ? "\(p.teams.count) " + (p.isGroup ? "grupe" : "nxënës") : (submitted ? "dorëzuar" : "pa dorëzuar")
                    items.append(.init(id: "p-" + p.id, kind: .project, title: p.title, detail: ["Projekt", p.className, state].joined(separator: " · "), date: due))
                }
                guard !p.mine else { continue }
                for team in p.teams {
                    for v in team.versions where !v.feedback.isEmpty {
                        guard let reviewed = v.reviewed, reviewed >= now - 14 * 86_400 else { continue }
                        items.append(.init(id: "f-" + v.id, kind: .feedback, title: p.title + " · v\(v.number)",
                                           detail: String(v.feedback.prefix(280)), date: reviewed))
                    }
                }
            }
        }
        return WatchSummary(updated: now, signedIn: true, items: Array(items.prefix(40)))
    }
}

#if os(iOS)
/// Mban sesionin WatchConnectivity në iPhone. `updateApplicationContext` ruan vetëm versionin e fundit:
/// ora e merr sapo hapet, edhe nëse në atë moment nuk ishte e lidhur.
final class WatchLink: NSObject, WCSessionDelegate {
    static let shared = WatchLink()
    private var pending: Data?

    func send(_ summary: WatchSummary) {
        guard let data = summary.encoded() else { return }
        let session = WCSession.default
        pending = data
        if session.delegate == nil { session.delegate = self }
        if session.activationState == .activated { flush() } else { session.activate() }
    }

    private func flush() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled, let data = pending else { return }
        do { try session.updateApplicationContext([WatchSummary.contextKey: data]); pending = nil } catch {}
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.flush() }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    func sessionWatchStateDidChange(_ session: WCSession) { DispatchQueue.main.async { self.flush() } }
}
#endif
