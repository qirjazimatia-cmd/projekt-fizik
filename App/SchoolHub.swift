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
                }.padding().background(.white,in:RoundedRectangle(cornerRadius:12))
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

private struct CustomQuestion: Identifiable {
    var id = UUID()
    var prompt = ""
    var answer = ""
    var explanation = ""
    var unit = ""
    var kind = "number"
    var tolerance = "0.005"
    var points = 4
    var options = ""
    var bankID: String? = nil
    /// Ushtrim nga banka → pyetje testi. Zgjedhjet me disa përgjigje të sakta nuk mbështeten (testi pranon një alternativë të saktë).
    init() {}
    init?(bank exercise: Exercise) {
        guard let first = exercise.answers.first else { return nil }
        prompt = exercise.prompt; explanation = exercise.why; bankID = exercise.id
        if exercise.kind == "number" {
            kind = "number"; answer = first; unit = exercise.unit
            tolerance = exercise.tolerance == 0 ? "0" : String(exercise.tolerance)
        } else if exercise.kind == "select", exercise.answers.count == 1, exercise.choices.count >= 2 {
            kind = "choice"; answer = first; options = exercise.choices.joined(separator: "\n")
        } else { return nil }
    }
    var json: [String:Any] {
        var d: [String:Any] = ["prompt":prompt,"answer":answer,"explanation":explanation,"unit":unit,"kind":kind,"points":points]
        if kind == "number" { d["tolerance"] = Double(tolerance.replacingOccurrences(of:",",with:".")) ?? -1 }
        if kind == "choice" { d["options"] = options.split(whereSeparator:{ $0 == "\n" || $0 == ";" }).map { $0.trimmingCharacters(in:.whitespaces) }.filter { !$0.isEmpty } }
        return d
    }
}
struct ExamComposer: View {
    let group: SchoolClass
    @EnvironmentObject private var account: Account
    @State private var title = ""
    @State private var subject = Subject.math
    @State private var minutes = 30
    @State private var generated = SupabaseConfig.enabled ? 0 : 5
    @State private var hasClose = false
    @State private var closesAt = Date().addingTimeInterval(7*86400)
    @State private var savedAsDraft = false
    @State private var questions: [CustomQuestion] = []
    @State private var bankSearch = ""
    @State private var picked: Set<String> = []
    @State private var busy = false
    @State private var published = false
    @State private var message = ""
    var body: some View {
        Page {
            Text("Test i ri · " + group.name).font(.title.bold())
            Text("Variantet numerike krijohen në shërbimin e shkollës kur nxënësi nis testin. Pyetjet personale dhe çelësi nuk përfshihen në bankën publike të praktikës.")
            TextField("Titulli",text:$title)
            Picker("Lënda",selection:$subject) { ForEach(Subject.allCases) { Text($0.rawValue).tag($0) } }
            Stepper("Koha: \(minutes) minuta",value:$minutes,in:1...180)
            if SupabaseConfig.enabled {
                Toggle("Afat i fundit për nisjen e testit",isOn:$hasClose)
                if hasClose { DatePicker("Afati",selection:$closesAt) }
                Text("Nisja dhe afati llogariten nga ora e serverit. Nëse interneti ndërpritet gjatë testit, përgjigjet ruhen në pajisje, por afati nuk zgjatet: pranohen vetëm ato që arrijnë në server para afatit.").font(.caption)
            } else {
                Stepper("Pyetje me variante të reja: \(generated)",value:$generated,in:0...30)
                Text("Çdo pyetje e gjeneruar vlen 4 pikë. Për çdo nxënës ruhen pyetjet e veta, kështu që rikthimi nuk gjeneron një test tjetër.").font(.caption)
            }
            if SupabaseConfig.enabled { bankSection }
            ForEach($questions) { $q in
                GroupBox(q.bankID.map { "Nga banka · " + $0 } ?? "Pyetje personale") {
                    VStack(alignment:.leading,spacing:10) {
                        TextField("Pyetja",text:$q.prompt,axis:.vertical)
                        Picker("Lloji",selection:$q.kind) {
                            Text("Numër").tag("number"); Text("Tekst").tag("text")
                            if SupabaseConfig.enabled { Text("Alternativa").tag("choice"); Text("E zhvilluar (korrigjim manual)").tag("open") }
                        }
                        if q.kind == "choice" { TextField("Alternativat, një për rresht ose të ndara me ;",text:$q.options,axis:.vertical) }
                        if q.kind == "open" { Text("Pa çelës automatik: e vlerëson mësuesi me pikë të pjesshme dhe koment.").font(.caption) }
                        else { TextField(q.kind == "choice" ? "Alternativa e saktë (shkruaje saktësisht si më sipër)" : "Përgjigjja për çelësin e mësuesit",text:$q.answer) }
                        if q.kind == "number" { TextField("Njësia",text:$q.unit); TextField("Gabimi absolut i lejuar, p.sh. 0.005",text:$q.tolerance) }
                        TextField("Hapat / rubrika e vlerësimit",text:$q.explanation,axis:.vertical)
                        Stepper("Pikë: \(q.points)",value:$q.points,in:1...20)
                        Button("Hiq pyetjen",role:.destructive) { let id = q.id; questions.removeAll { $0.id == id } }
                    }.padding(6)
                }
            }
            Button("Shto pyetje personale") { questions.append(CustomQuestion()) }.disabled(questions.count + generated >= 30)
            if !message.isEmpty { Text(message) }
            if published { Text(savedAsDraft ? "Drafti u ruajt. Publikoje nga lista e testeve te Shkolla ime kur të jetë gati." : "Testi u publikua. Nxënësit e miratuar të kësaj klase e shohin nga pajisjet e tyre.").font(.headline) }
            else {
                if SupabaseConfig.enabled {
                    Button("Ruaj si draft") { Task { await publish(draft:true) } }.disabled(busy || title.isEmpty || questions.isEmpty)
                }
                Button(busy ? "Duke publikuar…" : "Publiko testin") { Task { await publish(draft:false) } }
                    .buttonStyle(.borderedProminent).disabled(busy || title.isEmpty || generated+questions.count == 0 || generated+questions.count>30)
            }
        }.textFieldStyle(.roundedBorder).disabled(busy || published)
        .onChange(of: subject) { _ in picked = [] }
    }
    /// Ushtrimet e bankës për lëndën e zgjedhur dhe nivelin e klasës.
    private var bankCandidates: [Exercise] {
        let query = bankSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let used = Set(questions.compactMap(\.bankID))
        return Exercise.all
            .filter { $0.subject == subject.rawValue && $0.level == group.level && CustomQuestion(bank: $0) != nil && !used.contains($0.id) }
            .filter { query.isEmpty || $0.id.lowercased().hasPrefix(query) || $0.prompt.lowercased().contains(query) }
            .sorted { $0.id < $1.id }
    }
    @ViewBuilder private var bankSection: some View {
        let candidates = bankCandidates
        DisclosureGroup("Zgjidh ushtrime nga banka · " + subject.rawValue + " · " + (SchoolLevel(rawValue: group.level)?.name ?? "")) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Shfaqen ushtrimet e lëndës së zgjedhur me nivelin e klasës. Çelësi vjen nga banka dhe ruhet vetëm në server; nxënësi nuk e sheh. Mund ta ndryshosh pyetjen, pikët ose përgjigjen pasi ta shtosh.").font(.caption)
                Text("Ushtrimet me disa përgjigje të sakta nuk përfshihen, sepse testi pranon një alternativë të saktë.").font(.caption)
                TextField("Kërko me kod ose fjalë, p.sh. F2-05", text: $bankSearch).autocorrectionDisabled()
                HStack {
                    Button("Shto 5 rastësisht") { add(Array(candidates.shuffled().prefix(5))) }.disabled(candidates.isEmpty || questions.count >= 30)
                    Button("Shto të zgjedhurat (\(picked.count))") { add(candidates.filter { picked.contains($0.id) }); picked = [] }.disabled(picked.isEmpty || questions.count >= 30)
                }
                if candidates.isEmpty { Text("Nuk ka ushtrime të tjera për këtë lëndë dhe nivel.").font(.footnote) }
                ForEach(candidates.prefix(60)) { item in
                    Button {
                        if picked.contains(item.id) { picked.remove(item.id) } else { picked.insert(item.id) }
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: picked.contains(item.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(Color.lagoon)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.prompt).font(.subheadline).multilineTextAlignment(.leading)
                                Text(item.id + " · " + (item.kind == "number" ? "llogaritje" : "alternativa")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.buttonStyle(.plain)
                }
                if candidates.count > 60 { Text("Po shfaqen 60 nga \(candidates.count). Kërko për të ngushtuar listën.").font(.caption) }
            }
        }
    }
    private func add(_ items: [Exercise]) {
        for item in items where questions.count < 30 {
            if let question = CustomQuestion(bank: item) { questions.append(question) }
        }
    }
    private func publish(draft: Bool = false) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            var body: [String:Any] = ["classID":group.id,"title":title,"subject":subject.rawValue,"minutes":minutes,"generated":generated,"questions":questions.map(\.json),"publish":!draft]
            if SupabaseConfig.enabled && hasClose { body["closesAt"] = closesAt.timeIntervalSince1970 }
            let _: OKReply = try await SchoolAPI.call("examCreate",body:body,token:account.token)
            savedAsDraft = draft; published = true
        } catch { message = error.localizedDescription }
    }
}

