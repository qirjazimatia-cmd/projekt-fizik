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

/// Sfondi i gjallë i faqeve: njolla ngjyrash të buta lart dhe ujë poshtë, me valë që rrotullohen, dritë brenda ujit,
/// flluska dhe një spërkatje herë pas here (pika që kërcejnë dhe rrathë valësh). Gjithçka vizatohet në një `Canvas` të vetëm me 30 kuadro/s, pa turbullime,
/// që të mos rëndojë. Ndalet kur app-i nuk është në ekran, me «Reduce Motion» ose me «Low Power Mode».
struct WaterBackground: View {
    var colors: [Color]
    var animated = true
    var ribbons = false // hequr (Juri): sfondi tani është ujë me valë
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
        if !glyphs.isEmpty { drawGlyphs(&context, size: size, t: t) }
        if waves {
            drawWaves(&context, size: size, t: t, dark: dark)
            if bubbles { drawBubbles(&context, size: size, t: t, dark: dark) }
            drawSplash(&context, size: size, t: t, dark: dark)
        }
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

    // MARK: Uji: valë që rrotullohen dhe spërkatin

    /// Niveli i ujit (pjesë e lartësisë së ekranit) për shtresën `k` (0 = mbrapa, 3 = përpara).
    private func waterLevel(_ k: Int, _ size: CGSize) -> Double {
        size.height * (0.58 + 0.055 * Double(k))
    }

    /// Lartësia e sipërfaqes në pikën x: tri valë sinusoidale të mbivendosura, si ujë i vërtetë.
    private func surface(_ x: Double, k: Int, size: CGSize, t: Double) -> Double {
        let f = Double(k)
        let u = x / size.width * .pi * 2
        let amp = min(size.height * 0.022, 20) * (1 - 0.1 * f)
        let dir = k % 2 == 0 ? 1.0 : -1.0
        let a = sin(u * 1.3 + t * 0.9 * dir + f) * 0.6
        let b = sin(u * 2.7 - t * 1.4 + f * 2) * 0.3
        let c = sin(u * 0.6 + t * 0.5 + f * 0.7) * 0.5
        var y = waterLevel(k, size) + amp * (a + b + c)
        if k == 3 { y += splashBump(x, size: size, t: t) }
        return y
    }

    /// Spërkatja e radhës: ku ndodh dhe sa kohë ka kaluar (një çdo 3.2 s, në vend të rastësishëm).
    private func splash(size: CGSize, t: Double) -> (x: Double, phase: Double) {
        let period = 3.2
        let cycle = (t / period).rounded(.down)
        let noise = abs(sin(cycle * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)
        return (size.width * (0.15 + 0.7 * noise), t - cycle * period)
    }

    /// Kurora e spërkatjes dhe rrathët e valëve që hapen anash.
    private func splashBump(_ x: Double, size: CGSize, t: Double) -> Double {
        let s = splash(size: size, t: t)
        guard s.phase < 2.4 else { return 0 }
        let dx = abs(x - s.x)
        let rise = s.phase < 0.22 ? s.phase / 0.22 : exp(-(s.phase - 0.22) * 4)
        let crown = -26 * exp(-(dx / 28) * (dx / 28)) * rise
        let front = s.phase * 190
        let ring = dx < front ? 6 * sin(dx / 13 - s.phase * 9) * exp(-dx / 170) * exp(-s.phase * 1.4) : 0
        return crown + ring
    }

    private func wavePath(k: Int, size: CGSize, t: Double, closed: Bool) -> Path {
        var path = Path()
        var first = true
        for x in stride(from: -6.0, through: size.width + 6, by: 6) {
            let p = CGPoint(x: x, y: surface(x, k: k, size: size, t: t))
            if first { path.move(to: p); first = false } else { path.addLine(to: p) }
        }
        if closed {
            path.addLine(to: CGPoint(x: size.width + 6, y: size.height))
            path.addLine(to: CGPoint(x: -6, y: size.height))
            path.closeSubpath()
        }
        return path
    }

    private func drawWaves(_ context: inout GraphicsContext, size: CGSize, t: Double, dark: Bool) {
        let water = colors[0]
        for k in 0..<4 {
            let f = Double(k)
            let top = waterLevel(k, size) - 30
            let alpha = (dark ? 0.12 : 0.09) + 0.03 * f
            let body = Gradient(colors: [water.opacity(alpha * 1.5), water.opacity(alpha * 0.9), colors[min(1, colors.count - 1)].opacity(alpha * 0.8)])
            context.fill(wavePath(k: k, size: size, t: t, closed: true),
                         with: .linearGradient(body, startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: size.height)))
            let crest = wavePath(k: k, size: size, t: t, closed: false)
            // Brezi i ndritshëm nën kreshtë (drita që kalon nëpër ujë) dhe vija e shkëlqyer sipër.
            context.stroke(crest.offsetBy(dx: 0, dy: 5), with: .color(.white.opacity(dark ? 0.06 : 0.16)), lineWidth: 5)
            context.stroke(crest, with: .color(.white.opacity((dark ? 0.18 : 0.45) + 0.08 * f)), lineWidth: 1.2)
        }
        drawCaustics(&context, size: size, t: t, dark: dark)
    }

