import SwiftUI
#if os(iOS)
import CoreMotion
#endif

// Efektet «si uji» (Juri): progres i mbushur me ujë që anon me telefonin, shkëlqim xhami që ndjek pjerrësinë,
// tregues skede «goo» si pikë uji, hapje me spërkatje, sfond që rrjedh (mesh), koka që shkrihet, karta që përkulen,
// pikë uji kur tërheq poshtë, flluska në sfond dhe Liquid Glass origjinal në iOS 26.
// RREGULL: asnjë efekt këtu nuk merr prekje (allowsHitTesting(false)); butonat mbeten gjithmonë të shtypshëm.

// MARK: - Pjerrësia e telefonit (CoreMotion, pa leje të veçantë)

@MainActor
final class MotionTilt: ObservableObject {
    static let shared = MotionTilt()
    /// -1…1: majtas/djathtas dhe para/prapa.
    @Published private(set) var x: Double = 0
    @Published private(set) var y: Double = 0
    #if os(iOS)
    private let manager = CMMotionManager()
    #endif
    private var users = 0

    func start() {
        users += 1
        #if os(iOS)
        guard users == 1, manager.isDeviceMotionAvailable, !UIAccessibility.isReduceMotionEnabled else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 20.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else { return }
            // I butë: lëviz gradualisht drejt vlerës së re.
            self.x += (max(-1, min(1, gravity.x)) - self.x) * 0.25
            self.y += (max(-1, min(1, gravity.y + 0.6)) - self.y) * 0.25
        }
        #endif
    }
    func stop() {
        users = max(0, users - 1)
        #if os(iOS)
        if users == 0 { manager.stopDeviceMotionUpdates() }
        #endif
    }
}

/// Shkëlqimi mbi xham që lëviz kur anon telefonin.
struct TiltSpecular<S: InsettableShape>: View {
    let shape: S
    @ObservedObject private var tilt = MotionTilt.shared
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width, h = geometry.size.height
            Ellipse()
                .fill(RadialGradient(colors: [.white.opacity(0.32), .white.opacity(0)], center: .center, startRadius: 0, endRadius: max(w, h) * 0.45))
                .frame(width: max(w, h) * 0.9, height: max(w, h) * 0.55)
                .position(x: w * (0.3 + 0.35 * tilt.x), y: h * (0.15 - 0.25 * tilt.y))
                .blendMode(.plusLighter)
        }
        .clipShape(shape)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { tilt.start() }
        .onDisappear { tilt.stop() }
    }
}

// MARK: - 1. Progres i mbushur me ujë

/// Sipërfaqe uji që valëzohet; anon pak kur anon telefonin.
private struct WaterShape: Shape {
    var level: Double      // 0…1
    var phase: Double
    var tilt: Double
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(level, tilt) }
        set { level = newValue.first; tilt = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let base = rect.maxY - rect.height * min(max(level, 0), 1)
        let amp = level <= 0.001 || level >= 0.999 ? 0 : min(rect.height * 0.08, 4)
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for x in stride(from: rect.minX, through: rect.maxX, by: 2) {
            let t = (x - rect.minX) / max(rect.width, 1)
            let y = base + sin(t * .pi * 2 * 1.3 + phase * 3) * amp + (t - 0.5) * tilt * rect.height * 0.25
            path.addLine(to: CGPoint(x: x, y: min(max(y, rect.minY), rect.maxY)))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Shirit progresi i mbushur me ujë (p.sh. XP deri te niveli tjetër).
struct LiquidBar: View {
    let value: Double
    var color: Color = .lagoon
    var height: CGFloat = 14
    @ObservedObject private var tilt = MotionTilt.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.14))
                GeometryReader { geometry in
                    let width = geometry.size.width * min(max(value, 0), 1)
                    ZStack {
                        LinearGradient(colors: [color.opacity(0.75), color], startPoint: .leading, endPoint: .trailing)
                        // Valë e lehtë mbi ujë.
                        WaterShape(level: 0.82, phase: phase, tilt: tilt.x * 0.4)
                            .fill(.white.opacity(0.18))
                        LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .top, endPoint: .center)
                    }
                    .frame(width: width)
                    .clipShape(Capsule())
                }
            }
            .frame(height: height)
            .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.8))
        }
        .animation(.liquid, value: value)
        .accessibilityElement().accessibilityValue("\(Int(value * 100)) për qind")
        .onAppear { tilt.start() }
        .onDisappear { tilt.stop() }
    }
}

