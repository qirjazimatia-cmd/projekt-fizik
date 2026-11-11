import SwiftUI
import UserNotifications

/// Orari i klasës: mësuesi e krijon, nxënësit dhe prindërit e shohin; mësuesi merr njoftim para çdo ore.
@MainActor
final class ScheduleModel: ObservableObject {
    @Published var slots: [ScheduleSlot] = []
    @Published var message = ""
    @Published var busy = false

    func load() async {
        do { let reply: ScheduleReply = try await SchoolAPI.call("scheduleGet"); slots = reply.slots; message = "" }
        catch { message = error.localizedDescription }
        await ScheduleReminders.sync(slots)
    }
    func create(_ body: [String: Any]) async -> Bool {
        busy = true; defer { busy = false }
        do {
            let reply: OKReply = try await SchoolAPI.call("scheduleCreate", body: body)
            guard reply.ok == true else { message = "Ora nuk u ruajt."; return false }
            await load(); return true
        } catch { message = error.localizedDescription; return false }
    }
    func delete(_ slot: ScheduleSlot) async {
        do { let _: OKReply = try await SchoolAPI.call("scheduleDelete", body: ["slotID": slot.id]); await load() }
        catch { message = error.localizedDescription }
    }
}

/// Njoftime javore (përsëriten çdo javë) para orëve të mësuesit, ose të nxënësit nëse e aktivizon.
@MainActor
enum ScheduleReminders {
    static let minutesKey = "schedule.reminderMinutes.v1"
    static let prefix = "brainspark.orari."
    static var minutesBefore: Int { UserDefaults.standard.object(forKey: minutesKey) as? Int ?? 10 }

    static func sync(_ slots: [ScheduleSlot]) async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        let before = minutesBefore
        let chosen = slots.filter { $0.mine || UserDefaults.standard.bool(forKey: "schedule.studentReminders.v1") }
        guard before > 0, !chosen.isEmpty else { return }
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            guard (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true else { return }
        } else if settings.authorizationStatus == .denied { return }
        for slot in chosen.prefix(40) {
            let time = ScheduleWeek.reminderTime(slot, minutesBefore: before)
            let content = UNMutableNotificationContent()
            content.title = slot.mine ? "Mësim pas \(before) min" : "Ora e radhës pas \(before) min"
            content.body = slot.subject + " · " + slot.className + (slot.room.isEmpty ? "" : " · salla " + slot.room) + " · " + slot.starts + "–" + slot.ends
            content.threadIdentifier = "brainspark.orari"
            content.relevanceScore = 0.9
            content.sound = .default
            var parts = DateComponents(); parts.weekday = time.weekday; parts.hour = time.hour; parts.minute = time.minute
            let request = UNNotificationRequest(identifier: prefix + slot.id, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: true))
            try? await center.add(request)
        }
    }
}

struct ClassScheduleView: View {
    let classes: [SchoolClass]
    let canEdit: Bool
    @StateObject private var model = ScheduleModel()
    @AppStorage(ScheduleReminders.minutesKey, store: .standard) private var minutesBefore = 10
    @AppStorage("schedule.studentReminders.v1", store: .standard) private var studentReminders = false
    @State private var classID = ""
    @State private var weekday = 1
    @State private var start = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var end = Calendar.current.date(bySettingHour: 8, minute: 45, second: 0, of: Date()) ?? Date()
    @State private var subject = ""
    @State private var room = ""
    @State private var toDelete: ScheduleSlot?

    var body: some View {
        Page {
            Text("Orari i klasës").font(.largeTitle.bold())
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let status = ScheduleWeek.now(model.slots, at: context.date)
                if let current = status.current {
                    Label("Tani: " + current.subject + " · " + current.className + " (deri " + current.ends + ")", systemImage: "dot.radiowaves.left.and.right")
                        .font(.headline).foregroundStyle(Color.lagoon)
                } else if let next = status.next {
                    Label("Ora e radhës sot: " + next.subject + " · " + next.className + " në " + next.starts, systemImage: "clock")
                        .font(.headline)
                }
            }
            if model.slots.isEmpty {
                Text(canEdit ? "Shto orët e klasave të tua më poshtë. Nxënësit dhe prindërit i shohin menjëherë." : "Mësuesi nuk ka vendosur ende orarin e klasës.")
                    .foregroundStyle(.secondary)
            }
            ForEach(1...7, id: \.self) { day in
                let items = model.slots.filter { $0.weekday == day }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(ScheduleWeek.dayNames[day - 1]).font(.headline)
                        ForEach(items) { slot in
                            HStack(alignment: .top) {
                                Text(slot.starts + "\n" + slot.ends).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 46, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(slot.subject).font(.body.bold())
                                    Text(slot.className + (slot.room.isEmpty ? "" : " · salla " + slot.room)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if canEdit && slot.mine {
                                    Button { toDelete = slot } label: { Image(systemName: "trash") }
                                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Fshi orën")
                                }
                            }
                            .padding(10)
                            .background(Color.lagoon.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
            if canEdit { editor }
            reminderSettings
            if !model.message.isEmpty { Text(model.message).foregroundStyle(.red) }
        }
        .navigationTitle("Orari")
        .task { await model.load(); if classID.isEmpty { classID = classes.first?.id ?? "" } }
        .refreshable { await model.load() }
        .confirmationDialog("Ta fshij këtë orë?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
            Button("Fshi", role: .destructive) { if let slot = toDelete { Task { await model.delete(slot) } }; toDelete = nil }
            Button("Anulo", role: .cancel) { toDelete = nil }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shto një orë").font(.title3.bold())
            if classes.isEmpty {
                Text("Krijo fillimisht një klasë te «Shkolla ime».").font(.footnote)
            } else {
                Picker("Klasa", selection: $classID) { ForEach(classes) { Text($0.name).tag($0.id) } }
                Picker("Dita", selection: $weekday) { ForEach(1...7, id: \.self) { Text(ScheduleWeek.dayNames[$0 - 1]).tag($0) } }
                DatePicker("Fillon", selection: $start, displayedComponents: .hourAndMinute)
                DatePicker("Mbaron", selection: $end, displayedComponents: .hourAndMinute)
                TextField("Lënda (p.sh. Fizikë)", text: $subject)
                TextField("Salla (opsionale)", text: $room)
                Button("Shto në orar") {
                    let body: [String: Any] = ["classID": classID, "weekday": weekday, "starts": hhmm(start), "ends": hhmm(end),
                                               "subject": subject.trimmingCharacters(in: .whitespaces), "room": room.trimmingCharacters(in: .whitespaces)]
                    Task { if await model.create(body) { subject = ""; room = "" } }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.busy || classID.isEmpty || subject.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private var reminderSettings: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Njoftimet e orarit").font(.headline)
            Picker("Më njofto", selection: $minutesBefore) {
                Text("Asnjëherë").tag(0); Text("5 min para").tag(5); Text("10 min para").tag(10); Text("15 min para").tag(15); Text("30 min para").tag(30)
            }
            if !canEdit { Toggle("Më njofto edhe mua para orëve të klasës", isOn: $studentReminders) }
            Text(canEdit ? "Merr njoftim para çdo ore që jep, me klasën dhe sallën." : "Njoftimet vijnë çdo javë para orëve të klasës sate.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .onChange(of: minutesBefore) { _ in Task { await ScheduleReminders.sync(model.slots) } }
        .onChange(of: studentReminders) { _ in Task { await ScheduleReminders.sync(model.slots) } }
    }

    private func hhmm(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