/// Lista e skedarëve të një pyetjeje. E ndarë nga ekranet e testit që kompiluesi t'i kontrollojë shpejt.
struct SubmissionFilesView: View {
    let files: [AttachmentFile]
    let editable: Bool
    var emptyHint: String? = nil
    var onAdd: (() -> Void)? = nil
    var onRemove: ((AttachmentFile) -> Void)? = nil
    var onOpen: ((AttachmentFile) -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Skedarët").font(.headline)
            if files.isEmpty {
                Text(editable ? (emptyHint ?? "Mund të shtosh dokument, foto, audio ose video (deri 25 MB secili, gjithsej 10 për test).") : "Asnjë skedar.").font(.footnote)
            }
            ForEach(files) { file in
                HStack {
                    Label(file.name + " · " + file.sizeText, systemImage: file.icon)
                    Spacer()
                    if let open = onOpen { Button("Hap") { open(file) } }
                    if editable, let remove = onRemove { Button("Hiq", role: .destructive) { remove(file) } }
                }
            }
            if editable, let add = onAdd { Button("Shto skedar") { add() } }
        }
    }
}

struct SchoolTestPlayer: View {
    static let fileTypes: [UTType] = [.pdf, .plainText, .jpeg, .png, .heic, .mp3, .mpeg4Audio, .mpeg4Movie, .quickTimeMovie]
        + [UTType("org.openxmlformats.wordprocessingml.document"), UTType("com.microsoft.word.doc"), UTType("com.apple.m4a-audio")].compactMap { $0 }
    let exam: SchoolExam
    @EnvironmentObject private var account: Account
    @Environment(\.scenePhase) private var scenePhase
    @State private var attempt: RemoteAttempt?
    @State private var chosen = 0
    @State private var value = ""
    @State private var reasoning = ""
    @State private var message = ""
    @State private var busy = false
    @State private var now = 0.0
    @State private var receivedUptime = 0.0
    @State private var receivedServer = 0.0
    @State private var expired = false
    @State private var confirm = false
    @State private var dirty = false
    @State private var importing = false
    @State private var uploadNote = ""
    private let ticker = Timer.publish(every:1,on:.main,in:.common).autoconnect()
    private var remaining: Int { max(0,Int(ceil((attempt?.deadline ?? now)-now))) }
    private var question: ExamQuestion? {
        guard let a = attempt, a.questions.indices.contains(chosen) else { return nil }; return a.questions[chosen]
    }
    var body: some View {
        Page {
            Text(exam.title).font(.title.bold())
            if let a = attempt {
                if a.submitted {
                    Text("Testi u dorëzua").font(.title2.bold())
                    if let score = a.score { Text("\(score)/\(a.maximum) pikë · Mësuesi mund të japë pikë shtesë për arsyetimin.") }
                    else { Text("Statusi: " + (a.status ?? "në korrigjim") + ". Rezultati shfaqet pasi mësuesi ta publikojë.") }
                    Text("Dorëzimi dhe afati janë ruajtur në shërbimin e shkollës.")
                } else if let q = question {
                    Label(String(format:"%02d:%02d",remaining/60,remaining%60),systemImage:"timer").font(.title.monospacedDigit()).foregroundStyle(remaining<60 ? Color.red : Color.lagoon)
                    Text("Koha vazhdon edhe nëse del nga aplikacioni. Në afat dorëzohen përgjigjet që kanë mbërritur në shërbim.").font(.caption)
                    Text("Pyetja \(chosen+1)/\(a.questions.count) · \(q.points) pikë").bold()
                    Text(q.prompt).font(.title2)
                    Text(q.precision).font(.footnote)
                    if q.kind == "choice" {
                        ForEach(q.options ?? [],id:\.self) { option in
                            Button { value = option } label: { Label(option,systemImage:value == option ? "largecircle.fill.circle" : "circle") }.disabled(busy || expired)
                        }
                    } else if q.kind != "open" {
                        TextField("Përgjigjja " + q.unit,text:$value).textFieldStyle(.roundedBorder).disabled(busy || expired)
                    }
                    Text("Shkruaj arsyetimin për pikë të pjesshme:").font(.headline)
                    TextEditor(text:$reasoning).frame(minHeight:120).border(Color.gray.opacity(0.3)).disabled(busy || expired)
                    Text(dirty ? (busy ? "Në pritje për dërgim…" : "U ruajt në pajisje · dërgohet automatikisht") : "U dërgua në shërbimin e shkollës").font(.caption)
                    if SupabaseConfig.enabled {
                        SubmissionFilesView(files: (a.files ?? []).filter { $0.question == q.id }, editable: !expired && !busy,
                                            onAdd: { importing = true }, onRemove: { file in Task { await removeFile(file) } })
                        if !uploadNote.isEmpty { Text(uploadNote).font(.caption) }
                    }
                    HStack {
                        Button("Ruaj përgjigjen") { Task { await save() } }
                        if chosen>0 { Button("Mbrapa") { Task { if await save() { chosen -= 1; loadAnswer() } } } }
                        if chosen+1<a.questions.count { Button("Tjetra") { Task { if await save() { chosen += 1; loadAnswer() } } } }
                    }.disabled(busy || expired)
                    Button("Dorëzo testin") { confirm = true }.buttonStyle(.borderedProminent).disabled(busy || expired)
                }
            } else {
                Text("\(exam.minutes) minuta · \(exam.count) pyetje. Koha nis kur shtyp butonin.")
                Button("Fillo ose vazhdo testin") { Task { await start() } }.buttonStyle(.borderedProminent).disabled(busy)
            }
            if busy { ProgressView() }
            if !message.isEmpty { Text(message).foregroundStyle(Color.red) }
            if expired && attempt?.submitted != true { Text("Koha mbaroi. Përgjigjet janë bllokuar. Po kërkohet konfirmimi i dorëzimit."); Button("Kontrollo dorëzimin") { Task { await refresh() } } }
        }.navigationBarBackButtonHidden(busy)
        .onChange(of:value) { _ in stash() }.onChange(of:reasoning) { _ in stash() }
        .onReceive(ticker) { _ in
            guard let a = attempt, !a.submitted else { return }
            now = receivedServer + ProcessInfo.processInfo.systemUptime - receivedUptime
            if now >= a.deadline && !expired { expired = true; Task { await refresh() } }
        }
        .onChange(of:scenePhase) { phase in if phase == .active && attempt != nil { Task { await refresh() } } }
        .task(id:value + "\u{1F}" + reasoning) {
            guard dirty, !expired else { return }
            do { try await Task.sleep(nanoseconds:900_000_000) } catch { return }
            _ = await save()
        }
        .fileImporter(isPresented:$importing, allowedContentTypes:Self.fileTypes, allowsMultipleSelection:false) { result in Task { await upload(result) } }
        .alert("Ta dorëzosh testin?",isPresented:$confirm) {
            Button("Anulo",role:.cancel) {}
            Button("Dorëzo") { Task { if await save(), let a = attempt { await request("finish",body:["attemptID":a.id]) } } }
        }
        .disabled(expired && attempt?.submitted == false && busy)
    }
    private func adopt(_ a: RemoteAttempt) {
        attempt = a; receivedUptime = ProcessInfo.processInfo.systemUptime; receivedServer = a.serverNow; now = a.serverNow; expired = a.submitted || a.serverNow>=a.deadline
    }
    private func start() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { let a: RemoteAttempt = try await SchoolAPI.call("examStart",body:["examID":exam.id],token:account.token); adopt(a); loadAnswer() }
        catch { message = error.localizedDescription }
    }
    private func request(_ action: String, body: [String:Any]) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { let a: RemoteAttempt = try await SchoolAPI.call(action,body:body,token:account.token); adopt(a); message = "" }
        catch { message = error.localizedDescription }
    }
    private func refresh() async { if let a = attempt { await request("attempt",body:["attemptID":a.id]) } }
    private func reload(_ a: RemoteAttempt) async throws {
        let fresh: RemoteAttempt = try await SchoolAPI.call("attempt",body:["attemptID":a.id],token:account.token); adopt(fresh)
    }
    private func upload(_ result: Result<[URL], Error>) async {
        guard !busy, !expired, let a = attempt, let q = question else { return }
        let url: URL
        switch result {
        case .failure(let error): message = error.localizedDescription; return
        case .success(let urls): guard let first = urls.first else { return }; url = first
        }
        guard (a.files?.count ?? 0) < AttachmentFile.maxPerAttempt else { message = "Ke arritur kufirin prej 10 skedarësh për këtë test."; return }
        busy = true; defer { busy = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= AttachmentFile.maxBytes else { throw AuthFailure(message: "Skedari është më i madh se 25 MB. Zvogëloje ose ndaje.") }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let path = a.id.lowercased() + "/" + q.id.lowercased() + "/" + AttachmentFile.prefix() + "-" + AttachmentFile.safeName(url.lastPathComponent)
            uploadNote = "Në pritje për dërgim: " + url.lastPathComponent
            try await SupabaseAuth.shared.uploadSubmission(path: path, data: data, mime: mime)
            uploadNote = "U dërgua: " + url.lastPathComponent
            message = ""
            try await reload(a)
        } catch { uploadNote = ""; message = "Skedari nuk u dërgua: " + error.localizedDescription }
    }
    private func removeFile(_ file: AttachmentFile) async {
        guard !busy, !expired, let a = attempt else { return }
        busy = true; defer { busy = false }
        do { try await SupabaseAuth.shared.deleteSubmission(path: file.path); uploadNote = "U hoq: " + file.name; try await reload(a) }
        catch { message = error.localizedDescription }
    }
    private func draftKey(_ q: ExamQuestion) -> String { "examDraft.v7." + (attempt?.id ?? "") + "." + q.id }
    private func loadAnswer() {
        guard let q = question else { return }
        var a = attempt?.answers[q.id] ?? ExamAnswer(value:"",reasoning:"")
        if let bytes = account.storage.data(forKey:draftKey(q)), let draft = try? JSONDecoder().decode(ExamAnswer.self,from:bytes) { a = draft }
        value = a.value; reasoning = a.reasoning; dirty = attempt?.answers[q.id]?.value != value || attempt?.answers[q.id]?.reasoning != reasoning
    }
    private func stash() {
        guard let q = question, attempt?.submitted == false else { return }
        dirty = true
        if let data = try? JSONEncoder().encode(ExamAnswer(value:value,reasoning:reasoning)) { account.storage.set(data,forKey:draftKey(q)) }
    }
    @discardableResult private func save() async -> Bool {
        guard !busy, !expired, let a = attempt, let q = question else { return false }
        busy = true; defer { busy = false }
        let sentValue = value, sentReasoning = reasoning
        do {
            let reply: RemoteAttempt = try await SchoolAPI.call("answer",body:["attemptID":a.id,"questionID":q.id,"value":sentValue,"reasoning":sentReasoning],token:account.token)
            adopt(reply)
            guard !reply.submitted else { message = "Afati mbaroi; shërbimi nuk pranoi përgjigje të reja."; return false }
            if sentValue == value && sentReasoning == reasoning { dirty = false; account.storage.removeObject(forKey:draftKey(q)) }
            message = ""; return true
        } catch { message = "Përgjigjja mbetet në këtë pajisje; dërgimi dështoi: " + error.localizedDescription; return false }
    }
}

