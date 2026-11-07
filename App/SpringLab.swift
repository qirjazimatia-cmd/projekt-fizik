import SwiftUI

// Ideal springs, positive mass and stiffness; all distances in metres, g = 9.81.
enum SpringMode: String, CaseIterable, Identifiable {
    case hanging = "Masë e varur · Huku"
    case supported = "Masë mbi sustë"
    case horizontal = "Lëkundja horizontale"
    case vertical = "Lëkundja vertikale"
    case drop = "Rënie mbi sustë"
    case ramp = "Rampa dhe susta"
    case coupled = "Dy susta së bashku"
    var id: String { rawValue }
    var dynamic: Bool { ![Self.hanging, .supported, .coupled].contains(self) }
    var explanation: String {
        switch self {
        case .hanging: return "Varje e ngadaltë deri në ekuilibër: kx = mg. x matet nga gjatësia natyrore. Provo ta dyfishosh masën ose konstanten k."
        case .supported: return "Trupi qëndron mbi sustë dhe e shtyp deri në ekuilibër: kx = mg. Modeli përdor sustë ideale që mund të shtypet; dimensionet e vizatimit përshtaten me vlerat."
        case .horizontal: return "Në plan pa fërkim, x = A cos(ωt), ω = √(k/m). EK + Eel = kA²/2. Në mes trupi ka shpejtësinë më të madhe; në skaje ndalet për një çast."
        case .vertical: return "Masa është e lidhur me sustën. Ekuilibri është xₑ = mg/k dhe x = xₑ + A cos(ωt). Energjia elastike përdor x nga gjatësia natyrore. Zero e EPG-së është pika më e ulët e lëkundjes."
        case .drop: return "Trupi lirohet nga qetësia, bie mbi një sustë vertikale dhe kërcen përsëri. Kontakti dhe susta janë ideale, pa humbje. Në shtypjen maksimale: mg(h + x) = kx²/2. Zero e EPG-së është pozicioni i shtypjes maksimale."
        case .ramp: return "Trupi rrëshqet nga qetësia në një rampë 30°, kalon në plan horizontal pa humbje dhe shtyp sustën. Susta e kthen mbrapsht deri në lartësinë fillestare. EPG + EK + Eel = mgh. Lidhja mes rampës dhe planit modelohet ideale."
        case .coupled: return "Në paralel, zgjatja është e njëjtë: kₑ = k₁ + k₂. Në seri, forca është e njëjtë dhe zgjatjet mblidhen: 1/kₑ = 1/k₁ + 1/k₂. Pamja tregon lidhjen; matja numerike jep zgjatjen e saktë."
        }
    }
}
struct SpringSnapshot {
    let displacement, velocity, compression, progress: Double
    let potential, kinetic, elastic, total: Double
    let phase: String
}
struct SpringModel {
    let mode: SpringMode
    var mass: Double
    var stiffness: Double
    var secondStiffness: Double
    var amplitude: Double
    var height: Double
    var parallel: Bool
    let gravity = 9.81
    var omega: Double { sqrt(stiffness / mass) }
    var equilibrium: Double { mass * gravity / stiffness }
    var effective: Double { parallel ? stiffness + secondStiffness : 1 / (1 / stiffness + 1 / secondStiffness) }
    var impactSpeed: Double { sqrt(2 * gravity * height) }
    var dropCompression: Double { equilibrium + sqrt(equilibrium * equilibrium + 2 * mass * gravity * height / stiffness) }
    var contactDuration: Double { (2 * .pi - 2 * atan(impactSpeed / (omega * equilibrium))) / omega }
    var rampDuration: Double { sqrt(8 * height / gravity) }
    var period: Double {
        switch mode {
        case .drop: return 2 * sqrt(2 * height / gravity) + contactDuration
        case .ramp: return 2 * rampDuration + .pi / omega
        default: return 2 * .pi / omega
        }
    }
    func at(_ time: Double) -> SpringSnapshot {
        let t = max(0, time).truncatingRemainder(dividingBy: period)
        var x = 0.0, v = 0.0, compression = 0.0, progress = 0.0, epg = 0.0, eel = 0.0, total = 0.0
        var phase = "Ekuilibër statik"
        switch mode {
        case .hanging, .supported:
            x = equilibrium; compression = x; eel = stiffness * x * x / 2; total = eel
        case .coupled:
            x = mass * gravity / effective; compression = x; eel = effective * x * x / 2; total = eel
        case .horizontal:
            x = amplitude * cos(omega * t); v = -amplitude * omega * sin(omega * t)
            compression = x; eel = stiffness * x * x / 2; total = stiffness * amplitude * amplitude / 2
            phase = "EK ↔ energji elastike"
        case .vertical:
            x = equilibrium + amplitude * cos(omega * t)
            v = -amplitude * omega * sin(omega * t)
            epg = mass * gravity * (equilibrium + amplitude - x)
            eel = stiffness * x * x / 2; compression = x
            total = stiffness * pow(equilibrium + amplitude, 2) / 2
            phase = "EPG ↔ EK ↔ energji elastike"
        case .drop:
            let fall = sqrt(2 * height / gravity)
            if t < fall {
                x = -height + gravity * t * t / 2; v = gravity * t
                phase = "Rënie e lirë · pa kontakt"
            } else if t < fall + contactDuration {
                let u = t - fall
                x = equilibrium * (1 - cos(omega * u)) + impactSpeed / omega * sin(omega * u)
                v = equilibrium * omega * sin(omega * u) + impactSpeed * cos(omega * u)
                phase = v >= 0 ? "Shtypja e sustës" : "Susta e shtyn trupin lart"
            } else {
                let u = t - fall - contactDuration
                x = -impactSpeed * u + gravity * u * u / 2; v = -impactSpeed + gravity * u
                phase = "Ngjitje e lirë · pa kontakt"
            }
            compression = max(0, x); eel = stiffness * compression * compression / 2
            epg = mass * gravity * (dropCompression - x)
            total = mass * gravity * (dropCompression + height)
        case .ramp:
            if t < rampDuration {
                progress = (gravity * t * t / 4) / (2 * height)
                v = gravity * t / 2; epg = mass * gravity * height * (1 - progress)
                phase = "Zbritja në rampë"
            } else if t < rampDuration + .pi / omega {
                let u = t - rampDuration
                compression = max(0, impactSpeed / omega * sin(omega * u))
                v = impactSpeed * cos(omega * u); progress = 1
                phase = v >= 0 ? "Susta shtypet" : "Susta e kthen trupin"
            } else {
                let u = t - rampDuration - .pi / omega
                let distance = impactSpeed * u - gravity * u * u / 4
                progress = 1 - distance / (2 * height)
                v = -(impactSpeed - gravity * u / 2)
                epg = mass * gravity * distance / 2
                phase = "Ngjitja në rampë"
            }
            x = compression; eel = stiffness * compression * compression / 2
            total = mass * gravity * height
        }
        let ek = mass * v * v / 2
        return SpringSnapshot(displacement: x, velocity: v, compression: compression, progress: min(1,max(0,progress)),
                              potential: max(0,epg), kinetic: ek, elastic: max(0,eel), total: total, phase: phase)
    }
}
private struct SpringMeasurement: Codable, Identifiable {
    var id = UUID()
    let mode, values: String
}
struct SpringLaboratory: View {
    @State private var mode = SpringMode.hanging
    @State private var mass = 1.0
    @State private var stiffness = 100.0
    @State private var second = 100.0
    @State private var amplitude = 0.2
    @State private var height = 1.0
    @State private var parallel = true
    @State private var running = false
    @State private var elapsed = 0.0
    @State private var started = Date()
    @State private var slow = true
    @AppStorage("springNotebook.v1") private var notebook = Data()
    @State private var notebookBlocked = false
    private var model: SpringModel {
        SpringModel(mode: mode, mass: mass, stiffness: stiffness, secondStiffness: second, amplitude: amplitude, height: height, parallel: parallel)
    }
    private var records: [SpringMeasurement] { (try? JSONDecoder().decode([SpringMeasurement].self,from:notebook)) ?? [] }
    private var signature: [Double] { [mass, stiffness, second, amplitude, height, parallel ? 1 : 0] }
    var body: some View {
        Page {
            VStack(alignment: .leading, spacing: 10) {
                Text("Punishtja e sustave").font(.largeTitle.bold())
                Text("Zgjidh një eksperiment. Ndrysho kushtet dhe ndiq forcën, lëvizjen e energjitë.")
                Picker("Eksperimenti",selection:$mode) {
                    ForEach(SpringMode.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.menu)
            }
            TimelineView(.animation(minimumInterval:0.04,paused:!running)) { context in
                let t = elapsed + (running ? context.date.timeIntervalSince(started) * (slow ? 0.25 : 1) : 0)
                let state = model.at(t)
                VStack(alignment: .leading, spacing: 12) {
                    SpringScene(model:model,state:state).frame(height:300)
                        .background(Color.midnight,in:RoundedRectangle(cornerRadius:22))
                    Text(state.phase).font(.headline)
                    Text(String(format:"x = %.3f m · |v| = %.3f m/s",state.displacement,abs(state.velocity))).monospacedDigit()
                    if mode == .coupled { Text(String(format:"k ekuivalente = %.2f N/m",model.effective)) }
                    if !mode.dynamic { Text(String(format:"Forca mbajtëse = mg = %.2f N",mass * 9.81)) }
                    if mode.dynamic {
                        energyBar("EPG",state.potential,state.total,.cyan)
                        energyBar("EK",state.kinetic,state.total,.orange)
                        energyBar("Elastike",state.elastic,state.total,.pink)
                        Text(String(format:"Shuma %.3f J · Energjia fillestare %.3f J",state.potential+state.kinetic+state.elastic,state.total)).font(.caption).monospacedDigit()
                    }
                }
            }
            controls
            if mode.dynamic { playback }
            SectionText(heading:"Si funksionon modeli",text:mode.explanation)
            Text("g = 9,81 m/s². Sustat janë ideale, pa masë dhe pa kufi të deformimit në këtë model. Vizatimi përshtatet me ekranin; leximi në metra jep vlerën fizike.").font(.footnote)
            DisclosureGroup("Fletorja ime · \(records.count) matje") {
                VStack(alignment: .leading,spacing:10) {
                    Button("Ruaj gjendjen e ndaluar") {
                        let state=model.at(elapsed)
                        let values=String(format:"m %.2f kg · k₁ %.1f N/m · k₂ %.1f N/m · A %.2f m · h %.2f m · t %.3f s\nx %.4f m · EK %.4f J · EPG %.4f J · Eel %.4f J",mass,stiffness,second,amplitude,height,elapsed,state.displacement,state.kinetic,state.potential,state.elastic)
                        guard var all=NotebookCodec.load(SpringMeasurement.self,from:notebook) else { notebookBlocked=true; return }
                        notebookBlocked=false
                        all.insert(SpringMeasurement(mode:mode.rawValue+(mode == .coupled ? (parallel ? " · paralel" : " · seri") : ""),values:values),at:0)
                        notebook=(try? JSONEncoder().encode(Array(all.prefix(60)))) ?? notebook
                    }.disabled(running)
                    if running { Text("Ndalo lëvizjen për të ruajtur matjen.").font(.caption) }
                    if notebookBlocked { Text(NotebookCodec.blockedMessage).font(.caption).foregroundStyle(Color.red) }
                    ForEach(records) { item in SectionText(heading:item.mode,text:item.values) }
                }
            }
        }.navigationTitle("Sustat dhe energjia")
        .onChange(of:signature) { _ in reset() }
        .onChange(of:mode) { _ in reset() }
        .onChange(of:slow) { _ in reset() }
        .onDisappear { running=false }
    }
    private var controls: some View {
        VStack(alignment:.leading,spacing:12) {
            control("Masa (kg)",$mass,0.2...5,0.2)
            control("Konstantja k₁ (N/m)",$stiffness,20...300,10)
            if mode == .coupled {
                control("Konstantja k₂ (N/m)",$second,20...300,10)
                Picker("Lidhja",selection:$parallel) { Text("Paralel").tag(true); Text("Seri").tag(false) }.pickerStyle(.segmented)
            }
            if mode == .horizontal || mode == .vertical { control("Amplituda rreth ekuilibrit (m)",$amplitude,0.05...0.8,0.05) }
            if mode == .drop || mode == .ramp { control("Lartësia e nisjes (m)",$height,0.1...3,0.1) }
        }
    }
    private var playback: some View {
        VStack(alignment:.leading,spacing:12) {
            Toggle("Luajtje e ngadaltë ×0,25",isOn:$slow)
            HStack {
                Button(running ? "Ndalo" : "Nis lëvizjen") {
                    if running {
                        elapsed = (elapsed + Date().timeIntervalSince(started) * (slow ? 0.25 : 1))
                            .truncatingRemainder(dividingBy: model.period)
                    }
                    started=Date();running.toggle()
                }.buttonStyle(.borderedProminent)
                Button("Kthe në nisje") { reset() }.buttonStyle(.bordered)
            }
            if !running {
                Text(String(format:"Koha fizike: %.3f s · Një cikël: %.3f s",elapsed,model.period)).font(.caption)
                Slider(value:$elapsed,in:0...model.period).accessibilityLabel("Shfleto një cikël të lëvizjes")
            }
        }
    }
    private func control(_ title:String,_ value:Binding<Double>,_ range:ClosedRange<Double>,_ step:Double) -> some View {
        VStack(alignment:.leading) {
            Text(title+String(format:" · %.2f",value.wrappedValue)).bold()
            Slider(value:value,in:range,step:step).accessibilityLabel(title)
        }
    }
    private func energyBar(_ label:String,_ value:Double,_ total:Double,_ color:Color) -> some View {
        HStack {
            Text(label).frame(width:65,alignment:.leading)
            ProgressView(value:min(max(value,0),max(total,0.000001)),total:max(total,0.000001)).tint(color)
            Text(String(format:"%.2f J",value)).monospacedDigit().frame(minWidth:75,alignment:.trailing)
        }.font(.callout)
    }
    private func reset() { running=false;elapsed=0;started=Date() }
}

private struct SpringScene: View {
    let model:SpringModel
    let state:SpringSnapshot
    var body: some View {
        Canvas { context,size in
            func p(_ x:Double,_ y:Double)->CGPoint { CGPoint(x:x*size.width,y:y*size.height) }
            func line(_ points:[CGPoint],_ color:Color = .white,_ width:CGFloat = 2) {
                guard let first=points.first else{return};var path=Path();path.move(to:first)
                for point in points.dropFirst(){path.addLine(to:point)}
                context.stroke(path,with:.color(color),lineWidth:width)
            }
            func coil(_ a:CGPoint,_ b:CGPoint,_ color:Color = .mint) {
                let dx=b.x-a.x,dy=b.y-a.y,length=max(1,hypot(dx,dy)),nx = -dy/length,ny=dx/length
                var points=[a]
                for i in 1...20 {
                    let f=Double(i)/21,offset:Double=i%2==0 ? 7 : -7
                    points.append(CGPoint(x:a.x+dx*f+nx*offset,y:a.y+dy*f+ny*offset))
                };points.append(b);line(points,color,2.5)
            }
            func label(_ text:String,_ x:Double,_ y:Double) {
                context.draw(Text(text).font(.system(size:12,weight:.semibold)).foregroundColor(.white),at:p(x,y))
            }
            func block(_ x:Double,_ y:Double) {
                let center=p(x,y)
                context.fill(Path(roundedRect:CGRect(x:center.x-23,y:center.y-19,width:46,height:38),cornerRadius:8),with:.color(.orange))
                context.draw(Text(String(format:"%.1f kg",model.mass)).font(.caption.bold()).foregroundColor(.black),at:center)
            }
            switch model.mode {
            case .horizontal:
                let x=0.55+0.28*state.displacement/max(model.amplitude,0.01)
                line([p(0.08,0.25),p(0.08,0.75)],.gray,7)
                line([p(0.08,0.68),p(0.94,0.68)],.gray)
                coil(p(0.1,0.55),p(x,0.55));block(x,0.55)
                line([p(0.55,0.7),p(0.55,0.8)],.cyan)
                label("Ekuilibri x = 0",0.55,0.9)
            case .hanging,.vertical:
                let amplitude=model.mode == .vertical ? model.amplitude : 0
                let natural=max(0.3,amplitude-model.equilibrium+0.15)
                let span=natural+model.equilibrium+amplitude+0.2
                let y=0.13+0.66*(natural+state.displacement)/span
                let zero=0.13+0.66*natural/span
                line([p(0.2,0.1),p(0.8,0.1)],.gray,7)
                coil(p(0.5,0.12),p(0.5,y));block(0.5,y)
                line([p(0.65,zero),p(0.85,zero)],.cyan)
                label("Gjatësia natyrore",0.76,max(0.06,zero-0.06))
                label(state.displacement >= 0 ? "↓ mg   ·   ↑ forca elastike" : "↓ mg   ·   ↓ forca elastike",0.5,0.94)
            case .supported,.drop:
                let range=model.mode == .drop ? model.height+model.dropCompression : model.equilibrium+0.4
                let restY=model.mode == .drop ? 0.18+0.58*model.height/range : 0.36
                let y=restY+0.58*state.displacement/range
                line([p(0.15,0.93),p(0.85,0.93)],.gray,7)
                let springTop=model.mode == .drop && state.displacement<0 ? restY : y
                coil(p(0.5,springTop+0.06),p(0.5,0.91));block(0.5,y)
                line([p(0.64,restY),p(0.88,restY)],.cyan)
                label("Pa deformim",0.77,max(0.06,restY-0.05))
            case .ramp:
                line([p(0.08,0.16),p(0.52,0.7),p(0.94,0.7)],.gray,4)
                let maxCompression=model.impactSpeed/model.omega
                let x=state.compression>0 ? 0.52+0.22*state.compression/maxCompression : 0.08+0.44*state.progress
                let y=state.compression>0 ? 0.63 : 0.09+0.54*state.progress
                line([p(0.92,0.35),p(0.92,0.7)],.gray,7)
                coil(p(max(0.52,x)+0.04,0.62),p(0.9,0.62));block(x,y)
                label("EPG → EK → Eel → EK → EPG",0.5,0.9)
            case .coupled:
                line([p(0.2,0.12),p(0.8,0.12)],.gray,7)
                if model.parallel {
                    coil(p(0.36,0.14),p(0.36,0.67))
                    coil(p(0.64,0.14),p(0.64,0.67),.pink)
                    line([p(0.36,0.67),p(0.64,0.67)],.white,4);block(0.5,0.75)
                    label("k₁",0.25,0.4);label("k₂",0.75,0.4)
                } else {
                    coil(p(0.5,0.14),p(0.5,0.43))
                    coil(p(0.5,0.43),p(0.5,0.73),.pink);block(0.5,0.79)
                    label("k₁",0.7,0.28);label("k₂",0.7,0.59)
                }
                label(model.parallel ? "E njëjta zgjatje" : "E njëjta forcë",0.5,0.96)
            }
        }.accessibilityLabel(model.mode.rawValue+". Pozicioni dhe energjitë jepen edhe me numra poshtë pamjes.")
    }
}
