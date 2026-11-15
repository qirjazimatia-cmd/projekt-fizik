import SwiftUI

// Pamja «xham» në stilin Liquid Glass të Apple-it (kërkesa e Juri-t).
// Në iOS 26 / macOS 26 përdor efektin e vërtetë `glassEffect`; në versionet më të vjetra një imitim me material
// të turbullt, shkëlqim në buzë dhe hije të butë. Pas xhamit lëvizin njolla ngjyrash, që xhami të duket i gjallë.

struct GlassBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    var tint: Color? = nil
    /// Sa e fortë është ngjyra në xham (0 = i tejdukshëm, 1 = plot ngjyrë).
    var strength: Double = 0.18
    var interactive = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        // Aksesueshmëri: me «Reduce Transparency» ose «Increase Contrast» xhami bëhet kartë e plotë, me buzë të dukshme,
        // që teksti të lexohet mirë mbi çdo sfond.
        if reduceTransparency || contrast == .increased {
            solid(content)
        } else {
            glass(content)
        }
    }

    private func solid(_ content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(Color.card)
                    shape.fill((tint ?? .clear).opacity(min(strength, 0.85) * 0.9))
                }
            }
            .overlay { shape.strokeBorder(Color.ink.opacity(contrast == .increased ? 0.55 : 0.18), lineWidth: contrast == .increased ? 1.5 : 1) }
    }

    @ViewBuilder private func glass(_ content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            // Pa `.interactive()`: xhami ndodhet brenda butonave dhe lidhjeve, dhe në iOS 26 xhami interaktiv
            // mund ta marrë prekjen para butonit. Butoni vetë jep reagimin (shtypje + valëzim).
            content.glassEffect(Glass.regular.tint(tint?.opacity(strength) ?? AppAccent.color.opacity(0.12)), in: shape)
        } else {
            liquid(content)
        }
        #else
        liquid(content)
        #endif
    }

    /// Imitimi i Liquid Glass për çdo version: xham i turbullt e i tejdukshëm, shkëlqim lart, buzë që thyejnë dritën
    /// dhe hije e butë poshtë.
    private func liquid(_ content: Content) -> some View {
        let dark = scheme == .dark
        return content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    // Nuanca: ngjyra e lëndës, ose ngjyra që zgjodhe te Cilësimet → Ngjyra.
                    shape.fill((tint ?? AppAccent.color).opacity(tint == nil ? (dark ? 0.10 : 0.08) : strength * 0.75))
                    // Shkëlqimi i sipërm (si drita që bie mbi xham).
                    shape.fill(LinearGradient(colors: [.white.opacity(dark ? 0.16 : 0.45), .white.opacity(0)],
                                              startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.55)))
                    // Refleks i pjerrët në cepin e sipërm majtas.
                    shape.fill(RadialGradient(colors: [.white.opacity(dark ? 0.18 : 0.35), .clear],
                                              center: UnitPoint(x: 0.12, y: 0.0), startRadius: 0, endRadius: 140))
                    // Refleks i pjerrët si te xhami i derdhur: një shirit drite që e përshkon kartën.
                    shape.fill(LinearGradient(stops: [.init(color: .clear, location: 0.05),
                                                      .init(color: .white.opacity(dark ? 0.09 : 0.26), location: 0.20),
                                                      .init(color: .clear, location: 0.34)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                    // Pak errësim poshtë, që xhami të ketë «trashësi».
                    shape.fill(LinearGradient(colors: [.clear, .black.opacity(dark ? 0.18 : 0.05)],
                                              startPoint: UnitPoint(x: 0.5, y: 0.6), endPoint: .bottom))
                }
            }
            .overlay {
                // Buza: e ndritshme lart-majtas, më e zbehtë në mes, pak dritë poshtë-djathtas.
                shape.strokeBorder(
                    LinearGradient(stops: [.init(color: .white.opacity(dark ? 0.55 : 0.95), location: 0),
                                           .init(color: .white.opacity(dark ? 0.10 : 0.25), location: 0.45),
                                           .init(color: .white.opacity(dark ? 0.05 : 0.15), location: 0.6),
                                           .init(color: (tint ?? AppAccent.color).opacity(dark ? 0.55 : 0.5), location: 1)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.2)
            }
            .overlay {
                // Buza e brendshme thyen dritën në ngjyra (cyan → rozë), si skajet e xhamit në diell.
                shape.inset(by: 1.2).strokeBorder(AngularGradient(colors: [.white.opacity(dark ? 0.08 : 0.3), .cyan.opacity(dark ? 0.30 : 0.25),
                                                                           .pink.opacity(dark ? 0.22 : 0.18), .white.opacity(dark ? 0.06 : 0.25),
                                                                           .white.opacity(dark ? 0.08 : 0.3)],
                                                                  center: .center, angle: .degrees(20)), lineWidth: 0.7)
            }
            // Një hije e vetme (dy hije në çdo kartë e ngadalësonin lëvizjen).
            .shadow(color: .black.opacity(dark ? 0.35 : 0.09), radius: 14, y: 7)
    }
}

/// Butona xhami (në vend të butonave të zakonshëm). `prominent` = xham me ngjyrë të fortë për veprimin kryesor.
struct LiquidButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        LiquidButton(configuration: configuration, prominent: prominent)
    }
    private struct LiquidButton: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        @Environment(\.subjectTheme) private var subject
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            let color = subject?.color ?? .lagoon
            configuration.label
                .font(.headline)
                .padding(.horizontal, 18).padding(.vertical, 11)
                .foregroundStyle(prominent ? Color.white : color)
                .glassCapsule(tint: color, strength: prominent ? 0.85 : 0.10, interactive: true)
                // «Lëng»: shtypet pak dhe zgjerohet anash kur e prek.
                .scaleEffect(x: configuration.isPressed ? 1.04 : 1, y: configuration.isPressed ? 0.94 : 1)
                .brightness(configuration.isPressed ? 0.06 : 0)
                .opacity(enabled ? 1 : 0.45)
                .overlay { PressRipple(pressed: configuration.isPressed, color: prominent ? .white : color, cornerRadius: 40) }
                .animation(.spring(response: 0.28, dampingFraction: 0.55), value: configuration.isPressed)
        }
    }
}

