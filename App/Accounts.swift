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
    /// Rihap seancën e ruajtur me Face ID / Touch ID (pas një anulimi).
    func unlockSavedSession() async {
        guard lockedSession, SupabaseAuth.shared.session != nil, await BiometricGate.unlock() else { return }
        lockedSession = false
        do { _ = try await SupabaseAuth.shared.accessToken(); try await finishSignIn() }
        catch { cloudMessage = "Seanca nuk u rikthye (" + error.localizedDescription + "). Hyr përsëri." }
    }
    /// Ka një seancë të ruajtur që pret Face ID / Touch ID.
    @Published private(set) var lockedSession = false
    func restore() async {
        guard cloud, role == nil, SupabaseAuth.shared.session == nil else { return }
        SupabaseAuth.shared.loadStored()
        guard SupabaseAuth.shared.session != nil else { return }
        if BiometricGate.enabled {
            lockedSession = true
            guard await BiometricGate.unlock() else { return }
            lockedSession = false
        }
        do { _ = try await SupabaseAuth.shared.accessToken(); try await finishSignIn() }
        catch { cloudMessage = "Seanca nuk u rikthye (" + error.localizedDescription + "). Hyr përsëri ose shfleto mësimet pa llogari." }
    }
    /// Pas çdo hyrje/verifikimi: kontrollon faktorin e dytë, pastaj pyet SERVERIN për rolin. Roli nuk vjen kurrë nga klienti.
    private func finishSignIn() async throws {
        lockedSession = false
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
        pendingRole = nil; attemptedRole = nil; pendingTeacherCode = ""; pendingNewPassword = nil; recoveryVerified = false; recoveryEmail = ""; stage = .entry; cloudMessage = ""; lockedSession = false
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
