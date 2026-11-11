import Foundation
import Security
import CommonCrypto

// Used only in offline mode. Keychain stores a salted verifier, never the password.
enum LocalLogin {
    struct Record: Codable {
        let id: UUID
        let role: String
        let salt: Data
        let verifier: Data
    }
    private static func key(_ email: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "ScienceQuest") + ".offline.v1",
         kSecAttrAccount as String: email.lowercased()]
    }
    private static func derive(_ password: String, salt: Data) throws -> Data {
        let bytes = Array(password.utf8)
        guard !bytes.isEmpty else { throw AuthFailure(message: "Shkruaj fjalëkalimin.") }
        var hash = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeBytes { p in
            salt.withUnsafeBytes { s in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                    p.bindMemory(to: Int8.self).baseAddress!, bytes.count,
                    s.bindMemory(to: UInt8.self).baseAddress!, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 600_000, &hash, 32)
            }
        }
        guard status == kCCSuccess else { throw AuthFailure(message: "Fjalëkalimi nuk u përpunua.") }
        return Data(hash)
    }
    static func login(_ email: String, _ password: String) throws -> Record {
        var query = key(email)
        query[kSecReturnData as String] = true
        var output: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &output)
        guard status == errSecSuccess, let data = output as? Data,
              let record = try? JSONDecoder().decode(Record.self, from: data),
              record.verifier == (try derive(password, salt: record.salt)) else {
            throw AuthFailure(message: "Emaili ose fjalëkalimi nuk përputhet me llogarinë në këtë pajisje.")
        }
        return record
    }
    static func remove(_ email: String) throws {
        guard SecItemDelete(key(email) as CFDictionary) == errSecSuccess else { throw AuthFailure(message: "Fshirja nuk u krye. Provo përsëri.") }
    }
}

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

enum AuthStage: Equatable { case entry, emailCode(String), emailLogin(String), mfa(String), mfaSetup, role, recoveryCode(String), existingAccount(String), roleMismatch(SchoolRole) }
enum AccessEntry: String { case studentParent, teacher }

struct AuthFailure: LocalizedError {
    let message: String
    var code: String? = nil
    var errorDescription: String? { message }
}

@MainActor
final class Account: ObservableObject {
    @Published private(set) var role: SchoolRole?
    @Published private(set) var isOnline = false
    @Published var recoveryNotice = ""
    @Published var syncMessage = ""
    @Published var stage: AuthStage = .entry
    @Published var cloudMessage = ""
    /// Kodi i rikuperimit u pranua; mbetet vetëm fjalëkalimi i ri (p.sh. pas një fjalëkalimi të dobët).
    @Published private(set) var recoveryVerified = false
    private var recoveryEmail = ""
    // Vetëm në memorie; kurrë në disk. Përdoren pas konfirmimit të emailit.
    var pendingRole: SchoolRole?
    /// Roli që përdoruesi provoi të regjistronte me një email që kishte tashmë llogari (rasti B). Vetëm për mesazhin; serveri vendos rolin.
    private var attemptedRole: SchoolRole?
    var pendingTeacherCode = ""
    private var pendingNewPassword: String?
    var cloud: Bool { SupabaseConfig.enabled }
    private(set) var identity = ""
    private(set) var email = ""
    private(set) var token = ""
    private var baseline: [String: ProgressEntry] = [:]
    private var syncing = false
    var storage: UserDefaults { UserDefaults(suiteName: "ScienceQuest." + identity)! }

