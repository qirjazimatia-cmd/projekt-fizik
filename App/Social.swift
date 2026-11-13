import SwiftUI

// Shokët dhe profili publik (Juri): username unik, emri i shfaqur, avatari, ftesat dhe lista e shokëve.
// Serveri: Supabase/migrations/20261113_1900_juri_shoket.sql (api_profile*, api_userSearch, api_friend*).
// Kërkimi kthen vetëm username, emrin dhe avatarin; emaili nuk i shfaqet askujt tjetër.

struct PublicUser: Decodable, Identifiable, Equatable {
    let username: String
    let displayName: String
    let avatarEmoji: String
    let avatarColor: Int
    var relation: String?
    var id: String { username }
    var color: Color { AvatarStore.colors[min(max(avatarColor, 0), AvatarStore.colors.count - 1)] }
}

struct ProfileReply: Decodable {
    let email: String?
    let username: String?
    let displayName: String?
    let avatarEmoji: String?
    let avatarColor: Int?
}

/// `blocked`: arsyeja kur llogaria nuk mund të ketë shokë (vetëm nxënës të pranuar në një klasë; shih 20261113_2200_matia_shoket_vetem_nxenes.sql).
private struct FriendsReply: Decodable { let friends: [PublicUser]; let incoming: [PublicUser]; let outgoing: [PublicUser]; let blocked: String? }
private struct SearchReply: Decodable { let users: [PublicUser] }
private struct AvailableReply: Decodable { let available: Bool }
private struct RelationReply: Decodable { let ok: Bool?; let relation: String? }

@MainActor
final class SocialModel: ObservableObject {
    @Published var profile: ProfileReply?
    @Published var loadedProfile = false
    @Published var friends: [PublicUser] = []
    @Published var incoming: [PublicUser] = []
    @Published var outgoing: [PublicUser] = []
    @Published var results: [PublicUser] = []
    @Published var message = ""
    @Published var busy = false
    /// Kur serveri nuk lejon shokë për këtë llogari (prind, mësues, ose nxënës ende pa klasë), këtu vjen arsyeja.
    @Published var blocked: String?

    var needsUsername: Bool { loadedProfile && (profile?.username ?? "").isEmpty }

    func loadProfile() async {
        do { profile = try await SchoolAPI.call("profileGet"); loadedProfile = true }
        catch { message = error.localizedDescription }
    }

    /// Ruan username, emrin dhe avatarin. Kthen true kur serveri i pranon.
    func save(username: String? = nil, displayName: String? = nil, emoji: String? = nil, color: Int? = nil) async -> Bool {
        var body: [String: Any] = [:]
        if let username { body["username"] = username.lowercased().trimmingCharacters(in: .whitespaces) }
        if let displayName { body["displayName"] = displayName.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let emoji { body["avatarEmoji"] = emoji }
        if let color { body["avatarColor"] = color }
        busy = true; defer { busy = false }
        do {
            let _: OKReply = try await SchoolAPI.call("profileUpdate", body: body)
            await loadProfile(); message = ""; return true
        } catch { message = error.localizedDescription; return false }
    }

    func isAvailable(_ username: String) async -> Bool? {
        guard Self.validUsername(username) else { return false }
        let reply: AvailableReply? = try? await SchoolAPI.call("usernameAvailable", body: ["username": username.lowercased()])
        return reply?.available
    }

    func loadFriends() async {
        do {
            let reply: FriendsReply = try await SchoolAPI.call("friendsList")
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                friends = reply.friends; incoming = reply.incoming; outgoing = reply.outgoing
            }
            blocked = reply.blocked
            message = ""
        } catch { message = error.localizedDescription }
    }

    func search(_ query: String) async {
        let clean = query.lowercased().trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
        guard clean.count >= 3 else { results = []; return }
        do {
            let reply: SearchReply = try await SchoolAPI.call("userSearch", body: ["query": clean])
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { results = reply.users }
        } catch { message = error.localizedDescription }
    }

