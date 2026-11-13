import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SchoolModel: ObservableObject {
    @Published var data = SchoolSnapshot()
    @Published var message = ""
    @Published var busy = false
    func refresh(_ token: String) async {
        do { data = try await SchoolAPI.call("snapshot",token:token); message = ""; await LocalReminders.sync(data) }
        catch { message = error.localizedDescription }
    }
    func change(_ action: String, _ body: [String:Any], token: String) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { let _: OKReply = try await SchoolAPI.call(action,body:body,token:token); await refresh(token) }
        catch { message = error.localizedDescription }
    }
}

struct SchoolHub: View {
    @EnvironmentObject private var account: Account
    @StateObject private var model = SchoolModel()
    @State private var className = ""
    @State private var level = SchoolLevel.basic
    @State private var code = ""
    @State private var familyCode = ""
    @State private var selectedClass = ""
    @State private var classToDelete: SchoolClass?
    @State private var examToDelete: SchoolExam?
    @AppStorage("studentLevel4") private var studentLevel = 0
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Shkolla ime").font(.title.bold())
            if account.isOnline {
                Text("Testet dhe kalendari ndahen vetëm me klasat ku je anëtar i miratuar.").font(.callout)
                if account.role == .teacher { teacherTools }
                if account.role == .student { studentTools }
                if account.role == .parent { familyTools }
                classList
                if SupabaseConfig.enabled {
                    NavigationLink { ClassScheduleView(classes: account.role == .teacher ? model.data.classes : [], canEdit: account.role == .teacher) } label: {
                        Tile(icon: "calendar.day.timeline.left", title: "Orari i klasës", detail: account.role == .teacher ? "Krijo orarin; merr njoftim para çdo ore" : "Orët e javës, me lëndën dhe sallën")
                    }
                }
                if SupabaseConfig.enabled {
                    NavigationLink { ProjectsScreen(ownedClasses: model.data.classes.filter { $0.owner == account.identity.replacingOccurrences(of:"school-",with:"") }) } label: {
                        Tile(icon:"folder",title:"Projektet",detail:"Individuale dhe në grup: role, ditar kontributesh, versione dorëzimi me skedarë")
                    }
                }
                assignedTests
                results
                if !model.message.isEmpty { Text(model.message).foregroundStyle(Color.red) }
                Button("Përditëso klasat dhe rezultatet") { Task { await model.refresh(account.token); await WatchPublisher.publish(model.data) } }
            } else {
                Text("Për klasa, teste me afat dhe rezultate mes pajisjeve, hyr te llogaria e shkollës. Mësimet dhe laboratorët punojnë edhe pa lidhje.")
                Text("Të dhënat e vjetra lokale ruhen në pajisje; nuk publikohen automatikisht si teste të reja.").font(.footnote)
            }
        }.disabled(model.busy).textFieldStyle(.roundedBorder)
        .onReceive(NotificationCenter.default.publisher(for: .brainSparkRefresh)) { _ in
            guard account.isOnline else { return }
            Task { await model.refresh(account.token); await WatchPublisher.publish(model.data) }
        }
        .task(id: account.isOnline) {
            // Apple Watch (#17): përmbledhja shkon në orë pas çdo rifreskimi; pa llogari, ora pastrohet.
            if account.isOnline { await model.refresh(account.token); await WatchPublisher.publish(model.data) } else { WatchPublisher.clear() }
        }
        .confirmationDialog("Të fshihet klasa?", isPresented: Binding(get: { classToDelete != nil }, set: { if !$0 { classToDelete = nil } }), titleVisibility: .visible, presenting: classToDelete) { group in
            Button("Fshi «" + group.name + "» përgjithmonë", role: .destructive) {
                if selectedClass == group.id { selectedClass = "" }
                change("classDelete", ["classID": group.id, "confirm": true])
            }
            Button("Anulo", role: .cancel) {}
        } message: { _ in
            Text("Do të fshihen anëtarësimet, testet, rezultatet dhe notat e kësaj klase. Eventet e kalendarit të klasës fshihen gjithashtu. Nuk kthehet mbrapsht.")
        }
        .confirmationDialog("Të fshihet testi?", isPresented: Binding(get: { examToDelete != nil }, set: { if !$0 { examToDelete = nil } }), titleVisibility: .visible, presenting: examToDelete) { exam in
            Button("Fshi «" + exam.title + "» përgjithmonë", role: .destructive) { change("examDelete", ["examID": exam.id, "confirm": true]) }
            Button("Anulo", role: .cancel) {}
        } message: { _ in
            Text("Do të fshihen pyetjet, përgjigjet e nxënësve dhe notat e këtij testi. Nuk kthehet mbrapsht. Nëse do t'i ruash rezultatet, mos e fshi.")
        }
    }
    private var teacherTools: some View {
        VStack(alignment:.leading,spacing:12) {
            DisclosureGroup("Krijo një klasë reale") {
                TextField("Emri, p.sh. XI B · Don Bosco",text:$className)
                LevelPicker(level:$level)
                Button("Krijo klasën") { change("classCreate",["name":className,"level":level.rawValue]) }.disabled(className.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            }
            let owned = model.data.classes.filter { $0.owner == account.identity.replacingOccurrences(of:"school-",with:"") }
            if !owned.isEmpty {
                Picker("Klasa e testit",selection:$selectedClass) {
                    Text("Zgjidh klasën").tag("")
                    ForEach(owned) { Text($0.name).tag($0.id) }
                }
                if let group = owned.first(where: { $0.id == selectedClass }) {
                    NavigationLink { ExamComposer(group:group) } label: { Tile(icon:"doc.badge.plus",title:"Krijo test për " + group.name,detail:"Ushtrime nga banka sipas lëndës dhe nivelit, pyetje personale, afat dhe pikë") }
                }
            }
        }
    }
    private var studentTools: some View {
        VStack(alignment:.leading,spacing:12) {
            DisclosureGroup("Bashkohu me klasën") {
                TextField("Kodi i klasës",text:$code).autocorrectionDisabled()
                Button("Kërko anëtarësim") { change("classJoin",["code":code]) }.disabled(code.isEmpty)
                Text("Mësuesi e miraton kërkesën para se të shohësh testet.").font(.caption)
            }
            DisclosureGroup("Lidh prindin me profilin tim") {
                Button("Krijo kod për prindin · 15 minuta") {
                    Task { do { let reply: OKReply = try await SchoolAPI.call("familyCode",token:account.token); familyCode = reply.code ?? "" } catch { model.message = error.localizedDescription } }
                }
                if !familyCode.isEmpty { Text(familyCode).font(.headline.monospaced()).textSelection(.enabled); ShareLink(item:familyCode) { Text("Ndaje kodin me prindin") } }
                ForEach(model.data.parents) { parent in
                    Text(parent.email)
                    Button("Hiq qasjen e këtij prindi",role:.destructive) { change("unlinkParent",["parent":parent.id]) }
                }
            }
        }
    }
    private var familyTools: some View {
        DisclosureGroup("Lidh profilin e fëmijës") {
            Text("Fëmija e gjeneron kodin nga profili i vet. Kodi përdoret vetëm një herë.")
            TextField("Kodi i lidhjes",text:$code).autocorrectionDisabled()
            Button("Lidh profilin") { change("familyJoin",["code":code]) }.disabled(code.isEmpty)
            ForEach(model.data.children ?? []) { child in
                Text("Fëmija i lidhur: " + child.email)
                Button("Hiq lidhjen me këtë fëmijë",role:.destructive) { change("unlinkChild",["child":child.id]) }
            }
        }
    }
    private var classList: some View {
        VStack(alignment:.leading,spacing:12) {
            if model.data.classes.isEmpty { Text("Ende nuk je lidhur me ndonjë klasë.") }
            ForEach(model.data.classes) { group in
                DisclosureGroup(group.name + (group.approved ? "" : " · Në pritje")) {
                    Text(SchoolLevel(rawValue:group.level)?.name ?? "")
                    if account.role == .student && group.approved {
                        Button("Përdor nivelin e kësaj klase për mësimet") { studentLevel = group.level }
                    }
                    if !group.code.isEmpty {
                        Text("Kodi i anëtarësimit: " + group.code).textSelection(.enabled)
                        ShareLink(item:group.name + " · " + group.code) { Text("Ndaje kodin e klasës") }
                        Button("Ndrysho kodin e klasës") { change("rotateCode",["classID":group.id]) }
                        if SupabaseConfig.enabled && group.owner == account.identity.replacingOccurrences(of:"school-",with:"") {
                            Button("Fshi klasën",role:.destructive) { classToDelete = group }
                        }
                        ForEach(model.data.members.filter { $0.classID == group.id }) { member in
                            HStack {
                                Text(member.email)
                                Spacer()
                                if !member.approved { Button("Mirato") { change("approve",["classID":group.id,"student":member.id]) } }
                                Button("Hiq",role:.destructive) { change("removeMember",["classID":group.id,"student":member.id]) }
                            }
                        }
                    }
                }.padding().glass(cornerRadius: 12)
            }
        }
    }
    private var assignedTests: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Testet e klasës").font(.title2.bold())
            ForEach(model.data.tests) { exam in
                if account.role == .student {
                    NavigationLink { SchoolTestPlayer(exam:exam) } label: {
                        Tile(icon:"timer",title:exam.title,detail:"\(exam.count) pyetje · \(exam.minutes) min · " + (model.data.classes.first { $0.id == exam.classID }?.name ?? ""))
                    }
                } else {
                    VStack(alignment:.leading,spacing:6) {
                        Text(exam.title + " · \(exam.minutes) min" + statusSuffix(exam.status))
                        if account.role == .teacher && SupabaseConfig.enabled {
                            HStack {
                                if exam.status != "published" { Button("Publiko") { change("examPublish",["examID":exam.id]) } }
                                if exam.status == "published" { Button("Mbyll testin") { change("examPublish",["examID":exam.id,"close":true]) } }
                                if exam.status != "published" { Button("Fshi",role:.destructive) { examToDelete = exam } }
                            }
                            if exam.status == "published" { Text("Për ta fshirë, mbylle më parë testin.").font(.caption) }
                        }
                    }
                }
            }
        }
    }
    private var results: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Vlerësimi").font(.title2.bold())
            if model.data.results.isEmpty { Text("Këtu shfaqen testet e dorëzuara dhe testet me kohë të përfunduar.") }
            ForEach(model.data.results) { result in
                if account.role == .teacher {
                    NavigationLink { ExamReview(attempt:result) } label: {
                        Tile(icon:"checklist",title:(result.student ?? "") + " · " + result.title,detail:scoreText(result) + " · " + (result.className ?? ""))
                    }
                } else {
                    DisclosureGroup(result.title + " · " + scoreText(result)) {
                        Text((result.student ?? "") + " · " + (result.className ?? ""))
                        Text("Rezultati mund të përditësohet pas vlerësimit të arsyetimit nga mësuesi.").font(.caption)
                        ForEach(result.questions) { q in
                            if let feedback = result.feedback[q.id], !feedback.isEmpty { SectionText(heading:q.prompt,text:feedback) }
                        }
                    }
                }
            }
        }
    }
    private func statusSuffix(_ status: String?) -> String {
        switch status { case "draft": return " · draft"; case "published": return " · publikuar"; case "closed": return " · mbyllur"; default: return "" }
    }
    private func scoreText(_ r: RemoteAttempt) -> String {
        if account.role == .teacher { return "\(r.score ?? 0)/\(r.maximum) pikë" + (r.status.map { " · " + $0 } ?? "") + (r.preliminary.map { " · automatike paraprake \($0)" } ?? "") }
        if let score = r.score { return "\(score)/\(r.maximum) pikë" }
        return r.status ?? "në pritje të vlerësimit"
    }
    private func change(_ action: String, _ body: [String:Any]) { Task { await model.change(action,body,token:account.token) } }
}
