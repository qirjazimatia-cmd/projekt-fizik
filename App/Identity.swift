import SwiftUI
import UniformTypeIdentifiers

// Identiteti i nxënësit (#102).
// · Vizitorët: Info pa llogari + mësime prove.
// · Nxënësit: kodi personal nga sekretaria (një përdorim) lidh llogarinë me regjistrin e shkollës.
// · Sekretaria: ngarkon regjistrin (CSV), printon kodet, ndez detyrimin. Serveri kontrollon çdo hap (api_admin*).

// MARK: - Aktivizimi i nxënësit

struct StudentActivationView: View {
    @EnvironmentObject private var account: Account
    @State private var code = ""
    @State private var busy = false
    @State private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "person.badge.key.fill").font(.system(size: 44)).foregroundStyle(Color.lagoon)
                .accessibilityHidden(true)
            Text("Aktivizo llogarinë e nxënësit").font(.title.bold())
            Text("Shkolla lejon si nxënës vetëm ata që janë në regjistrin e saj. Shkruaj kodin personal që të dha sekretaria (8 shkronja dhe shifra, p.sh. K7Q4-9MDR).")
                .font(.callout)
            TextField("Kodi i aktivizimit", text: $code)
                .font(.title3.monospaced())
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                .textContentType(.oneTimeCode)
                #endif
                .onSubmit(activate)
            Button(action: activate) {
                Label("Aktivizo", systemImage: "checkmark.seal.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.liquidProminent).controlSize(.large)
            .disabled(busy || code.filter { $0.isLetter || $0.isNumber }.count != 8)
            if busy { ProgressView() }
            if !message.isEmpty { Text(message).foregroundStyle(Color.red).font(.callout) }
            VStack(alignment: .leading, spacing: 6) {
                Label("Kodi përdoret vetëm një herë dhe lidhet me këtë llogari.", systemImage: "1.circle")
                Label("Emri dhe klasa merren nga regjistri i shkollës; do të futesh vetë në klasën tënde.", systemImage: "person.2")
                Label("Nuk e ke kodin ose ka skaduar? Kërko një të ri te sekretaria.", systemImage: "questionmark.circle")
            }.font(.footnote).foregroundStyle(.secondary)
            Button("Jam prind, jo nxënës") { run { try await account.cloudChooseRole(.parent) } }
                .font(.footnote)
            Button("Dil") { account.cancelCloudSignIn() }
        }
        .disabled(busy)
    }
    private func activate() {
        guard code.filter({ $0.isLetter || $0.isNumber }).count == 8 else { return }
        run { try await account.cloudActivateStudent(code); code = "" }
    }
    private func run(_ work: @escaping () async throws -> Void) {
        guard !busy else { return }; busy = true; message = ""
        Task { defer { busy = false }; do { try await work() } catch { message = error.localizedDescription } }
    }
}

// MARK: - Lidhjet publike (#67): politika e privatësisë, mbështetja, fshirja nga web-i

enum PublicPages {
    static let base = "https://qirjazimatia-cmd.github.io/projekt-fizik/"
    static let privacy = URL(string: base + "privatesia.html")!
    static let support = URL(string: base)!
    static let deleteAccount = URL(string: base + "fshi-llogarine.html")!
}

struct PrivacyLinks: View {
    var body: some View {
        HStack(spacing: 16) {
            Link("Politika e privatësisë", destination: PublicPages.privacy)
            Link("Mbështetja", destination: PublicPages.support)
        }.font(.footnote)
    }
}

// MARK: - Mënyra vizitor: vetëm mësimet

struct GuestLessonsView: View {
    @EnvironmentObject private var account: Account
    var body: some View {
        NavigationStack {
            StudySubjects()
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { account.leaveGuest() } label: { Label("Hyr", systemImage: "person.crop.circle") }
                    }
                    // Modeli 3D i shkollës është publik: e shohin edhe vizitorët.
                    ToolbarItem(placement: .navigation) {
                        NavigationLink { School3DView() } label: { Label("Shkolla 3D", systemImage: "cube.transparent") }
                    }
                }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Image(systemName: "eye").accessibilityHidden(true)
                Text("Mënyra vizitor: mësimet dhe shkolla në 3D. Klasa, bisedat dhe Bosko AI janë për anëtarët e shkollës.")
                    .font(.footnote).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button("Hyr") { account.leaveGuest() }.buttonStyle(.liquidProminent)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 12).padding(.bottom, 6)
        }
    }
}