struct ExamReview: View {
    let attempt: RemoteAttempt
    @EnvironmentObject private var account: Account
    @Environment(\.openURL) private var openURL
    @State private var scores: [String:Int] = [:]
    @State private var notes: [String:String] = [:]
    @State private var message = ""
    @State private var busy = false
    var body: some View {
        Page {
            Text(attempt.title).font(.title.bold())
            Text(attempt.student ?? "")
            Text("Kontrollo hapat e nxënësit. Pikët e vendosura këtu zëvendësojnë vlerësimin automatik për pyetjen; nuk i shtohen atij.")
            ForEach(attempt.reviewQuestions ?? []) { q in
                GroupBox {
                    VStack(alignment:.leading,spacing:12) {
                        Text(q.prompt).font(.headline)
                        Text("Përgjigjja e nxënësit: " + (attempt.answers[q.id]?.value ?? "Pa përgjigje"))
                        Text("Arsyetimi: " + (attempt.answers[q.id]?.reasoning ?? ""))
                        if SupabaseConfig.enabled {
                            SubmissionFilesView(files: (attempt.files ?? []).filter { $0.question == q.id }, editable: false,
                                                onOpen: { file in Task { await open(file) } })
                        }
                        SectionText(heading:"Çelësi",text:(q.answer ?? "") + " " + q.unit + "\n" + (q.explanation ?? ""))
                        Picker("Pikët pas shqyrtimit",selection:Binding(get:{ scores[q.id] ?? -1 },set:{ scores[q.id]=$0 })) {
                            Text("Zgjidh pikët").tag(-1)
                            ForEach(0...q.points,id:\.self) { Text("\($0)/\(q.points)").tag($0) }
                        }
                        TextField("Komenti për nxënësin",text:Binding(get:{notes[q.id] ?? ""},set:{notes[q.id]=$0}),axis:.vertical)
                        Button("Ruaj vlerësimin") { Task { await save(q) } }.disabled(scores[q.id] == nil || scores[q.id] == -1 || busy)
                    }.padding(8)
                }
            }
            if SupabaseConfig.enabled {
                Text("Statusi: " + (attempt.status ?? "") + (attempt.preliminary.map { " · pikë automatike paraprake: \($0)" } ?? "")).font(.footnote)
                Button("Publiko rezultatin te nxënësi dhe prindi") { Task { await publishResults() } }.buttonStyle(.borderedProminent).disabled(busy)
            }
            Text(message)
        }.textFieldStyle(.roundedBorder).onAppear { scores = attempt.grades ?? [:]; notes = attempt.feedback }
    }
    private func open(_ file: AttachmentFile) async {
        do { openURL(try await SupabaseAuth.shared.signedSubmissionURL(path: file.path)) }
        catch { message = error.localizedDescription }
    }
    private func publishResults() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { let _: OKReply = try await SchoolAPI.call("publishResults",body:["attemptID":attempt.id],token:account.token); message = "Rezultati u publikua te nxënësi dhe prindi." }
        catch { message = error.localizedDescription }
    }
    private func save(_ q: ExamQuestion) async {
        guard !busy, let points = scores[q.id] else { return }; busy = true; defer { busy = false }
        do { let _: OKReply = try await SchoolAPI.call("grade",body:["attemptID":attempt.id,"questionID":q.id,"points":points,"feedback":notes[q.id] ?? ""],token:account.token); message = "Vlerësimi u ruajt dhe i shfaqet nxënësit e prindit të lidhur." }
        catch { message = error.localizedDescription }
    }
}