    func invite(_ user: PublicUser) async {
        do {
            let reply: RelationReply = try await SchoolAPI.call("friendRequest", body: ["username": user.username])
            if let index = results.firstIndex(of: user) { results[index].relation = reply.relation }
            Haptics.success()
            message = reply.relation == "friend" ? "Tani jeni shokë me \(user.displayName)! 🎉" : "Ftesa u dërgua te @\(user.username)."
            await loadFriends()
        } catch { message = error.localizedDescription; Haptics.error() }
    }

    func respond(_ user: PublicUser, accept: Bool) async {
        do {
            let _: OKReply = try await SchoolAPI.call("friendRespond", body: ["username": user.username, "accept": accept])
            if accept { Haptics.celebrate() } else { Haptics.tap() }
            await loadFriends()
        } catch { message = error.localizedDescription }
    }

    func remove(_ user: PublicUser) async {
        do {
            let _: OKReply = try await SchoolAPI.call("friendRemove", body: ["username": user.username])
            await loadFriends()
        } catch { message = error.localizedDescription }
    }

    static func validUsername(_ value: String) -> Bool {
        let v = value.lowercased()
        return (3...20).contains(v.count) && v.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "." || $0 == "_" }
    }
    /// Sugjerim username-i nga emaili (p.sh. juri.qirjazi@... → juri.qirjazi).
    static func suggestion(from email: String) -> String {
        let local = email.split(separator: "@").first.map(String.init)?.lowercased() ?? ""
        let cleaned = String(local.filter { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "." || $0 == "_" }.prefix(20))
        return cleaned.count >= 3 ? cleaned : ""
    }
}

// MARK: - Krijimi i profilit pas regjistrimit

/// Del pas regjistrimit/hyrjes kur llogaria s'ka ende username: username unik + emri i shfaqur + avatari.
struct ProfileSetup: View {
    @ObservedObject var social: SocialModel
    @EnvironmentObject private var account: Account
    private var avatar = AvatarStore()
    @State private var username = ""
    @State private var displayName = ""
    @State private var available: Bool?
    @State private var checking = false

    init(social: SocialModel) { self.social = social }

