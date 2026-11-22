import SwiftUI

// Këndi i mësuesit dhe këndi i prindit (#116).
// Mësuesi: lëndët që jep, klasat ku është kujdestar ose mësues lënde, ftesat, mësuesit e klasës (kujdestari i fton),
// mbledhjet me prindër. Biblioteka e shkencave hapet vetëm për lëndët shkencore që jep.
// Prindi: shkruaj sekretarisë, shkruaj mësuesve, progresi i fëmijës, mbledhjet me prindër.

struct TeacherClassInfo: Decodable, Identifiable, Hashable {
    let id, name: String
    let level: Int
    let official: Bool
    let homeroom: Bool
    let homeroomName: String?
    let subject: String?
    let students: Int
    let teachers: [ClassTeacherInfo]?
}
struct ClassTeacherInfo: Decodable, Identifiable, Hashable { let id: String; let name: String?; let subject: String?; let status: String }
struct TeacherInvite: Decodable, Identifiable { let classID, className: String; let homeroomName: String?; let subject: String?; var id: String { classID } }
private struct TeacherHomeReply: Decodable { let subjects: [String]; let allSubjects: [String]; let classes: [TeacherClassInfo]; let invites: [TeacherInvite] }
struct DirectoryTeacher: Decodable, Identifiable, Hashable { let id: String; let name: String?; let email: String?; let subjects: [String]? }
private struct DirectoryReply: Decodable { let teachers: [DirectoryTeacher] }
private struct SubjectsReply: Decodable { let subjects: [String] }
private struct ChatOpenReply: Decodable { let id: String? }

@MainActor
final class TeacherHomeModel: ObservableObject {
    @Published var subjects: [String] = []
    @Published var allSubjects: [String] = []
    @Published var classes: [TeacherClassInfo] = []
    @Published var invites: [TeacherInvite] = []
    @Published var directory: [DirectoryTeacher] = []
    @Published var loaded = false
    @Published var error = ""
    @Published var message = ""

