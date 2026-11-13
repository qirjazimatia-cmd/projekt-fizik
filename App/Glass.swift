import SwiftUI

// Pamja «xham» në stilin Liquid Glass të Apple-it (kërkesa e Juri-t).
// Në iOS 26 / macOS 26 përdor efektin e vërtetë `glassEffect`; në versionet më të vjetra një imitim me material
// të turbullt, shkëlqim në buzë dhe hije të butë. Pas xhamit lëvizin njolla ngjyrash, që xhami të duket i gjallë.

struct GlassBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    var tint: Color? = nil
    var interactive = false
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(interactive ? Glass.regular.tint(tint?.opacity(0.18)).interactive() : Glass.regular.tint(tint?.opacity(0.18)), in: shape)
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    if let tint { shape.fill(tint.opacity(0.10)) }
                    shape.fill(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.08 : 0.35), .clear],
                                              startPoint: .top, endPoint: .center))
                }
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.35 : 0.8), .white.opacity(0.05), (tint ?? .white).opacity(0.25)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
            .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.08), radius: 14, y: 6)
    }
}

extension View {
    /// Kartë xhami me kënde të rrumbullakëta.
    func glass(cornerRadius: CGFloat = 18, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassBackground(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), tint: tint, interactive: interactive))
    }
    /// Kapsulë xhami (butona, shirita).
    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassBackground(shape: Capsule(), tint: tint, interactive: interactive))
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
