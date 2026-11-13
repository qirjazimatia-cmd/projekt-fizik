import SwiftUI

struct StudyDiagram: Decodable { let kind, caption: String; let nodes: [String] }
private struct LessonDrawing {
    let c: GraphicsContext
    let size: CGSize
    func point(_ x:Double,_ y:Double) -> CGPoint { CGPoint(x:x*size.width,y:y*size.height) }
    func line(_ points:[(Double,Double)],color:Color = .lagoon,width:CGFloat = 2) {
        guard let first = points.first else { return }
        var p=Path(); p.move(to:point(first.0,first.1)); for q in points.dropFirst() { p.addLine(to:point(q.0,q.1)) }
        c.stroke(p,with:.color(color),lineWidth:width)
    }
    func text(_ value:String,_ x:Double,_ y:Double,color:Color = .midnight) {
        c.draw(Text(value).font(.system(size:13,weight:.semibold)).foregroundColor(color),at:point(x,y))
    }
    func ellipse(_ x:Double,_ y:Double,_ w:Double,_ h:Double,color:Color,fill:Bool = true) {
        let p=Path(ellipseIn:CGRect(x:x*size.width,y:y*size.height,width:w*size.width,height:h*size.height))
        if fill { c.fill(p,with:.color(color)) } else { c.stroke(p,with:.color(color),lineWidth:2) }
    }
    func arrow(_ x1:Double,_ y1:Double,_ x2:Double,_ y2:Double,color:Color = .lagoon) {
        line([(x1,y1),(x2,y2)],color:color,width:3)
        let a=atan2((y2-y1)*size.height,(x2-x1)*size.width)
        let end=point(x2,y2);var p=Path();p.move(to:CGPoint(x:end.x-9*cos(a - .pi/6),y:end.y-9*sin(a - .pi/6)));p.addLine(to:end);p.addLine(to:CGPoint(x:end.x-9*cos(a + .pi/6),y:end.y-9*sin(a + .pi/6)))
        c.stroke(p,with:.color(color),lineWidth:3)
    }
}
struct LessonDiagramView: View {
    let lesson: StudyLesson
    @State private var control = 3.0
    @State private var reveal = 1
    private var diagram: StudyDiagram { lesson.diagram }
    private var range: ClosedRange<Double> {
        switch diagram.kind {
        case "numberline":return -5...5
        case "rays":return 0...70
        case "ph":return 0...14
        case "atom":return 1...18
        case "curve":return -2...2
        case "spring":return 0.1...5
        case "circuit":return 1...20
        default:return 1...8
        }
    }
    private var controlName: String {
        switch diagram.kind {
        case "triangle":return "Kateti horizontal a (cm)"
        case "circle":return "Rrezja r (cm)"
        case "curve":return "Pika x në y=x²"
        case "spring":return "Masa m (kg), k=100 N/m"
        case "rays":return "Këndi i rënies i (gradë)"
        case "circuit":return "Rezistenca R (Ω), U=12 V"
        case "atom":return "Numri atomik Z"
        case "ph":return "pH në 25 °C"
        case "numberline":return "Numri x"
        default:return "Parametri"
        }
    }
    private var interactive: Bool { !["flow","cell","membrane","punnett"].contains(diagram.kind) }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Label("Shiko dhe kupto",systemImage:"eye").font(.title2.bold())
            if diagram.kind == "flow" { solutionFlow }
            else {
                Canvas { c,size in draw(LessonDrawing(c:c,size:size)) }
                    .frame(height:240).background(Color.white,in:RoundedRectangle(cornerRadius:12))
                    .accessibilityLabel(explanation)
                if interactive {
                    Text(controlName + ": " + control.formatted(.number.precision(.fractionLength(0...2))))
                    Slider(value:$control,in:range,step:diagram.kind == "atom" ? 1 : 0.1).accessibilityLabel(controlName)
                }
                Text(explanation).font(.callout).fixedSize(horizontal:false,vertical:true)
            }
            Text(diagram.caption).font(.caption).foregroundStyle(.secondary)
            if lesson.schoolSubject == .physics && (lesson.title.lowercased().contains("sust") || lesson.chapterTitle.lowercased().contains("hukut")) {
                NavigationLink("Provoje këtë temë në laboratorin e sustave") { SpringLaboratory() }.buttonStyle(.liquidProminent)
            }
        }.padding(16).background(lesson.schoolSubject.color.opacity(0.06),in:RoundedRectangle(cornerRadius:16))
        .onAppear { control = min(range.upperBound,max(range.lowerBound,diagram.kind == "rays" ? 45 : 3)) }
    }
    private var solutionFlow: some View {
        VStack(alignment:.leading,spacing:10) {
            ForEach(Array(diagram.nodes.prefix(reveal).enumerated()),id:\.offset) { i,node in
                HStack(alignment:.top,spacing:12) {
                    VStack { Text("\(i+1)").font(.headline).foregroundStyle(.white).frame(width:30,height:30).background(lesson.schoolSubject.color,in:Circle()); if i<reveal-1 { Image(systemName:"arrow.down").foregroundStyle(lesson.schoolSubject.color) } }
                    Text(node).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
                }
            }
            if reveal<diagram.nodes.count { Button("Zbulo hapin tjetër") { withAnimation { reveal += 1 } }.buttonStyle(.liquid) }
            else { Button("Fillo arsyetimin përsëri") { reveal = 1 } }
        }
    }
    private var explanation: String {
        let a=control
        switch diagram.kind {
        case "triangle":return String(format:"Model kënddrejtë: a=%.2f cm, b=4 cm. c=√(a²+b²)=%.2f cm; S=a·4/2=%.2f cm². Këndi i shënuar është 90°.",a,sqrt(a*a+16),2*a)
        case "circle":return String(format:"Rrethi: r=%.2f cm, diametri=%.2f cm. Perimetri=%.2f cm; syprina=%.2f cm². Tangjentja në pikën e djathtë është pingule me rrezen horizontale.",a,2*a,2*Double.pi*a,Double.pi*a*a)
        case "curve":return String(format:"Model y=x²: në x=%.2f, y=%.2f dhe pjerrësia e tangjentes është 2x=%.2f. Vija portokalli tregon tangjenten; kur x<0 pjerrësia është negative.",a,a*a,2*a)
        case "spring":return String(format:"Ekuilibër statik, g=9.81 N/kg: x=mg/k=%.3f m dhe Eel=kx²/2=%.3f J. Kjo është zgjatje ekuilibri; rënia e një mase mbi sustë ka tjetër ngjeshje maksimale.",a*9.81/100,0.5*100*pow(a*9.81/100,2))
        case "rays":let r=asin(sin(a * .pi/180)/1.5)*180 / .pi;return String(format:"Nga ajri n₁=1 në qelq n₂=1.5: i=%.1f°, r=%.1f°. Këndet maten nga normalja vertikale. Rrezja në qelq afrohet me normalen.",a,r)
        case "circuit":
            let parallel = lesson.title.contains("paralel")
            let equivalent = parallel ? a*10/(a+10) : a+10
            return String(format:"Dy rezistorë: R₁=%.1f Ω, R₂=10 Ω, burimi 12 V. %@ Re=%.3f Ω dhe rryma totale I=12/Re=%.3f A.",a,parallel ? "Në paralel: 1/Re=1/R₁+1/R₂." : "Në seri: Re=R₁+R₂.",equivalent,12/equivalent)
        case "cell":return "Skemë e qelizës eukariote shtazore: membrana e jashtme, citoplazma, bërthama dhe mitokondritë. Këtu nuk paraqiten të gjitha organelet; qeliza nuk ka mur qelizor ose kloroplaste."
        case "atom":return "Model shtresash për atom neutral me Z=\(Int(a)). Ka \(Int(a)) protone dhe \(Int(a)) elektrone. Rrathët shënojnë shtresa energjetike të thjeshtuara, jo trajektore reale të elektroneve."
        case "membrane":return "Difuzion neto i një substance që kalon membranën: nga zona me përqendrim më të lartë në atë me përqendrim më të ulët. Grimcat lëvizin në të dyja drejtimet; shigjeta përmbledh drejtimin neto."
        case "punnett":
            if lesson.title.contains("provë") { return "Kryqëzimi provë Aa × aa: Aa, aa, Aa, aa. P(Aa)=1/2 dhe P(aa)=1/2. Me dominancë të plotë pritet raport fenotipik 1:1, jo rezultat i garantuar në pak pasardhës." }
            return "Model Aa × Aa me ndarje të barabartë të aleleve: AA, Aa, Aa, aa. P(Aa)=1/2 dhe P(aa)=1/4. Këto janë probabilitete për çdo pasardhës, jo garanci që çdo grup me katër do t'i përmbajë të katër rastet."
        case "ph":return String(format:"Në modelin e tretësirës ideale, [H⁺]≈10^(−pH)=%.3g mol/L. Në 25 °C: nën 7 acid, 7 neutral, mbi 7 bazik. pH është shkallë logaritmike.",pow(10,-a))
        case "numberline":return String(format:"x=%.1f, largësia nga zero |x|=%.1f. Shenja tregon anën e zeros; vlera absolute tregon largësinë.",a,abs(a))
        default:return lesson.example.conclusion
        }
    }
    private func draw(_ d:LessonDrawing) {
        let a=control
        switch diagram.kind {
        case "triangle":
            let x=0.2+a*0.07
            d.line([(0.2,0.2),(0.2,0.8),(x,0.8),(0.2,0.2)],width:3)
            d.line([(0.2,0.73),(0.24,0.73),(0.24,0.8)],color:.gray)
            d.text("b = 4",0.1,0.5);d.text(String(format:"a = %.1f",a),(x+0.2)/2,0.9);d.text("c",(x+0.2)/2+0.04,0.43)
        case "circle":
            let r=0.08+a*0.025;let rx=r*d.size.height/d.size.width
            d.ellipse(0.45-rx,0.5-r,2*rx,2*r,color:.lagoon,fill:false)
            d.line([(0.45,0.5),(0.45+rx,0.5)],color:.orange,width:3)
            d.line([(0.45+rx,0.12),(0.45+rx,0.88)],color:.green)
            d.text("r",0.45+rx/2,0.43);d.text("O",0.42,0.53);d.text("Tangjente",0.76,0.1)
        case "curve":
            d.line([(0.08,0.86),(0.93,0.86)],color:.gray);d.line([(0.5,0.94),(0.5,0.08)],color:.gray)
            let values=(0...80).map { i -> (Double,Double) in let x=Double(i)/20-2;return (0.5+x*0.18,0.86-x*x*0.17) };d.line(values,width:3)
            let tangent=(0...80).compactMap { i -> (Double,Double)? in let x=Double(i)/20-2;let y=2*a*x-a*a;return y>=0 && y<=4.5 ? (0.5+x*0.18,0.86-y*0.17):nil };d.line(tangent,color:.orange,width:3)
            d.ellipse(0.5+a*0.18-0.01,0.86-a*a*0.17-0.015,0.02,0.03,color:.red)
            d.text("x",0.95,0.86);d.text("y=x²",0.73,0.1)
        case "spring":
            d.line([(0.3,0.12),(0.7,0.12)],color:.gray,width:6)
            let end=0.3+a*0.075
            var pts:[(Double,Double)]=[(0.5,0.12)]
            for i in 0...18 { pts.append((i%2==0 ? 0.44:0.56,0.16+Double(i)/18*(end-0.16))) }
            pts.append((0.5,end+0.05));d.line(pts,width:3)
            d.ellipse(0.42,end+0.04,0.16,0.13,color:.orange)
            d.arrow(0.75,end,0.75,end+0.16,color:.red);d.text("mg",0.84,end+0.1)
            d.text("k=100 N/m",0.22,0.45)
        case "rays":
            d.line([(0.05,0.5),(0.95,0.5)],color:.gray);d.line([(0.5,0.08),(0.5,0.92)],color:.gray)
            let i=a * .pi/180,r=asin(sin(i)/1.5),scale=0.36
            d.arrow(0.5-scale*sin(i),0.5-scale*cos(i),0.5,0.5,color:.orange)
            d.arrow(0.5,0.5,0.5+scale*sin(r),0.5+scale*cos(r),color:.blue)
            d.text("Ajër · n=1",0.18,0.12);d.text("Qelq · n=1.5",0.2,0.88);d.text("Normalja",0.7,0.12)
        case "circuit":
            d.line([(0.18,0.42),(0.18,0.2),(0.4,0.2)])
            d.line([(0.66,0.2),(0.86,0.2),(0.86,0.8),(0.18,0.8),(0.18,0.58)])
            d.line([(0.4,0.2),(0.43,0.14),(0.47,0.26),(0.51,0.14),(0.55,0.26),(0.59,0.14),(0.63,0.26),(0.66,0.2)],color:.orange)
            d.text("R₁",0.53,0.07)
            if lesson.title.contains("paralel") {
                d.line([(0.32,0.2),(0.32,0.5),(0.4,0.5)])
                d.line([(0.66,0.5),(0.76,0.5),(0.76,0.2)])
                d.line([(0.4,0.5),(0.44,0.44),(0.48,0.56),(0.52,0.44),(0.56,0.56),(0.6,0.44),(0.66,0.5)],color:.green)
                d.text("R₂ = 10 Ω",0.54,0.64)
            } else {
                d.line([(0.86,0.8),(0.68,0.8)],color:.lagoon)
                // Draw the second resistor over the bottom wire, separated by its white backing.
                d.line([(0.4,0.8),(0.66,0.8)],color:.white,width:8)
                d.line([(0.4,0.8),(0.44,0.74),(0.48,0.86),(0.52,0.74),(0.56,0.86),(0.6,0.74),(0.66,0.8)],color:.green)
                d.text("R₂ = 10 Ω",0.53,0.96)
            }
            d.line([(0.1,0.42),(0.26,0.42)],width:4);d.line([(0.13,0.58),(0.23,0.58)],width:4)
            d.text("+",0.29,0.39);d.text("−",0.28,0.6);d.text("12 V",0.09,0.51)
        case "cell":
            d.ellipse(0.12,0.15,0.76,0.67,color:.mint.opacity(0.25));d.ellipse(0.12,0.15,0.76,0.67,color:.green,fill:false)
            d.ellipse(0.39,0.35,0.2,0.26,color:.purple.opacity(0.5));d.text("Bërthama",0.49,0.48)
            d.ellipse(0.23,0.32,0.09,0.13,color:.orange);d.ellipse(0.65,0.6,0.1,0.1,color:.orange)
            d.text("Citoplazma",0.33,0.69);d.text("Membrana",0.5,0.9);d.text("Mitokondri",0.73,0.31);d.line([(0.72,0.35),(0.7,0.59)],color:.gray)
        case "atom":
            let z=Int(a);d.ellipse(0.45,0.43,0.1,0.14,color:.orange);d.text("+\(z)",0.5,0.5)
            let shell=[min(z,2),min(max(z-2,0),8),max(z-10,0)]
            for k in 0..<3 where shell[k]>0 {
                let r=0.13+Double(k)*0.1;let rx=r*d.size.height/d.size.width
                d.ellipse(0.5-rx,0.5-r,2*rx,2*r,color:.gray,fill:false)
                for j in 0..<shell[k] { let t=Double(j)*2 * .pi/Double(shell[k]);d.ellipse(0.5+rx*cos(t)-0.009,0.5+r*sin(t)-0.014,0.018,0.028,color:.blue) }
            }
        case "membrane":
            d.line([(0.48,0.15),(0.48,0.85)],width:5);d.line([(0.52,0.15),(0.52,0.85)],width:5)
            for i in 0..<15 { d.ellipse(0.1+Double(i%3)*0.1,0.2+Double(i/3)*0.12,0.025,0.035,color:.orange) }
            for i in 0..<5 { d.ellipse(0.66+Double(i%2)*0.12,0.2+Double(i/2)*0.2,0.025,0.035,color:.orange) }
            d.arrow(0.37,0.55,0.65,0.55,color:.green);d.text("Më shumë",0.2,0.1);d.text("Më pak",0.78,0.1);d.text("Membrana",0.5,0.94)
        case "punnett":
            for x in [0.32,0.58,0.84] { d.line([(x,0.28),(x,0.86)]) }
            for y in [0.28,0.57,0.86] { d.line([(0.32,y),(0.84,y)]) }
            let testCross = lesson.title.contains("provë")
            d.text("A",0.45,0.17);d.text("a",0.71,0.17);d.text(testCross ? "a" : "A",0.2,0.42);d.text("a",0.2,0.72)
            d.text(testCross ? "Aa" : "AA",0.45,0.42);d.text(testCross ? "aa" : "Aa",0.71,0.42);d.text("Aa",0.45,0.72);d.text("aa",0.71,0.72)
        case "ph":
            for i in 0...14 { let x=0.1+Double(i)*0.057;d.line([(x,0.35),(x,0.65)],color:i<7 ? .orange:i==7 ? .green:.purple,width:10) }
            d.arrow(0.1+a*0.057,0.18,0.1+a*0.057,0.32,color:.midnight)
            d.text("Acid",0.22,0.78);d.text("7 · Neutral",0.5,0.78);d.text("Bazik",0.8,0.78)
        case "numberline":
            d.arrow(0.06,0.5,0.95,0.5)
            for i in -5...5 { let x=0.5+Double(i)*0.08;d.line([(x,0.46),(x,0.54)]);d.text("\(i)",x,0.64) }
            d.line([(0.5,0.35),(0.5+a*0.08,0.35)],color:.orange,width:6)
            d.ellipse(0.5+a*0.08-0.012,0.475,0.024,0.05,color:.red);d.text("|x|",0.5+a*0.04,0.2)
        default:break
        }
    }
}
