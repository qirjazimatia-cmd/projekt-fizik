import Foundation
import SwiftUI
import Security

// The only server setting: an address owned by the school. No vendor keys.
enum SchoolConfig {
    static let defaultURL = "" // Example: https://science.school.example:8443
    static var address: String {
        get { UserDefaults.standard.string(forKey: "schoolServer.v7") ?? defaultURL }
        set { UserDefaults.standard.set(newValue, forKey: "schoolServer.v7") }
    }
}
struct RemoteUser: Codable { let id, email, role: String }
struct LoginReply: Decodable { let token: String; let user: RemoteUser; let recovery: String? }
struct OKReply: Decodable { let ok: Bool?; let recovery: String?; let code: String? }
struct ServiceError: Decodable { let error: String }
struct SchoolClass: Decodable, Identifiable { let id, name, owner, code: String; let level: Int; let approved: Bool }
struct ClassMember: Decodable, Identifiable { let id, email, classID: String; let approved: Bool }
struct SchoolExam: Decodable, Identifiable { let id, classID, title, subject: String; let minutes, count: Int; let status: String? }
struct RemoteEvent: Decodable, Identifiable { let id, classID, owner, title, note: String; let date: Double; let subject: String?; let examID: String? }
struct FamilyMember: Decodable, Identifiable { let id, email: String }
struct ExamQuestion: Decodable, Identifiable {
    let id, prompt, kind, unit: String
    let points: Int
    let tolerance: Double
    let answer, explanation: String?
    let options: [String]?
    var precision: String { kind == "choice" ? "Zgjidh një alternativë." : kind == "open" ? "Shkruaj përgjigjen e plotë. Mësuesi e vlerëson dhe jep pikë." : kind == "number" ? "Pranohet gabim absolut deri në \(tolerance.formatted(.number.precision(.significantDigits(1...3)))) \(unit). Mund të shkruash edhe thyesë." : "Shkruaj përgjigjen me fjalë." }
}
struct ExamAnswer: Codable { var value: String; var reasoning: String }
struct RemoteAttempt: Decodable, Identifiable {
    let id, exam, title: String
    let deadline, serverNow: Double
    let submitted: Bool
    let questions: [ExamQuestion]
    let answers: [String: ExamAnswer]
    let score: Int?
    let maximum: Int
    let feedback: [String: String]
    let student, className: String?
    let status: String?
    let preliminary: Int?
    let reviewQuestions: [ExamQuestion]?
    let grades: [String: Int]?
    let files: [AttachmentFile]?
}
/// Skedar i dorëzuar në kovën private `submissions`. Leja për ngarkim/lexim kontrollohet nga rregullat e Supabase Storage.
struct AttachmentFile: Decodable, Identifiable, Hashable {
    let path, question, name, mime: String
    let size: Int64
    var id: String { path }
    var sizeText: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
    var icon: String {
        if mime.hasPrefix("image/") { return "photo" }
        if mime.hasPrefix("audio/") { return "waveform" }
        if mime.hasPrefix("video/") { return "film" }
        if mime == "application/pdf" { return "doc.richtext" }
        return "doc"
    }
    static let maxBytes = 25 * 1024 * 1024
    static let maxPerAttempt = 10
    /// Emër i sigurt për rrugën e skedarit: vetëm shkronja/shifra latine, pikë, vizë dhe nënvizë.
    static func safeName(_ original: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        let mapped = String(original.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        let trimmed = String(mapped.suffix(100))
        return trimmed.isEmpty ? "skedar" : trimmed
    }
    static func prefix() -> String { String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)) }
}
struct SchoolSnapshot: Decodable {
    var classes: [SchoolClass] = []
    var members: [ClassMember] = []
    var tests: [SchoolExam] = []
    var events: [RemoteEvent] = []
    var results: [RemoteAttempt] = []
    var parents: [FamilyMember] = []
    var children: [FamilyMember]? = nil
}