    func load() async {
        do {
            let reply: TeacherHomeReply = try await SchoolAPI.call("teacherHome")
            subjects = reply.subjects; allSubjects = reply.allSubjects; classes = reply.classes; invites = reply.invites
            loaded = true; error = ""
        } catch { self.error = error.localizedDescription }
    }
    func saveSubjects(_ list: [String], account: Account) async -> Bool {
        do {
            let reply: SubjectsReply = try await SchoolAPI.call("teacherSubjects", body: ["subjects": list])
            subjects = reply.subjects; account.teacherSubjects = reply.subjects; error = ""; return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func respond(_ invite: TeacherInvite, accept: Bool) async {
        await run("classTeacherRespond", ["classID": invite.classID, "accept": accept], done: accept ? "U bashkove me klasën " + invite.className + "." : "")
    }
    func loadDirectory() async {
        if let reply: DirectoryReply = try? await SchoolAPI.call("teacherDirectory") { directory = reply.teachers }
    }
    func invite(_ teacher: DirectoryTeacher, to info: TeacherClassInfo, subject: String) async -> Bool {
        await run("classTeacherInvite", ["classID": info.id, "teacherID": teacher.id, "subject": subject], done: "Ftesa u dërgua te " + (teacher.name ?? "mësuesi") + ".")
    }
    func remove(_ teacher: ClassTeacherInfo?, from info: TeacherClassInfo) async {
        var body: [String: Any] = ["classID": info.id]
        if let teacher { body["teacherID"] = teacher.id }
        await run("classTeacherRemove", body, done: "")
    }
    func meeting(_ info: TeacherClassInfo, title: String, date: Date, note: String) async -> Bool {
        await run("eventCreate", ["classID": info.id, "title": title, "note": note, "date": date.timeIntervalSince1970, "kind": "parent_meeting"],
                  done: "Mbledhja u caktua. Prindërit e shohin te kalendari.")
    }
    @discardableResult
    private func run(_ action: String, _ body: [String: Any], done: String) async -> Bool {
        do {
            let _: OKReply = try await SchoolAPI.call(action, body: body)
            message = done; error = ""; await load(); return true
        } catch { self.error = error.localizedDescription; return false }
    }
}

struct TeacherHome: View {
    @EnvironmentObject private var account: Account
    @ObservedObject var chats: ChatStore
    let open: (Subject) -> Void
    @StateObject private var model = TeacherHomeModel()
    @State private var pickSubjects = false
    var body: some View {
        Page {
            HomeHeader(role: .teacher).appearIn(0)
            subjectsCard.appearIn(1)
            if !model.error.isEmpty { Label(model.error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout) }
            if !model.message.isEmpty { Label(model.message, systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout) }
            if !model.invites.isEmpty { invitesCard }
            TodaySection(role: .teacher)
            classesCard
            Text("Mjetet e mia").font(.title2.bold())
            NavigationLink { RoleDesk(role: .teacher) } label: {
                Tile(icon: "doc.text.fill", title: "Testet, detyrat dhe materialet", detail: "Krijo teste, publiko rezultate, menaxho klasat")
            }
            NavigationLink { SharedSchoolCalendar() } label: { Tile(icon: "calendar", title: "Kalendari", detail: "Testet, detyrat dhe mbledhjet e klasave të mia") }
            ForEach(account.teacherSciences) { subject in
                Button { open(subject) } label: {
                    Tile(icon: subject.icon, title: "Biblioteka · " + subject.rawValue, detail: "Mësime, ushtrime dhe laboratorë për t'ua dërguar klasave")
                }
            }
        }
        .buttonStyle(.plain)
        .task { await model.load(); if model.subjects.isEmpty && model.loaded { pickSubjects = true } }
        .refreshable { await model.load() }
        .sheet(isPresented: $pickSubjects) {
            SubjectPickerSheet(all: model.allSubjects, chosen: Set(model.subjects)) { list in
                await model.saveSubjects(list, account: account)
            }
        }
    }
    private var subjectsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.subjects.isEmpty ? "Cilat lëndë jep?" : "Lëndët e mia").font(.headline)
                Spacer()
                Button(model.subjects.isEmpty ? "Zgjidh" : "Ndrysho") { pickSubjects = true }.font(.subheadline.bold())
            }
            if model.subjects.isEmpty {
                Text("Zgjidh lëndët që jep. Faqja përshtatet sipas tyre: shkencat hapin bibliotekën dhe laboratorin.").font(.footnote).foregroundStyle(.secondary)
            } else {
                FlowChips(items: model.subjects)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 18)
    }
    private var invitesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Ftesa për klasa", systemImage: "envelope.badge.fill").font(.headline)
            ForEach(model.invites) { invite in
                VStack(alignment: .leading, spacing: 6) {
                    Text("Klasa " + invite.className + (invite.subject.map { " · " + $0 } ?? "")).font(.body.weight(.semibold))
                    Text("Kujdestari: " + (invite.homeroomName ?? "—")).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Prano") { Task { await model.respond(invite, accept: true) } }.buttonStyle(.liquidProminent)
                        Button("Refuzo", role: .destructive) { Task { await model.respond(invite, accept: false) } }
                    }
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.10)))
            }
        }
    }
    private var classesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Klasat e mia").font(.title2.bold())
            if model.loaded && model.classes.isEmpty {
                Text("Nuk je ende në asnjë klasë. Sekretaria cakton kujdestarët; kujdestari të fton si mësues lënde.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(model.classes) { info in
                NavigationLink { TeacherClassView(info: info, model: model, chats: chats) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: info.homeroom ? "star.circle.fill" : "person.3.fill")
                            .font(.title2).foregroundStyle(info.homeroom ? Color.sun : Color.lagoon).frame(width: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(info.name).font(.headline)
                            Text((info.homeroom ? "Kujdestar" : (info.subject ?? "Mësues")) + " · \(info.students) nxënës")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding(12).glass(cornerRadius: 14)
                }
            }
        }
    }
}

/// Etiketa të vogla për lëndët.
struct FlowChips: View {
    let items: [String]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item).font(.subheadline.weight(.semibold)).lineLimit(1)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Color.lagoon.opacity(0.15)))
            }
        }
    }
}

