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
            let glass = Glass.regular.tint(tint?.opacity(strength))
            content.glassEffect(interactive ? glass.interactive() : glass, in: shape)
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
                    shape.fill((tint ?? .white).opacity(tint == nil ? (dark ? 0.02 : 0.12) : strength * 0.75))
                    // Shkëlqimi i sipërm (si drita që bie mbi xham).
                    shape.fill(LinearGradient(colors: [.white.opacity(dark ? 0.16 : 0.45), .white.opacity(0)],
                                              startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.55)))
                    // Refleks i pjerrët në cepin e sipërm majtas.
                    shape.fill(RadialGradient(colors: [.white.opacity(dark ? 0.18 : 0.35), .clear],
                                              center: UnitPoint(x: 0.12, y: 0.0), startRadius: 0, endRadius: 140))
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
                                           .init(color: (tint ?? .white).opacity(dark ? 0.45 : 0.6), location: 1)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.2)
            }
            .overlay {
                shape.inset(by: 1.2).strokeBorder(.white.opacity(dark ? 0.06 : 0.25), lineWidth: 0.6)
            }
            .shadow(color: .black.opacity(dark ? 0.40 : 0.10), radius: 18, y: 8)
            .shadow(color: (tint ?? .black).opacity(dark ? 0.15 : 0.06), radius: 3, y: 1)
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
                .liquidRipple(prominent ? .white : color, cornerRadius: 40)
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

/// Njolla të mëdha ngjyrash, të turbulluara, që lëvizin ngadalë pas xhamit.
struct AmbientBlobs: View {
    let colors: [Color]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var move = false

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width, h = max(geometry.size.height, 600)
            ZStack {
                ForEach(colors.indices, id: \.self) { i in
                    let size = max(w, 400) * (0.75 - Double(i) * 0.08)
                    let start = CGPoint(x: w * [0.1, 0.9, 0.3, 0.75][i % 4], y: h * [0.05, 0.3, 0.7, 0.95][i % 4])
                    let end = CGPoint(x: w * [0.4, 0.6, 0.05, 1.0][i % 4], y: h * [0.2, 0.05, 0.85, 0.6][i % 4])
                    Circle()
                        .fill(colors[i].opacity(scheme == .dark ? 0.30 : 0.22))
                        .frame(width: size, height: size)
                        .position(move ? end : start)
                }
            }
            .blur(radius: 70)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) { move = true }
        }
    }
}

/// Kartat zbehen dhe zvogëlohen pak kur dalin nga ekrani gjatë lëvizjes (iOS 17+/macOS 14+), si në app-et e Apple-it.
struct ScrollFade: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            content.scrollTransition(.animated(.spring(response: 0.4, dampingFraction: 0.85))) { view, phase in
                view.opacity(phase.isIdentity ? 1 : 0.55)
                    .scaleEffect(phase.isIdentity ? 1 : 0.94)
                    .blur(radius: phase.isIdentity ? 0 : 1.5)
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

/// Valë uji që lëvizin ngadalë poshtë faqes (pas xhamit). Ndalen me «Reduce Motion».
struct LiquidWaves: View {
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        if reduceMotion {
            wave(phase: 0)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                wave(phase: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }
    private func wave(phase: Double) -> some View {
        Canvas { context, size in
            let layers: [(amp: Double, length: Double, speed: Double, height: Double, alpha: Double)] = [
                (14, 1.6, 0.35, 0.80, scheme == .dark ? 0.10 : 0.08),
                (10, 1.1, -0.5, 0.85, scheme == .dark ? 0.08 : 0.07),
                (7, 0.8, 0.7, 0.90, scheme == .dark ? 0.07 : 0.06),
            ]
            for layer in layers {
                var path = Path()
                let base = size.height * layer.height
                path.move(to: CGPoint(x: 0, y: size.height))
                stride(from: 0.0, through: size.width, by: 6).forEach { x in
                    let y = base + sin(x / size.width * .pi * 2 * layer.length + phase * layer.speed * 2) * layer.amp
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()
                context.fill(path, with: .linearGradient(Gradient(colors: [color.opacity(layer.alpha * 1.6), color.opacity(layer.alpha * 0.4)]),
                                                         startPoint: CGPoint(x: 0, y: base), endPoint: CGPoint(x: 0, y: size.height)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Valëzim uji nga pika ku prek (kartat dhe butonat prej xhami).
struct LiquidRipple: ViewModifier {
    var color: Color = .white
    var cornerRadius: CGFloat = 22
    @State private var ripples: [Ripple] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private struct Ripple: Identifiable { let id = UUID(); let point: CGPoint; var grown = false }

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geometry in
                    ZStack {
                        ForEach(ripples) { ripple in
                            let size = max(geometry.size.width, geometry.size.height) * 2.2
                            Circle()
                                .fill(RadialGradient(colors: [color.opacity(0.0), color.opacity(0.22), color.opacity(0.0)],
                                                     center: .center, startRadius: size * 0.25, endRadius: size * 0.5))
                                .frame(width: size, height: size)
                                .scaleEffect(ripple.grown ? 1 : 0.02)
                                .opacity(ripple.grown ? 0 : 1)
                                .position(ripple.point)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
                .allowsHitTesting(false)
            }
            .simultaneousGesture(SpatialTapGesture().onEnded { value in
                guard !reduceMotion else { return }
                let ripple = Ripple(point: value.location)
                ripples.append(ripple)
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.7)) {
                        if let index = ripples.firstIndex(where: { $0.id == ripple.id }) { ripples[index].grown = true }
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { ripples.removeAll { $0.id == ripple.id } }
            })
    }
}

extension View {
    func liquidRipple(_ color: Color = .white, cornerRadius: CGFloat = 22) -> some View {
        modifier(LiquidRipple(color: color, cornerRadius: cornerRadius))
    }
}

/// Kalimi «si lëng» midis faqeve: zbehje, turbullim i lehtë, pak zmadhim dhe rrëshqitje.
struct LiquidTransitionModifier: ViewModifier {
    let progress: Double
    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .blur(radius: (1 - progress) * 10)
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