/// Rreth i mbushur me ujë (si një gotë e rrumbullakët), me përmbajtje sipër.
struct LiquidOrb<Content: View>: View {
    let value: Double
    var color: Color = .lagoon
    @ViewBuilder var content: () -> Content
    @ObservedObject private var tilt = MotionTilt.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var level: Double = 0
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle().fill(.white.opacity(0.15))
                WaterShape(level: level, phase: phase + 1.4, tilt: tilt.x).fill(color.opacity(0.45)).clipShape(Circle())
                WaterShape(level: level, phase: phase, tilt: tilt.x).fill(LinearGradient(colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom)).clipShape(Circle())
                Circle().fill(LinearGradient(colors: [.white.opacity(0.5), .clear], startPoint: .topLeading, endPoint: .center))
                Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1.5)
                content()
            }
        }
        .onAppear { tilt.start(); withAnimation(.spring(response: 1.2, dampingFraction: 0.6).delay(0.15)) { level = value } }
        .onDisappear { tilt.stop() }
        .onChange(of: value) { new in withAnimation(.liquid) { level = new } }
    }
}

// MARK: - 3. Treguesi i skedës «goo» (pikë uji që shtrihet dhe ndahet)

/// Dy pika (njëra shpejt, tjetra me vonesë) të bashkuara me efektin «goo» (turbullim + prag alfa):
/// kur ndërron skedë, pika zgjatet si ujë dhe shkëputet.
struct GooeyTabIndicator: View {
    let index: Int
    let count: Int
    var color: Color = .lagoon
    @State private var from = 0
    @State private var to = 0
    @State private var changed = Date.distantPast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: Date().timeIntervalSince(changed) > 1.2)) { timeline in
            let t = timeline.date.timeIntervalSince(changed)
            Canvas { context, size in
                let slot = size.width / CGFloat(max(count, 1))
                func x(_ i: Int) -> CGFloat { slot * (CGFloat(i) + 0.5) }
                let lead = reduceMotion ? 1 : spring(t, response: 0.32, damping: 0.62)
                let tail = reduceMotion ? 1 : spring(t, response: 0.62, damping: 0.75)
                let leadX = x(from) + (x(to) - x(from)) * lead
                let tailX = x(from) + (x(to) - x(from)) * tail
                let w = slot - 8, h = size.height - 6
                context.addFilter(.alphaThreshold(min: 0.5, color: color.opacity(0.24)))
                context.addFilter(.blur(radius: 7))
                context.drawLayer { layer in
                    for (cx, scale) in [(leadX, 1.0), (tailX, 0.86)] {
                        let rect = CGRect(x: cx - w * scale / 2, y: (size.height - h * scale) / 2, width: w * scale, height: h * scale)
                        layer.fill(Path(roundedRect: rect, cornerRadius: h * scale / 2), with: .color(.black))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { from = index; to = index }
        .onChange(of: index) { new in
            // Nis nga pozicioni ku ndodhet tani pika.
            from = to; to = new; changed = Date()
        }
    }

    /// Lëvizje spring e thjeshtë (0 → 1), e mbiderdhur pak si lëng.
    private func spring(_ t: Double, response: Double, damping: Double) -> Double {
        guard t > 0 else { return 0 }
        let omega = 2 * Double.pi / response
        let decay = exp(-damping * omega * t)
        let dampedOmega = omega * sqrt(max(1 - damping * damping, 0.0001))
        return 1 - decay * (cos(dampedOmega * t) + damping * omega / dampedOmega * sin(dampedOmega * t))
    }
}

// MARK: - 4. Hapja me spërkatje

/// Atomi (logoja) bie në ujë, bën valë rrethore dhe app-i shfaqet. ~1.5 s, një herë për çdo hapje; me «Reduce Motion» kalohet.
struct SplashIntro: View {
    let done: () -> Void
    @State private var dropped = false
    @State private var rings = false
    @State private var fade = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let water = geometry.size.height * 0.56
            ZStack {
                LinearGradient(colors: [Color(red: 0.38, green: 0.27, blue: 1.0), Color(red: 0.84, green: 0.25, blue: 0.9), Color(red: 1.0, green: 0.5, blue: 0.36)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                // Uji.
                Rectangle().fill(LinearGradient(colors: [Color.cyan.opacity(0.45), Color.indigo.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                    .frame(height: geometry.size.height - water)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .overlay(alignment: .top) { Capsule().fill(.white.opacity(0.8)).frame(height: 3) }
                ForEach(0..<3, id: \.self) { i in
                    Ellipse().strokeBorder(.white.opacity(rings ? 0 : 0.8), lineWidth: 3)
                        .frame(width: rings ? 360 + CGFloat(i) * 120 : 40, height: rings ? 60 + CGFloat(i) * 22 : 8)
                        .position(x: geometry.size.width / 2, y: water)
                        .animation(.easeOut(duration: 1.0).delay(Double(i) * 0.12), value: rings)
                }
                BrainSparkLogo(size: 130)
                    .position(x: geometry.size.width / 2, y: dropped ? water : -120)
            }
            .ignoresSafeArea()
        }
        .opacity(fade ? 0 : 1)
        .scaleEffect(fade ? 1.15 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { done(); return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) { dropped = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { rings = true; Haptics.tap() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) { withAnimation(.easeInOut(duration: 0.4)) { fade = true } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { done() }
        }
    }
}

// MARK: - 5. Sfond me gradient që rrjedh (iOS 18+ MeshGradient)

@available(iOS 18.0, macOS 15.0, *)
struct FlowingMesh: View {
    let colors: [Color]
    private static func points(_ t: Float) -> [SIMD2<Float>] {
        let top: Float = 0.5 + 0.12 * sin(t * 0.3)
        let left: Float = 0.5 + 0.1 * cos(t * 0.25)
        let midX: Float = 0.5 + 0.15 * sin(t * 0.21)
        let midY: Float = 0.5 + 0.15 * cos(t * 0.17)
        let right: Float = 0.5 + 0.1 * sin(t * 0.27)
        let bottom: Float = 0.5 + 0.12 * cos(t * 0.23)
        return [SIMD2(0, 0), SIMD2(top, 0), SIMD2(1, 0),
                SIMD2(0, left), SIMD2(midX, midY), SIMD2(1, right),
                SIMD2(0, 1), SIMD2(bottom, 1), SIMD2(1, 1)]
    }
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { timeline in
            let t = Float(timeline.date.timeIntervalSinceReferenceDate)
            let c = colors.count >= 4 ? colors : colors + [.clear, .clear, .clear, .clear]
            let base = scheme == .dark ? Color.black.opacity(0.0) : Color.white.opacity(0.0)
            MeshGradient(width: 3, height: 3, points: Self.points(t), colors: [
                c[0].opacity(0.30), base, c[1].opacity(0.25),
                base, c[2].opacity(0.22), base,
                c[3].opacity(0.25), base, c[0].opacity(0.22),
            ])
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - 6–7. Koka që shkrihet dhe kartat që përkulen

/// Kur lëviz poshtë, pjesa sipër zvogëlohet, turbullohet dhe zbehet (iOS 17+).
struct HeaderMelt: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            content.visualEffect { view, proxy in
                let y = proxy.frame(in: .scrollView).minY
                let progress = min(max(-y / 220, 0), 1)
                return view
                    .scaleEffect(1 - 0.12 * progress, anchor: .top)
                    .blur(radius: 6 * progress)
                    .opacity(1 - 0.65 * progress)
            }
        } else {
            content
        }
    }
}

// MARK: - 8. Pikë uji kur tërheq poshtë

/// Një pikë që zgjatet nga lart sa më shumë tërheq faqen poshtë (iOS 18+). Vetëm pamje; rifreskimi bëhet nga sistemi.
struct PullDroplet: View {
    let pull: CGFloat
    var color: Color = .lagoon
    var body: some View {
        let stretch = min(max(pull, 0), 140)
        Canvas { context, size in
            guard stretch > 4 else { return }
            let cx = size.width / 2
            let r = 10 + stretch * 0.08
            context.addFilter(.alphaThreshold(min: 0.5, color: color.opacity(0.55)))
            context.addFilter(.blur(radius: 5))
            context.drawLayer { layer in
                layer.fill(Path(ellipseIn: CGRect(x: cx - 26, y: -14, width: 52, height: 28)), with: .color(.black))
                layer.fill(Path(ellipseIn: CGRect(x: cx - r, y: stretch * 0.75 - r, width: r * 2, height: r * 2)), with: .color(.black))
                var neck = Path()
                neck.move(to: CGPoint(x: cx - 6, y: 8))
                neck.addLine(to: CGPoint(x: cx + 6, y: 8))
                neck.addLine(to: CGPoint(x: cx + 3, y: stretch * 0.75))
                neck.addLine(to: CGPoint(x: cx - 3, y: stretch * 0.75))
                neck.closeSubpath()
                if stretch < 110 { layer.fill(neck, with: .color(.black)) }
            }
        }
        .frame(height: 160)
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - 9. Flluska që ngrihen në sfond

private struct BubblesKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// Faqja shfaq flluska që ngrihen në sfond (te Krye).
    var pageBubbles: Bool {
        get { self[BubblesKey.self] }
        set { self[BubblesKey.self] = newValue }
    }
}

struct BubbleField: View {
    var color: Color = .lagoon
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private struct Bubble { let x: Double; let size: Double; let speed: Double; let offset: Double; let sway: Double }
    private let bubbles: [Bubble] = (0..<14).map(BubbleField.makeBubble)

    private static func makeBubble(_ i: Int) -> Bubble {
        let x: Double = Double((i * 37) % 100) / 100
        let size: Double = 8 + Double((i * 53) % 22)
        let speed: Double = 0.035 + Double((i * 29) % 40) / 1000
        let offset: Double = Double((i * 71) % 100) / 100
        let sway: Double = 6 + Double((i * 13) % 14)
        return Bubble(x: x, size: size, speed: speed, offset: offset, sway: sway)
    }
    var body: some View {
        if !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    for b in bubbles {
                        let progress = (t * b.speed + b.offset).truncatingRemainder(dividingBy: 1)
                        let y = size.height * (1.05 - progress * 1.15)
                        let x = size.width * b.x + sin(t * 0.8 + b.offset * 6) * b.sway
                        let alpha = progress < 0.9 ? 1 : (1 - progress) * 10   // «plas» afër majës
                        let scale = progress < 0.9 ? 1 : 1 + (progress - 0.9) * 6
                        let r = b.size * scale / 2
                        let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                        context.opacity = alpha * 0.55
                        context.stroke(Path(ellipseIn: rect), with: .color(color.opacity(0.6)), lineWidth: 1.2)
                        context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.07)))
                        context.fill(Path(ellipseIn: CGRect(x: x - r * 0.5, y: y - r * 0.6, width: r * 0.4, height: r * 0.3)), with: .color(.white.opacity(0.8)))
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