struct SubjectPickerSheet: View {
    let all: [String]
    @State var chosen: Set<String>
    let save: ([String]) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    var body: some View {
        NavigationStack {
            List {
                Section(footer: Text("Deri në 6 lëndë. Matematika, Fizika, Kimia dhe Biologjia hapin edhe bibliotekën e mësimeve dhe laboratorin.")) {
                    ForEach(all, id: \.self) { subject in
                        Button {
                            if chosen.contains(subject) { chosen.remove(subject) } else if chosen.count < 6 { chosen.insert(subject) }
                        } label: {
                            HStack {
                                Text(subject).foregroundStyle(Color.primary)
                                Spacer()
                                if chosen.contains(subject) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.lagoon) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Lëndët që jep")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Anulo") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ruaj") {
                        busy = true
                        Task { if await save(all.filter { chosen.contains($0) }) { dismiss() }; busy = false }
                    }.disabled(chosen.isEmpty || busy)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }
}

struct TeacherClassView: View {
    let info: TeacherClassInfo
    @ObservedObject var model: TeacherHomeModel
    @ObservedObject var chats: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var inviting = false
    @State private var meeting = false
    @State private var chatID: String?
    @State private var openChat = false
    @State private var leave = false
    /// Gjendja e freskët (pas ftesave/heqjeve).
    private var current: TeacherClassInfo { model.classes.first(where: { $0.id == info.id }) ?? info }
    var body: some View {
        Page {
            Text("Klasa " + current.name).font(.largeTitle.bold())
            Text(current.homeroom ? "Je kujdestari i kësaj klase (administratori i grupit)." : "Jep " + (current.subject ?? "mësim") + " në këtë klasë · kujdestar: " + (current.homeroomName ?? "—"))
                .font(.callout).foregroundStyle(.secondary)
            Text("\(current.students) nxënës").font(.headline)
            if !model.error.isEmpty { Label(model.error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout) }
            if !model.message.isEmpty { Label(model.message, systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout) }
            Button {
                Task { @MainActor in
                    if let reply: ChatOpenReply = try? await SchoolAPI.call("chatOpen", body: ["classID": current.id]), let id = reply.id {
                        chatID = id; openChat = true
                    }
                }
            } label: { Label("Grupi i klasës", systemImage: "bubble.left.and.bubble.right.fill").frame(maxWidth: .infinity) }
            .buttonStyle(.liquidProminent).controlSize(.large)
            NavigationLink { RoleDesk(role: .teacher) } label: {
                Label("Dërgo test, detyrë ose material", systemImage: "paperplane.fill").frame(maxWidth: .infinity)
            }.buttonStyle(.liquid)
            if current.homeroom {
                teachersSection
                Button { meeting = true } label: {
                    Label("Cakto mbledhje me prindër", systemImage: "person.2.wave.2.fill").frame(maxWidth: .infinity)
                }.buttonStyle(.liquid)
            } else {
                Button("Largohu nga kjo klasë", role: .destructive) { leave = true }
            }
        }
        .navigationDestination(isPresented: $openChat) {
            if let chatID { ChatThreadView(chatID: chatID, store: chats) }
        }
        .sheet(isPresented: $inviting) { InviteTeacherSheet(info: current, model: model) }
        .sheet(isPresented: $meeting) { ParentMeetingSheet(info: current, model: model) }
        .alert("Të largohesh nga klasa " + current.name + "?", isPresented: $leave) {
            Button("Anulo", role: .cancel) {}
            Button("Largohu", role: .destructive) { Task { await model.remove(nil, from: current); dismiss() } }
        }
    }
    private var teachersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Mësuesit e klasës").font(.title3.bold())
                Spacer()
                Button { inviting = true } label: { Label("Fto", systemImage: "person.badge.plus") }.buttonStyle(.liquidProminent)
            }
            let teachers = current.teachers ?? []
            if teachers.isEmpty { Text("Fto mësuesit që japin mësim në këtë klasë.").font(.footnote).foregroundStyle(.secondary) }
            ForEach(teachers) { teacher in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(teacher.name ?? "Mësues").font(.body.weight(.semibold))
                        Text((teacher.subject ?? "Pa lëndë") + (teacher.status == "invited" ? " · pret pranimin" : "")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Hiq", role: .destructive) { Task { await model.remove(teacher, from: current) } }.font(.caption)
                }
                .padding(10).background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
            }
        }
    }
}