    func open(_ address: String, password: String, newRole: SchoolRole?, teacherCode: String) async throws {
        let reply: LoginReply = try await SchoolAPI.call(newRole == nil ? "login" : "register", body: [
            "email":address, "password":password, "role":newRole?.rawValue ?? "", "teacherCode":teacherCode])
        try SessionVault.save(reply.token)
        token = reply.token; identity = "school-" + reply.user.id; email = reply.user.email
        isOnline = true
        recoveryNotice = reply.recovery ?? ""
        baseline = [:]
        // Never merge local identities merely because their email matches.
        // Cloud authentication must succeed, then local password verification proves
        // access to the old device's progress before offering an explicit import.
        if let bytes = storage.data(forKey:"syncBaseline.v7"), let entries = try? JSONDecoder().decode([ProgressEntry].self, from:bytes) {
            baseline = Dictionary(uniqueKeysWithValues:entries.map { ($0.key,$0) })
        }
        role = SchoolRole(rawValue:reply.user.role) ?? .student
        await synchronize()
    }
    // MARK: Supabase
    private static func cloudRole(_ value: String) -> SchoolRole? {
        switch value { case "student": return .student; case "parent": return .parent; case "teacher": return .teacher; default: return nil }
    }
    func cloudSignUp(email: String, password: String) async throws {
        let exists = try await SupabaseAuth.shared.signUp(email: email, password: password)
        if exists {
            // Rasti A: nuk krijohet llogari e dytë dhe roli ekzistues nuk ndryshon. Roli nuk zbulohet para hyrjes.
            attemptedRole = pendingRole; pendingRole = nil; pendingTeacherCode = ""
            stage = .existingAccount(email); return
        }
        stage = .emailCode(email)
    }
    /// Rasti B, pasi përdoruesi provoi pronësinë (fjalëkalim + kod emaili): vazhdon te këndi i rolit të tij real.
    func cloudContinueWithServerRole() async throws {
        attemptedRole = nil
        try await finishSignIn()
    }
    func cloudResend(email: String) async throws { try await SupabaseAuth.shared.resend(email: email) }
    func cloudVerify(email: String, code: String) async throws {
        _ = try await SupabaseAuth.shared.verify(email: email, code: code.trimmingCharacters(in: .whitespacesAndNewlines), type: "signup")
        try await finishSignIn()
    }
    func cloudSignIn(email: String, password: String) async throws {
        do { _ = try await SupabaseAuth.shared.signIn(email: email, password: password) }
        catch let failure as AuthFailure where failure.code == "email_not_confirmed" {
            try? await SupabaseAuth.shared.resend(email: email)
            stage = .emailCode(email)
            throw AuthFailure(message: "Emaili nuk është konfirmuar. Të dërguam një kod të ri; shkruaje më poshtë.")
        }
        try await finishSignIn()
    }
    func cloudMFA(code: String) async throws {
        guard case .mfa(let factor) = stage else { return }
        try await SupabaseAuth.shared.mfaChallengeVerify(factorID: factor, code: code.trimmingCharacters(in: .whitespacesAndNewlines))
        if let password = pendingNewPassword { try await SupabaseAuth.shared.updatePassword(password); pendingNewPassword = nil }
        try await finishSignIn()
    }
    /// 2FA i detyrueshëm: nëse serveri e kërkon dhe llogaria nuk ka faktor, aplikacioni e çon përdoruesin te konfigurimi.
    func cloudStartMFASetup() async throws -> GoTrueEnroll { try await SupabaseAuth.shared.mfaEnroll() }
    func cloudFinishMFASetup(factorID: String, code: String) async throws {
        try await SupabaseAuth.shared.mfaChallengeVerify(factorID: factorID, code: code.trimmingCharacters(in: .whitespacesAndNewlines))
        try await finishSignIn()
    }
    func cloudSubmitLoginCode(_ code: String) async throws {
        let _: OKReply = try await SchoolAPI.call("loginCodeVerify", body: ["code": code.trimmingCharacters(in: .whitespacesAndNewlines)])
        try await finishSignIn()
    }
    func cloudResendLoginCode() async throws { try await SupabaseAuth.shared.sendLoginCode() }
    func cloudChooseRole(_ chosen: SchoolRole) async throws {
        guard chosen != .teacher else { return }
        let _: OKReply = try await SchoolAPI.call("chooseRole", body: ["role": chosen == .student ? "student" : "parent"])
        try await finishSignIn()
    }
    func cloudRedeemTeacher(_ code: String) async throws {
        let _: OKReply = try await SchoolAPI.call("redeemTeacherCode", body: ["code": code.trimmingCharacters(in: .whitespacesAndNewlines)])
        try await finishSignIn()
    }
    func cloudRecover(email: String) async throws {
        try await SupabaseAuth.shared.recover(email: email)
        stage = .recoveryCode(email)
    }
    func cloudCompleteRecovery(email: String, code: String, newPassword: String) async throws {
        guard newPassword.count >= 10 else { throw AuthFailure(message: "Fjalëkalimi duhet të ketë të paktën 10 karaktere.") }
        // Kodi përdoret vetëm një herë. Nëse fjalëkalimi refuzohet (p.sh. shumë i zakonshëm), nuk e kërkojmë kodin përsëri.
        if !(recoveryVerified && recoveryEmail == email && SupabaseAuth.shared.session != nil) {
            _ = try await SupabaseAuth.shared.verify(email: email, code: code.trimmingCharacters(in: .whitespacesAndNewlines), type: "recovery")
            recoveryVerified = true; recoveryEmail = email
        }
        do { try await SupabaseAuth.shared.updatePassword(newPassword) }
        catch let failure as AuthFailure where failure.code == "insufficient_aal" {
            // Llogaria ka 2FA: kërko faktorin e dytë, pastaj ndrysho fjalëkalimin.
            pendingNewPassword = newPassword
            let user = try await SupabaseAuth.shared.currentUser()
            if let factor = user.factors?.first(where: { $0.status == "verified" }) { stage = .mfa(factor.id); return }
            throw failure
        }
        recoveryVerified = false; recoveryEmail = ""
        try await finishSignIn()
    }
    func cancelCloudSignIn() { logout() }
    func restore() async {
        guard cloud, role == nil, SupabaseAuth.shared.session == nil else { return }
        SupabaseAuth.shared.loadStored()
        guard SupabaseAuth.shared.session != nil else { return }
        do { _ = try await SupabaseAuth.shared.accessToken(); try await finishSignIn() }
        catch { cloudMessage = "Seanca nuk u rikthye (" + error.localizedDescription + "). Hyr përsëri ose shfleto mësimet pa llogari." }
    }
    /// Pas çdo hyrje/verifikimi: kontrollon faktorin e dytë, pastaj pyet SERVERIN për rolin. Roli nuk vjen kurrë nga klienti.
    private func finishSignIn() async throws {
        guard let current = SupabaseAuth.shared.session else { throw AuthFailure(message: "Seanca ka mbaruar. Hyr përsëri.") }
        let user = try await SupabaseAuth.shared.currentUser()
        if current.aal != "aal2", let factor = user.factors?.first(where: { $0.status == "verified" && ($0.factor_type ?? "totp") == "totp" }) {
            stage = .mfa(factor.id); return
        }
        let me: MeReply = try await SchoolAPI.call("me")
        if me.mfaRequired ?? false {
            if (me.mfaMethod ?? "totp") == "email" {
                // Faktori i dytë me kod emaili: kërkohet në çdo hyrje (çdo seancë e re). Serveri e zbaton rregullin.
                if !(me.secondFactorOk ?? false) {
                    email = me.email
                    do { try await SupabaseAuth.shared.sendLoginCode(); cloudMessage = "Të dërguam një kod te " + me.email + "." }
                    catch { cloudMessage = error.localizedDescription }
                    stage = .emailLogin(me.email); return
                }
            } else if !me.mfaEnrolled { email = me.email; stage = .mfaSetup; return }
        }
        if me.role == "unassigned" {
            email = me.email
            // Llogari pa rol ende: roli që provoi në regjistrim përdoret si zgjedhje e parë (serveri e vendos një herë).
            if pendingRole == nil, let attempted = attemptedRole { pendingRole = attempted }
            attemptedRole = nil
            if let chosen = pendingRole, chosen != .teacher { pendingRole = nil; try await cloudChooseRole(chosen); return }
            if !pendingTeacherCode.isEmpty {
                let code = pendingTeacherCode; pendingTeacherCode = ""; stage = .role
                try await cloudRedeemTeacher(code); return
            }
            stage = .role; return
        }
        if me.role == "teacher" && me.teacherStatus != "active" {
            let pending = me.teacherStatus == "pending_approval"
            await SupabaseAuth.shared.logout(); stage = .entry
            throw AuthFailure(message: pending ? "Llogaria e mësuesit pret miratimin e administratorit. Provo përsëri pas miratimit." : "Llogaria e mësuesit nuk u miratua. Kontakto administratorin.")
        }
        guard let resolved = Self.cloudRole(me.role) else { throw AuthFailure(message: "Roli i llogarisë nuk njihet. Kontakto administratorin.") }
        // Rasti B: provoi të regjistrohej me rol tjetër. Tani që pronësia u vërtetua, i tregojmë rolin real dhe e çojmë te hyrja e duhur.
        if let attempted = attemptedRole, attempted != resolved {
            email = me.email; cloudMessage = ""; stage = .roleMismatch(resolved); return
        }
        attemptedRole = nil
        token = current.access; identity = "school-" + me.id; email = me.email; isOnline = true
        recoveryNotice = ""; baseline = [:]; cloudMessage = ""
        if let bytes = storage.data(forKey:"syncBaseline.v7"), let entries = try? JSONDecoder().decode([ProgressEntry].self, from:bytes) {
            baseline = Dictionary(uniqueKeysWithValues:entries.map { ($0.key,$0) })
        }
        stage = .entry; role = resolved
        await synchronize()
    }
    func openLegacy(_ address: String, password: String) async throws {
        let record = try await Task.detached { try LocalLogin.login(address,password) }.value
        identity = "local-" + record.id.uuidString; email = address; token = ""; isOnline = false
        role = SchoolRole(rawValue:record.role) ?? .student
    }
    func guest() { identity = "guest-v7"; email = ""; token = ""; isOnline = false; role = .student }
    func logout() {
        let old = token
        if cloud { Task { await SupabaseAuth.shared.logout() } }
        else if !old.isEmpty { Task { let _: OKReply? = try? await SchoolAPI.call("logout",token:old) } }
        pendingRole = nil; attemptedRole = nil; pendingTeacherCode = ""; pendingNewPassword = nil; recoveryVerified = false; recoveryEmail = ""; stage = .entry; cloudMessage = ""
        SessionVault.clear(); role = nil; identity = ""; email = ""; token = ""; isOnline = false; baseline = [:]; recoveryNotice = ""; syncMessage = ""
    }
    func remove(password: String) async throws {
        if isOnline { let _: OKReply = try await SchoolAPI.call("deleteAccount",body:["password":password],token:token) }
        else if !email.isEmpty { _ = try LocalLogin.login(email,password); try LocalLogin.remove(email) }
        UserDefaults.standard.removePersistentDomain(forName:"ScienceQuest." + identity)
        logout()
    }
    func importLegacy(password: String) async throws {
        guard isOnline else { return }
        let record = try await Task.detached { [email] in try LocalLogin.login(email,password) }.value
        let old = UserDefaults(suiteName:"ScienceQuest.local-" + record.id.uuidString)!
        for (key,value) in old.dictionaryRepresentation() where Self.allowed(key) && storage.object(forKey:key) == nil { storage.set(value,forKey:key) }
        await synchronize()
    }
    private static func allowed(_ key: String) -> Bool {
        ["study","mastered","studentLevel","goal","quiz","lab","homeActivity","solvedTopics","spring","practical","chemMixHistory","game","familyReport"].contains { key.hasPrefix($0) }
    }
    private func localProgress() -> [String: ProgressValue] {
        var result: [String: ProgressValue] = [:]
        // Use only this account's persistent domain, never global defaults.
        let values = UserDefaults.standard.persistentDomain(forName:"ScienceQuest." + identity) ?? [:]
        for (key,value) in values where Self.allowed(key) {
            if let v = value as? Data { result[key] = .data(v.base64EncodedString()) }
            else if let v = value as? String { result[key] = .string(v) }
            else if let v = value as? NSNumber { result[key] = .number(v.doubleValue) }
        }
        return result
    }
    func synchronize() async {
        guard isOnline, !syncing else { return }
        syncing = true; defer { syncing = false }
        let accountID = identity, session = token, local = localProgress()
        let changes = local.compactMap { key,value -> ProgressEntry? in
            guard baseline[key]?.value != value else { return nil }
            return ProgressEntry(key:key,value:value,version:baseline[key]?.version ?? 0)
        }
        do {
            let reply: ProgressReply
            if changes.isEmpty { reply = try await SchoolAPI.call("progressGet",token:session) }
            else {
                let data = try JSONEncoder().encode(changes)
                let values = try JSONSerialization.jsonObject(with:data)
                reply = try await SchoolAPI.call("progressPut",body:["changes":values],token:session)
            }
            guard identity == accountID, token == session else { return }
            let conflicts = Set(reply.conflicts ?? [])
            let current = localProgress()
            for entry in reply.entries {
                // If another device changed the same note, keep our version as a
                // visible backup; do not silently overwrite it with stale text.
                if conflicts.contains(entry.key), let mine = current[entry.key] {
                    storage.set(mine.property,forKey:"conflict." + entry.key)
                }
                // Do not erase edits made while the HTTP request was in flight.
                if current[entry.key] == local[entry.key] { storage.set(entry.value.property,forKey:entry.key) }
                baseline[entry.key] = entry
            }
            storage.set(try JSONEncoder().encode(Array(baseline.values)),forKey:"syncBaseline.v7")
            syncMessage = conflicts.isEmpty ? "Progresi u sinkronizua." : "Ka ndryshime nga dy pajisje. Versioni yt ruhet te Konfliktet e shënimeve."
        } catch { if identity == accountID { syncMessage = "Progresi mbetet në pajisje; sinkronizimi nuk u krye: " + error.localizedDescription } }
    }
}