// MARK: - Info për vizitorët (pa llogari)

struct VisitorInfoView: View {
    @EnvironmentObject private var account: Account
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        BrainSparkLogo(size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("BrainSpark").font(.largeTitle.bold())
                            Text("App-i i shkollës Don Bosko për shkencat").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink { School3DView() } label: {
                        Label("Shiko shkollën në 3D", systemImage: "cube.transparent").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.liquid).controlSize(.large)
                    infoCard("Çfarë ka brenda", "sparkles", [
                        "\(StudyLesson.all.count) mësime në matematikë, fizikë, kimi dhe biologji, në pesë nivele.",
                        "Laboratorë interaktivë dhe lojëra me ushtrime.",
                        "Për nxënësit e shkollës: klasa, detyrat, kalendari, bisedat e klasës dhe asistenti Bosko AI."
                    ])
                    infoCard("Kush hyn dhe si", "person.badge.key", [
                        "Nxënës: regjistrohu me emailin tënd, pastaj shkruaj kodin personal që të jep sekretaria e shkollës.",
                        "Prind: regjistrohu si prind dhe lidhu me fëmijën me kodin që ai krijon te llogaria e tij.",
                        "Mësues: regjistrohu te «Mësues» me kodin e mësuesve që jep shkolla.",
                        "Vizitor: mund të provosh mësimet pa llogari. Klasat, bisedat dhe të dhënat e nxënësve janë vetëm për anëtarët e shkollës."
                    ])
                    infoCard("Privatësia", "lock.shield", [
                        "Llogaritë e nxënësve lidhen vetëm me regjistrin e shkollës (emri, klasa, numri i amzës). Nuk ruhen foto.",
                        "Mënyra pa llogari nuk dërgon asnjë të dhënë personale."
                    ])
                    infoCard("Kontakt", "building.columns", [
                        "Për kodin e aktivizimit ose për informacion mbi shkollën, drejtohu sekretarisë së shkollës."
                    ])
                    PrivacyLinks()
                    Button {
                        dismiss(); account.guest()
                    } label: {
                        Label("Provo mësimet pa llogari", systemImage: "book.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.liquidProminent).controlSize(.large)
                }
                .padding(20).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
            }
            .navigationTitle("Info")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Mbyll") { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 600)
        #endif
    }
    private func infoCard(_ title: String, _ symbol: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.headline)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").foregroundStyle(Color.lagoon)
                    Text(line).fixedSize(horizontal: false, vertical: true)
                }.font(.callout)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.lagoon.opacity(0.08)))
    }
}

// MARK: - Paneli i sekretarisë

struct RosterRow: Decodable, Identifiable, Hashable {
    let id: String
    let amza, firstName, lastName, className: String
    let birthYear: Int?
    let status: String
    let account: String?
    let hasCode: Bool
    let codeExpires: String?
    var name: String { firstName + " " + lastName }
}
private struct RosterReply: Decodable { let required: Bool; let codeDays: Int; let rows: [RosterRow]; let unverifiedStudents: Int; let exempt: [SchoolAccount]? }
/// Llogari e thjeshtë (përjashtim nga kodi ose sekretar).
struct SchoolAccount: Decodable, Identifiable, Hashable { let id: String; let email: String?; let name: String?; let me: Bool? }
private struct AdminsReply: Decodable { let admins: [SchoolAccount] }
private struct CountReply: Decodable { let count: Int }
private struct RosterImportError: Decodable { let row: Int; let amza: String }
private struct RosterImportReply: Decodable { let added: Int; let changed: Int; let errors: [RosterImportError] }
struct IssuedCode: Decodable, Identifiable, Hashable { let id, amza, name, className, code: String }
private struct IssueReply: Decodable { let expires: String; let codes: [IssuedCode] }
private struct VerificationReply: Decodable { let required: Bool }

struct IssuedBatch: Identifiable { let id = UUID(); let codes: [IssuedCode]; let expires: String }