    var body: some View {
        Page {
            VStack(spacing: 10) {
                AvatarBadge(emoji: avatar.emoji, color: avatar.color, size: 96)
                Text("Krijo profilin tënd").font(.system(.largeTitle, design: .rounded).weight(.black))
                Text("Username-i është vetëm i yti dhe shokët të gjejnë me të. Emri i shfaqur është ai që shohin.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity)
            UsernameField(username: $username, available: $available, checking: $checking, social: social)
            TextField("Emri i shfaqur (p.sh. Juri Q.)", text: $displayName)
                .textFieldStyle(.plain).padding(14).glass(cornerRadius: 16)
            Text("Personazhi").font(.headline)
            AvatarPicker()
            if !social.message.isEmpty { Text(social.message).foregroundStyle(.red) }
            Button {
                Task {
                    if await social.save(username: username, displayName: displayName, emoji: avatar.emoji, color: avatar.colorIndex) {
                        avatar.nickname = displayName
                        Haptics.celebrate()
                    }
                }
            } label: { Text(social.busy ? "Po ruhet…" : "Vazhdo").frame(maxWidth: .infinity) }
            .buttonStyle(.liquidProminent)
            .disabled(available != true || displayName.trimmingCharacters(in: .whitespaces).isEmpty || social.busy)
        }
        .onAppear {
            if username.isEmpty { username = SocialModel.suggestion(from: account.email) }
            if displayName.isEmpty { displayName = avatar.nickname }
        }
    }
}

/// Fusha e username-it me kontroll të menjëhershëm nëse është i lirë.
struct UsernameField: View {
    @Binding var username: String
    @Binding var available: Bool?
    @Binding var checking: Bool
    @ObservedObject var social: SocialModel
    var current: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("@").font(.headline).foregroundStyle(Color.lagoon)
                TextField("username", text: $username)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                if checking { ProgressView().controlSize(.small) }
                else if let available {
                    Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(available ? Color.green : Color.red)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(14).glass(cornerRadius: 16)
            Text(hint).font(.caption).foregroundStyle(available == false ? Color.red : Color.secondary)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: available)
        .task(id: username) {
            let value = username.lowercased()
            if value != username { username = value; return }
            if let current, value == current { available = true; return }
            guard SocialModel.validUsername(value) else { available = value.isEmpty ? nil : false; return }
            checking = true
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            available = await social.isAvailable(value)
            checking = false
        }
    }
    private var hint: String {
        if username.isEmpty { return "3–20 shkronja të vogla, numra, pikë ose _ (pa hapësira)." }
        if !SocialModel.validUsername(username) { return "Vetëm shkronja të vogla a–z, numra, pikë ose _ (3–20)." }
        switch available {
        case true?: return "I lirë ✓ Vetëm ti do ta kesh."
        case false?: return "Ky username është i zënë. Provo një tjetër."
        default: return "Po kontrollohet…"
        }
    }
}

/// Zgjedhja e avatarit (emoji + ngjyrë), e përdorur te krijimi i profilit dhe te Cilësimet.
struct AvatarPicker: View {
    private var avatar = AvatarStore()
    init() {}
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 50), spacing: 8)], spacing: 8) {
                ForEach(AvatarStore.emojis, id: \.self) { emoji in
                    Button {
                        Haptics.tap()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { avatar.emoji = emoji }
                    } label: {
                        Text(emoji).font(.system(size: 26)).frame(width: 50, height: 50)
                            .glass(cornerRadius: 14, tint: avatar.emoji == emoji ? avatar.color : nil, strength: avatar.emoji == emoji ? 0.4 : 0)
                            .scaleEffect(avatar.emoji == emoji ? 1.08 : 1)
                    }.buttonStyle(.springy)
                }
            }
            HStack(spacing: 12) {
                ForEach(AvatarStore.colors.indices, id: \.self) { index in
                    Button {
                        Haptics.tap()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { avatar.colorIndex = index }
                    } label: {
                        Circle().fill(AvatarStore.colors[index]).frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(.white, lineWidth: avatar.colorIndex == index ? 3 : 0))
                            .scaleEffect(avatar.colorIndex == index ? 1.15 : 1)
                    }.buttonStyle(.plain).accessibilityLabel("Ngjyra \(index + 1)")
                }
            }
        }
    }
}

// MARK: - Shokët

struct FriendsView: View {
    @ObservedObject var social: SocialModel
    @EnvironmentObject private var account: Account
    @State private var query = ""
    @State private var removing: PublicUser?

