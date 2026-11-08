import SwiftUI

/// Pamje vetëm për lexim: afatet e testeve, ngjarjet, projektet dhe komentet e reja të mësuesit.
struct WatchSchoolView: View {
    @EnvironmentObject private var inbox: WatchInbox
    var body: some View {
        List {
            if !inbox.summary.signedIn {
                Text("Hap Science Quest në iPhone dhe hyr te «Shkolla ime». Afatet dhe komentet shfaqen këtu pas rifreskimit.")
                    .font(.footnote)
            } else {
                let upcoming = inbox.summary.items.filter { $0.kind != .feedback }.sorted { ($0.date ?? 0) < ($1.date ?? 0) }
                let feedback = inbox.summary.items.filter { $0.kind == .feedback }
                Section("Në vijim") {
                    if upcoming.isEmpty { Text("Asgjë në 3 javët e ardhshme.").font(.footnote) }
                    ForEach(upcoming) { row($0) }
                }
                if !feedback.isEmpty {
                    Section("Komente të reja") {
                        ForEach(feedback) { item in
                            NavigationLink { WatchFeedbackDetail(item: item) } label: { row(item) }
                        }
                    }
                }
                Text("Përditësuar " + Date(timeIntervalSince1970: inbox.summary.updated).formatted(date: .abbreviated, time: .shortened) + " nga iPhone-i")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Shkolla")
    }

    private func row(_ item: WatchSummary.Item) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title).font(.headline).lineLimit(2)
            if let date = item.date {
                Text(date < Date().timeIntervalSince1970 && item.kind != .feedback ? "Sot / ka kaluar" : Date(timeIntervalSince1970: date).formatted(.relative(presentation: .named)))
                    .font(.footnote).foregroundStyle(item.kind == .feedback ? Color.secondary : Color.orange)
            }
            if item.kind != .feedback { Text(item.detail).font(.footnote).foregroundStyle(.secondary).lineLimit(2) }
        }
    }
}

struct WatchFeedbackDetail: View {
    let item: WatchSummary.Item
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title).font(.headline)
                Text(item.detail)
            }
        }
        .navigationTitle("Komenti")
    }
}