extension ButtonStyle where Self == LiquidButtonStyle {
    static var liquid: LiquidButtonStyle { LiquidButtonStyle() }
    static var liquidProminent: LiquidButtonStyle { LiquidButtonStyle(prominent: true) }
}

extension View {
    /// Kartë xhami me kënde të rrumbullakëta.
    func glass(cornerRadius: CGFloat = 18, tint: Color? = nil, strength: Double = 0.18, interactive: Bool = false) -> some View {
        modifier(GlassBackground(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), tint: tint, strength: strength, interactive: interactive))
    }
    /// Kapsulë xhami (butona, shirita).
    func glassCapsule(tint: Color? = nil, strength: Double = 0.18, interactive: Bool = false) -> some View {
        modifier(GlassBackground(shape: Capsule(), tint: tint, strength: strength, interactive: interactive))
    }
}

/// Njolla ngjyrash pas xhamit. Tani vizatohen pa turbullim të rëndë (gradient i butë në një Canvas të vetëm),
/// që të mos e ngadalësojnë app-in.
struct AmbientBlobs: View {
    let colors: [Color]
    var animated = true
    var body: some View { WaterBackground(colors: colors, animated: animated, ribbons: false, bubbles: false, waves: false) }
}

/// Kartat zbehen dhe zvogëlohen pak kur dalin nga ekrani gjatë lëvizjes (iOS 17+/macOS 14+), si në app-et e Apple-it.
struct ScrollFade: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            content.scrollTransition(.animated(.spring(response: 0.4, dampingFraction: 0.85))) { view, phase in
                view.opacity(phase.isIdentity ? 1 : 0.55)
                    .scaleEffect(phase.isIdentity ? 1 : 0.94)
                                }
        } else {
            content
        }
    }
}

extension View {
    /// Madhësia minimale e dritareve (sheet) vlen vetëm në Mac. Në iPhone/iPad dritarja përshtatet me ekranin,
    /// përndryshe del e prerë në gjysmë.
    @ViewBuilder func macSheetFrame(minWidth: CGFloat, minHeight: CGFloat) -> some View {
        #if os(macOS)
        self.frame(minWidth: minWidth, minHeight: minHeight)
        #else
        self
        #endif
    }
}