struct AccessScreen: View {
    @EnvironmentObject private var account: Account
    @State private var signup = false
    @State private var email = ""
    @State private var password = ""
    @State private var teacherCode = ""
    @State private var role = SchoolRole.student
    @State private var busy = false
    @State private var message = ""
    @State private var server = SchoolConfig.address
    @State private var recovery = ""
    @State private var newPassword = ""
    @State private var newRecovery = ""
    var body: some View {
        if SupabaseConfig.enabled { CloudAccessScreen() } else { legacyBody }
    }
    private var legacyBody: some View {
        Page {
            QuestCover()
            Text("Llogaria e shkollës").font(.title.bold())
            Picker("Llogaria",selection:$signup) { Text("Hyr").tag(false); Text("Regjistrohu").tag(true) }.pickerStyle(.segmented)
            TextField("Email",text:$email).autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(.emailAddress).textInputAutocapitalization(.never)
                #endif
            PasswordInput(title: "Fjalëkalimi", text: $password, isNew: signup)
            if signup {
                Picker("Roli",selection:$role) { ForEach(SchoolRole.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                if role == .teacher {
                    SecureField("Kodi i ftesës (5 shifra)",text:$teacherCode)
                    Text("Administratori e jep kodin për emailin tënd. Kodi përdoret një herë, skadon pas 7 ditësh dhe bllokohet pas 5 gabimeve; nëse bllokohet, kërko një të ri.").font(.footnote)
                }
                Text("Fjalëkalimi: të paktën 10 karaktere. Pas regjistrimit ruaj kodin personal të rikuperimit.").font(.footnote)
            }
            Button(signup ? "Regjistrohu" : "Hyr") { perform { try await account.open(email.trimmingCharacters(in:.whitespacesAndNewlines).lowercased(),password:password,newRole:signup ? role : nil,teacherCode:teacherCode) } }.buttonStyle(.borderedProminent)
            if busy { ProgressView() }
            if !message.isEmpty { Text(message).foregroundStyle(Color.red) }
            DisclosureGroup("Lidhja e shkollës") {
                TextField("https://adresa-e-shkollës",text:$server).autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                Text("Të gjitha pajisjet duhet të përdorin të njëjtën adresë. Shërbimi është në folderin Server dhe drejtohet nga shkolla.").font(.footnote)
                Button("Ruaj adresën") { SchoolConfig.address = server.trimmingCharacters(in:.whitespacesAndNewlines); message = "Adresa u ruajt." }
            }
            DisclosureGroup("Harrove fjalëkalimin?") {
                Text("Përdor emailin më sipër dhe kodin personal që ruajte gjatë regjistrimit. Nuk kërkohet kod me email në çdo hyrje.")
                SecureField("Kodi i rikuperimit",text:$recovery)
                PasswordInput(title: "Fjalëkalimi i ri", text: $newPassword, isNew: true)
                Button("Ndrysho fjalëkalimin") {
                    perform {
                        let reply: OKReply = try await SchoolAPI.call("recover",body:["email":email,"recovery":recovery,"password":newPassword])
                        newRecovery = reply.recovery ?? ""; recovery = ""; newPassword = ""; message = "Fjalëkalimi u ndryshua. Ruaj kodin e ri dhe përdor Hyr."
                    }
                }
                if !newRecovery.isEmpty { Text("Kodi i ri: " + newRecovery).textSelection(.enabled) }
            }
            DisclosureGroup("Llogaria ime e vjetër në këtë pajisje") {
                Text("Llogaritë e versionit 6 janë lokale. Hapi këtu me emailin dhe fjalëkalimin e vjetër. Krijo llogarinë e përbashkët veçmas; pastaj mund të importosh progresin nga Profili.")
                Button("Hap llogarinë e vjetër") { perform { try await account.openLegacy(email.trimmingCharacters(in:.whitespacesAndNewlines).lowercased(),password:password) } }
            }
            Button("Shfleto mësimet pa llogari") { account.guest() }
        }.textFieldStyle(.roundedBorder).tint(.lagoon).disabled(busy)
    }
    private func perform(_ work: @escaping () async throws -> Void) {
        guard !busy else { return }; busy = true; message = ""
        Task { defer { busy = false }; do { try await work() } catch { message = error.localizedDescription } }
    }
}

struct AccountControls: View {
    @EnvironmentObject private var account: Account
    @State private var confirm = false
    @State private var password = ""
    @State private var message = ""
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            if account.isOnline {
                Text(account.email).font(.caption)
                Text(account.syncMessage).font(.caption)
                Button("Sinkronizo progresin tani") { Task { await account.synchronize() } }
                DisclosureGroup("Importo progresin nga llogaria e vjetër") {
                    PasswordInput(title: "Fjalëkalimi i llogarisë së vjetër", text: $password)
                    Button("Importo nga kjo pajisje") { Task { do { try await account.importLegacy(password:password); message = "Importimi përfundoi." } catch { message = error.localizedDescription }; password = "" } }
                }
                NavigationLink("Konfliktet e shënimeve") { ProgressConflicts() }
                if account.cloud { SecuritySettings() }
            }
            Button("Dil nga llogaria") { Task { await account.synchronize(); account.logout() } }
            DisclosureGroup("Fshi llogarinë") {
                PasswordInput(title: "Fjalëkalimi aktual", text: $password)
                Button("Fshi llogarinë",role:.destructive) { confirm = true }
            }
            if !message.isEmpty { Text(message) }
        }.buttonStyle(.bordered)
        .alert("Ta fshish llogarinë dhe të dhënat e saj?",isPresented:$confirm) {
            Button("Anulo",role:.cancel) {}
            Button("Fshije",role:.destructive) { Task { do { try await account.remove(password:password) } catch { message = error.localizedDescription } } }
        }
    }
}

