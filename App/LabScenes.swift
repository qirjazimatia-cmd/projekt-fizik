import SwiftUI

// Normalized coordinates keep each illustration legible on phone and desktop.
private struct LabDrawing {
    let context: GraphicsContext
    let size: CGSize
    func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: x * size.width, y: y * size.height)
    }
    func text(_ value: String, x: Double, y: Double, color: Color = .white) {
        context.draw(Text(value).font(.system(size: 13, weight: .semibold)).foregroundColor(color), at: point(x, y))
    }
    func circle(x: Double, y: Double, radius: Double, color: Color) {
        let center = point(x, y)
        let r = radius * min(size.width, size.height)
        context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
    }
    func line(_ values: [(Double, Double)], color: Color = .white, width: CGFloat = 2) {
        guard let first = values.first else { return }
        var path = Path()
        path.move(to: point(first.0, first.1))
        for value in values.dropFirst() { path.addLine(to: point(value.0, value.1)) }
        context.stroke(path, with: .color(color), lineWidth: width)
    }
    func rectangle(x: Double, y: Double, width: Double, height: Double, color: Color) {
        context.fill(Path(roundedRect: CGRect(x: x * size.width, y: y * size.height,
                                            width: width * size.width, height: height * size.height), cornerRadius: 6),
                     with: .color(color))
    }
}