@MainActor
final class RosterStore: ObservableObject {
    @Published var rows: [RosterRow] = []
    @Published var required = false
    @Published var codeDays = 30
    @Published var unverified = 0
    @Published var exempt: [SchoolAccount] = []
    @Published var admins: [SchoolAccount] = []
    @Published var loading = false
    @Published var message = ""
    @Published var error = ""
    func load() async {
        loading = true; defer { loading = false }
        do {
            let reply: RosterReply = try await SchoolAPI.call("adminRoster")
            rows = reply.rows; required = reply.required; codeDays = reply.codeDays; unverified = reply.unverifiedStudents
            exempt = reply.exempt ?? []; error = ""
            let list: AdminsReply = try await SchoolAPI.call("adminAdmins", body: ["action": "list"])
            admins = list.admins
        } catch { self.error = error.localizedDescription }
    }
    /// Llogaritë e nxënësve që ekzistojnë sot (p.sh. llogaritë e provës) vazhdojnë të hyjnë pa kod.
    func exemptExisting() async {
        do {
            let reply: CountReply = try await SchoolAPI.call("adminExempt", body: ["action": "existing"])
            message = reply.count == 0 ? "Nuk ka llogari të reja për të lejuar." : "\(reply.count) llogari nxënësish do të hyjnë pa kod."
            error = ""; await load()
        } catch { self.error = error.localizedDescription }
    }
    func removeExempt(_ account: SchoolAccount) async {
        do {
            let _: CountReply = try await SchoolAPI.call("adminExempt", body: ["action": "remove", "userId": account.id])
            error = ""; await load()
        } catch { self.error = error.localizedDescription }
    }
    func addAdmin(_ email: String) async -> Bool {
        do {
            let reply: AdminsReply = try await SchoolAPI.call("adminAdmins", body: ["action": "add", "email": email.trimmingCharacters(in: .whitespacesAndNewlines)])
            admins = reply.admins; error = ""; message = "Sekretari u shtua."; return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func removeAdmin(_ account: SchoolAccount) async {
        do {
            let reply: AdminsReply = try await SchoolAPI.call("adminAdmins", body: ["action": "remove", "userId": account.id])
            admins = reply.admins; error = ""
        } catch { self.error = error.localizedDescription }
    }
    func upload(_ input: [RosterInput], badLines: [Int]) async {
        guard !input.isEmpty else { error = "Nuk u gjet asnjë rresht i vlefshëm."; return }
        do {
            let reply: RosterImportReply = try await SchoolAPI.call("adminRosterImport", body: ["rows": input.map(\.json)])
            var text = "U shtuan \(reply.added), u përditësuan \(reply.changed)."
            let skipped = badLines.count + reply.errors.count
            if skipped > 0 { text += " \(skipped) rreshta u anashkaluan" + (badLines.isEmpty ? "." : " (rreshtat " + badLines.prefix(8).map(String.init).joined(separator: ", ") + (badLines.count > 8 ? "…" : "") + ").") }
            message = text; error = ""
            await load()
        } catch { self.error = error.localizedDescription }
    }
    func issue(_ ids: [String]) async -> IssuedBatch? {
        guard !ids.isEmpty else { return nil }
        do {
            let reply: IssueReply = try await SchoolAPI.call("adminIssueCodes", body: ["ids": ids])
            await load()
            return IssuedBatch(codes: reply.codes, expires: reply.expires)
        } catch { self.error = error.localizedDescription; return nil }
    }
    func act(_ row: RosterRow, _ action: String) async {
        do {
            let _: OKReply = try await SchoolAPI.call("adminRosterUpdate", body: ["id": row.id, "action": action])
            error = ""; await load()
        } catch { self.error = error.localizedDescription }
    }
    func setRequired(_ on: Bool) async {
        do {
            let reply: VerificationReply = try await SchoolAPI.call("adminSetVerification", body: ["on": on])
            required = reply.required; error = ""
            message = on ? "Tani çdo nxënës duhet të aktivizohet me kodin e sekretarisë." : "Detyrimi u fik: nxënësit hyjnë pa kod."
            await load()
        } catch { self.error = error.localizedDescription; required = !on }
    }
}

struct SecretariatView: View {
    @StateObject private var store = RosterStore()
    @State private var className = ""
    @State private var search = ""
    @State private var pasted = ""
    @State private var importing = false
    @State private var confirmIssue = false
    @State private var confirmRequired = false
    @State private var batch: IssuedBatch?
    @State private var busy = false
    @State private var newAdmin = ""
    private var classes: [String] { Array(Set(store.rows.map(\.className))).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    private var visible: [RosterRow] {
        store.rows.filter { row in
            (className.isEmpty || row.className == className) &&
            (search.isEmpty || row.name.localizedCaseInsensitiveContains(search) || row.amza.localizedCaseInsensitiveContains(search))
        }
    }
    private var waiting: [RosterRow] { visible.filter { $0.status == "pending" } }
    var body: some View {
        Page {
            Text("Sekretaria").font(.largeTitle.bold())
            Text("Regjistri i nxënësve dhe kodet e aktivizimit. Vetëm nxënësit në regjistër mund të hyjnë si nxënës kur detyrimi është i ndezur.")
                .font(.callout).foregroundStyle(.secondary)
            stats
            verificationCard
            HomeroomAdminSection()
            accountsCard
            importCard
            if !store.message.isEmpty { Label(store.message, systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout) }
            if !store.error.isEmpty { Label(store.error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout) }
            listSection
        }
        .disabled(busy)
        .task { await store.load() }
        .refreshable { await store.load() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .utf8PlainText]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                pasted = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1250) ?? ""
            }
        }
        .sheet(item: $batch) { CodesSheet(batch: $0) }
        .alert("Të krijohen kodet?", isPresented: $confirmIssue) {
            Button("Anulo", role: .cancel) {}
            Button("Krijo \(waiting.count) kode") { work { batch = await store.issue(waiting.map(\.id)) } }
        } message: {
            Text("Kodet tregohen vetëm tani, për t'u printuar. Nëse një nxënës kishte kod të vjetër, ai anulohet. Kodet vlejnë \(store.codeDays) ditë.")
        }
        .alert(store.required ? "Të fiket detyrimi?" : "Të ndizet detyrimi?", isPresented: $confirmRequired) {
            Button("Anulo", role: .cancel) {}
            Button(store.required ? "Fike" : "Ndize", role: store.required ? .destructive : nil) {
                let on = !store.required
                work { await store.setRequired(on) }
            }
        } message: {
            Text(store.required
                 ? "Çdo llogari nxënësi do të hyjë sërish pa kod sekretarie."
                 : "\(store.unverified) llogari nxënësish që nuk janë lidhur ende me regjistrin do të bllokohen derisa të shkruajnë kodin e tyre. Printo kodet para se ta ndezësh.")
        }
    }
    private var stats: some View {
        let active = store.rows.filter { $0.status == "active" }.count
        let pending = store.rows.filter { $0.status == "pending" }
        let left = store.rows.filter { $0.status == "left" }.count
        return HStack(spacing: 10) {
            stat("\(store.rows.count)", "në regjistër", "list.bullet.rectangle")
            stat("\(active)", "të aktivizuar", "checkmark.seal.fill")
            stat("\(pending.filter(\.hasCode).count)", "me kod në pritje", "ticket.fill")
            stat("\(pending.filter { !$0.hasCode }.count)", "pa kod", "questionmark.circle")
            if left > 0 { stat("\(left)", "larguar", "figure.walk.departure") }
        }
    }
    private func stat(_ value: String, _ label: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(Color.lagoon)
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.lagoon.opacity(0.08)))
        .accessibilityElement(children: .combine)
    }
    private var verificationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { store.required }, set: { _ in confirmRequired = true })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kërko kodin e sekretarisë për çdo nxënës").font(.headline)
                    Text(store.required ? "I ndezur: vetëm nxënësit e regjistrit hyjnë." : "I fikur: kushdo mund të regjistrohet si nxënës (si më parë).")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if store.unverified > 0 {
                Label("\(store.unverified) llogari nxënësish nuk janë lidhur ende me regjistrin.", systemImage: "exclamationmark.circle")
                    .font(.footnote).foregroundStyle(.orange)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.lagoon.opacity(0.08)))
    }
    /// Llogaritë e provës që hyjnë pa kod dhe sekretarët e shkollës.
    private var accountsCard: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text("Llogaritë që lejohen pa kod").font(.subheadline.bold())
                Text("P.sh. llogaritë e provës. Llogaritë e reja të nxënësve do ta kërkojnë gjithmonë kodin kur detyrimi është i ndezur.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button { work { await store.exemptExisting() } } label: {
                    Label(store.unverified > 0 ? "Lejo pa kod llogaritë që ekzistojnë sot (\(store.unverified))" : "Të gjitha llogaritë ekzistuese janë në regjistër ose të lejuara",
                          systemImage: "person.crop.circle.badge.checkmark")
                }.disabled(store.unverified == 0)
                ForEach(store.exempt) { account in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(account.name ?? account.email ?? "Llogari").font(.callout)
                            if let email = account.email { Text(email).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Button("Kërko kodin") { work { await store.removeExempt(account) } }.font(.caption)
                    }
                }
                Divider()
                Text("Sekretarët").font(.subheadline.bold())
                ForEach(store.admins) { admin in
                    HStack {
                        Label((admin.name ?? admin.email ?? "Sekretar") + (admin.me == true ? " (ti)" : ""), systemImage: "building.columns")
                            .font(.callout)
                        Spacer()
                        if store.admins.count > 1 {
                            Button("Hiq", role: .destructive) { work { await store.removeAdmin(admin) } }.font(.caption)
                        }
                    }
                }
                HStack {
                    TextField("Email i një mësuesi", text: $newAdmin)
                        .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never).keyboardType(.emailAddress)
                        #endif
                    Button("Shto") { work { if await store.addAdmin(newAdmin) { newAdmin = "" } } }
                        .disabled(!newAdmin.contains("@"))
                }
                Text("Vetëm mësues me llogari aktive mund të bëhen sekretarë; ata hyjnë me kodin e dytë me email.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 8)
        } label: {
            Label("Llogaritë e provës dhe sekretarët", systemImage: "person.2.badge.gearshape").font(.headline)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.lagoon.opacity(0.08)))
    }
    private var importCard: some View {
        let parsed = RosterCSV.parse(pasted)
        return DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                Text("Kolonat: Nr. i Amzës; Emri; Mbiemri; Klasa; Viti i lindjes (opsional). Ndarësi mund të jetë «;», «,» ose tab (p.sh. eksport nga Excel). Nxënësit ekzistues përditësohen sipas numrit të Amzës.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button { importing = true } label: { Label("Zgjidh skedarin CSV", systemImage: "doc.badge.plus") }
                TextEditor(text: $pasted)
                    .font(.footnote.monospaced())
                    .frame(minHeight: 110)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                    .accessibilityLabel("Teksti i regjistrit")
                if !pasted.isEmpty {
                    Text("\(parsed.rows.count) rreshta gati" + (parsed.bad.isEmpty ? "" : " · \(parsed.bad.count) me gabim (rreshtat " + parsed.bad.prefix(8).map(String.init).joined(separator: ", ") + ")"))
                        .font(.footnote).foregroundStyle(parsed.bad.isEmpty ? Color.secondary : Color.orange)
                }
                Button {
                    work { await store.upload(parsed.rows, badLines: parsed.bad); if store.error.isEmpty { pasted = "" } }
                } label: { Label("Ngarko regjistrin", systemImage: "arrow.up.circle.fill") }
                .buttonStyle(.liquidProminent).disabled(parsed.rows.isEmpty)
            }.padding(.top, 8)
        } label: {
            Label("Ngarko ose përditëso regjistrin", systemImage: "tray.and.arrow.up.fill").font(.headline)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.lagoon.opacity(0.08)))
    }
    @ViewBuilder private var listSection: some View {
        HStack {
            Picker("Klasa", selection: $className) {
                Text("Të gjitha klasat").tag("")
                ForEach(classes, id: \.self) { Text($0).tag($0) }
            }.frame(maxWidth: 220)
            TextField("Kërko emër ose nr. amze", text: $search).textFieldStyle(.roundedBorder)
        }
        Button { confirmIssue = true } label: {
            Label(waiting.isEmpty ? "Të gjithë kanë llogari" : "Krijo dhe printo kodet (\(waiting.count))", systemImage: "printer.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.liquidProminent).disabled(waiting.isEmpty)
        if store.loading && store.rows.isEmpty { ProgressView() }
        if !store.loading && store.rows.isEmpty {
            Text("Regjistri është bosh. Ngarko listën e nxënësve më sipër.").foregroundStyle(.secondary)
        }
        LazyVStack(spacing: 8) {
            ForEach(visible) { row in rowView(row) }
        }
    }
    private func rowView(_ row: RosterRow) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).font(.body.weight(.semibold))
                Text("\(row.className) · Amza \(row.amza)" + (row.birthYear.map { " · \($0)" } ?? "") + (row.account.map { " · " + $0 } ?? ""))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            badge(row)
            Menu {
                if row.status == "pending" {
                    Button { work { batch = await store.issue([row.id]) } } label: { Label(row.hasCode ? "Kod i ri (anulon të vjetrin)" : "Krijo kodin", systemImage: "ticket") }
                    if row.hasCode { Button { work { await store.act(row, "revoke") } } label: { Label("Anulo kodin", systemImage: "xmark.circle") } }
                }
                if row.status == "active" {
                    Button { work { await store.act(row, "reset") } } label: { Label("Shkëput llogarinë (kërkon kod të ri)", systemImage: "link.badge.plus") }
                }
                if row.status == "left" {
                    Button { work { await store.act(row, "return") } } label: { Label("Rikthehet në shkollë", systemImage: "arrow.uturn.backward") }
                } else {
                    Button { work { await store.act(row, "leave") } } label: { Label("Largohet nga shkolla", systemImage: "figure.walk.departure") }
                }
                if row.account == nil {
                    Button(role: .destructive) { work { await store.act(row, "delete") } } label: { Label("Fshi nga regjistri", systemImage: "trash") }
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3).frame(width: 36, height: 36)
            }
            .accessibilityLabel("Veprime për " + row.name)
            #if os(macOS)
            .menuStyle(.borderlessButton).frame(width: 40)
            #endif
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.04)))
    }
    private func badge(_ row: RosterRow) -> some View {
        let (text, color): (String, Color) = row.status == "active" ? ("Aktiv", .green)
            : row.status == "left" ? ("Larguar", .gray)
            : row.hasCode ? ("Kod në pritje", .orange) : ("Pa kod", .secondary)
        return Text(text).font(.caption.bold()).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.12)))
    }
    private func work(_ job: @escaping () async -> Void) {
        guard !busy else { return }; busy = true; store.message = ""
        Task { await job(); busy = false }
    }
}

