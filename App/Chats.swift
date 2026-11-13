import SwiftUI

// Bisedat (#80, Matia): grupi i klasës, prind↔mësues, shok↔shok.
// Serveri: Supabase/migrations/20261114_0010_matia_bisedat.sql (api_chat*). Të gjitha rregullat (kush shkruan ku, filtri,
// bllokimi) janë në server; app-i vetëm i shfaq. Mesazhet rifreskohen çdo 4 sekonda kur biseda është e hapur
// (pa push: kërkon llogarinë Apple Developer).

struct ChatSummary: Decodable, Identifiable, Equatable {
    struct Last: Decodable, Equatable { let body: String; let at: Double; let mine: Bool }
    let id: String
    let kind: String
    let classID: String?
    let teacherOnly: Bool
    let title: String?
    let subtitle: String
    let otherID: String?
    let canWrite: Bool
    let last: Last?
    let unread: Int
    var name: String { title ?? "Bisedë" }
    var icon: String {
        switch kind {
        case "class": return "person.3.fill"
        case "family": return "figure.and.child.holdinghands"
        case "tutor": return "graduationcap.fill"
        default: return "bubble.left.fill"
        }
    }
}

struct ChatMessage: Decodable, Identifiable, Equatable {
    let id: Int
    let body: String
    let deleted: Bool
    let at: Double
    let mine: Bool
    let senderID: String
    let sender: String?
    let emoji: String
    let color: Int?
    let teacher: Bool
}

struct ChatContact: Decodable, Identifiable {
    let userID: String
    let name: String?
    let kind: String
    let detail: String
    var id: String { userID }
}

private struct ChatListReply: Decodable { let chats: [ChatSummary] }
private struct ContactsReply: Decodable { let contacts: [ChatContact] }
private struct OpenReply: Decodable { let id: String? }
private struct MessagesReply: Decodable { let messages: [ChatMessage]; let summary: ChatSummary; let reason: String?; let isOwner: Bool }
private struct UnreadReply: Decodable { let unread: Int }

@MainActor
final class ChatStore: ObservableObject {
    @Published var chats: [ChatSummary] = []
    @Published var contacts: [ChatContact] = []
    @Published var unread = 0
    @Published var loaded = false
    @Published var message = ""

    func loadList() async {
        do {
            let reply: ChatListReply = try await SchoolAPI.call("chatList")
            chats = reply.chats; unread = reply.chats.reduce(0) { $0 + $1.unread }; loaded = true; message = ""
        } catch { message = error.localizedDescription; loaded = true }
    }
    func loadUnread() async {
        if let reply: UnreadReply = try? await SchoolAPI.call("chatUnread") { unread = reply.unread }
    }
    func loadContacts() async {
        if let reply: ContactsReply = try? await SchoolAPI.call("chatContacts") { contacts = reply.contacts }
    }
    func open(userID: String) async -> String? {
        do {
            let reply: OpenReply = try await SchoolAPI.call("chatOpen", body: ["userID": userID])
            return reply.id
        } catch { message = error.localizedDescription; return nil }
    }
}

// MARK: - Lista e bisedave

struct ChatsView: View {
    @ObservedObject var store: ChatStore
    @ObservedObject var social: SocialModel
    @EnvironmentObject private var account: Account
    @State private var showNew = false
    @State private var openID: String?

    private var groups: [ChatSummary] { store.chats.filter { $0.kind == "class" } }
    private var privateChats: [ChatSummary] { store.chats.filter { $0.kind != "class" } }