private struct DayMark { var count = 0; var hasExam = false }

/// Kalendar mujor interaktiv: ditët me evente kanë pika (portokalli = test), prek një ditë për ta zgjedhur.
private struct MonthGrid: View {
    @Binding var selected: Date
    let marks: [Date: DayMark]
    @State private var month = Date()
    private var cal: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }
    private let names = ["H", "M", "M", "E", "P", "S", "D"]
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Muaji i mëparshëm")
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "sq")))).font(.headline)
                Spacer()
                Button("Sot") { month = Date(); selected = Date() }
                Button { shift(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Muaji tjetër")
            }.buttonStyle(.borderless)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(0..<7, id: \.self) { index in Text(names[index]).font(.caption.bold()).foregroundStyle(.secondary) }
                ForEach(Array(cells().enumerated()), id: \.offset) { _, cell in
                    if let date = cell { dayCell(date) } else { Color.clear.frame(height: 44) }
                }
            }
        }
        .padding().background(.white, in: RoundedRectangle(cornerRadius: 12))
        .onAppear { month = selected }
        .onChange(of: selected) { value in if !cal.isDate(value, equalTo: month, toGranularity: .month) { month = value } }
    }
    private func dayCell(_ date: Date) -> some View {
        let isSelected = cal.isDate(date, inSameDayAs: selected)
        let isToday = cal.isDateInToday(date)
        let mark = marks[cal.startOfDay(for: date)]
        let dot = (mark?.hasExam ?? false) ? Color.orange : (isSelected ? Color.white : Color.lagoon)
        return Button { selected = date } label: {
            VStack(spacing: 3) {
                Text("\(cal.component(.day, from: date))")
                    .font(.body.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                HStack(spacing: 2) {
                    ForEach(0..<min(mark?.count ?? 0, 3), id: \.self) { _ in Circle().fill(dot).frame(width: 6, height: 6) }
                }.frame(height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 10).fill(isSelected ? Color.lagoon : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isToday && !isSelected ? Color.lagoon : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "sq"))) + ((mark?.count ?? 0) > 0 ? ", \(mark?.count ?? 0) evente" : ""))
    }
    private func cells() -> [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: month), let days = cal.range(of: .day, in: .month, for: month) else { return [] }
        let lead = (cal.component(.weekday, from: interval.start) - cal.firstWeekday + 7) % 7
        var result: [Date?] = Array(repeating: nil, count: lead)
        for offset in 0..<days.count { result.append(cal.date(byAdding: .day, value: offset, to: interval.start)) }
        return result
    }
    private func shift(_ delta: Int) { if let next = cal.date(byAdding: .month, value: delta, to: month) { month = next } }
}