struct InviteTeacherSheet: View {
    let info: TeacherClassInfo
    @ObservedObject var model: TeacherHomeModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var selected: DirectoryTeacher?
    @State private var subject = ""
    private var candidates: [DirectoryTeacher] {
        let taken = Set((info.teachers ?? []).map(\.id))
        return model.directory.filter { !taken.contains($0.id) && (search.isEmpty || ($0.name ?? "").localizedCaseInsensitiveContains(search)
                                                              || ($0.subjects ?? []).joined(separator: " ").localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        NavigationStack {
            List {
                if let selected {
                    Section("Lënda në klasën " + info.name) {
                        Picker("Lënda", selection: $subject) {
                            ForEach((selected.subjects ?? []).isEmpty ? model.allSubjects : (selected.subjects ?? []), id: \.self) { Text($0).tag($0) }
                        }
                        Button("Dërgo ftesën") {
                            Task { if await model.invite(selected, to: info, subject: subject) { dismiss() } }
                        }.disabled(subject.isEmpty)
                    }
                }
                Section("Mësuesit e shkollës") {
                    ForEach(candidates) { teacher in
                        Button {
                            selected = teacher
                            subject = (teacher.subjects ?? []).first ?? model.allSubjects.first ?? ""
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(teacher.name ?? teacher.email ?? "Mësues").foregroundStyle(Color.primary)
                                    Text((teacher.subjects ?? []).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selected?.id == teacher.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.lagoon) }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Kërko mësues ose lëndë")
            .navigationTitle("Fto mësues")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Mbyll") { dismiss() } } }
            .task { await model.loadDirectory() }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }
}

struct ParentMeetingSheet: View {
    let info: TeacherClassInfo
    @ObservedObject var model: TeacherHomeModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = "Mbledhje me prindër"
    @State private var date = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State private var note = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("Titulli", text: $title)
                DatePicker("Data dhe ora", selection: $date, in: Date.now...)
                TextField("Shënim (vendi, rendi i ditës)", text: $note, axis: .vertical).lineLimit(2...5)
                Text("Prindërit e nxënësve të klasës " + info.name + " e shohin te kalendari dhe te faqja e tyre.").font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Mbledhje me prindër")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Anulo") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cakto") { Task { if await model.meeting(info, title: title, date: date, note: note) { dismiss() } } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }
}

// MARK: - Prindi

struct ParentHome: View {
    @EnvironmentObject private var account: Account
    @ObservedObject var chats: ChatStore
    let openChats: () -> Void
    @StateObject private var school = SchoolModel()
    @State private var chatID: String?
    @State private var openChat = false
    private var meetings: [RemoteEvent] {
        school.data.events.filter { $0.isParentMeeting && $0.date >= Date.now.addingTimeInterval(-86_400).timeIntervalSince1970 }
    }
    var body: some View {
        Page {
            HomeHeader(role: .parent).appearIn(0)
            Text("Këndi i prindit").font(.title2.bold())
            meetingsCard
            Button {
                Task { @MainActor in
                    if let id = await chats.open(userID: "office") { chatID = id; openChat = true }
                }
            } label: {
                Tile(icon: "building.columns.fill", title: "Shkruaj sekretarisë", detail: "Pyetje, dokumente, mungesa, takime")
            }
            Button { openChats() } label: {
                Tile(icon: "bubble.left.and.bubble.right.fill", title: "Shkruaj mësuesve", detail: "Kujdestari dhe mësuesit e lëndëve të fëmijës")
            }
            NavigationLink { RoleDesk(role: .parent) } label: {
                Tile(icon: "chart.line.uptrend.xyaxis", title: "Progresi i fëmijës", detail: "Rezultatet e testeve dhe lidhja me fëmijën")
            }
            TodaySection(role: .parent)
        }
        .buttonStyle(.plain)
        .task { await school.refresh(account.token) }
        .refreshable { await school.refresh(account.token) }
        .navigationDestination(isPresented: $openChat) {
            if let chatID { ChatThreadView(chatID: chatID, store: chats) }
        }
    }
    private var meetingsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Mbledhjet me prindër", systemImage: "person.2.wave.2.fill").font(.headline).foregroundStyle(Color.pink)
            if meetings.isEmpty {
                Text("Nuk ka mbledhje të caktuara. Kur kujdestari cakton një, shfaqet këtu.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(meetings) { event in
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title).font(.body.weight(.semibold))
                    let className = school.data.classes.first(where: { $0.id == event.classID })?.name ?? ""
                    Text(className + " · " + Date(timeIntervalSince1970: event.date).formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                    if !event.note.isEmpty { Text(event.note).font(.caption) }
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.pink.opacity(0.08)))
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 18)
    }
}
