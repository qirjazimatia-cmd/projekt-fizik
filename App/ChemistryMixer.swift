import SwiftUI

private enum MixingLiquid: String, CaseIterable {
    case water = "Ujë", vinegar = "Uthull", oil = "Vaj"
}
private enum MixingAddition: String, CaseIterable {
    case salt = "Kripë", sugar = "Sheqer", soda = "Sodë buke", oil = "Vaj"
}
private struct MixingRecord: Codable, Identifiable {
    var id = UUID()
    let liquid, addition, result: String
}

struct ChemistryMixer: View {
    @State private var liquid = MixingLiquid.water
    @State private var addition = MixingAddition.salt
    @State private var mixed = false
    @State private var began = Date()
    @State private var prediction = ""
    @State private var notice = ""
    @AppStorage("chemMixHistory") private var history = Data()
    // Tërhiq shtesën në gotë dhe tunde gotën.
    @State private var jarOffset: CGSize = .zero
    @State private var pouring = false
    @State private var tilt: Double = 0
    @State private var glassFrame: CGRect = .zero
    private var fizz: Bool { liquid == .vinegar && addition == .soda }
    private var layers: Bool { liquid != .oil && addition == .oil }
    private var residue: Bool { liquid == .oil && addition != .oil }
    private var result: String {
        if fizz { return "Formohen flluska CO₂. Acidi acetik reagon me hidrogjenkarbonatin e natriumit, duke formuar acetat natriumi, ujë dhe dioksid karboni." }
        if layers { return "Formohen dy shtresa. Vaji dhe faza ujore përzihen përkohësisht gjatë tundjes dhe më pas ndahen. Vaji qëndron sipër sepse ka dendësi më të vogël." }
        if residue { return "Lënda e ngurtë mbetet kryesisht e patretur në vaj. Tundja e shpërndan përkohësisht, por grimcat vendosen sërish në fund." }
        if addition == .oil { return "Vaji bashkohet me vajin. Në gotë shfaqet një fazë e vetme." }
        return "Sasia e vogël e " + addition.rawValue.lowercased() + " tretet në fazën ujore. Formohet tretësirë. Në këtë provë nuk vëzhgohet çlirim gazi."
    }
    private var records: [MixingRecord] {
        (try? JSONDecoder().decode([MixingRecord].self, from: history)) ?? []
    }
    var body: some View {
        Page {
            Text("🧪 Tavolina e përzierjeve").font(.largeTitle.bold())
            Text("Zgjidh një lëng dhe një shtesë. Parashiko rezultatin, përzieji dhe krahaso vëzhgimin.")
            VStack(alignment: .leading, spacing: 12) {
                Picker("Lëngu bazë · 100 mL", selection: $liquid) {
                    ForEach(MixingLiquid.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("Shtesa · 1 g, ose 10 mL vaj", selection: $addition) {
                    ForEach(MixingAddition.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                TextField("Çfarë mendon se do të ndodhë?", text: $prediction, axis: .vertical).textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 12) {
                Text(emoji(addition)).font(.system(size: 44))
                    .padding(10).glassCapsule(tint: .orange, interactive: true)
                    .scaleEffect(jarOffset == .zero ? 1 : 1.15)
                    .rotationEffect(.degrees(jarOffset == .zero ? 0 : -30))
                    .offset(jarOffset)
                    .zIndex(2)
                    .gesture(DragGesture(coordinateSpace: .named("mixer"))
                        .onChanged { value in jarOffset = value.translation }
                        .onEnded { value in
                            if glassFrame.insetBy(dx: -30, dy: -30).contains(value.location) { pour() }
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { jarOffset = .zero }
                        })
                    .accessibilityLabel("Hidh " + addition.rawValue.lowercased() + " në gotë")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { pour() }
                VStack(alignment: .leading, spacing: 2) {
                    Text(mixed ? "Tunde gotën majtas–djathtas" : "Tërhiq " + addition.rawValue.lowercased() + " në gotë").font(.headline)
                    Text(mixed ? "Shiko si ndryshojnë fazat" : "Lëshoje sipër gotës për ta hedhur").font(.caption).foregroundStyle(.secondary)
                }
            }
            .zIndex(2)
            TimelineView(.animation(minimumInterval: 0.03, paused: !(mixed || pouring))) { context in
                let elapsed = max(0, context.date.timeIntervalSince(began))
                Canvas { drawing, size in
                    let glass = CGRect(x: size.width * 0.25, y: 25, width: size.width * 0.5, height: 175)
                    let fluid = CGRect(x: glass.minX+4, y: 65, width: glass.width-8, height: 130)
                    let color: Color = liquid == .oil ? .yellow.opacity(0.75) : .cyan.opacity(0.5)
                    drawing.fill(Path(roundedRect: fluid, cornerRadius: 8), with: .color(color))
                    var rim = Path()
                    rim.move(to: CGPoint(x: glass.minX,y: 25))
                    rim.addLine(to: CGPoint(x: glass.minX,y: 200))
                    rim.addLine(to: CGPoint(x: glass.maxX,y: 200))
                    rim.addLine(to: CGPoint(x: glass.maxX,y: 25))
                    drawing.stroke(rim,with: .color(.white),lineWidth: 3)
                    if mixed && layers {
                        drawing.fill(Path(CGRect(x: fluid.minX,y: fluid.minY,width: fluid.width,height: 28)),with: .color(.yellow))
                    }
                    if mixed && fizz && elapsed < 12 {
                        for i in 0..<18 {
                            let phase = (Double(i)/18+elapsed/3).truncatingRemainder(dividingBy: 1)
                            let x = fluid.minX + 8 + Double((i*19)%83)/83*(fluid.width-16)
                            let y = fluid.maxY-phase*130
                            drawing.stroke(Path(ellipseIn: CGRect(x: x,y: y,width: 8,height: 8)),with: .color(.white),lineWidth: 2)
                        }
                    }
                    if mixed && (residue || (!layers && !fizz && addition != .oil)) {
                        let opacity = residue ? 1 : max(0,1-elapsed/4)
                        for i in 0..<24 {
                            let x = fluid.minX+6+Double((i*13)%97)/97*(fluid.width-12)
                            let y = residue ? 182+Double(i%3)*4 : 100+Double((i*11)%90)
                            drawing.fill(Path(ellipseIn: CGRect(x:x,y:y,width:4,height:4)),with:.color(.white.opacity(opacity)))
                        }
                    }
                    // Kokrrat/pikat që bien nga lart kur hedh shtesën.
                    if pouring {
                        for i in 0..<26 {
                            let phase = (Double(i) / 26 + elapsed * 1.6).truncatingRemainder(dividingBy: 1)
                            let x = size.width / 2 + sin(Double(i) * 2.1) * 14
                            let y = 6 + phase * 70
                            let dot = CGRect(x: x, y: y, width: addition == .oil ? 7 : 5, height: addition == .oil ? 9 : 5)
                            drawing.fill(Path(ellipseIn: dot), with: .color(addition == .oil ? .yellow : .white))
                        }
                    }
                    // Valëzimi i lëngut kur tundet gota.
                    if mixed && elapsed < 3 {
                        var wave = Path()
                        wave.move(to: CGPoint(x: fluid.minX, y: fluid.minY))
                        for step in 0...20 {
                            let x = fluid.minX + Double(step) / 20 * fluid.width
                            wave.addLine(to: CGPoint(x: x, y: fluid.minY + sin(Double(step) * 0.9 + elapsed * 9) * 6 * (1 - elapsed / 3)))
                        }
                        drawing.stroke(wave, with: .color(.white.opacity(0.7)), lineWidth: 2)
                    }
                    drawing.draw(Text(pouring ? "Po hidhet…" : mixed ? (fizz ? "CO₂ ↑" : "Vëzhgo fazat") : "Gati për provën").font(.headline).foregroundColor(.white),
                                 at:CGPoint(x:size.width/2,y:220))
                }
            }
            .frame(height: 240)
            .background {
                ZStack {
                    LinearGradient(colors: [Color.midnight, Subject.chemistry.deep], startPoint: .top, endPoint: .bottom)
                    RadialGradient(colors: [Subject.chemistry.color.opacity(fizz && mixed ? 0.6 : 0.3), .clear], center: .center, startRadius: 5, endRadius: 200)
                }.clipShape(RoundedRectangle(cornerRadius: 24))
            }
            .rotationEffect(.degrees(tilt), anchor: .bottom)
            .background(GeometryReader { geo in Color.clear.onAppear { glassFrame = geo.frame(in: .named("mixer")) }
                .onChange(of: geo.frame(in: .named("mixer"))) { glassFrame = $0 } })
            .gesture(DragGesture(minimumDistance: 8).onChanged { value in
                guard mixed else { return }
                let newTilt = max(-12, min(12, value.translation.width / 8))
                if abs(newTilt - tilt) > 3 { Haptics.selection(); began = Date() }
                tilt = newTilt
            }.onEnded { _ in withAnimation(.spring(response: 0.4, dampingFraction: 0.35)) { tilt = 0 } })
            .shadow(color: Subject.chemistry.color.opacity(0.35), radius: 14, y: 8)
            HStack {
                Button("Përzieji pa tërhequr") { pour() }.buttonStyle(.bordered).disabled(mixed || pouring)
                Button("Zbraz gotën") { withAnimation { reset() } }
            }
            if mixed {
                AnswerBanner(correct: true, heading: fizz ? "Reaksion kimik! 🫧" : "Vëzhgimi", text: result)
                if !prediction.isEmpty { Text("Parashikimi yt · " + prediction) }
                Button("Ruaj provën") {
                    guard var all = NotebookCodec.load(MixingRecord.self, from: history) else { notice = NotebookCodec.blockedMessage; return }
                    all.insert(MixingRecord(liquid:liquid.rawValue,addition:addition.rawValue,result:result),at:0)
                    history = (try? JSONEncoder().encode(Array(all.prefix(50)))) ?? history
                    notice = "Prova u ruajt."
                }
            }
            Text("Simulim cilësor në temperaturë dhome. Shpejtësia e flluskave dhe e tretjes është ilustruese.").font(.footnote)
            DisclosureGroup("Provat e mia · \(records.count)") {
                ForEach(records) { row in
                    SectionText(heading: row.liquid + " + " + row.addition, text: row.result)
                }
            }
            if !notice.isEmpty { Text(notice) }
        }.navigationTitle("Përzierje të lira")
        .coordinateSpace(name: "mixer")
        .subjectStyle(.chemistry)
        .onChange(of: liquid) { _ in reset() }
        .onChange(of: addition) { _ in reset() }
    }
    private func reset() { mixed = false; pouring = false; prediction = ""; notice = ""; tilt = 0 }
    private func pour() {
        guard !mixed, !pouring else { return }
        Haptics.tap()
        began = Date(); pouring = true; notice = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            pouring = false
            began = Date()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { mixed = true }
            if fizz { Haptics.celebrate() } else { Haptics.success() }
        }
    }
    private func emoji(_ item: MixingAddition) -> String {
        switch item {
        case .salt: return "🧂"
        case .sugar: return "🍬"
        case .soda: return "🥄"
        case .oil: return "🫒"
        }
    }
}