struct ProgressConflicts: View {
    @EnvironmentObject private var account: Account
    @State private var refresh = 0
    var body: some View {
        Page {
            Text("Konfliktet e shënimeve").font(.title.bold())
            Text("Kur dy pajisje ndryshojnë të njëjtën të dhënë, kopja lokale ruhet këtu. Kopjo tekstin që do të mbash te mësimi përkatës dhe sinkronizoje sërish.")
            let values = account.storage.dictionaryRepresentation().filter { $0.key.hasPrefix("conflict.") }
            if values.isEmpty { Text("Nuk ka konflikte.") }
            ForEach(values.keys.sorted(),id: \.self) { key in
                Text(key.replacingOccurrences(of:"conflict.",with:"")).bold()
                Text(String(describing:values[key]!)).textSelection(.enabled)
                Button("E kontrollova; hiq kopjen") { account.storage.removeObject(forKey:key); refresh += 1 }
            }
        }.id(refresh)
    }
}

// MARK: - Hyrja me Supabase: dy ekrane (Nxënës / Prind, Mësues)
struct CloudAccessScreen: View {
    @EnvironmentObject private var account: Account
    @State private var entry = AccessEntry(rawValue: UserDefaults.standard.string(forKey: "lastEntry.v8") ?? "") ?? .studentParent
    @State private var signup = false
    @State private var email = ""
    @State private var password = ""
    @State private var teacherCode = ""
    @State private var role = SchoolRole.student
    @State private var code = ""
    @State private var newPassword = ""
    @State private var busy = false
    @State private var message = ""
    var body: some View {
        Page {
            QuestCover()
            switch account.stage {
            case .entry: entryView
            case .emailCode(let mail): emailCodeView(mail)
            case .emailLogin(let mail): emailLoginView(mail)
            case .mfa: mfaView
            case .mfaSetup: MFASetupView()
            case .role: roleView
            case .recoveryCode(let mail): recoveryView(mail)
            case .existingAccount(let mail): existingAccountView(mail)
            case .roleMismatch(let real): roleMismatchView(real)
            }
            if busy { ProgressView() }
            if !message.isEmpty { Text(message).foregroundStyle(Color.red) }
            else if !account.cloudMessage.isEmpty { Text(account.cloudMessage).font(.footnote) }
        }.textFieldStyle(.roundedBorder).tint(.lagoon).disabled(busy)
    }
    private var mail: String { email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    @ViewBuilder private var entryView: some View {
        Text("Hyrja në shkollë").font(.title.bold())
        Picker("Hyrja", selection: $entry) { Text("Nxënës / Prind").tag(AccessEntry.studentParent); Text("Mësues").tag(AccessEntry.teacher) }.pickerStyle(.segmented)
        Text(entry == .teacher ? "Hyrje për mësuesit. Roli kontrollohet nga serveri në çdo kërkesë, jo nga ky ekran." : "Hyrje për nxënës dhe prindër. Një email është një llogari me një rol të vetëm; nëse je edhe prind edhe mësues, përdor dy emaile.").font(.footnote)
        Picker("Llogaria", selection: $signup) { Text("Hyr").tag(false); Text("Regjistrohu").tag(true) }.pickerStyle(.segmented)
        TextField("Email", text: $email).autocorrectionDisabled()
            #if os(iOS)
            .keyboardType(.emailAddress).textInputAutocapitalization(.never)
            #endif
        PasswordInput(title: "Fjalëkalimi", text: $password, isNew: signup)
        if signup { PasswordChecklist(password: password) }
        if signup {
            if entry == .studentParent {
                Picker("Roli", selection: $role) { Text("Nxënës").tag(SchoolRole.student); Text("Prind").tag(SchoolRole.parent) }.pickerStyle(.segmented)
                Text("Roli zgjidhet një herë dhe nuk ndryshohet nga aplikacioni.").font(.footnote)
            } else {
                SecureField("Kodi 5-shifror i mësuesit", text: $teacherCode)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                Text("Kodi kontrollohet vetëm në server dhe është i përbashkët, prandaj nuk provon vetë që je mësues. Administratori mund të kërkojë edhe miratim.").font(.footnote)
            }
            Text("Pas regjistrimit të dërgojmë një kod konfirmimi me email, pastaj çdo hyrje kërkon një kod të ri me email. Një email është një llogari.").font(.footnote)
        }
        Button(signup ? "Regjistrohu" : "Hyr") { submit() }.buttonStyle(.borderedProminent)
        DisclosureGroup("Harrove fjalëkalimin?") {
            Text("Të dërgojmë një kod me email për të caktuar fjalëkalim të ri. Nëse ke 2FA, do të kërkohet edhe faktori i dytë.").font(.footnote)
            Button("Më dërgo kodin") { perform { try await account.cloudRecover(email: mail) } }.disabled(mail.isEmpty)
        }
        DisclosureGroup("Llogaria ime e vjetër në këtë pajisje") {
            Text("Llogaritë lokale të versioneve të vjetra nuk ngarkohen në Supabase. Hyr me llogarinë e re, pastaj nga Profili importo progresin e praktikës me fjalëkalimin e vjetër. Ai nuk bëhet notë e verifikuar.").font(.footnote)
        }
        Button("Shfleto mësimet pa llogari") { account.guest() }
    }
    private func submit() {
        UserDefaults.standard.set(entry.rawValue, forKey: "lastEntry.v8")
        perform {
            if signup, let problem = PasswordPolicy.problem(password, email: mail) { throw AuthFailure(message: problem) }
            if signup {
                if entry == .teacher {
                    guard teacherCode.count == 5, teacherCode.allSatisfy({ $0.isNumber }) else { throw AuthFailure(message: "Kodi i mësuesit ka 5 shifra.") }
                    account.pendingRole = .teacher; account.pendingTeacherCode = teacherCode
                } else { account.pendingRole = role; account.pendingTeacherCode = "" }
                try await account.cloudSignUp(email: mail, password: password)
                teacherCode = ""
            } else { try await account.cloudSignIn(email: mail, password: password) }
        }
    }
    /// Rasti A: emaili ka tashmë llogari. Asnjë llogari e re nuk krijohet; roli nuk zbulohet para hyrjes.
    @ViewBuilder private func existingAccountView(_ address: String) -> some View {
        Text("Ke tashmë një llogari").font(.title.bold())
        Text("Ke tashmë një llogari. Hyr për të vazhduar.").font(.headline)
        Text("Adresa: " + address + ". Pas hyrjes do të hapet këndi i rolit tënd ekzistues. Një email është një llogari me një rol të vetëm.").font(.footnote)
        PasswordInput(title: "Fjalëkalimi", text: $password)
        Button("Hyr") { signup = false; perform { try await account.cloudSignIn(email: address, password: password) } }
            .buttonStyle(.borderedProminent).disabled(password.isEmpty)
        Button("Harrova fjalëkalimin") { perform { try await account.cloudRecover(email: address) } }
        Button("Kthehu") { signup = false; account.cancelCloudSignIn() }
    }
    /// Rasti B: pronësia u vërtetua; roli real ndryshon nga ai që u zgjodh në regjistrim.
    @ViewBuilder private func roleMismatchView(_ real: SchoolRole) -> some View {
        let section = real == .teacher ? "Mësues" : "Nxënës / Prind"
        Text("Ky email ka një rol tjetër").font(.title.bold())
        Text("Kjo adresë emaili ka rolin " + real.rawValue + ". Hyr nga seksioni " + section + ". Për rol tjetër përdor një adresë tjetër emaili.").font(.headline)
        Text("Roli nuk ndryshohet. Nëse je edhe prind edhe mësues, krijo llogarinë tjetër me email tjetër.").font(.footnote)
        Button("Vazhdo te " + real.title) {
            entry = real == .teacher ? .teacher : .studentParent
            UserDefaults.standard.set(entry.rawValue, forKey: "lastEntry.v8")
            perform { try await account.cloudContinueWithServerRole() }
        }.buttonStyle(.borderedProminent)
        Button("Dil") { account.cancelCloudSignIn() }
    }
    @ViewBuilder private func emailCodeView(_ address: String) -> some View {
        Text("Konfirmo emailin").font(.title.bold())
        Text("Dërguam një kod 6-shifror te " + address + ". Pa konfirmim llogaria nuk ka akses te të dhënat. Kodi skadon; nëse ka skaduar, kërko një të ri. Ky kod konfirmon vetëm emailin. Pas tij, çdo hyrje kërkon edhe një kod të ri që të vjen me email.").font(.footnote)
        Text("Nuk të vjen kodi? Nëse ky email ka tashmë një llogari, nuk dërgohet kod i ri: përdor «Hyr» ose «Harrove fjalëkalimin?». Kontrollo edhe dosjen Spam.").font(.footnote)
        TextField("Kodi nga emaili", text: $code).autocorrectionDisabled()
        Button("Konfirmo") { perform { try await account.cloudVerify(email: address, code: code); code = "" } }.buttonStyle(.borderedProminent).disabled(code.isEmpty)
        Button("Ridërgo kodin") { perform { try await account.cloudResend(email: address); message = "" ; account.cloudMessage = "Kodi i ri u dërgua." } }
        Button("Kthehu") { account.cancelCloudSignIn() }
    }
    @ViewBuilder private func emailLoginView(_ address: String) -> some View {
        Text("Kodi i hyrjes").font(.title.bold())
        Text("Për siguri, çdo hyrje kërkon një kod 6-shifror që të dërgojmë te " + address + " (adresa e regjistrimit, Gmail, Yahoo ose tjetër). Kodi vlen 10 minuta. Kontrollo edhe dosjen Spam.").font(.footnote)
        TextField("Kodi 6-shifror", text: $code).autocorrectionDisabled()
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif
        Button("Hyr") { perform { try await account.cloudSubmitLoginCode(code); code = "" } }.buttonStyle(.borderedProminent).disabled(code.isEmpty)
        Button("Ridërgo kodin") { perform { try await account.cloudResendLoginCode(); account.cloudMessage = "Kodi i ri u dërgua te " + address + "." } }
        Text("Pas 5 kodeve të gabuara duhet të kërkosh një kod të ri.").font(.footnote)
        Button("Anulo hyrjen") { account.cancelCloudSignIn() }
    }
    @ViewBuilder private var mfaView: some View {
        Text("Faktori i dytë").font(.title.bold())
        Text("Shkruaj kodin 6-shifror nga aplikacioni i autentikimit. Kërkohet në çdo hyrje; pa të nuk hapet llogaria, edhe me fjalëkalim të saktë.").font(.footnote)
        TextField("Kodi 6-shifror", text: $code).autocorrectionDisabled()
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif
        Button("Vazhdo") { perform { try await account.cloudMFA(code: code); code = "" } }.buttonStyle(.borderedProminent).disabled(code.isEmpty)
        Text("Humbe aksesin te aplikacioni? Kontakto administratorin e shkollës për të hequr faktorin; vetë aplikacioni nuk e anashkalon.").font(.footnote)
        Button("Anulo hyrjen") { account.cancelCloudSignIn() }
    }
    @ViewBuilder private var roleView: some View {
        Text("Përfundo regjistrimin").font(.title.bold())
        if entry == .studentParent {
            Picker("Roli", selection: $role) { Text("Nxënës").tag(SchoolRole.student); Text("Prind").tag(SchoolRole.parent) }.pickerStyle(.segmented)
            Text("Roli caktohet një herë nga serveri dhe nuk ndryshohet më.").font(.footnote)
            Button("Vazhdo") { perform { try await account.cloudChooseRole(role) } }.buttonStyle(.borderedProminent)
        } else {
            SecureField("Kodi 5-shifror i mësuesit", text: $teacherCode)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            Button("Verifiko kodin") { perform { try await account.cloudRedeemTeacher(teacherCode); teacherCode = "" } }.buttonStyle(.borderedProminent).disabled(teacherCode.isEmpty)
            Text("Pas 5 gabimesh llogaria bllokohet për 24 orë për këtë kod.").font(.footnote)
        }
        Button("Dil") { account.cancelCloudSignIn() }
    }
    @ViewBuilder private func recoveryView(_ address: String) -> some View {
        Text("Fjalëkalim i ri").font(.title.bold())
        if account.recoveryVerified {
            Text("Kodi u pranua. Zgjidh një fjalëkalim të ri që plotëson kërkesat më poshtë (jo një fjalëkalim i zakonshëm).").font(.footnote)
        } else {
            Text("Shkruaj kodin që të erdhi te " + address + " dhe fjalëkalimin e ri. Nëse ke 2FA, do të kërkohet edhe kodi i aplikacionit.").font(.footnote)
            TextField("Kodi nga emaili", text: $code).autocorrectionDisabled()
        }
        PasswordInput(title: "Fjalëkalimi i ri", text: $newPassword, isNew: true)
        PasswordChecklist(password: newPassword)
        Button("Ndrysho fjalëkalimin") { perform {
            if let problem = PasswordPolicy.problem(newPassword, email: address) { throw AuthFailure(message: problem) }
            try await account.cloudCompleteRecovery(email: address, code: code, newPassword: newPassword); code = ""; newPassword = "" } }
            .buttonStyle(.borderedProminent).disabled((code.isEmpty && !account.recoveryVerified) || newPassword.isEmpty)
        if !account.recoveryVerified {
            Button("Ridërgo kodin") { perform { try await account.cloudRecover(email: address); account.cloudMessage = "Kodi i ri u dërgua. Mund të duhet rreth 1 minutë para se të kërkosh përsëri." } }
        }
        Button("Kthehu") { account.cancelCloudSignIn() }
    }
    private func perform(_ work: @escaping () async throws -> Void) {
        guard !busy else { return }; busy = true; message = ""
        Task { defer { busy = false }; do { try await work() } catch { message = error.localizedDescription } }
    }
}

// MARK: - 2FA me aplikacion autentikimi (TOTP, Supabase MFA)
/// Konfigurimi i detyrueshëm i faktorit të dytë pas konfirmimit të emailit (ose në hyrjen e parë pa faktor).
private struct MFASetupView: View {
    @EnvironmentObject private var account: Account
    @State private var enrolling: GoTrueEnroll?
    @State private var code = ""
    @State private var busy = false
    @State private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Aktivizo faktorin e dytë").font(.title.bold())
            Text("Për siguri, çdo hyrje kërkon edhe një kod 6-shifror nga një aplikacion autentikimi (Google Authenticator, Microsoft Authenticator, Authy, 1Password ose Apple Passwords). Konfigurohet vetëm një herë.").font(.footnote)
            if let pending = enrolling {
                Text("1. Hap aplikacionin e autentikimit dhe skano kodin QR. 2. Shkruaj kodin 6-shifror që shfaq.").font(.footnote)
                QRCodeView(text: pending.totp.uri)
                Text("Ose shkruaj çelësin me dorë: " + pending.totp.secret).font(.caption.monospaced()).textSelection(.enabled)
                TextField("Kodi 6-shifror", text: $code).autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                Button("Aktivizo dhe vazhdo") { confirm(pending) }.buttonStyle(.borderedProminent).disabled(code.isEmpty || busy)
                Text("Humbe aksesin te aplikacioni? Administratori i shkollës mund ta rivendosë faktorin; vetë aplikacioni nuk e anashkalon.").font(.footnote)
            } else if message.isEmpty {
                ProgressView()
            } else {
                Button("Provo përsëri") { Task { await start() } }
            }
            if !message.isEmpty { Text(message).foregroundStyle(Color.red) }
            Button("Dil") { account.cancelCloudSignIn() }
        }
        .task { if enrolling == nil { await start() } }
    }
    private func start() async {
        message = ""
        do { enrolling = try await account.cloudStartMFASetup() } catch { message = error.localizedDescription }
    }
    private func confirm(_ pending: GoTrueEnroll) {
        guard !busy else { return }; busy = true; message = ""
        Task {
            defer { busy = false }
            do { try await account.cloudFinishMFASetup(factorID: pending.id, code: code); code = "" }
            catch { message = error.localizedDescription }
        }
    }
}

