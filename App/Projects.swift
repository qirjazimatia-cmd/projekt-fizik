import SwiftUI
import UniformTypeIdentifiers

// MARK: - Projekte individuale dhe në grup (prompt §8, issue #6)
// Të gjitha vendimet merren nga serveri (public.api_project* + rregullat e kovës private `projects`).
// Ky ekran vetëm shfaq atë që serveri lejon; fshehja e një butoni nuk është mbrojtje.

struct ProjectMember: Decodable, Identifiable, Hashable { let id, email, role: String }
struct ProjectContribution: Decodable, Identifiable { let id, student, note: String; let date: Double }
struct ProjectVersion: Decodable, Identifiable {
    let id: String
    let number: Int
    let note: String
    let created: Double
    let submitted: Double?
    let submittedBy: String?
    let late: Bool
    let feedback: String
    let reviewed: Double?
    let files: [AttachmentFile]
    var isDraft: Bool { submitted == nil }
}
struct ProjectTeam: Decodable, Identifiable {
    let id, name: String
    let members: [ProjectMember]
    let contributions: [ProjectContribution]
    let versions: [ProjectVersion]
    var draft: ProjectVersion? { versions.first { $0.isDraft } }
}
struct SchoolProject: Decodable, Identifiable {
    let id, classID, className, title, description, kind, status: String
    let mine: Bool
    let due: Double?
    let teams: [ProjectTeam]
    let students: [FamilyMember]?
    var isGroup: Bool { kind == "group" }
    var isOpen: Bool { status == "open" }
    var kindText: String { isGroup ? "Në grup" : "Individual" }
}
struct ProjectsReply: Decodable { let projects: [SchoolProject]; let serverNow: Double }

@MainActor
final class ProjectsStore: ObservableObject {
    @Published var projects: [SchoolProject] = []
    @Published var message = ""
    @Published var busy = false
    @Published var loaded = false
    func refresh() async {
        do { let reply: ProjectsReply = try await SchoolAPI.call("projects"); projects = reply.projects; message = "" }
        catch { message = error.localizedDescription }
        loaded = true
    }
    /// Kryen veprimin dhe rifreskon listën. Kthen `code` (p.sh. ID-në e krijuar) ose nil kur dështon.
    @discardableResult func act(_ action: String, _ body: [String: Any]) async -> String? {
        guard !busy else { return nil }
        busy = true; defer { busy = false }
        do {
            let reply: OKReply = try await SchoolAPI.call(action, body: body)
            await refresh()
            return reply.code ?? ""
        } catch { message = error.localizedDescription; return nil }
    }
    func project(_ id: String) -> SchoolProject? { projects.first { $0.id == id } }
}

// MARK: Storage · kova private `projects` (rruga: <teamID>/<versionID>/<8 shenja>-<emri>)
@MainActor
enum ProjectFiles {
    static let maxPerVersion = 10
    static let types: [UTType] = SchoolTestPlayer.fileTypes + [
        UTType("org.openxmlformats.presentationml.presentation"), UTType("com.microsoft.powerpoint.ppt"),
        UTType("org.openxmlformats.spreadsheetml.sheet"), UTType("com.microsoft.excel.xls")].compactMap { $0 }