    var body: some View {
        Page {
            HStack {
                Text("Shokët").font(.system(.largeTitle, design: .rounded).weight(.black))
                Spacer()
                if let username = social.profile?.username {
                    Text("@" + username).font(.subheadline.bold()).padding(.horizontal, 12).padding(.vertical, 6).glassCapsule()
                }
            }
            if !account.isOnline {
                Label("Shokët punojnë vetëm me llogari online. Hyr me emailin e shkollës.", systemImage: "wifi.slash")
                    .padding().glass(cornerRadius: 18)
            } else if let blocked = social.blocked {
                // Mbrojtja e nxënësve: shokët vetëm mes nxënësve të pranuar në klasë.
                VStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill").font(.system(size: 44)).foregroundStyle(Color.lagoon)
                    Text(blocked).font(.headline).multilineTextAlignment(.center)
                    Text("Për sigurinë e nxënësve, shokët mund të shtohen vetëm mes nxënësve që mësuesi i ka pranuar në klasë.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(24).glass(cornerRadius: 22)
            } else {
                // Kërkimi me username.
                HStack(spacing: 10) {
                    Image(systemName: "person.badge.plus").font(.headline).foregroundStyle(Color.lagoon)
                    TextField("Shto shok: kërko @username", text: $query)
                        .textFieldStyle(.plain).autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain) }
                }
                .padding(.horizontal, 16).padding(.vertical, 13).glassCapsule()
                .task(id: query) {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    guard !Task.isCancelled else { return }
                    await social.search(query)
                }
                if !social.message.isEmpty {
                    Text(social.message).font(.callout.bold()).transition(.move(edge: .top).combined(with: .opacity))
                }
                if query.count >= 3 {
                    if social.results.isEmpty { Text("Askush me këtë username.").foregroundStyle(.secondary) }
                    ForEach(social.results) { user in
                        row(user) {
                            switch user.relation {
                            case "friend": Label("Shokë", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.subheadline.bold())
                            case "sent": Text("Ftesa u dërgua").font(.subheadline).foregroundStyle(.secondary)
                            case "received": Button("Prano") { Task { await social.respond(user, accept: true); await social.search(query) } }.buttonStyle(.liquidProminent)
                            default: Button { Task { await social.invite(user) } } label: { Label("Shto", systemImage: "person.badge.plus") }.buttonStyle(.liquidProminent)
                            }
                        }
                    }
                }
                // Ftesat që të kanë ardhur.
                if !social.incoming.isEmpty {
                    sectionTitle("Ftesa për ty", count: social.incoming.count, icon: "bell.badge.fill")
                    ForEach(social.incoming) { user in
                        row(user) {
                            HStack(spacing: 8) {
                                Button { Task { await social.respond(user, accept: false) } } label: { Image(systemName: "xmark") }.buttonStyle(.liquid)
                                Button { Task { await social.respond(user, accept: true) } } label: { Label("Prano", systemImage: "checkmark") }.buttonStyle(.liquidProminent)
                            }
                        }
                    }
                }
                sectionTitle("Shokët e mi", count: social.friends.count, icon: "person.2.fill")
                if social.friends.isEmpty {
                    VStack(spacing: 8) {
                        Text("👋").font(.system(size: 48))
                        Text("Ende pa shokë. Kërko username-in e një shoku sipër dhe dërgoji ftesë.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(20).glass(cornerRadius: 22)
                }
                ForEach(Array(social.friends.enumerated()), id: \.element.id) { index, user in
                    row(user) { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                        .contextMenu {
                            Button(role: .destructive) { removing = user } label: { Label("Hiqe nga shokët", systemImage: "person.badge.minus") }
                        }
                        .appearIn(index)
                }
                if !social.outgoing.isEmpty {
                    sectionTitle("Ftesa të dërguara", count: social.outgoing.count, icon: "paperplane.fill")
                    ForEach(social.outgoing) { user in
                        row(user) { Button("Anulo") { Task { await social.remove(user) } }.buttonStyle(.liquid) }
                    }
                }
            }
        }
        .navigationTitle("Shokët")
        .refreshable { await social.loadFriends() }
        .task { if account.isOnline { await social.loadFriends(); if !social.loadedProfile { await social.loadProfile() } } }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: social.message)
        .confirmationDialog("Ta heqësh \(removing?.displayName ?? "") nga shokët?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Hiqe", role: .destructive) { if let user = removing { Task { await social.remove(user) } }; removing = nil }
            Button("Anulo", role: .cancel) { removing = nil }
        }
    }

    private func sectionTitle(_ title: String, count: Int, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(Color.lagoon).bounceSymbol(on: count)
            Text(title).font(.title3.bold())
            Text("\(count)").font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 2).glassCapsule()
        }.padding(.top, 8)
    }

    private func row<Trailing: View>(_ user: PublicUser, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            AvatarBadge(emoji: user.avatarEmoji, color: user.color, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName).font(.headline)
                Text("@" + user.username).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            trailing()
        }
        .padding(12).glass(cornerRadius: 20, interactive: true)
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .scale.combined(with: .opacity)))
    }
}

// MARK: - Cilësimet

struct SettingsView: View {
    @ObservedObject var social: SocialModel
    @EnvironmentObject private var account: Account
    private var avatar = AvatarStore()
    @State private var username = ""
    @State private var displayName = ""
    @State private var available: Bool?
    @State private var checking = false
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var passwordMessage = ""
    @State private var savedMessage = ""

    init(social: SocialModel) { self.social = social }

