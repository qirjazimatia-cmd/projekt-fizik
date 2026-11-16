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
                }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Image(systemName: "eye").accessibilityHidden(true)
                Text("Mënyra vizitor: vetëm mësimet. Klasa, bisedat dhe Bosko AI janë për anëtarët e shkollës.")
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
private struct RosterReply: Decodable { let required: Bool; let codeDays: Int; let rows: [RosterRow]; let unverifiedStudents: Int }
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
    @Published var loading = false
    @Published var message = ""
    @Published var error = ""
    func load() async {
        loading = true; defer { loading = false }
        do {
            let reply: RosterReply = try await SchoolAPI.call("adminRoster")
            rows = reply.rows; required = reply.required; codeDays = reply.codeDays; unverified = reply.unverifiedStudents; error = ""
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