@MainActor
enum SchoolAPI {
    static func call<T: Decodable>(_ action: String, body: [String: Any] = [:], token: String = "") async throws -> T {
        if SupabaseConfig.enabled { return try await cloud(action, body: body) }
        let address = SchoolConfig.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = URL(string: address), let scheme = base.scheme, base.host != nil,
              base.user == nil, base.password == nil, base.query == nil, base.fragment == nil else {
            throw AuthFailure(message: "Vendos adresën e shërbimit të shkollës te Lidhja e shkollës. Udhëzimet janë te START-HERE.md.")
        }
        #if DEBUG
        let local = base.host == "localhost" || base.host == "127.0.0.1" || base.host?.hasSuffix(".local") == true
        guard scheme == "https" || (scheme == "http" && local) else { throw AuthFailure(message: "Përdor HTTPS. Në provat lokale lejohet localhost ose emri i Mac-ut me .local.") }
        #else
        guard scheme == "https" else { throw AuthFailure(message: "Lidhja e shkollës duhet të përdorë HTTPS.") }
        #endif
        var data = body; data["action"] = action
        var request = URLRequest(url: base.appendingPathComponent("api")); request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: data)
        let (bytes, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw AuthFailure(message: "Shërbimi nuk ktheu përgjigje.") }
        guard (200..<300).contains(response.statusCode) else {
            throw AuthFailure(message: (try? JSONDecoder().decode(ServiceError.self, from: bytes).error) ?? "Shërbimi nuk e përfundoi kërkesën (\(response.statusCode)).")
        }
        return try JSONDecoder().decode(T.self, from: bytes)
    }
}

extension SchoolAPI {
    /// Mënyra Supabase: çdo veprim është një funksion `api_<veprimi>` në bazën e të dhënave, thirrur me token-in e përdoruesit.
    /// Argumenti `token` injorohet: token-i merret (dhe rinovohet) nga SupabaseAuth.
    fileprivate static func cloud<T: Decodable>(_ action: String, body: [String: Any]) async throws -> T {
        var payload = body
        if action == "deleteAccount" {
            try await SupabaseAuth.shared.checkPassword(email: SupabaseAuth.shared.session?.email ?? "", password: (body["password"] as? String) ?? "")
            payload = [:]
        }
        let data = try await SupabaseAuth.shared.rpc(action, body: payload)
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let message = object["error"] as? String {
            throw AuthFailure(message: message)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// Tokens, unlike reading preferences, are stored only in the system Keychain.
enum SessionVault {
    static func key() -> [String: Any] {
        [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:(Bundle.main.bundleIdentifier ?? "ScienceQuest") + ".school-session.v7", kSecAttrAccount as String:SchoolConfig.address]
    }
    static func save(_ token: String) throws {
        var item = key(); SecItemDelete(item as CFDictionary)
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let result = SecItemAdd(item as CFDictionary, nil)
        guard result == errSecSuccess else { throw AuthFailure(message: "Seanca nuk u ruajt në Keychain. Provo përsëri.") }
    }
    static func clear() { SecItemDelete(key() as CFDictionary) }
    // Seanca Supabase (access + refresh token) ruhet vetëm në Keychain, jo në UserDefaults.
    private static func sessionKey() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "ScienceQuest") + ".supabase-session.v8", kSecAttrAccount as String: "default"]
    }
    static func saveSession(_ session: AuthSession) throws {
        var item = sessionKey(); SecItemDelete(item as CFDictionary)
        item[kSecValueData as String] = try JSONEncoder().encode(session)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw AuthFailure(message: "Seanca nuk u ruajt në Keychain. Provo përsëri.") }
    }
    static func loadSession() -> AuthSession? {
        var query = sessionKey(); query[kSecReturnData as String] = true
        var output: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &output) == errSecSuccess, let data = output as? Data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }
    static func clearSession() { SecItemDelete(sessionKey() as CFDictionary) }
}