// MARK: - Klasat dhe kujdestarët (#116)

struct AdminClassRow: Decodable, Identifiable, Hashable {
    let className: String
    let classID: String?
    let homeroomID: String?
    let homeroomName: String?
    let rosterStudents: Int
    let activeStudents: Int
    let members: Int
    let teachers: Int
    var id: String { className }
}
private struct AdminClassesReply: Decodable { let classes: [AdminClassRow]; let teachers: [DirectoryTeacher] }
private struct HomeroomReply: Decodable { let studentsAdded: Int? }

/// Sekretaria cakton kujdestarin e çdo klase të regjistrit; klasa krijohet vetë dhe nxënësit e aktivizuar futen në të.
struct HomeroomAdminSection: View {
    @State private var classes: [AdminClassRow] = []
    @State private var teachers: [DirectoryTeacher] = []
    @State private var message = ""
    @State private var error = ""
    @State private var busy = false
    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                Text("Për çdo klasë të regjistrit zgjidh mësuesin kujdestar. Kujdestari është administratori i grupit të klasës dhe fton mësuesit e lëndëve; nxënësit e aktivizuar futen vetë.")
                    .font(.footnote).foregroundStyle(.secondary)
                if !message.isEmpty { Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout) }
                if !error.isEmpty { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout) }
                if classes.isEmpty { Text("Ngarko fillimisht regjistrin e nxënësve; klasat dalin këtu vetë.").font(.footnote).foregroundStyle(.secondary) }
                ForEach(classes) { row in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.className).font(.headline)
                            Text("\(row.activeStudents)/\(row.rosterStudents) nxënës aktivë · \(row.teachers) mësues lëndësh")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            ForEach(teachers) { teacher in
                                Button(Self.title(teacher)) { assign(row, teacher) }
                            }
                        } label: {
                            Label(row.homeroomName ?? "Cakto kujdestarin", systemImage: row.homeroomName == nil ? "person.badge.plus" : "star.circle.fill")
                                .font(.subheadline.bold())
                        }
                        .disabled(busy || teachers.isEmpty)
                    }
                    .padding(10).background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
                }
            }.padding(.top, 8)
        } label: {
            Label("Klasat dhe kujdestarët", systemImage: "star.circle").font(.headline)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.lagoon.opacity(0.08)))
        .task { await load() }
    }
    static func title(_ teacher: DirectoryTeacher) -> String {
        let name: String = teacher.name ?? teacher.email ?? "Mësues"
        let subjects: [String] = Array((teacher.subjects ?? []).prefix(2))
        return subjects.isEmpty ? name : name + " · " + subjects.joined(separator: ", ")
    }
    private func load() async {
        do {
            let reply: AdminClassesReply = try await SchoolAPI.call("adminClasses", body: ["action": "list"])
            classes = reply.classes; teachers = reply.teachers; error = ""
        } catch { self.error = error.localizedDescription }
    }
    private func assign(_ row: AdminClassRow, _ teacher: DirectoryTeacher) {
        busy = true; message = ""
        Task { @MainActor in
            defer { busy = false }
            do {
                let reply: HomeroomReply = try await SchoolAPI.call("adminClasses", body: ["action": "homeroom", "className": row.className, "teacherID": teacher.id])
                message = (teacher.name ?? "Mësuesi") + " është kujdestar i " + row.className + ". U futën \(reply.studentsAdded ?? 0) nxënës."
                error = ""; await load()
            } catch { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Kodet për printim

enum CodeDate {
    /// "2026-12-16T19:07:26.95+00:00" → "16.12.2026"
    static func short(_ iso: String) -> String {
        let parts = iso.prefix(10).split(separator: "-")
        guard parts.count == 3 else { return String(iso.prefix(10)) }
        return parts[2] + "." + parts[1] + "." + parts[0]
    }
}

struct CodesSheet: View {
    let batch: IssuedBatch
    @Environment(\.dismiss) private var dismiss
    @State private var pdf: URL?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Këto kode shfaqen vetëm tani. Printoji ose ruaje PDF-në para se ta mbyllësh.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                    Text("\(batch.codes.count) kode · vlejnë deri më \(CodeDate.short(batch.expires)) · secili përdoret një herë.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let pdf {
                        ShareLink(item: pdf) { Label("Printo / ruaj PDF-në", systemImage: "printer.fill").frame(maxWidth: .infinity) }
                            .buttonStyle(.liquidProminent).controlSize(.large)
                    } else { ProgressView("Po përgatitet PDF-ja…") }
                    ForEach(batch.codes) { code in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(code.name).font(.body.weight(.semibold))
                                Text(code.className + " · Amza " + code.amza).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(code.code).font(.title3.monospaced().bold()).textSelection(.enabled)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
                    }
                }.padding(20)
            }
            .navigationTitle("Kodet e aktivizimit")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Mbyll") { dismiss() } } }
            .task { pdf = CodeSlips.pdf(batch) }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 620)
        #endif
    }
}

