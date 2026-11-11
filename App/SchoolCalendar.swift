import SwiftUI

// Kalendari i përbashkët i klasës.
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
        .padding().background(Color.card, in: RoundedRectangle(cornerRadius: 12))
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
        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(Color.card, in: RoundedRectangle(cornerRadius: 12))
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