// JSON-safe values: binary lab notebooks are tagged as base64. No passwords here.
enum ProgressValue: Codable, Equatable {
    case string(String), number(Double), bool(Bool), data(String)
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode([String:String].self), let b = v["base64"] { self = .data(b) }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else { self = .string(try c.decode(String.self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .string(let v): try c.encode(v); case .number(let v): try c.encode(v); case .bool(let v): try c.encode(v); case .data(let v): try c.encode(["base64":v]) }
    }
    var property: Any {
        switch self { case .string(let v): return v; case .number(let v): return v; case .bool(let v): return v; case .data(let v): return Data(base64Encoded:v) ?? Data() }
    }
}
struct ProgressEntry: Codable { let key: String; let value: ProgressValue; let version: Int }
struct ProgressReply: Decodable { let entries: [ProgressEntry]; let conflicts: [String]? }

// MARK: - Supabase Auth + REST (pa paketa të jashtme)
// Në aplikacion vendoset vetëm URL-ja dhe çelësi PUBLIK (publishable/anon) te Info.plist (SupabaseURL, SupabaseKey).
// Çelësi service_role nuk duhet vendosur kurrë këtu; aplikacioni e refuzon nëse e njeh.
enum JWTInspector {
    static func claims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var text = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while text.count % 4 != 0 { text += "=" }
        guard let data = Data(base64Encoded: text), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }
}

    enum SupabaseConfig {
        // Vlerat e projektit `projekt-fizik` (Supabase → Project Settings → API).
        private static let builtInURL = "https://bdebgetyyvirxuaivyly.supabase.co"
        private static let builtInKey = "sb_publishable_Kbiv0ppf8i6RP8JfkbFi-g_okXTOXo4"

        private static func plist(_ key: String) -> String {
            (Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        /// Vlera nga Info.plist vetëm kur është plotësuar vërtet (jo bosh dhe jo variabël i pazëvendësuar si `$(SUPABASE_URL)`).
        private static func configured(_ key: String) -> String? {
            let value = plist(key)
            return value.isEmpty || value.contains("$(") ? nil : value
        }
        static var url: String { configured("SupabaseURL") ?? builtInURL }
        static var key: String { configured("SupabaseKey") ?? builtInKey }
        static var enabled: Bool {
            guard let base = URL(string: url), base.host != nil, !key.isEmpty else { return false }
            // Siguri: çelësat e serverit nuk lejohen kurrë në aplikacion.
            if (JWTInspector.claims(key)?["role"] as? String) == "service_role" || key.hasPrefix("sb_secret_") { return false }
            #if DEBUG
            let local = base.host == "localhost" || base.host == "127.0.0.1"
            return base.scheme == "https" || (base.scheme == "http" && local)
            #else
            return base.scheme == "https"
            #endif
        }
    }

struct AuthSession: Codable {
    var access: String
    var refresh: String
    var expires: Double
    var userID: String
    var email: String
    var aal: String { (JWTInspector.claims(access)?["aal"] as? String) ?? "aal1" }
}
struct GoTrueFactor: Decodable { let id: String; let factor_type: String?; let status: String? }
struct GoTrueUser: Decodable { let id: String; let email: String?; let factors: [GoTrueFactor]? }
struct GoTrueSession: Decodable { let access_token: String?; let refresh_token: String?; let expires_in: Double?; let user: GoTrueUser? }
struct GoTrueTotp: Decodable { let secret: String; let uri: String }
struct GoTrueEnroll: Decodable { let id: String; let totp: GoTrueTotp }
struct GoTrueChallenge: Decodable { let id: String }
struct GoTrueFault: Decodable { let error_code: String?; let msg: String?; let message: String?; let error_description: String? }
struct PostgrestFault: Decodable { let code: String?; let message: String? }
struct MeReply: Decodable { let id, email, role, teacherStatus: String; let mfaEnrolled: Bool; let aal: String; let mfaRequired: Bool?; let mfaMethod: String?; let secondFactorOk: Bool? }

@MainActor
final class SupabaseAuth {
    static let shared = SupabaseAuth()
    private(set) var session: AuthSession?
    private var refreshTask: Task<String, Error>?

    func loadStored() { if session == nil { session = SessionVault.loadSession() } }

    private func endpoint(_ path: String, _ query: [String: String]) throws -> URL {
        var base = SupabaseConfig.url
        while base.hasSuffix("/") { base.removeLast() }
        guard var parts = URLComponents(string: base + path) else { throw AuthFailure(message: "Adresa e shërbimit nuk është e vlefshme.") }
        if !query.isEmpty { parts.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = parts.url else { throw AuthFailure(message: "Adresa e shërbimit nuk është e vlefshme.") }
        return url
    }
    private func send(_ method: String, _ path: String, query: [String: String] = [:], body: [String: Any]? = nil, bearer: String? = nil) async throws -> Data {
        var request = URLRequest(url: try endpoint(path, query))
        request.httpMethod = method; request.timeoutInterval = 25
        request.setValue(SupabaseConfig.key, forHTTPHeaderField: "apikey")
        if let bearer { request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization") }
        if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthFailure(message: "Shërbimi nuk ktheu përgjigje.") }
        guard (200..<300).contains(http.statusCode) else { throw Self.fault(data, http.statusCode) }
        return data
    }
    // Mesazhe të dobishme, pa hollësi teknike të panevojshme.
    private static func fault(_ data: Data, _ status: Int) -> AuthFailure {
        if let pg = try? JSONDecoder().decode(PostgrestFault.self, from: data), let code = pg.code, code.hasPrefix("PT"), let message = pg.message, !message.isEmpty {
            return AuthFailure(message: message, code: code)
        }
        let f = try? JSONDecoder().decode(GoTrueFault.self, from: data)
        let code = f?.error_code ?? ""
        let text: String
        switch code {
        case "email_not_confirmed": text = "Emaili nuk është konfirmuar. Shkruaj kodin që të erdhi me email ose kërko një kod të ri."
        case "invalid_credentials": text = "Emaili ose fjalëkalimi nuk është i saktë."
        case "otp_expired": text = "Kodi ka skaduar ose nuk është i saktë. Kërko një kod të ri."
        case "over_email_send_rate_limit": text = "Për siguri prit rreth 1 minutë para se të kërkosh një kod tjetër. Nëse ke kërkuar shumë kode, kufiri i emaileve në orë mund të jetë arritur."
        case "over_request_rate_limit", "over_sms_send_rate_limit": text = "Shumë kërkesa. Prit pak dhe provo përsëri."
        case "email_exists", "user_already_exists": text = "Ky email ka tashmë një llogari. Një email është një llogari: hyr ose përdor «Harrove fjalëkalimin?»."
        case "unexpected_failure" where (f?.msg ?? f?.message ?? "").contains("saving new user"): text = "Ke tashmë një llogari me këtë email. Hyr për të vazhduar ose përdor «Harrove fjalëkalimin?»."
        case "weak_password": text = "Fjalëkalimi është shumë i dobët. Përdor të paktën 10 karaktere, jo një fjalëkalim të zakonshëm."
        case "same_password": text = "Fjalëkalimi i ri duhet të jetë i ndryshëm nga i vjetri."
        case "mfa_verification_failed", "mfa_challenge_expired": text = "Kodi i faktorit të dytë nuk është i saktë ose ka skaduar."
        case "insufficient_aal": text = "Kjo kërkon faktorin e dytë. Hyr përsëri me kodin 6-shifror."
        case "email_address_invalid", "validation_failed": text = "Emaili ose fjalëkalimi nuk është i vlefshëm."
        case "signup_disabled": text = "Regjistrimi është i mbyllur nga administratori."
        default:
            if status == 401 || status == 403 { text = "Seanca ka mbaruar ose veprimi nuk lejohet. Hyr përsëri." }
            else { text = "Kërkesa nuk u krye (\(status)). Provo përsëri." }
        }
        return AuthFailure(message: text, code: code.isEmpty ? nil : code)
    }
    private func adopt(_ data: Data, fallbackEmail: String) throws -> AuthSession {
        let reply = try JSONDecoder().decode(GoTrueSession.self, from: data)
        guard let access = reply.access_token, let refresh = reply.refresh_token, let user = reply.user else { throw AuthFailure(message: "Shërbimi nuk ktheu seancë. Provo përsëri.") }
        let value = AuthSession(access: access, refresh: refresh, expires: Date().timeIntervalSince1970 + (reply.expires_in ?? 3600), userID: user.id, email: (user.email ?? fallbackEmail).lowercased())
        session = value
        try? SessionVault.saveSession(value)
        return value
    }

    /// Kthen `true` nëse emaili ka TASHMË llogari të konfirmuar. Supabase në këtë rast nuk krijon gjë dhe nuk dërgon email,
    /// por kthen një përdorues me `identities` bosh (rasti A: regjistrim i përsëritur). Për llogari të pakonfirmuar ridërgon kodin.
    func signUp(email: String, password: String) async throws -> Bool {
        let data = try await send("POST", "/auth/v1/signup", body: ["email": email, "password": password])
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        let user = (object["user"] as? [String: Any]) ?? object
        if let identities = user["identities"] as? [Any] { return identities.isEmpty }
        return false
    }
    func signIn(email: String, password: String) async throws -> AuthSession {
        try adopt(try await send("POST", "/auth/v1/token", query: ["grant_type": "password"], body: ["email": email, "password": password]), fallbackEmail: email)
    }
    /// Verifikon fjalëkalimin pa ndryshuar seancën aktuale (për fshirje llogarie / çaktivizim 2FA).
    func checkPassword(email: String, password: String) async throws {
        _ = try await send("POST", "/auth/v1/token", query: ["grant_type": "password"], body: ["email": email, "password": password])
    }
    func verify(email: String, code: String, type: String) async throws -> AuthSession {
        try adopt(try await send("POST", "/auth/v1/verify", body: ["type": type, "email": email, "token": code]), fallbackEmail: email)
    }
    /// Kërkon nga Edge Function `send-login-code` që t'i dërgojë kodin e hyrjes te emaili i llogarisë së kyçur (faktori i dytë).
    func sendLoginCode() async throws {
        let token = try await accessToken()
        var request = URLRequest(url: try endpoint("/functions/v1/send-login-code", [:]))
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue(SupabaseConfig.key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthFailure(message: "Shërbimi nuk ktheu përgjigje.") }
        guard (200..<300).contains(http.statusCode) else {
            if let message = (try? JSONDecoder().decode(ServiceError.self, from: data))?.error { throw AuthFailure(message: message) }
            throw AuthFailure(message: http.statusCode == 404 ? "Dërgimi i kodit nuk është konfiguruar ende te Supabase (funksioni send-login-code). Kontakto administratorin." : "Kodi nuk u dërgua (\(http.statusCode)). Provo përsëri.")
        }
    }
    // MARK: Storage · dorëzime me skedarë (kova private `submissions`)
    private struct StorageFault: Decodable { let message: String?; let error: String?; let statusCode: String? }
    private struct SignedReply: Decodable { let signedURL: String? }
    private func storageRequest(_ method: String, _ path: String) async throws -> URLRequest {
        let encoded = path.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "._-"))) ?? String($0) }.joined(separator: "/")
        var request = URLRequest(url: try endpoint("/storage/v1/object/" + encoded, [:]))
        request.httpMethod = method; request.timeoutInterval = 120
        request.setValue(SupabaseConfig.key, forHTTPHeaderField: "apikey")
        let token = try await accessToken()
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        return request
    }
    private static func storageCheck(_ data: Data, _ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw AuthFailure(message: "Shërbimi nuk ktheu përgjigje.") }
        guard !(200..<300).contains(http.statusCode) else { return }
        let fault = try? JSONDecoder().decode(StorageFault.self, from: data)
        let raw = ((fault?.message ?? "") + " " + (fault?.error ?? "")).lowercased()
        if http.statusCode == 413 || raw.contains("size") { throw AuthFailure(message: "Skedari është më i madh se 25 MB.") }
        if http.statusCode == 415 || raw.contains("mime") { throw AuthFailure(message: "Ky lloj skedari nuk pranohet. Përdor PDF, Word, tekst, foto (JPG/PNG/HEIC), audio (MP3/M4A) ose video (MP4/MOV).") }
        if raw.contains("security") || raw.contains("policy") || http.statusCode == 403 { throw AuthFailure(message: "Skedari nuk pranohet: testi është dorëzuar ose mbyllur, ose ke arritur kufirin prej 10 skedarësh.") }
        if raw.contains("exists") || raw.contains("duplicate") { throw AuthFailure(message: "Ky skedar ekziston tashmë.") }
        throw AuthFailure(message: "Skedari nuk u përpunua (\(http.statusCode)). Provo përsëri.")
    }
    func uploadSubmission(path: String, data: Data, mime: String) async throws {
        var request = try await storageRequest("POST", "submissions/" + path)
        request.setValue(mime, forHTTPHeaderField: "Content-Type")
        request.setValue("false", forHTTPHeaderField: "x-upsert")
        let (body, response) = try await URLSession.shared.upload(for: request, from: data)
        try Self.storageCheck(body, response)
    }
    func deleteSubmission(path: String) async throws {
        let request = try await storageRequest("DELETE", "submissions/" + path)
        let (body, response) = try await URLSession.shared.data(for: request)
        try Self.storageCheck(body, response)
    }
    /// Lidhje e përkohshme (10 minuta) për ta hapur skedarin. Serveri e jep vetëm nëse rregulli i leximit lejon.
    func signedSubmissionURL(path: String) async throws -> URL {
        var request = try await storageRequest("POST", "sign/submissions/" + path)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["expiresIn": 600])
        let (body, response) = try await URLSession.shared.data(for: request)
        try Self.storageCheck(body, response)
        var base = SupabaseConfig.url
        while base.hasSuffix("/") { base.removeLast() }
        guard let signed = try JSONDecoder().decode(SignedReply.self, from: body).signedURL,
              let url = URL(string: base + "/storage/v1" + (signed.hasPrefix("/") ? signed : "/" + signed)) else {
            throw AuthFailure(message: "Lidhja e skedarit nuk u krijua.")
        }
        return url
    }
    func resend(email: String) async throws { _ = try await send("POST", "/auth/v1/resend", body: ["type": "signup", "email": email]) }
    func recover(email: String) async throws { _ = try await send("POST", "/auth/v1/recover", body: ["email": email]) }
    func updatePassword(_ password: String) async throws {
        _ = try await send("PUT", "/auth/v1/user", body: ["password": password], bearer: try await accessToken())
    }
    func currentUser() async throws -> GoTrueUser {
        try JSONDecoder().decode(GoTrueUser.self, from: try await send("GET", "/auth/v1/user", bearer: try await accessToken()))
    }
    func mfaEnroll() async throws -> GoTrueEnroll {
        let name = "ScienceQuest-" + String(UUID().uuidString.prefix(6))
        return try JSONDecoder().decode(GoTrueEnroll.self, from: try await send("POST", "/auth/v1/factors", body: ["factor_type": "totp", "friendly_name": name, "issuer": "ScienceQuest"], bearer: try await accessToken()))
    }
    func mfaChallengeVerify(factorID: String, code: String) async throws {
        let token = try await accessToken()
        let challenge = try JSONDecoder().decode(GoTrueChallenge.self, from: try await send("POST", "/auth/v1/factors/\(factorID)/challenge", bearer: token))
        let data = try await send("POST", "/auth/v1/factors/\(factorID)/verify", body: ["challenge_id": challenge.id, "code": code], bearer: token)
        _ = try adopt(data, fallbackEmail: session?.email ?? "")
    }
    func mfaUnenroll(factorID: String) async throws {
        _ = try await send("DELETE", "/auth/v1/factors/\(factorID)", bearer: try await accessToken())
    }
    func logout() async {
        if let token = session?.access { _ = try? await send("POST", "/auth/v1/logout", bearer: token) }
        session = nil; refreshTask = nil; SessionVault.clearSession()
    }
    /// Token i vlefshëm; rinovohet automatikisht (një rinovim i vetëm në çast, që refresh token-i të mos përdoret dy herë).
    func accessToken() async throws -> String {
        guard let current = session else { throw AuthFailure(message: "Seanca ka mbaruar. Hyr përsëri.") }
        if current.expires - Date().timeIntervalSince1970 > 60 { return current.access }
        if let running = refreshTask { return try await running.value }
        let task = Task { () throws -> String in
            let data = try await self.send("POST", "/auth/v1/token", query: ["grant_type": "refresh_token"], body: ["refresh_token": current.refresh])
            return try self.adopt(data, fallbackEmail: current.email).access
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }
    func rpc(_ action: String, body: [String: Any]) async throws -> Data {
        let token = try await accessToken()
        // Postgres i ruan emrat pa thonjëza me shkronja të vogla: api_classcreate, api_examstart, ...
        return try await send("POST", "/rest/v1/rpc/api_" + action.lowercased(), body: ["p_body": body], bearer: token)
    }
}