// MARK: - «Si uji»: valë, valëzim kur prek, pika që zgjatet dhe kalime të buta (Juri)

/// Valë uji poshtë faqes (tani pjesë e `WaterBackground`).
struct LiquidWaves: View {
    var color: Color
    var body: some View { WaterBackground(colors: [color], ribbons: false, bubbles: false, waves: true, blobs: false) }
}

/// Valëzim uji kur shtypet një buton ose kartë. Niset nga gjendja «i shtypur» e butonit (jo nga një gjest më vete),
/// kështu që nuk ia merr kurrë prekjen butonit.
struct PressRipple: View {
    let pressed: Bool
    var color: Color = .white
    var cornerRadius: CGFloat = 22
    @State private var waves: [UUID] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let size = max(geometry.size.width, geometry.size.height) * 1.6
            ZStack {
                ForEach(waves, id: \.self) { id in RippleWave(color: color, size: size) }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: pressed) { now in
            guard now, !reduceMotion else { return }
            let id = UUID()
            waves.append(id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { waves.removeAll { $0 == id } }
        }
    }
}

private struct RippleWave: View {
    let color: Color
    let size: CGFloat
    @State private var grown = false
    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(0.0), color.opacity(0.25), color.opacity(0.0)],
                                 center: .center, startRadius: size * 0.2, endRadius: size * 0.5))
            .frame(width: size, height: size)
            .scaleEffect(grown ? 1 : 0.05)
            .opacity(grown ? 0 : 1)
            .onAppear { withAnimation(.easeOut(duration: 0.7)) { grown = true } }
    }
}

/// Kalimi «si lëng» midis faqeve: zbehje, turbullim i lehtë, pak zmadhim dhe rrëshqitje.
struct LiquidTransitionModifier: ViewModifier {
    let progress: Double
    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .blur(radius: (1 - progress) * 4)
            .scaleEffect(0.965 + 0.035 * progress)
            .offset(y: (1 - progress) * 16)
    }
}

extension AnyTransition {
    static var liquid: AnyTransition {
        .modifier(active: LiquidTransitionModifier(progress: 0), identity: LiquidTransitionModifier(progress: 1))
    }
}

extension Animation {
    /// Spring i butë si uji, i përdorur në gjithë app-in për kalimet kryesore.
    static var liquid: Animation { .spring(response: 0.55, dampingFraction: 0.82, blendDuration: 0.25) }
    static var liquidBounce: Animation { .spring(response: 0.42, dampingFraction: 0.58) }
}

/// Treguesi i skedës së zgjedhur: një «pikë» xhami që rrëshqet te skeda e re, zgjatet dhe kthehet si lëng.
struct LiquidSelection: View {
    let color: Color
    let namespace: Namespace.ID
    @State private var squash = true
    var body: some View {
        Capsule()
            .fill(color.opacity(0.20))
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.1), color.opacity(0.5)],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.9))
            .overlay(alignment: .top) {
                Capsule().fill(LinearGradient(colors: [.white.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom))
                    .frame(height: 12).padding(.horizontal, 8).padding(.top, 2)
            }
            .shadow(color: color.opacity(0.35), radius: 8, y: 3)
            .matchedGeometryEffect(id: "liquid-selection", in: namespace)
            .scaleEffect(x: squash ? 1.22 : 1, y: squash ? 0.84 : 1)
            .onAppear { withAnimation(.liquidBounce.delay(0.05)) { squash = false } }
    }
}

// MARK: - Sfondi «ujë dhe xham» (Juri, nëntor 2026)

/// Sfondi i gjallë i faqeve: njolla ngjyrash të buta, shirita xhami që përdreden si ujë (si foto e Juri-t),
/// flluska që ngjiten dhe valë poshtë. Gjithçka vizatohet në një `Canvas` të vetëm me 30 kuadro/s, pa turbullime,
/// që të mos rëndojë. Ndalet kur app-i nuk është në ekran, me «Reduce Motion» ose me «Low Power Mode».
struct WaterBackground: View {
    var colors: [Color]
    var animated = true
    var ribbons = true
    var bubbles = true
    var waves = true
    var blobs = true
    var glyphs: [SubjectGlyph] = []
    var glyphColor: Color = .clear
    var glyphOpacity: Double = 0.06
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase

