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
            TimelineView(.animation(minimumInterval: 0.05, paused: !mixed)) { context in
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
                    drawing.draw(Text(mixed ? (fizz ? "CO₂ ↑" : "Vëzhgo fazat") : "Gati për provën").font(.headline).foregroundColor(.white),
                                 at:CGPoint(x:size.width/2,y:220))
                }
            }.frame(height: 240).background(Color.midnight,in:RoundedRectangle(cornerRadius:24))
            HStack {
                Button("Përzieji") { mixed = true; began = Date(); notice = "" }.buttonStyle(.borderedProminent)
                Button("Zbraz gotën") { reset() }
            }
            if mixed {
                SectionText(heading: "Vëzhgimi", text: result)
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
        .onChange(of: liquid) { _ in reset() }
        .onChange(of: addition) { _ in reset() }
    }
    private func reset() { mixed = false; prediction = ""; notice = "" }
}