    var body: some View {
        Page {
            HStack {
                Text("Bisedat").font(.system(.largeTitle, design: .rounded).weight(.black))
                Spacer()
                if account.role == .student {
                    NavigationLink { FriendsView(social: social) } label: {
                        Label(social.incoming.isEmpty ? "Shokët" : "Shokët · \(social.incoming.count)", systemImage: "person.2.fill")
                            .font(.subheadline.bold()).padding(.horizontal, 12).padding(.vertical, 8).glassCapsule()
                    }.buttonStyle(.plain)
                }
                Button { showNew = true } label: {
                    Image(systemName: "square.and.pencil").font(.title3).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain).accessibilityLabel("Bisedë e re")
            }
            if !account.isOnline {
                Label("Bisedat punojnë vetëm me llogarinë e shkollës, me internet.", systemImage: "wifi.slash")
                    .padding().glass(cornerRadius: 18)
            } else if !store.loaded {
                ProgressView("Po ngarkohen bisedat…").frame(maxWidth: .infinity).padding(30)
            } else {
                if !store.message.isEmpty { Text(store.message).font(.callout).foregroundStyle(.orange) }
                if store.chats.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 44)).foregroundStyle(Color.lagoon)
                        Text("Ende pa biseda").font(.headline)
                        Text(emptyText).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button { showNew = true } label: { Label("Bisedë e re", systemImage: "square.and.pencil") }.buttonStyle(.liquidProminent)
                    }.frame(maxWidth: .infinity).padding(24).glass(cornerRadius: 22)
                }
                if !groups.isEmpty {
                    Text("Grupet e klasave").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, chat in row(chat).appearIn(index) }
                }
                if !privateChats.isEmpty {
                    Text("Bisedat private").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                    ForEach(Array(privateChats.enumerated()), id: \.element.id) { index, chat in row(chat).appearIn(index) }
                }
            }
        }
        .navigationDestination(isPresented: Binding(get: { openID != nil }, set: { if !$0 { openID = nil } })) {
            if let openID { ChatThreadView(chatID: openID, store: store) }
        }
        .sheet(isPresented: $showNew) {
            NavigationStack { NewChatSheet(store: store) { id in showNew = false; openID = id } }
                .macSheetFrame(minWidth: 420, minHeight: 480)
        }
        .refreshable { await store.loadList() }
        .task(id: account.isOnline) {
            guard account.isOnline else { return }
            // Lista rifreskohet çdo 15 sekonda ndërsa është e hapur.
            while !Task.isCancelled {
                await store.loadList()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    private var emptyText: String {
        switch account.role ?? .student {
        case .teacher: return "Grupi i çdo klase krijohet vetë. Prindërit e nxënësve të tu i gjen te «Bisedë e re»."
        case .parent: return "Lidhu me fëmijën tënd me kodin e familjes; pastaj sheh grupin e klasës dhe mund t'i shkruash mësuesit."
        default: return "Pasi mësuesi të pranon në klasë, këtu del grupi i klasës. Shokëve u shkruan te «Bisedë e re»."
        }
    }

    private func row(_ chat: ChatSummary) -> some View {
        NavigationLink { ChatThreadView(chatID: chat.id, store: store) } label: {
            HStack(spacing: 12) {
                Image(systemName: chat.icon).font(.headline).foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(chat.kind == "class" ? Color.lagoon : chat.kind == "family" ? Color.orange : chat.kind == "tutor" ? Color.indigo : Color.pink))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(chat.name).font(.headline).lineLimit(1)
                        if chat.teacherOnly { Image(systemName: "megaphone.fill").font(.caption).foregroundStyle(.secondary).accessibilityLabel("Vetëm njoftime") }
                        Spacer(minLength: 4)
                        if let last = chat.last { Text(ChatTime.short(last.at)).font(.caption).foregroundStyle(.secondary) }
                    }
                    HStack {
                        Text(chat.last.map { ($0.mine ? "Ti: " : "") + $0.body } ?? chat.subtitle)
                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 4)
                        if chat.unread > 0 {
                            Text("\(chat.unread)").font(.caption.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 7).frame(minHeight: 20).background(Capsule().fill(.red))
                        }
                    }
                }
            }
            .padding(12).glass(cornerRadius: 18)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(chat.name + ", " + chat.subtitle + (chat.unread > 0 ? ", \(chat.unread) të palexuara" : ""))
        }
        .buttonStyle(.springy)
    }
}

/// «Bisedë e re»: grupet e klasave dhe kontaktet e lejuara (shokët, ose prind↔mësues).
private struct NewChatSheet: View {
    @ObservedObject var store: ChatStore
    let opened: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var account: Account
    @State private var busy = false

    var body: some View {
        List {
            let groups = store.chats.filter { $0.kind == "class" }
            if !groups.isEmpty {
                Section("Grupet e klasave") {
                    ForEach(groups) { chat in Button { opened(chat.id) } label: { Label(chat.name, systemImage: "person.3.fill") } }
                }
            }
            ForEach(sections, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.contacts) { contact in contactRow(contact) }
                }
            }
            if store.contacts.isEmpty {
                Section {
                    Text(account.role == .student ? "Pasi mësuesi të pranon në klasë, këtu dalin mësuesit e tu; shokët i shton te «Shokët»." :
                         account.role == .parent ? "Lidhu me fëmijën tënd me kodin e familjes." : "Prindërit shfaqen kur lidhen me fëmijët e klasave të tua.")
                        .foregroundStyle(.secondary)
                }
            }
            if !store.message.isEmpty { Text(store.message).foregroundStyle(.orange) }
        }
        .navigationTitle("Bisedë e re")
        .safeAreaInset(edge: .bottom) {
            if account.role != .parent {
                Label("Bisedat mësues–nxënës i sheh edhe prindi i lidhur i nxënësit.", systemImage: "eye")
                    .font(.caption).foregroundStyle(.secondary).padding(10)
            }
        }
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Mbyll") { dismiss() } } }
        .task { await store.loadContacts() }
    }
}