    private var paused: Bool {
        !animated || reduceMotion || scenePhase != .active || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 36_000)
            Canvas { context, size in
                draw(&context, size: size, t: t)
            } symbols: {
                ForEach(glyphs.indices, id: \.self) { i in
                    glyphView(glyphs[i]).foregroundStyle(glyphColor).tag(i)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, t: Double) {
        guard size.width > 1, size.height > 1, !colors.isEmpty else { return }
        let dark = scheme == .dark
        if blobs { drawBlobs(&context, size: size, t: t, dark: dark) }
        if ribbons { drawRibbons(&context, size: size, t: t, dark: dark) }
        if !glyphs.isEmpty { drawGlyphs(&context, size: size, t: t) }
        if bubbles { drawBubbles(&context, size: size, t: t, dark: dark) }
        if waves { drawWaves(&context, size: size, t: t, dark: dark) }
    }

    /// Njolla të mëdha me gradient të butë (në vend të `.blur(70)`, që ishte shumë i rëndë).
    private func drawBlobs(_ context: inout GraphicsContext, size: CGSize, t: Double, dark: Bool) {
        let base = max(size.width, size.height, 500)
        for (i, color) in colors.prefix(4).enumerated() {
            let f = Double(i)
            let cx = size.width * (0.5 + 0.40 * sin(t * 0.06 * (1 + f * 0.3) + f * 1.9))
            let cy = size.height * (0.5 + 0.42 * cos(t * 0.045 * (1 + f * 0.25) + f * 2.7))
            let r = base * (0.55 - f * 0.06)
            let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
            context.fill(Path(ellipseIn: rect),
                         with: .radialGradient(Gradient(colors: [color.opacity(dark ? 0.30 : 0.22), color.opacity(0)]),
                                               center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r))
        }
    }

    /// Shirita xhami që përdreden ngadalë: trup i tejdukshëm, shkëlqim lart dhe buzë me ngjyrë poshtë.
    private func drawRibbons(_ context: inout GraphicsContext, size: CGSize, t: Double, dark: Bool) {
        for k in 0..<3 {
            let f = Double(k)
            let color = colors[k % colors.count]
            let yBase = size.height * (0.16 + 0.30 * f)
            let amp = min(size.height * 0.06, 60) * (1 + 0.3 * f)
            let length = 1.1 + 0.4 * f
            let speed = 0.22 * (k % 2 == 0 ? 1 : -1)
            var path = Path()
            for x in stride(from: -40.0, through: size.width + 40, by: 10) {
                let u = x / size.width * .pi * 2
                let y = yBase + sin(u * length + t * speed + f) * amp + sin(u * 2.4 + t * 0.13 + f * 2) * amp * 0.3
                if x == -40 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            let w = 34.0 + 14 * f
            let round = StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)
            context.stroke(path, with: .color(color.opacity(dark ? 0.12 : 0.08)), style: round)
            context.stroke(path, with: .color(.white.opacity(dark ? 0.05 : 0.16)),
                           style: StrokeStyle(lineWidth: w * 0.45, lineCap: .round, lineJoin: .round))
            context.stroke(path.offsetBy(dx: 0, dy: -w * 0.42), with: .color(.white.opacity(dark ? 0.32 : 0.70)), lineWidth: 1.2)
            context.stroke(path.offsetBy(dx: 0, dy: w * 0.42), with: .color(color.opacity(dark ? 0.45 : 0.32)), lineWidth: 1.4)
            context.stroke(path.offsetBy(dx: 0, dy: w * 0.30), with: .color(Color.cyan.opacity(dark ? 0.16 : 0.14)), lineWidth: 0.8)
        }
    }

    /// Flluska që ngjiten dhe lëkunden pak, me një pikë drite.
    private func drawBubbles(_ context: inout GraphicsContext, size: CGSize, t: Double, dark: Bool) {
        let travel = size.height + 60
        for b in 0..<12 {
            let f = Double(b)
            let seed = (f * 0.618 + 0.13).truncatingRemainder(dividingBy: 1)
            let speed = 14 + 20 * seed
            let y = size.height + 30 - (t * speed + seed * travel).truncatingRemainder(dividingBy: travel)
            let x = size.width * (0.05 + 0.9 * (f * 0.381 + 0.07).truncatingRemainder(dividingBy: 1)) + sin(t * 1.1 + f) * 8
            let r = 3 + 8 * seed
            let circle = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            context.fill(circle, with: .color(.white.opacity(dark ? 0.04 : 0.12)))
            context.stroke(circle, with: .color(.white.opacity(dark ? 0.28 : 0.55)), lineWidth: 0.8)
            context.fill(Path(ellipseIn: CGRect(x: x - r * 0.55, y: y - r * 0.6, width: r * 0.5, height: r * 0.35)),
                         with: .color(.white.opacity(dark ? 0.5 : 0.8)))
        }
    }

    /// Simbolet e lëndës që lëkunden si mbi ujë.
    private func drawGlyphs(_ context: inout GraphicsContext, size: CGSize, t: Double) {
        let columns = max(3, Int(size.width / 120)), rows = max(3, Int(size.height / 140))
        var layer = context
        layer.opacity = glyphOpacity
        for index in 0..<(columns * rows) {
            guard let symbol = context.resolveSymbol(id: index % glyphs.count) else { continue }
            let row = index / columns, column = index % columns
            let seed = Double((index * 37 + row * 11) % 97) / 97
            let x = (Double(column) + 0.25 + 0.5 * seed) / Double(columns) * size.width
            let y = (Double(row) + 0.2 + 0.6 * Double((index * 53) % 89) / 89) / Double(rows) * size.height
                + sin(t * 0.5 + seed * 6) * 6
            layer.drawLayer { g in
                g.translateBy(x: x, y: y)
                g.rotate(by: .degrees(-20 + 40 * seed + sin(t * 0.4 + seed * 5) * 6))
                let s = (22 + 18 * seed) / 30
                g.scaleBy(x: s, y: s)
                g.draw(symbol, at: .zero)
            }
        }
    }

    private func drawWaves(_ context: inout GraphicsContext, size: CGSize, t: Double, dark: Bool) {
        let color = colors[0]
        let layers: [(amp: Double, length: Double, speed: Double, height: Double, alpha: Double)] = [
            (14, 1.6, 0.35, 0.82, dark ? 0.10 : 0.08),
            (10, 1.1, -0.5, 0.87, dark ? 0.08 : 0.07),
            (7, 0.8, 0.7, 0.92, dark ? 0.07 : 0.06),
        ]
        for layer in layers {
            var path = Path()
            let base = size.height * layer.height
            path.move(to: CGPoint(x: 0, y: size.height))
            for x in stride(from: 0.0, through: size.width + 8, by: 8) {
                path.addLine(to: CGPoint(x: x, y: base + sin(x / size.width * .pi * 2 * layer.length + t * layer.speed * 2) * layer.amp))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
            context.fill(path, with: .linearGradient(Gradient(colors: [color.opacity(layer.alpha * 1.6), color.opacity(layer.alpha * 0.4)]),
                                                     startPoint: CGPoint(x: 0, y: base), endPoint: CGPoint(x: 0, y: size.height)))
            // Vija e shkëlqyer mbi valë.
            var crest = Path()
            for x in stride(from: 0.0, through: size.width + 8, by: 8) {
                let p = CGPoint(x: x, y: base + sin(x / size.width * .pi * 2 * layer.length + t * layer.speed * 2) * layer.amp)
                if x == 0 { crest.move(to: p) } else { crest.addLine(to: p) }
            }
            context.stroke(crest, with: .color(.white.opacity(dark ? 0.12 : 0.35)), lineWidth: 1)
        }
    }

    @ViewBuilder private func glyphView(_ glyph: SubjectGlyph) -> some View {
        switch glyph {
        case .text(let text): Text(text).font(.system(size: 30, weight: .heavy, design: .rounded))
        case .symbol(let name): Image(systemName: name).font(.system(size: 30, weight: .semibold))
        }
    }
}