struct SharedSchoolCalendar: View {
    @EnvironmentObject private var account: Account
    @StateObject private var model = SchoolModel()
    @State private var day = Date()
    @State private var date = Date()
    @State private var title = ""
    @State private var note = ""
    @State private var group = ""
    @State private var examLink = ""
    @State private var mode = CalendarMode.month
    @State private var classFilter = ""
    @State private var adding = false

    private enum CalendarMode: String, CaseIterable, Identifiable {
        case month = "Muaji", upcoming = "Të ardhshmet"
        var id: String { rawValue }
    }
    private var visibleEvents: [RemoteEvent] {
        model.data.events.filter { classFilter.isEmpty || $0.classID == classFilter }.sorted { $0.date < $1.date }
    }
    private var marks: [Date: DayMark] {
        var result: [Date: DayMark] = [:]
        let cal = Calendar.current
        for event in visibleEvents {
            let key = cal.startOfDay(for: Date(timeIntervalSince1970: event.date))
            var mark = result[key] ?? DayMark()
            mark.count += 1
            if let linked = event.examID, !linked.isEmpty { mark.hasExam = true }
            result[key] = mark
        }
        return result
    }
    var body: some View {
        Page {
            Text("Kalendari i klasave").font(.largeTitle.bold())
            Picker("Pamja", selection: $mode) { ForEach(CalendarMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            if model.data.classes.count > 1 {
                Picker("Klasa", selection: $classFilter) {
                    Text("Të gjitha klasat").tag("")
                    ForEach(model.data.classes) { Text($0.name).tag($0.id) }
                }
            }
            if mode == .month { monthView } else { upcomingView }
            if account.role == .teacher { composer }
            if !model.message.isEmpty { Text(model.message).font(.footnote) }
            Button("Përditëso kalendarin") { Task { await model.refresh(account.token) } }
        }
        .textFieldStyle(.roundedBorder)
        .task { await model.refresh(account.token) }
        .onChange(of: day) { _ in date = merged(day: day, time: date) }
    }
    @ViewBuilder private var monthView: some View {
        MonthGrid(selected: $day, marks: marks)
        let daily = visibleEvents.filter { Calendar.current.isDate(Date(timeIntervalSince1970: $0.date), inSameDayAs: day) }
        HStack {
            Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(Locale(identifier: "sq")))).font(.headline)
            Spacer()
            if account.role == .teacher { Button("Shto këtu") { date = merged(day: day, time: date); adding = true } }
        }
        if daily.isEmpty { Text("Nuk ka evente në këtë datë.").foregroundStyle(.secondary) }
        ForEach(daily) { event in eventRow(event) }
    }
    @ViewBuilder private var upcomingView: some View {
        let start = Calendar.current.startOfDay(for: Date())
        let coming = visibleEvents.filter { Date(timeIntervalSince1970: $0.date) >= start }
        if coming.isEmpty { Text("Nuk ka evente të ardhshme.").foregroundStyle(.secondary) }
        ForEach(coming) { event in eventRow(event) }
    }
    @ViewBuilder private var composer: some View {
        DisclosureGroup("Shto event ose test në kalendar", isExpanded: $adding) {
            Picker("Klasa", selection: $group) {
                Text("Zgjidh klasën").tag("")
                ForEach(model.data.classes.filter { !$0.code.isEmpty }) { Text($0.name).tag($0.id) }
            }
            if SupabaseConfig.enabled {
                Picker("Testi i lidhur", selection: $examLink) {
                    Text("Pa test").tag("")
                    ForEach(model.data.tests.filter { $0.classID == group }) { Text($0.title).tag($0.id) }
                }
            }
            TextField("P.sh. Testi i biologjisë", text: $title)
            TextField("Shënim", text: $note, axis: .vertical)
            DatePicker("Data dhe ora", selection: $date)
            Button("Publiko eventin") {
                Task {
                    await model.change("eventCreate", ["classID": group, "title": title, "note": note, "date": date.timeIntervalSince1970, "examID": examLink, "subject": model.data.tests.first(where: { $0.id == examLink })?.subject ?? ""], token: account.token)
                    if model.message.isEmpty { day = date; title = ""; note = ""; adding = false }
                }
            }.disabled(group.isEmpty || title.isEmpty || model.busy)
        }
    }
    private func merged(day: Date, time: Date) -> Date {
        let cal = Calendar.current
        var parts = cal.dateComponents([.year, .month, .day], from: day)
        let clock = cal.dateComponents([.hour, .minute], from: time)
        parts.hour = clock.hour; parts.minute = clock.minute
        return cal.date(from: parts) ?? day
    }
    private func relative(_ date: Date) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return "sot"
        case 1: return "nesër"
        case -1: return "dje"
        case let n where n > 1: return "pas \(n) ditësh"
        default: return "para \(-days) ditësh"
        }
    }
    private func eventRow(_ event: RemoteEvent) -> some View {
        let when = Date(timeIntervalSince1970: event.date)
        let isExam = !(event.examID ?? "").isEmpty
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: isExam ? "checkmark.seal.fill" : "calendar").foregroundStyle(isExam ? Color.orange : Color.lagoon)
                Text(event.title).font(.title3.bold())
            }
            let className: String = model.data.classes.first(where: { $0.id == event.classID })?.name ?? ""
            let dateStyle: Date.FormatStyle.DateStyle = mode == .upcoming ? .abbreviated : .omitted
            let timeText: String = when.formatted(date: dateStyle, time: .shortened)
            Text(className + " · " + timeText + " · " + relative(when)).font(.subheadline)
            if !event.note.isEmpty { Text(event.note) }
            if let linked = event.examID, let exam = model.data.tests.first(where: { $0.id == linked }) { Text("Lidhur me testin: " + exam.title).font(.caption) }
            if let subject = event.subject, !subject.isEmpty { Text(subject).font(.caption) }
            if mode == .upcoming { Button("Shiko në kalendar") { day = when; mode = .month }.buttonStyle(.borderless) }
            if event.owner == account.identity.replacingOccurrences(of: "school-", with: "") {
                if SupabaseConfig.enabled {
                    EventEditor(event: event) { newTitle, newNote, newDate in
                        Task { await model.change("eventUpdate", ["eventID": event.id, "title": newTitle, "note": newNote, "date": newDate.timeIntervalSince1970], token: account.token) }
                    }
                }
                Button("Anulo eventin", role: .destructive) { Task { await model.change("eventDelete", ["eventID": event.id], token: account.token) } }
            }
        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct EventEditor: View {
    let event: RemoteEvent
    let save: (String, String, Date) -> Void
    @State private var title = ""
    @State private var note = ""
    @State private var date = Date()
    var body: some View {
        DisclosureGroup("Ndrysho eventin") {
            TextField("Titulli",text:$title)
            TextField("Shënim",text:$note,axis:.vertical)
            DatePicker("Data dhe ora",selection:$date)
            Button("Ruaj ndryshimet") { save(title,note,date) }.disabled(title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
        }.onAppear { title = event.title; note = event.note; date = Date(timeIntervalSince1970:event.date) }
    }
}