private extension NewChatSheet {
    struct ContactSection { let title: String; let contacts: [ChatContact] }
    var sections: [ContactSection] {
        let titles: [(String, String)] = [("tutor", account.role == .teacher ? "Nxënësit e klasave të mia" : "Mësuesit e mi"),
                                          ("family", account.role == .teacher ? "Prindërit e nxënësve" : "Mësuesit e fëmijës"),
                                          ("friend", "Shokët e mi")]
        return titles.compactMap { kind, title in
            let list = store.contacts.filter { $0.kind == kind }
            return list.isEmpty ? nil : ContactSection(title: title, contacts: list)
        }
    }
    func contactRow(_ contact: ChatContact) -> some View {
        Button {
            busy = true
            Task { @MainActor in
                if let id = await store.open(userID: contact.userID) { opened(id) }
                busy = false
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name ?? "Pa emër").font(.headline)
                Text(contact.detail).font(.caption).foregroundStyle(.secondary)
            }
        }.disabled(busy)
    }
}

// MARK: - Biseda

struct ChatThreadView: View {
    let chatID: String
    @ObservedObject var store: ChatStore
    @State private var messages: [ChatMessage] = []
    @State private var summary: ChatSummary?
    @State private var reason: String?
    @State private var isOwner = false
    @State private var draft = ""
    @State private var error = ""
    @State private var sending = false
    @State private var reporting: ChatMessage?
    @State private var blocking: ChatMessage?
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if summary?.kind == "friend" {
                            Label("Mos ndaj numra telefoni, adresa ose fjalëkalime. Raporto çdo gjë që të shqetëson (mbaj shtypur mesazhin).",
                                  systemImage: "shield.lefthalf.filled")
                                .font(.caption).foregroundStyle(.secondary).padding(10).glass(cornerRadius: 14)
                        }
                        if summary?.kind == "tutor" {
                            Label("Bisedë mësues–nxënës: prindi i lidhur i nxënësit mund ta lexojë.", systemImage: "eye")
                                .font(.caption).foregroundStyle(.secondary).padding(10).glass(cornerRadius: 14)
                        }
                        if summary?.kind == "class" {
                            Label(summary?.teacherOnly == true ? "Grup njoftimesh: shkruan vetëm mësuesi. Prindërit e lidhur e lexojnë."
                                                               : "Grupi i klasës: shkruajnë mësuesi dhe nxënësit; prindërit e lidhur e lexojnë.",
                                  systemImage: "info.circle")
                                .font(.caption).foregroundStyle(.secondary).padding(10).glass(cornerRadius: 14)
                        }
                        if messages.isEmpty { Text("Ende pa mesazhe. Shkruaj i pari!").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(30) }
                        ForEach(messages) { message in bubble(message).id(message.id) }
                    }
                    .frame(maxWidth: 720).padding(16).frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.last?.id) { _ in
                    if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(.orange).padding(.horizontal, 12).padding(.top, 6) }
            composer
        }
        .background { PageBackground().ignoresSafeArea() }
        .navigationTitle(summary?.name ?? "Biseda")
        .toolbar {
            if isOwner, let summary {
                ToolbarItem(placement: .primaryAction) {
                    Toggle(isOn: Binding(get: { summary.teacherOnly }, set: { value in Task { await setTeacherOnly(value) } })) {
                        Label("Vetëm njoftime", systemImage: "megaphone")
                    }
                    .help("Kur është ndezur, në grup shkruan vetëm mësuesi.")
                }
            }
        }
        .confirmationDialog("Pse po e raporton këtë mesazh?", isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } }),
                            titleVisibility: .visible) {
            Button("Ngacmim ose fyerje") { Task { await report("bullying") } }
            Button("I papërshtatshëm") { Task { await report("inappropriate") } }
            Button("Spam") { Task { await report("spam") } }
            Button("Tjetër") { Task { await report("other") } }
            Button("Anulo", role: .cancel) { reporting = nil }
        } message: { Text("Mesazhi i dërgohet shkollës për kontroll. Dërguesi nuk e merr vesh kush e raportoi.") }
        .confirmationDialog("Ta bllokosh \(blocking?.sender ?? "")?", isPresented: Binding(get: { blocking != nil }, set: { if !$0 { blocking = nil } }),
                            titleVisibility: .visible) {
            Button("Blloko", role: .destructive) { Task { await block() } }
            Button("Anulo", role: .cancel) { blocking = nil }
        } message: { Text("Nuk do të shohësh më mesazhet e tij/saj dhe nuk mund t'i shkruani njëri-tjetrit privatisht.") }
        .task {
            // Rifreskim çdo 4 sekonda ndërsa biseda është e hapur.
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
        .onDisappear { Task { await store.loadList() } }
    }

    @ViewBuilder private var composer: some View {
        if let reason {
            Label(reason, systemImage: "lock.fill").font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(14).background(Color.card)
        } else if summary != nil {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Shkruaj një mesazh…", text: $draft, axis: .vertical)
                    .focused($typing).textFieldStyle(.roundedBorder).lineLimit(1...5)
                    .onSubmit { Task { await send() } }
                Button { Task { await send() } } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                    .buttonStyle(.plain)
                    .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending ? Color.secondary : Color.lagoon)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityLabel("Dërgo mesazhin")
            }
            .padding(12).background(Color.card)
        }
    }

    private func bubble(_ message: ChatMessage) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.mine { Spacer(minLength: 50) }
            else {
                AvatarBadge(emoji: message.emoji, color: AvatarStore.colors[min(max(message.color ?? 0, 0), AvatarStore.colors.count - 1)], size: 30)
                    .accessibilityHidden(true)
            }
            VStack(alignment: message.mine ? .trailing : .leading, spacing: 3) {
                if !message.mine && (summary?.kind == "class" || summary?.otherID == nil) {
                    HStack(spacing: 4) {
                        Text(message.sender ?? "").font(.caption.bold())
                        if message.teacher { Text("Mësues").font(.caption2.bold()).padding(.horizontal, 5).padding(.vertical, 1).background(Capsule().fill(Color.lagoon.opacity(0.2))) }
                    }
                }
                Text(message.deleted ? "Mesazhi u fshi" : message.body)
                    .italic(message.deleted)
                    .foregroundStyle(message.mine ? Color.white : (message.deleted ? Color.secondary : Color.ink))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background {
                        if message.mine { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.lagoon) }
                    }
                    .modifier(MessageGlass(enabled: !message.mine))
                    .textSelection(.enabled)
                Text(ChatTime.short(message.at)).font(.caption2).foregroundStyle(.secondary)
            }
            if !message.mine { Spacer(minLength: 50) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel((message.mine ? "Ti" : (message.sender ?? "")) + ": " + (message.deleted ? "mesazhi u fshi" : message.body))
        .contextMenu {
            if !message.deleted {
                if message.mine || isOwner {
                    Button(role: .destructive) { Task { await delete(message) } } label: { Label("Fshi mesazhin", systemImage: "trash") }
                }
                if !message.mine {
                    Button { reporting = message } label: { Label("Raporto", systemImage: "flag") }
                    if !message.teacher || summary?.kind != "class" {
                        Button(role: .destructive) { blocking = message } label: { Label("Blloko", systemImage: "hand.raised") }
                    }
                }
            }
        }
    }

    // MARK: Veprimet

    private func load() async {
        do {
            let reply: MessagesReply = try await SchoolAPI.call("chatMessages", body: ["id": chatID])
            if reply.messages != messages { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { messages = reply.messages } }
            summary = reply.summary; reason = reply.reason; isOwner = reply.isOwner
        } catch { self.error = error.localizedDescription }
    }
    private func send() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !sending else { return }
        sending = true; defer { sending = false }
        do {
            let _: OKReply = try await SchoolAPI.call("chatSend", body: ["id": chatID, "body": body])
            draft = ""; error = ""; Haptics.tap()
            await load()
        } catch { self.error = error.localizedDescription; Haptics.error() }
    }
    private func delete(_ message: ChatMessage) async {
        do { let _: OKReply = try await SchoolAPI.call("chatDelete", body: ["messageID": message.id]); await load() }
        catch { self.error = error.localizedDescription }
    }
    private func report(_ reason: String) async {
        guard let message = reporting else { return }
        reporting = nil
        do {
            let _: OKReply = try await SchoolAPI.call("chatReport", body: ["messageID": message.id, "reason": reason])
            error = "Faleminderit. Mesazhi u raportua."; Haptics.success()
        } catch { self.error = error.localizedDescription }
    }
    private func block() async {
        guard let message = blocking else { return }
        blocking = nil
        do {
            let _: OKReply = try await SchoolAPI.call("chatBlock", body: ["userID": message.senderID, "block": true])
            error = "U bllokua."; await load()
        } catch { self.error = error.localizedDescription }
    }
    private func setTeacherOnly(_ value: Bool) async {
        do { let _: OKReply = try await SchoolAPI.call("chatSettings", body: ["id": chatID, "teacherOnly": value]); await load() }
        catch { self.error = error.localizedDescription }
    }
}

private struct MessageGlass: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.glass(cornerRadius: 18) } else { content }
    }
}

enum ChatTime {
    static func short(_ seconds: Double) -> String {
        let date = Date(timeIntervalSince1970: seconds)
        if Calendar.current.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if Calendar.current.isDateInYesterday(date) { return "Dje" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