    private static func request(_ method: String, _ path: String) async throws -> URLRequest {
        var base = SupabaseConfig.url
        while base.hasSuffix("/") { base.removeLast() }
        let encoded = path.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "._-"))) ?? String($0) }.joined(separator: "/")
        guard let url = URL(string: base + "/storage/v1/object/" + encoded) else { throw AuthFailure(message: "Adresa e shërbimit nuk është e vlefshme.") }
        var request = URLRequest(url: url)
        request.httpMethod = method; request.timeoutInterval = 120
        request.setValue(SupabaseConfig.key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer " + (try await SupabaseAuth.shared.accessToken()), forHTTPHeaderField: "Authorization")
        return request
    }
    private static func check(_ data: Data, _ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw AuthFailure(message: "Shërbimi nuk ktheu përgjigje.") }
        guard !(200..<300).contains(http.statusCode) else { return }
        let raw = (String(data: data, encoding: .utf8) ?? "").lowercased()
        if http.statusCode == 413 || raw.contains("size") { throw AuthFailure(message: "Skedari është më i madh se 25 MB.") }
        if http.statusCode == 415 || raw.contains("mime") { throw AuthFailure(message: "Ky lloj skedari nuk pranohet. Përdor PDF, Word, PowerPoint, Excel, tekst, foto, audio ose video.") }
        if raw.contains("security") || raw.contains("policy") || http.statusCode == 403 { throw AuthFailure(message: "Skedari nuk pranohet: versioni është dorëzuar, projekti është mbyllur ose ke arritur 10 skedarë.") }
        if raw.contains("exists") || raw.contains("duplicate") { throw AuthFailure(message: "Ky skedar ekziston tashmë.") }
        throw AuthFailure(message: "Skedari nuk u përpunua (\(http.statusCode)). Provo përsëri.")
    }
    static func upload(path: String, data: Data, mime: String) async throws {
        var r = try await request("POST", "projects/" + path)
        r.setValue(mime, forHTTPHeaderField: "Content-Type")
        r.setValue("false", forHTTPHeaderField: "x-upsert")
        let (body, response) = try await URLSession.shared.upload(for: r, from: data)
        try check(body, response)
    }
    static func delete(path: String) async throws {
        let r = try await request("DELETE", "projects/" + path)
        let (body, response) = try await URLSession.shared.data(for: r)
        try check(body, response)
    }
    private struct Signed: Decodable { let signedURL: String? }
    /// Lidhje e përkohshme (10 minuta); serveri e jep vetëm kur rregulli i leximit lejon.
    static func signedURL(path: String) async throws -> URL {
        var r = try await request("POST", "sign/projects/" + path)
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: ["expiresIn": 600])
        let (body, response) = try await URLSession.shared.data(for: r)
        try check(body, response)
        var base = SupabaseConfig.url
        while base.hasSuffix("/") { base.removeLast() }
        guard let signed = try JSONDecoder().decode(Signed.self, from: body).signedURL,
              let url = URL(string: base + "/storage/v1" + (signed.hasPrefix("/") ? signed : "/" + signed)) else {
            throw AuthFailure(message: "Lidhja e skedarit nuk u krijua.")
        }
        return url
    }
}

private func dateText(_ epoch: Double) -> String {
    Date(timeIntervalSince1970: epoch).formatted(date: .abbreviated, time: .shortened)
}