struct ExtendedLabScene: View {
    let experiment: LabExperiment
    let a, b, time: Double
    var body: some View {
        Canvas { context, size in
            let d = LabDrawing(context: context, size: size)
            switch experiment.subject {
            case .physics: physics(d)
            case .math: mathematics(d)
            case .biology: biology(d)
            case .chemistry: chemistry(d)
            }
        }.accessibilityLabel(experiment.title + ". Parametrat dhe rezultati jepen edhe me tekst.")
    }
    private func physics(_ d: LabDrawing) {
        switch experiment {
        case .energy:
            let progress = b / 100
            d.line([(0.1,0.16),(0.86,0.74)], color: .mint, width: 5)
            d.line([(0.1,0.16),(0.1,0.74),(0.86,0.74)], color: .gray)
            d.circle(x: 0.1 + 0.76 * progress, y: 0.12 + 0.58 * progress, radius: 0.035, color: .orange)
            d.text(String(format: "h = %.1f m", a * (1 - progress)), x: 0.3, y: 0.08)
            d.rectangle(x: 0.1, y: 0.85, width: 0.8 * (1 - progress), height: 0.06, color: .cyan)
            d.rectangle(x: 0.1 + 0.8 * (1 - progress), y: 0.85, width: 0.8 * progress, height: 0.06, color: .orange)
            d.text("EPG", x: 0.2, y: 0.97, color: .cyan)
            d.text("EK", x: 0.8, y: 0.97, color: .orange)
        case .forces:
            let acceleration = a / b
            let t = time.truncatingRemainder(dividingBy: 3)
            let x = 0.08 + min(0.67, acceleration * t * t / 200)
            d.line([(0.05,0.78),(0.95,0.78)], color: .gray)
            d.rectangle(x: x, y: 0.48, width: 0.16, height: 0.2, color: .cyan)
            d.circle(x: x + 0.035, y: 0.72, radius: 0.035, color: .white)
            d.circle(x: x + 0.125, y: 0.72, radius: 0.035, color: .white)
            d.text("\(Int(b)) kg", x: x + 0.08, y: 0.57, color: .black)
            if a > 0 { d.line([(x + 0.18,0.58),(x + 0.18 + a / 250,0.58)], color: .yellow, width: 4) }
            d.text("F = \(Int(a)) N →", x: 0.5, y: 0.25)
        case .springEnergy:
            let length = 0.2 + b / 65
            var spring: [(Double,Double)] = [(0.12,0.45)]
            for i in 1...20 { spring.append((0.12 + length * Double(i) / 20, i % 2 == 0 ? 0.5 : 0.4)) }
            d.line(spring, color: .mint, width: 3)
            d.line([(0.1,0.25),(0.1,0.65)], width: 7)
            d.circle(x: 0.12 + length, y: 0.45, radius: 0.06, color: .orange)
            d.text("k = \(Int(a)) N/m", x: 0.5, y: 0.2)
            d.text("x = \(Int(b)) cm", x: 0.5, y: 0.8)
        case .waves:
            let points = (0...160).map { index -> (Double,Double) in
                let x = Double(index) / 160
                return (0.05 + 0.9 * x, 0.5 - 0.2 * sin(2 * .pi * (x * 5 / b - time * a)))
            }
            d.line([(0.05,0.5),(0.95,0.5)], color: .gray)
            d.line(points, color: .cyan, width: 3)
            d.circle(x: 0.5, y: 0.5 - 0.2 * sin(2 * .pi * (2.5 / b - time * a)), radius: 0.025, color: .orange)
            d.text("Pika portokalli lëkundet lart e poshtë", x: 0.5, y: 0.88)
        case .refraction:
            let incidence = a * .pi / 180
            let refracted = asin(sin(incidence) / b)
            d.rectangle(x: 0, y: 0.5, width: 1, height: 0.5, color: .cyan.opacity(0.2))
            d.line([(0.5,0.08),(0.5,0.92)], color: .gray)
            let ray = min(d.size.width, d.size.height) * 0.4
            d.line([(0.5 - ray * sin(incidence) / d.size.width,0.5 - ray * cos(incidence) / d.size.height),(0.5,0.5),
                    (0.5 + ray * sin(refracted) / d.size.width,0.5 + ray * cos(refracted) / d.size.height)], color: .yellow, width: 4)
            d.text("Ajër · n = 1", x: 0.78, y: 0.13)
            d.text(String(format: "n = %.1f", b), x: 0.78, y: 0.82)
        case .buoyancy:
            d.rectangle(x: 0.05, y: 0.4, width: 0.9, height: 0.5, color: .cyan.opacity(0.5))
            let fraction = a / b
            let top = fraction <= 1 ? 0.4 - 0.2 * (1 - fraction) : 0.7
            d.rectangle(x: 0.38, y: top, width: 0.24, height: 0.2, color: .orange)
            d.text(fraction < 1 ? "Pluskim" : (fraction == 1 ? "Dendësi të barabarta" : "Fundosje"), x: 0.5, y: 0.15)
        default: break
        }
    }
    private func mathematics(_ d: LabDrawing) {
        switch experiment {
        case .unitCircle:
            let center = d.point(0.5,0.5)
            let radius = min(d.size.width,d.size.height) * 0.34
            d.context.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)), with: .color(.white), lineWidth: 2)
            let x = 0.5 + cos(a * .pi / 180) * radius / d.size.width
            let y = 0.5 - sin(a * .pi / 180) * radius / d.size.height
            d.line([(0.1,0.5),(0.9,0.5)], color: .gray)
            d.line([(0.5,0.05),(0.5,0.95)], color: .gray)
            d.line([(0.5,0.5),(x,y),(x,0.5)], color: .orange, width: 3)
            d.circle(x: x,y: y,radius: 0.025,color: .pink)
            d.text(String(format: "r = %.0f · θ = %.0f°", b,a),x: 0.5,y: 0.94)
        case .pythagoras:
            let scale = min(d.size.width * 0.7, d.size.height * 0.7) / 12
            let x = 0.16 + a * scale / d.size.width
            let y = 0.82 - b * scale / d.size.height
            d.line([(0.16,y),(0.16,0.82),(x,0.82),(0.16,y)], color: .mint, width: 3)
            let corner = min(a,b) * scale * 0.22
            d.line([(0.16,0.82-corner/d.size.height),(0.16+corner/d.size.width,0.82-corner/d.size.height),(0.16+corner/d.size.width,0.82)], color: .yellow)
            d.text("a = \(Int(a))",x: (0.16+x)/2,y: 0.92)
            d.text("b = \(Int(b))",x: 0.1,y: (y+0.82)/2)
            d.text("c",x: (x+0.16)/2 + 0.04,y: (y+0.82)/2 - 0.05)
        case .linear:
            d.line([(0.08,0.5),(0.92,0.5)],color: .gray)
            d.line([(0.5,0.08),(0.5,0.92)],color: .gray)
            let points = (0...160).compactMap { i -> (Double,Double)? in
                let x = -4 + Double(i)/20
                let y = a*x+b
                guard abs(y) <= 10 else { return nil }
                return (0.5+x/10,0.5-y/24)
            }
            d.line(points,color: .pink,width: 3)
            d.circle(x: 0.7,y: 0.5-7/24,radius: 0.025,color: .yellow)
            d.text("Synimi (2, 7)",x: 0.72,y: 0.12)
            d.text("x",x: 0.95,y: 0.55)
        case .polygon:
            let radius = min(d.size.width,d.size.height)*0.35
            let points = (0...Int(a)).map { i -> (Double,Double) in
                let angle = 2 * .pi * Double(i)/a - .pi/2
                return (0.5+cos(angle)*radius/d.size.width,0.5+sin(angle)*radius/d.size.height)
            }
            d.line(points,color: .pink,width: 3)
            d.line([(0.5,0.5),points[0]],color: .yellow)
            d.text("r = \(Int(b))",x: 0.5,y: 0.5)
            d.text("\(Int(a)) brinjë të barabarta",x: 0.5,y: 0.94)
        case .dice:
            for row in 1...6 {
                for col in 1...6 {
                    let hit = row + col == Int(a)
                    d.circle(x: 0.23 + Double(col-1)*0.11,y: 0.16+Double(row-1)*0.12,radius: 0.027,color: hit ? .orange : .cyan.opacity(0.4))
                }
            }
            d.text("Çiftet portokalli japin shumën \(Int(a))",x: 0.5,y: 0.93)
        case .exponential:
            let maximum = pow(a,5)
            for i in 0...5 {
                let height = pow(a,Double(i))/maximum*0.65
                d.rectangle(x: 0.1+Double(i)*0.14,y: 0.82-height,width: 0.09,height: height,color: Double(i)==b ? .orange : .cyan)
                d.text("\(i)",x: 0.145+Double(i)*0.14,y: 0.92)
            }
            d.text("Eksponenti →",x: 0.5,y: 0.06)
        default: break
        }
    }
    private func biology(_ d: LabDrawing) {
        let activity = experiment.value(a,b)
        switch experiment {
        case .photosynthesis:
            d.circle(x: 0.18,y: 0.18,radius: 0.1,color: .yellow.opacity(0.2+a/125))
            d.line([(0.5,0.85),(0.5,0.35)],color: .green,width: 5)
            d.circle(x: 0.42,y: 0.5,radius: 0.12,color: .green)
            d.circle(x: 0.58,y: 0.38,radius: 0.12,color: .mint)
            d.text("CO₂ ↓",x: 0.8,y: 0.2)
            let count = Int(activity / 10)
            for i in 0..<count {
                let phase = (Double(i)/10 + time/5).truncatingRemainder(dividingBy: 1)
                d.circle(x: 0.65 + Double(i%3)*0.04,y: 0.7-phase*0.5,radius: 0.015,color: .cyan)
            }
            d.text("O₂",x: 0.8,y: 0.8)
        case .enzyme:
            d.circle(x: 0.35,y: 0.5,radius: 0.2,color: .purple)
            d.circle(x: 0.52,y: 0.5,radius: 0.07,color: .midnight)
            let displacement = time == 0 ? 0.25 : 0.12 + cos(time)*0.1
            d.circle(x: 0.52+displacement,y: 0.5,radius: 0.06,color: .orange)
            d.text("Enzimë",x: 0.33,y: 0.82)
            d.text("Substrat",x: 0.75,y: 0.82)
            d.text(String(format: "%.0f%% aktivitet",activity),x: 0.5,y: 0.1)
        case .lungs:
            let breath = (sin(time * a / 60 * 2 * .pi)+1)/2
            let radius = 0.13 + b/10000*breath
            d.line([(0.5,0.1),(0.5,0.4),(0.35,0.6)],color: .white,width: 5)
            d.line([(0.5,0.4),(0.65,0.6)],color: .white,width: 5)
            d.circle(x: 0.35,y: 0.58,radius: radius,color: .pink)
            d.circle(x: 0.65,y: 0.58,radius: radius,color: .pink)
            d.text("Ajër ↕",x: 0.5,y: 0.06)
        case .heart:
            let beat = 1 + 0.1 * sin(time * a / 60 * 2 * .pi)
            d.circle(x: 0.44,y: 0.43,radius: 0.13*beat,color: .red)
            d.circle(x: 0.59,y: 0.43,radius: 0.13*beat,color: .red)
            d.circle(x: 0.515,y: 0.56,radius: 0.13*beat,color: .pink)
            d.line([(0.12,0.78),(0.3,0.78),(0.4,0.62),(0.48,0.9),(0.55,0.7),(0.65,0.78),(0.9,0.78)],color: .mint,width: 3)
            d.text("\(Int(a)) rrahje/min",x: 0.5,y: 0.1)
        case .foodEnergy:
            let values = [a,a*b/100,activity]
            let names = ["🌱 Prodhues","🐇 Konsumatorë I","🦊 Konsumatorë II"]
            for i in 0..<3 {
                let width = 0.8-Double(i)*0.22
                let y = 0.7-Double(i)*0.23
                d.rectangle(x: (1-width)/2,y: y,width: width,height: 0.18,color: [Color.green,.cyan,.orange][i])
                d.text(names[i]+" · "+String(format:"%.0f kJ",values[i]),x: 0.5,y: y+0.09,color: .black)
            }
        case .microscope:
            let radius = 0.1+min(0.24,activity/5000)
            d.circle(x: 0.5,y: 0.48,radius: radius+0.015,color: .mint)
            d.circle(x: 0.5,y: 0.48,radius: radius,color: .cyan.opacity(0.8))
            d.circle(x: 0.53,y: 0.46,radius: radius*0.3,color: .purple)
            d.text("Bërthama",x: 0.78,y: 0.46)
            d.text("Membrana",x: 0.5,y: 0.9)
        default: break
        }
    }
    private func chemistry(_ d: LabDrawing) {
        switch experiment {
        case .neutralization:
            let ph = experiment.value(a,b)
            d.rectangle(x: 0.35,y: 0.28,width: 0.3,height: 0.52,color: Color(hue: ph/20,saturation: 0.7,brightness: 0.95))
            d.line([(0.33,0.2),(0.33,0.82),(0.67,0.82),(0.67,0.2)],width: 3)
            d.text("H⁺ + OH⁻ → H₂O",x: 0.5,y: 0.11)
            d.text(String(format:"Tepricë %.1f mmol %@",abs(a-b)*0.1,a>b ? "H⁺" : (a<b ? "OH⁻" : "")),x: 0.5,y: 0.94)
        case .ions:
            let center = d.point(0.5,0.5)
            let r = min(d.size.width,d.size.height)*0.33
            d.context.stroke(Path(ellipseIn: CGRect(x: center.x-r,y: center.y-r,width: 2*r,height: 2*r)),with: .color(.white.opacity(0.4)),lineWidth: 2)
            d.circle(x: 0.5,y: 0.5,radius: 0.11,color: .pink)
            d.text("\(Int(a)) p⁺",x: 0.5,y: 0.5)
            for i in 0..<Int(b) {
                let angle = 2 * .pi * Double(i)/max(1,b)+time*0.4
                d.circle(x: 0.5+cos(angle)*r/d.size.width,y: 0.5+sin(angle)*r/d.size.height,radius: 0.018,color: .cyan)
            }
            d.text("Model simbolik i ngarkesës",x: 0.5,y: 0.95)
        case .reaction:
            let molecules = Int(experiment.value(a,b))
            for i in 0..<molecules {
                let x = 0.15+Double(i%4)*0.23
                let y = 0.26+Double(i/4)*0.23
                d.circle(x: x,y: y,radius: 0.035,color: .red)
                d.circle(x: x-0.035,y: y+0.035,radius: 0.02,color: .white)
                d.circle(x: x+0.035,y: y+0.035,radius: 0.02,color: .white)
            }
            d.text("2H₂ + O₂ → 2H₂O",x: 0.5,y: 0.07)
            d.text("Mbeten H₂ · \(Int(a)-molecules)   O₂ · \(Int(b)-molecules/2)",x: 0.5,y: 0.94)
        case .equilibrium:
            let fraction = a/(1+a)
            for i in 0..<40 {
                let x = 0.08+Double((i*29)%83)/100
                let y = 0.18+Double((i*17)%60)/100
                d.circle(x: x,y: y+sin(time+Double(i))*0.01,radius: 0.022,color: Double(i)<fraction*40 ? .orange : .cyan)
            }
            d.text("A (blu) ⇌ B (portokalli)",x: 0.5,y: 0.07)
            d.text(String(format:"[A] %.2f · [B] %.2f mol/L",b/(1+a),b*a/(1+a)),x: 0.5,y: 0.94)
        case .crystals:
            d.rectangle(x: 0.2,y: 0.22,width: 0.6,height: 0.6,color: .purple.opacity(0.3))
            d.line([(0.18,0.18),(0.18,0.85),(0.82,0.85),(0.82,0.18)],width: 3)
            let count = Int(experiment.value(a,b))
            for i in 0..<count {
                let x = 0.24+Double(i%10)*0.055
                let y = 0.8-Double(i/10)*0.045
                d.line([(x,y-0.018),(x+0.012,y),(x,y+0.018),(x-0.012,y),(x,y-0.018)],color: .pink,width: 2)
            }
            d.text("T = \(Int(a))°C",x: 0.5,y: 0.08)
            d.text("Substancë hipotetike",x: 0.5,y: 0.95)
        case .halfLife:
            let fraction = experiment.value(a,b)/1000
            for i in 0..<100 {
                let x = 0.14+Double(i%10)*0.08
                let y = 0.13+Double(i/10)*0.075
                d.circle(x: x,y: y,radius: 0.018,color: Double(i)<fraction*100 ? .orange : .gray.opacity(0.3))
            }
            d.text("Çdo pikë përfaqëson 10 bërthama",x: 0.5,y: 0.95)
        default: break
        }
    }
}

struct EnergyReadout: View {
    let height, percent: Double
    var body: some View {
        let kinetic = 20 * height * percent / 100
        let potential = 20 * height - kinetic
        VStack(alignment: .leading, spacing: 6) {
            Text(String(format: "EPG %.1f J + EK %.1f J = %.1f J", potential, kinetic, 20*height)).bold()
            Text(String(format: "Shpejtësia %.2f m/s · Zbritja %.1f%%", sqrt(kinetic), percent))
            Text("m = 2 kg · g = 10 m/s² · Pa fërkim").font(.caption)
            Text("Animacioni përsëritet me kohë të ngadalësuar për vëzhgim.").font(.caption)
        }.font(.callout).padding()
    }
}