    var body: some View {
        Page {
            Text("Cilësimet").font(.system(.largeTitle, design: .rounded).weight(.black))

            card("Profili", icon: "person.crop.circle.fill") {
                HStack(spacing: 14) {
                    AvatarBadge(emoji: avatar.emoji, color: avatar.color, size: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName.isEmpty ? "Pa emër" : displayName).font(.title3.bold())
                        if !username.isEmpty { Text("@" + username).foregroundStyle(.secondary) }
                    }
                }
                if account.isOnline {
                    Text("Emri i shfaqur").font(.subheadline.bold())
                    TextField("Emri i shfaqur", text: $displayName).textFieldStyle(.plain).padding(12).glass(cornerRadius: 14)
                    Text("Username").font(.subheadline.bold())
                    UsernameField(username: $username, available: $available, checking: $checking, social: social, current: social.profile?.username)
                    Button {
                        Task {
                            let changedName = username != (social.profile?.username ?? "")
                            if await social.save(username: changedName ? username : nil, displayName: displayName) {
                                avatar.nickname = displayName
                                withAnimation { savedMessage = "U ruajt ✓" }
                                Haptics.success()
                            }
                        }
                    } label: { Text(social.busy ? "Po ruhet…" : "Ruaj profilin").frame(maxWidth: .infinity) }
                    .buttonStyle(.liquidProminent)
                    .disabled(available == false || displayName.trimmingCharacters(in: .whitespaces).isEmpty || social.busy)
                    if !savedMessage.isEmpty { Text(savedMessage).font(.callout.bold()).foregroundStyle(.green) }
                    if !social.message.isEmpty { Text(social.message).font(.callout).foregroundStyle(.red) }
                } else {
                    TextField("Emri yt", text: avatar.$nickname).textFieldStyle(.plain).padding(12).glass(cornerRadius: 14)
                }
            }

            card("Avatari", icon: "face.smiling.fill") {
                AvatarPicker()
            }

            card("Llogaria", icon: "envelope.fill") {
                LabeledContent("Emaili", value: social.profile?.email ?? account.email)
                if account.isOnline {
                    Text("Ndrysho fjalëkalimin").font(.subheadline.bold()).padding(.top, 4)
                    PasswordInput(title: "Fjalëkalimi aktual", text: $currentPassword)
                    PasswordInput(title: "Fjalëkalimi i ri", text: $newPassword, isNew: true)
                    if !newPassword.isEmpty { PasswordChecklist(password: newPassword) }
                    Button("Ndrysho fjalëkalimin") { Task { await changePassword() } }
                        .buttonStyle(.liquidProminent)
                        .disabled(currentPassword.isEmpty || PasswordPolicy.problem(newPassword, email: account.email) != nil)
                    if !passwordMessage.isEmpty { Text(passwordMessage).font(.callout) }
                }
            }

            card("Pamja", icon: "paintpalette.fill") {
                AppearanceSettings()
            }
        }
        .navigationTitle("Cilësimet")
        .task {
            if account.isOnline && !social.loadedProfile { await social.loadProfile() }
            syncFields()
        }
        .onChange(of: social.profile?.username) { _ in syncFields() }
        .onChange(of: avatar.emoji) { value in if account.isOnline { Task { _ = await social.save(emoji: value) } } }
        .onChange(of: avatar.colorIndex) { value in if account.isOnline { Task { _ = await social.save(color: value) } } }
    }

    private func syncFields() {
        if let profile = social.profile {
            if username.isEmpty { username = profile.username ?? "" }
            if displayName.isEmpty { displayName = profile.displayName ?? avatar.nickname }
        } else if displayName.isEmpty { displayName = avatar.nickname }
    }

    private func changePassword() async {
        if let problem = PasswordPolicy.problem(newPassword, email: account.email) { passwordMessage = problem; return }
        do {
            try await SupabaseAuth.shared.checkPassword(email: account.email, password: currentPassword)
            try await SupabaseAuth.shared.updatePassword(newPassword)
            currentPassword = ""; newPassword = ""
            passwordMessage = "Fjalëkalimi u ndryshua ✓"
            Haptics.success()
        } catch {
            passwordMessage = (error as? LocalizedError)?.errorDescription ?? "Fjalëkalimi aktual nuk është i saktë."
            Haptics.error()
        }
    }

    private func card<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.title3.bold()).foregroundStyle(Color.lagoon)
            content()
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 24)
    }
}