// MARK: - Hyrja nga "Shkolla ime"
struct ProjectsScreen: View {
    /// Klasat e mësuesit (për krijimin e projektit). Bosh për nxënësin dhe prindin.
    let ownedClasses: [SchoolClass]
    @EnvironmentObject private var account: Account
    @StateObject private var store = ProjectsStore()
    @State private var classID = ""
    @State private var title = ""
    @State private var details = ""
    @State private var group = false
    @State private var hasDue = true
    @State private var due = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
    var body: some View {
        Page {
            Text("Projektet").font(.title.bold())
            Text(intro).font(.callout)
            if account.role == .teacher { creator }
            if store.loaded && store.projects.isEmpty { Text(emptyText) }
            ForEach(store.projects) { project in
                NavigationLink { ProjectDetail(projectID: project.id, store: store) } label: {
                    Tile(icon: project.isGroup ? "person.3" : "person", title: project.title, detail: summary(project))
                }
            }
            if !store.message.isEmpty { Text(store.message).foregroundStyle(Color.red) }
            Button("Përditëso projektet") { Task { await store.refresh() } }
        }
        .disabled(store.busy).textFieldStyle(.roundedBorder)
        .task { await store.refresh() }
    }
    private var intro: String {
        switch account.role {
        case .teacher: return "Krijo projekte për klasat e tua. Te projektet në grup krijon grupet dhe cakton nxënësit."
        case .parent: return "Shikon vetëm punën e fëmijës tënd. Skedarët dhe komentet shfaqen pasi mësuesi vlerëson një version."
        default: return "Puna e grupit tënd shihet vetëm nga anëtarët e grupit dhe mësuesi."
        }
    }
    private var emptyText: String {
        account.role == .teacher ? "Ende nuk ke krijuar projekte." : "Nuk ka projekte për klasat e tua."
    }
    private var creator: some View {
        DisclosureGroup("Krijo projekt të ri") {
            VStack(alignment: .leading, spacing: 10) {
                if ownedClasses.isEmpty { Text("Krijo më parë një klasë te «Shkolla ime».").font(.footnote) }
                Picker("Klasa", selection: $classID) {
                    Text("Zgjidh klasën").tag("")
                    ForEach(ownedClasses) { Text($0.name).tag($0.id) }
                }
                TextField("Titulli i projektit", text: $title)
                TextField("Përshkrimi dhe kërkesat", text: $details, axis: .vertical).lineLimit(3...8)
                Picker("Lloji", selection: $group) {
                    Text("Individual").tag(false)
                    Text("Në grup").tag(true)
                }.pickerStyle(.segmented)
                Toggle("Ka afat dorëzimi", isOn: $hasDue)
                if hasDue { DatePicker("Afati", selection: $due, in: Date()...) }
                Button("Krijo projektin") { Task { await create() } }
                    .disabled(classID.isEmpty || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text(group ? "Pas krijimit hap projektin për të krijuar grupet." : "Çdo nxënës i miratuar i klasës e nis projektin vetë.").font(.caption)
            }
        }
    }
    private func create() async {
        var body: [String: Any] = ["classID": classID, "title": title, "description": details, "kind": group ? "group" : "individual"]
        if hasDue { body["due"] = due.timeIntervalSince1970 }
        if await store.act("projectCreate", body) != nil { title = ""; details = "" }
    }
    private func summary(_ p: SchoolProject) -> String {
        var parts = [p.kindText, p.className]
        if let due = p.due { parts.append("afati " + dateText(due)) }
        if !p.isOpen { parts.append("mbyllur") }
        if p.mine { parts.append("\(p.teams.count) " + (p.isGroup ? "grupe" : "nxënës të nisur")) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Një projekt
struct ProjectDetail: View {
    let projectID: String
    @ObservedObject var store: ProjectsStore
    @EnvironmentObject private var account: Account
    @State private var teamName = ""
    @State private var confirmDelete = false
    var body: some View {
        Page {
            if let p = store.project(projectID) {
                Text(p.title).font(.title.bold())
                Text([p.kindText, p.className, p.isOpen ? "i hapur" : "i mbyllur"].joined(separator: " · ")).font(.callout)
                if let due = p.due { Text("Afati: " + dateText(due)).font(.headline) }
                if !p.description.isEmpty { Text(p.description).fixedSize(horizontal: false, vertical: true) }
                if p.mine { teacherTools(p) }
                if account.role == .student && p.teams.isEmpty {
                    if p.isGroup { Text("Mësuesi do të të caktojë në një grup. Pastaj puna e grupit shfaqet këtu.") }
                    else if p.isOpen { Button("Fillo projektin") { Task { await store.act("projectStart", ["projectID": p.id]) } } }
                }
                if account.role == .parent && p.teams.isEmpty { Text("Fëmija nuk ka nisur ende punë në këtë projekt.") }
                ForEach(p.teams) { team in
                    TeamPanel(project: p, team: team, store: store)
                        .padding().background(.white, in: RoundedRectangle(cornerRadius: 12))
                }
            } else if store.loaded {
                Text("Projekti nuk gjendet më.")
            }
            if !store.message.isEmpty { Text(store.message).foregroundStyle(Color.red) }
        }
        .disabled(store.busy).textFieldStyle(.roundedBorder)
        .confirmationDialog("Të fshihet projekti?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Fshi përgjithmonë", role: .destructive) { Task { await store.act("projectDelete", ["projectID": projectID, "confirm": true]) } }
            Button("Anulo", role: .cancel) {}
        } message: {
            Text("Fshirja lejohet vetëm kur nuk ka skedarë të dorëzuar. Përndryshe mbylle projektin.")
        }
    }
    @ViewBuilder private func teacherTools(_ p: SchoolProject) -> some View {
        HStack {
            Button(p.isOpen ? "Mbyll projektin" : "Rihap projektin") { Task { await store.act("projectStatus", ["projectID": p.id, "close": p.isOpen]) } }
            Button("Fshi", role: .destructive) { confirmDelete = true }
        }
        Text(p.isOpen ? "Kur e mbyll, nuk pranohen më versione, skedarë ose kontribute. Mund ta rihapësh." : "Projekti është mbyllur: puna nuk ndryshon më.").font(.caption)
        if p.isGroup {
            let assigned = Set(p.teams.flatMap { $0.members.map(\.id) })
            let free = (p.students ?? []).filter { !assigned.contains($0.id) }
            DisclosureGroup("Krijo grup") {
                TextField("Emri i grupit, p.sh. Grupi A", text: $teamName)
                Button("Krijo grupin") { Task { if await store.act("projectTeamCreate", ["projectID": p.id, "name": teamName]) != nil { teamName = "" } } }
                    .disabled(teamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text(free.isEmpty ? "Të gjithë nxënësit e miratuar janë në grupe." : "Pa grup: " + free.map(\.email).joined(separator: ", ")).font(.footnote)
        } else {
            let started = Set(p.teams.flatMap { $0.members.map(\.id) })
            let waiting = (p.students ?? []).filter { !started.contains($0.id) }
            if !waiting.isEmpty { Text("Nuk e kanë nisur ende: " + waiting.map(\.email).joined(separator: ", ")).font(.footnote) }
        }
    }
}

// MARK: - Një grup (ose puna individuale e një nxënësi)
private struct TeamPanel: View {
    let project: SchoolProject
    let team: ProjectTeam
    @ObservedObject var store: ProjectsStore
    @EnvironmentObject private var account: Account
    @Environment(\.openURL) private var openURL
    @State private var roles: [String: String] = [:]
    @State private var contribution = ""
    @State private var draftNote = ""
    @State private var feedback: [String: String] = [:]
    @State private var addStudent = ""
    @State private var importing = false
    @State private var uploadNote = ""
    @State private var confirmSubmit = false
    private var isMember: Bool { account.role == .student }
    private var canEdit: Bool { isMember && project.isOpen }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(project.isGroup ? team.name : "Puna e " + team.name).font(.title3.bold())
            members
            contributions
            versions
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: ProjectFiles.types, allowsMultipleSelection: false) { result in Task { await upload(result) } }
        .confirmationDialog("Të dorëzohet versioni?", isPresented: $confirmSubmit, titleVisibility: .visible) {
            Button("Dorëzo") { Task { await submit() } }
            Button("Anulo", role: .cancel) {}
        } message: { Text("Pas dorëzimit versioni nuk ndryshon më. Për ndryshime hap versionin pasardhës.") }
        .onAppear { roles = Dictionary(uniqueKeysWithValues: team.members.map { ($0.id, $0.role) }); draftNote = team.draft?.note ?? "" }
    }

    @ViewBuilder private var members: some View {
        Text("Anëtarët dhe rolet").font(.headline)
        ForEach(team.members) { m in
            if canEdit || (project.mine && project.isOpen) {
                HStack {
                    Text(m.email).lineLimit(1)
                    TextField("Roli, p.sh. koordinator", text: Binding(get: { roles[m.id] ?? m.role }, set: { roles[m.id] = $0 }))
                    if (roles[m.id] ?? m.role) != m.role {
                        Button("Ruaj") { Task { await store.act("projectRole", ["teamID": team.id, "student": m.id, "role": roles[m.id] ?? ""]) } }
                    }
                    if project.mine && project.isGroup {
                        Button("Hiq", role: .destructive) { Task { await store.act("projectMember", ["teamID": team.id, "student": m.id, "add": false]) } }
                    }
                }
            } else {
                Text(m.email + (m.role.isEmpty ? "" : " · " + m.role))
            }
        }
        if project.mine && project.isGroup {
            let assigned = Set(project.teams.flatMap { $0.members.map(\.id) })
            let free = (project.students ?? []).filter { !assigned.contains($0.id) }
            if !free.isEmpty {
                HStack {
                    Picker("Shto nxënës", selection: $addStudent) {
                        Text("Zgjidh nxënësin").tag("")
                        ForEach(free) { Text($0.email).tag($0.id) }
                    }
                    Button("Shto") { Task { if await store.act("projectMember", ["teamID": team.id, "student": addStudent, "add": true]) != nil { addStudent = "" } } }
                        .disabled(addStudent.isEmpty)
                }
            }
            if team.members.isEmpty && team.versions.isEmpty {
                Button("Fshi grupin bosh", role: .destructive) { Task { await store.act("projectTeamDelete", ["teamID": team.id]) } }
            }
        }
    }

    @ViewBuilder private var contributions: some View {
        Text("Ditari i kontributeve").font(.headline)
        if canEdit {
            TextField("Çfarë bëre sot për projektin?", text: $contribution, axis: .vertical).lineLimit(2...5)
            Button("Shto në ditar") { Task { if await store.act("projectContribute", ["teamID": team.id, "note": contribution]) != nil { contribution = "" } } }
                .disabled(contribution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        if team.contributions.isEmpty { Text("Ende pa shënime.").font(.footnote) }
        ForEach(team.contributions.prefix(30)) { c in
            VStack(alignment: .leading, spacing: 2) {
                Text(c.note).fixedSize(horizontal: false, vertical: true)
                Text(c.student + " · " + dateText(c.date)).font(.caption)
            }
        }
    }

    @ViewBuilder private var versions: some View {
        Text("Versionet e dorëzimit").font(.headline)
        if canEdit {
            if let draft = team.draft {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Versioni \(draft.number) · draft").bold()
                    TextField("Shënim për mësuesin: çfarë ndryshoi në këtë version", text: $draftNote, axis: .vertical).lineLimit(2...6)
                    SubmissionFilesView(files: draft.files, editable: true, emptyHint: "Mund të shtosh dokument, prezantim, foto, audio ose video (deri 25 MB secili, gjithsej 10 për version).",
                                        onAdd: { importing = true },
                                        onRemove: { f in Task { await remove(f) } },
                                        onOpen: { f in Task { await open(f) } })
                    if !uploadNote.isEmpty { Text(uploadNote).font(.footnote) }
                    Text("Deri në 10 skedarë, 25 MB secili. Shënimi ruhet kur e dorëzon versionin.").font(.caption)
                    Button("Dorëzo versionin \(draft.number)") { confirmSubmit = true }
                        .disabled(draftNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.files.isEmpty)
                }
            } else {
                Button(team.versions.isEmpty ? "Fillo versionin e parë" : "Hap versionin \((team.versions.map(\.number).max() ?? 0) + 1)") {
                    Task { await store.act("projectVersionNew", ["teamID": team.id]) }
                }
            }
        }
        let done = team.versions.filter { !$0.isDraft }
        if done.isEmpty && !canEdit { Text(account.role == .parent ? "Asnjë version i dorëzuar ende." : "Asnjë version i dorëzuar.").font(.footnote) }
        ForEach(done) { v in
            DisclosureGroup("Versioni \(v.number) · " + statusText(v)) {
                VStack(alignment: .leading, spacing: 8) {
                    if let s = v.submitted { Text("Dorëzuar " + dateText(s) + (v.submittedBy.map { " nga " + $0 } ?? "") + (v.late ? " · me vonesë" : "")).font(.footnote) }
                    if !v.note.isEmpty { Text(v.note).fixedSize(horizontal: false, vertical: true) }
                    if !v.files.isEmpty || account.role != .parent {
                        SubmissionFilesView(files: v.files, editable: false, onOpen: { f in Task { await open(f) } })
                    }
                    if !v.feedback.isEmpty { SectionText(heading: "Komenti i mësuesit", text: v.feedback) }
                    if project.mine {
                        TextField("Komenti yt për këtë version", text: Binding(get: { feedback[v.id] ?? v.feedback }, set: { feedback[v.id] = $0 }), axis: .vertical).lineLimit(2...8)
                        Button(v.reviewed == nil ? "Dërgo vlerësimin" : "Përditëso vlerësimin") {
                            Task { await store.act("projectFeedback", ["versionID": v.id, "feedback": feedback[v.id] ?? v.feedback]) }
                        }
                        Text("Pas vlerësimit, prindi i anëtarëve sheh komentin dhe skedarët e këtij versioni.").font(.caption)
                    }
                }
            }
        }
    }

    private func statusText(_ v: ProjectVersion) -> String {
        (v.reviewed != nil ? "vlerësuar" : "në pritje të vlerësimit") + (v.late ? " · me vonesë" : "")
    }
    private func submit() async {
        guard let draft = team.draft else { return }
        await store.act("projectVersionSubmit", ["versionID": draft.id, "note": draftNote])
        if store.project(project.id)?.teams.first(where: { $0.id == team.id })?.draft == nil { draftNote = "" }
    }
    private func upload(_ result: Result<[URL], Error>) async {
        guard let draft = team.draft, !store.busy else { return }
        let url: URL
        switch result {
        case .failure(let error): store.message = error.localizedDescription; return
        case .success(let urls): guard let first = urls.first else { return }; url = first
        }
        guard draft.files.count < ProjectFiles.maxPerVersion else { store.message = "Ke arritur kufirin prej 10 skedarësh për këtë version."; return }
        store.busy = true
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= AttachmentFile.maxBytes else { throw AuthFailure(message: "Skedari është më i madh se 25 MB. Zvogëloje ose ndaje.") }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let path = team.id.lowercased() + "/" + draft.id.lowercased() + "/" + AttachmentFile.prefix() + "-" + AttachmentFile.safeName(url.lastPathComponent)
            uploadNote = "Në pritje për dërgim: " + url.lastPathComponent
            try await ProjectFiles.upload(path: path, data: data, mime: mime)
            uploadNote = "U dërgua: " + url.lastPathComponent
            store.message = ""
        } catch { uploadNote = ""; store.message = "Skedari nuk u dërgua: " + error.localizedDescription }
        store.busy = false
        await store.refresh()
    }
    private func remove(_ file: AttachmentFile) async {
        guard !store.busy else { return }
        store.busy = true
        do { try await ProjectFiles.delete(path: file.path); uploadNote = "U hoq: " + file.name }
        catch { store.message = error.localizedDescription }
        store.busy = false
        await store.refresh()
    }
    private func open(_ file: AttachmentFile) async {
        do { openURL(try await ProjectFiles.signedURL(path: file.path)) }
        catch { store.message = error.localizedDescription }
    }
}
