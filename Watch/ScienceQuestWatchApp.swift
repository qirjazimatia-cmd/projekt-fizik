import SwiftUI

/// Science Quest për Apple Watch (issue #17): ushtrime të shkurtra pa llogari, dhe një pamje leximi e shkollës
/// që vjen nga iPhone-i (WatchSummary). Ora nuk mban seancë dhe nuk thërret serverin.
@main
struct ScienceQuestWatchApp: App {
    @StateObject private var inbox = WatchInbox()
    var body: some Scene {
        WindowGroup {
            NavigationStack { WatchHome() }
                .environmentObject(inbox)
        }
    }
}

struct WatchHome: View {
    @EnvironmentObject private var inbox: WatchInbox
    var body: some View {
        List {
            NavigationLink { WatchSchoolView() } label: {
                Label {
                    VStack(alignment: .leading) {
                        Text("Shkolla ime")
                        Text(inbox.badge).font(.footnote).foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: "calendar") }
            }
            Section("Ushtrime") {
                ForEach(WatchSubject.allCases) { subject in
                    NavigationLink { WatchLevelList(subject: subject) } label: {
                        Label(subject.rawValue, systemImage: subject.icon)
                    }
                }
            }
        }
        .navigationTitle("BrainSpark")
    }
}