/// PDF A4 me 10 fletëza (2 × 5) për faqe: emri, klasa, kodi dhe hapat.
@MainActor
enum CodeSlips {
    static let perPage = 10
    static func pdf(_ batch: IssuedBatch) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BrainSpark-kodet-" + CodeDate.short(batch.expires) + ".pdf")
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return nil }
        for start in stride(from: 0, to: batch.codes.count, by: perPage) {
            let slice = Array(batch.codes[start..<min(start + perPage, batch.codes.count)])
            let renderer = ImageRenderer(content: SlipPage(codes: slice, expires: CodeDate.short(batch.expires)))
            context.beginPDFPage(nil)
            renderer.render { _, draw in draw(context) }
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }
}

private struct SlipPage: View {
    let codes: [IssuedCode]
    let expires: String
    var body: some View {
        let columns = [GridItem(.fixed(270), spacing: 15), GridItem(.fixed(270), spacing: 15)]
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(codes) { slip($0) }
        }
        .padding(.top, 26).padding(.horizontal, 20)
        .frame(width: 595, height: 842, alignment: .top)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
    private func slip(_ code: IssuedCode) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("BrainSpark · Aktivizimi i nxënësit").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.gray)
            Text(code.name).font(.system(size: 14, weight: .bold)).foregroundStyle(Color.black).lineLimit(1)
            Text("Klasa " + code.className + " · Amza " + code.amza).font(.system(size: 9)).foregroundStyle(Color.black)
            Text(code.code).font(.system(size: 22, weight: .heavy, design: .monospaced)).foregroundStyle(Color.black)
                .padding(.vertical, 2)
            Text("1. Shkarko BrainSpark. 2. Regjistrohu si Nxënës me emailin tënd. 3. Shkruaj këtë kod kur të kërkohet.")
                .font(.system(size: 7.5)).foregroundStyle(Color.black).fixedSize(horizontal: false, vertical: true)
            Text("Vlen deri më \(expires), vetëm një herë. Mos ia jep askujt.").font(.system(size: 7.5, weight: .semibold)).foregroundStyle(Color.black)
        }
        .padding(10)
        .frame(width: 270, height: 142, alignment: .topLeading)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(style: StrokeStyle(lineWidth: 0.8, dash: [4, 3])).foregroundStyle(Color.gray))
    }
}