    /// Rrjeti i dritës brenda ujit (si dielli në fund të pishinës).
    private func drawCaustics(_ context: inout GraphicsContext, size: CGSize, t: Double, dark: Bool) {
        let start = waterLevel(3, size) + 34
        for j in 0..<4 {
            let fj = Double(j)
            var path = Path()
            for x in stride(from: 0.0, through: size.width + 10, by: 10) {
                let u = x / size.width * .pi * 2
                let y = start + fj * 26 + sin(u * 3 + t * 1.1 + fj) * 7 + sin(u * 5.3 - t * 0.8 + fj * 3) * 3
                if x == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(.white.opacity(dark ? 0.05 : 0.13)), lineWidth: 1.6)
        }
    }

    /// Pikat e spërkatjes: kërcejnë lart nga kurora, lënë një bisht të shkurtër dhe bien prapë në ujë.
    private func drawSplash(_ context: inout GraphicsContext, size: CGSize, t: Double, dark: Bool) {
        let s = splash(size: size, t: t)
        let tau = s.phase - 0.08
        guard tau > 0, tau < 1.6 else { return }
        let y0 = waterLevel(3, size) - 8
        let gravity = 430.0
        for i in 0..<10 {
            let fi = Double(i)
            let jitter = abs(sin(fi * 7.31 + s.x)).truncatingRemainder(dividingBy: 1)
            let angle = -Double.pi / 2 + (fi / 9 - 0.5) * 1.7 + (jitter - 0.5) * 0.25
            let speed = 150 + 110 * jitter
            let vx = cos(angle) * speed * 0.65, vy = sin(angle) * speed
            func at(_ time: Double) -> CGPoint {
                CGPoint(x: s.x + vx * time, y: y0 + vy * time + 0.5 * gravity * time * time)
            }
            let p = at(tau)
            guard p.y < y0 + 14 || tau < 0.2 else { continue }
            let r = 2.2 + 3 * jitter
            var tail = Path()
            tail.move(to: at(max(0, tau - 0.05)))
            tail.addLine(to: p)
            context.stroke(tail, with: .color(colors[0].opacity(dark ? 0.35 : 0.30)), style: StrokeStyle(lineWidth: r * 1.4, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(.white.opacity(dark ? 0.45 : 0.75)))
            context.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.5, y: p.y - r * 0.6, width: r * 0.6, height: r * 0.45)),
                         with: .color(.white))
        }
    }

    /// Flluska të vogla që ngjiten brenda ujit deri te sipërfaqja.
    private func drawBubbles(_ context: inout GraphicsContext, size: CGSize, t: Double, dark: Bool) {
        let top = waterLevel(3, size) + 12
        let depth = max(size.height - top, 40)
        for b in 0..<9 {
            let f = Double(b)
            let seed = (f * 0.618 + 0.13).truncatingRemainder(dividingBy: 1)
            let y = size.height - (t * (12 + 16 * seed) + seed * depth).truncatingRemainder(dividingBy: depth)
            let x = size.width * (0.05 + 0.9 * (f * 0.381 + 0.07).truncatingRemainder(dividingBy: 1)) + sin(t * 1.3 + f) * 6
            let r = 2 + 4 * seed
            let circle = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            context.stroke(circle, with: .color(.white.opacity(dark ? 0.25 : 0.5)), lineWidth: 0.8)
            context.fill(Path(ellipseIn: CGRect(x: x - r * 0.5, y: y - r * 0.6, width: r * 0.5, height: r * 0.4)),
                         with: .color(.white.opacity(0.7)))
        }
    }

    @ViewBuilder private func glyphView(_ glyph: SubjectGlyph) -> some View {
        switch glyph {
        case .text(let text): Text(text).font(.system(size: 30, weight: .heavy, design: .rounded))
        case .symbol(let name): Image(systemName: name).font(.system(size: 30, weight: .semibold))
        }
    }
}