struct QRCodeView: View {
    let text: String
    var body: some View {
        if let image = Self.make(text) { Image(decorative: image, scale: 1).interpolation(.none).resizable().scaledToFit().frame(width: 200, height: 200).background(Color.white) }
    }
    static func make(_ value: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(value.utf8); filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}

struct SecuritySettings: View {
    @EnvironmentObject private var account: Account
    @State private var factors: [GoTrueFactor] = []
    @State private var required = false
    @State private var enrolling: GoTrueEnroll?
    @State private var code = ""
    @State private var password = ""
    @State private var message = ""
    @State private var busy = false
    var body: some View {
        DisclosureGroup("Siguria · autentikimi me dy faktorë (2FA)") {
            VStack(alignment: .leading, spacing: 10) {
                if let active = factors.first(where: { $0.status == "verified" }) {
                    Text("2FA është aktiv (aplikacion autentikimi, TOTP). Pas fjalëkalimit kërkohet kodi 6-shifror në çdo hyrje.").font(.footnote)
                    if required {
                        Text("Shkolla e kërkon 2FA për këtë llogari, ndaj nuk çaktivizohet nga aplikacioni.").font(.footnote)
                    } else {
                        SecureField("Fjalëkalimi aktual", text: $password)
                        TextField("Kodi aktual 6-shifror", text: $code).autocorrectionDisabled()
                        Button("Çaktivizo 2FA", role: .destructive) { Task { await disable(active) } }.disabled(password.isEmpty || code.isEmpty || busy)
                    }
                } else if let pending = enrolling {
                    Text("1. Skano kodin QR me një aplikacion autentikimi. 2. Shkruaj kodin 6-shifror që shfaq.").font(.footnote)
                    QRCodeView(text: pending.totp.uri)
                    Text("Ose shkruaj çelësin me dorë: " + pending.totp.secret).font(.caption.monospaced()).textSelection(.enabled)
                    TextField("Kodi 6-shifror", text: $code).autocorrectionDisabled()
                    Button("Aktivizo 2FA") { Task { await confirm(pending) } }.disabled(code.isEmpty || busy)
                } else {
                    Text("Shton një kod që ndryshon në aplikacionin tënd. Pa të, fjalëkalimi i vjedhur nuk mjafton për të hyrë. Ruaj aksesin te aplikacioni; nëse e humbet, administratori duhet të heqë faktorin.").font(.footnote)
                    Button("Konfiguro 2FA") { Task { await start() } }.disabled(busy)
                }
                if !message.isEmpty { Text(message).font(.footnote) }
            }
        }.task { await load() }
    }
    private func load() async {
        factors = (try? await SupabaseAuth.shared.currentUser().factors) ?? []
        let me: MeReply? = try? await SchoolAPI.call("me")
        required = (me?.mfaRequired ?? false) && (me?.mfaMethod ?? "totp") == "totp"
    }
    private func start() async {
        busy = true; defer { busy = false }
        do { enrolling = try await SupabaseAuth.shared.mfaEnroll(); message = "" } catch { message = error.localizedDescription }
    }
    private func confirm(_ pending: GoTrueEnroll) async {
        busy = true; defer { busy = false }
        do {
            try await SupabaseAuth.shared.mfaChallengeVerify(factorID: pending.id, code: code.trimmingCharacters(in: .whitespacesAndNewlines))
            enrolling = nil; code = ""; message = "2FA u aktivizua. Seancat e tjera u mbyllën dhe duhet të hyjnë përsëri me faktorin e dytë."
            await load()
        } catch { message = error.localizedDescription }
    }
    private func disable(_ factor: GoTrueFactor) async {
        busy = true; defer { busy = false }
        do {
            try await SupabaseAuth.shared.checkPassword(email: account.email, password: password)
            try await SupabaseAuth.shared.mfaChallengeVerify(factorID: factor.id, code: code.trimmingCharacters(in: .whitespacesAndNewlines))
            try await SupabaseAuth.shared.mfaUnenroll(factorID: factor.id)
            password = ""; code = ""; message = "2FA u çaktivizua."
            await load()
        } catch { message = error.localizedDescription }
    }
}

// MARK: - Fusha e fjalëkalimit me «shfaq/fshih» dhe lista e kërkesave

/// Fushë fjalëkalimi me butonin 👁 për ta parë atë që shkruan. `isNew` i tregon sistemit që është fjalëkalim i ri
/// (që iCloud Keychain të sugjerojë një të fortë).
struct PasswordInput: View {
    let title: String
    @Binding var text: String
    var isNew = false
    @State private var visible = false

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if visible { TextField(title, text: $text) } else { SecureField(title, text: $text) }
            }
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .textContentType(isNew ? .newPassword : .password)
            #endif
            Button { visible.toggle() } label: {
                Image(systemName: visible ? "eye.slash" : "eye").foregroundStyle(.secondary).frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(visible ? "Fshih fjalëkalimin" : "Shfaq fjalëkalimin")
            .accessibilityLabel(visible ? "Fshih fjalëkalimin" : "Shfaq fjalëkalimin")
        }
    }
}

/// Kërkesat e fjalëkalimit, që plotësohen një nga një ndërsa shkruan.
struct PasswordChecklist: View {
    let password: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(PasswordPolicy.rules) { rule in
                let ok = !password.isEmpty && rule.passes(password)
                Label(rule.text, systemImage: ok ? "checkmark.circle.fill" : "circle")
                    .font(.footnote)
                    .foregroundStyle(ok ? Color.green : Color.secondary)
                    .accessibilityLabel(rule.text + (ok ? ", plotësuar" : ", mungon"))
            }
        }
        .animation(.easeOut(duration: 0.15), value: password)
    }
}
