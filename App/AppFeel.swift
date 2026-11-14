import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// Ndjesia kur përdor app-in (kërkesa e Juri-t): dridhje të lehta, animacione, konfeti, butona që «shtypen»
// dhe prezantimi në hapjen e parë.

/// Dridhjet e lehta të telefonit. Në Mac përdor trackpad-in kur ka; në pajisjet e tjera nuk bën asgjë.
enum Haptics {
    static let enabledKey = "haptics.enabled.v1"
    private static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    /// Përgjigje e saktë.
    static func success() { notify(success: true) }
    /// Përgjigje e gabuar.
    static func error() { notify(success: false) }
    /// Prekje e lehtë (zgjedhje, kalim faqeje).
    static func tap() {
        guard enabled else { return }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #endif
    }
    /// «Klik» i lehtë kur lëviz rrëshqitësin e laboratorit.
    static func selection() {
        guard enabled else { return }
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
    /// Festim: test i mbaruar mirë.
    static func celebrate() {
        guard enabled else { return }
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { generator.impactOccurred(intensity: 0.7) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        #endif
    }
    private static func notify(success: Bool) {
        guard enabled else { return }
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(success ? .success : .error)
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(success ? .levelChange : .generic, performanceTime: .now)
        #endif
    }
}

/// Butonat e kartave «shtypen» pak kur i prek, si në app-et e iPhone-it.
struct SpringyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay { PressRipple(pressed: configuration.isPressed, color: .lagoon) }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == SpringyButtonStyle {
    static var springy: SpringyButtonStyle { SpringyButtonStyle() }
}

/// Lëkundje anash (për përgjigje të gabuar).
struct Shake: GeometryEffect {
    var travel: CGFloat = 8
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(animatableData * .pi * 4), y: 0))
    }
}

/// Shfaqja e kartave një nga një kur hapet faqja.
struct AppearIn: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8).delay(min(Double(index) * 0.05, 0.4))) { shown = true }
            }
    }
}

extension View {
    func appearIn(_ index: Int) -> some View { modifier(AppearIn(index: index)) }

    /// Konfeti mbi pamjen kur `active` bëhet true.
    func confetti(_ active: Bool, colors: [Color] = ConfettiView.defaultColors) -> some View {
        overlay { if active { ConfettiView(colors: colors).allowsHitTesting(false) } }
    }
}

/// Konfeti që bien nga lart për rreth 3 sekonda. Me «Reduce Motion» shfaqet vetëm një yll i qetë.
struct ConfettiView: View {
    static let defaultColors: [Color] = [.sun, .pink, .orange, .green, .blue, .purple]
    var colors: [Color] = defaultColors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private struct Piece { let x, speed, spin, size, delay, sway: Double; let color: Int; let round: Bool }
    @State private var pieces: [Piece] = (0..<90).map { i in
        var g = SystemRandomNumberGenerator()
        return Piece(x: Double.random(in: 0...1, using: &g), speed: Double.random(in: 0.35...0.7, using: &g),
                     spin: Double.random(in: -6...6, using: &g), size: Double.random(in: 6...11, using: &g),
                     delay: Double.random(in: 0...0.6, using: &g), sway: Double.random(in: 10...40, using: &g),
                     color: i, round: i % 3 == 0)
    }

    var body: some View {
        if reduceMotion {
            Image(systemName: "star.fill").font(.system(size: 60)).foregroundStyle(Color.sun)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(.top, 40)
                .accessibilityHidden(true)
        } else {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let t = timeline.date.timeIntervalSince(start)
                    for piece in pieces {
                        let life = t - piece.delay
                        guard life > 0 else { continue }
                        let y = -20 + life * piece.speed * size.height
                        guard y < size.height + 20 else { continue }
                        let x = piece.x * size.width + sin(life * 3 + piece.spin) * piece.sway
                        var c = context
                        c.translateBy(x: x, y: y)
                        c.rotate(by: .radians(life * piece.spin))
                        c.opacity = max(0, min(1, 3.2 - life))
                        let rect = CGRect(x: -piece.size / 2, y: -piece.size / 4, width: piece.size, height: piece.round ? piece.size : piece.size / 2)
                        let shape = piece.round ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1.5)
                        c.fill(shape, with: .color(colors[piece.color % colors.count]))
                    }
                }
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }
}

/// Karta e rezultatit pas kontrollit të përgjigjes: hyn me animacion; e gabuara lëkundet.
struct AnswerBanner: View {
    let correct: Bool
    let heading: String
    let text: String
    @State private var pop = false
    @State private var shake: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title).foregroundStyle(correct ? Color.green : Color.orange)
                    .scaleEffect(pop ? 1 : 0.3)
                Text(heading).font(.title3.bold())
            }
            Text(text)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background((correct ? Color.green : Color.orange).opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke((correct ? Color.green : Color.orange).opacity(0.5), lineWidth: 1.5))
        .modifier(Shake(animatableData: shake))
        .transition(.scale(scale: 0.92).combined(with: .opacity))
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { pop = true }
            if !correct { withAnimation(.linear(duration: 0.4)) { shake = 1 } }
        }
    }
}

// MARK: - Prezantimi në hapjen e parë

struct Onboarding: View {
    static let doneKey = "onboarding.done.v1"
    let finish: () -> Void
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Slide { let symbol: String; let title: String; let text: String; let colors: [Color]; let subject: Subject? }
    private let slides: [Slide] = [
        Slide(symbol: "sparkles", title: "Mirë se erdhe në BrainSpark",
              text: "Mësimet, ushtrimet dhe laboratorët e shkollës Don Bosko, në një vend. Punojnë edhe pa internet.",
              colors: [Color(red: 0.32, green: 0.22, blue: 0.74), Color(red: 0.08, green: 0.07, blue: 0.19)], subject: nil),
        Slide(symbol: "square.grid.2x2.fill", title: "Çdo lëndë me botën e vet",
              text: "Matematika, Fizika, Kimia dhe Biologjia kanë ngjyrat dhe simbolet e tyre. Mësime sipas klasës, kuize, lojëra dhe eksperimente.",
              colors: [Subject.math.deep, Subject.physics.deep], subject: .math),
        Slide(symbol: "bubble.left.and.text.bubble.right.fill", title: "Bosko AI të ndihmon",
              text: "Pyet me shkrim, me zë ose me foto të ushtrimit. Ndize «Vetëm sugjerime» kur do ta zgjidhësh vetë, hap pas hapi.",
              colors: [Subject.chemistry.color, Subject.chemistry.deep], subject: .chemistry),
        Slide(symbol: "bell.badge.fill", title: "Mos humb asnjë orë",
              text: "Orari i klasës, testet dhe detyrat të vijnë si njoftime. Ndiq përparimin dhe ditët radhazi që mëson. 🔥",
              colors: [Subject.biology.color, Subject.biology.deep], subject: .biology),
    ]

    var body: some View {
        let slide = slides[page]
        ZStack {
            LinearGradient(colors: slide.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: page)
            if let subject = slide.subject {
                GlyphField(subject: subject, opacity: 0.16, tint: .white).ignoresSafeArea()
                    .id(page).transition(.opacity)
            }
            VStack(spacing: 24) {
                HStack {
                    Spacer()
                    if page < slides.count - 1 { Button("Kapërce") { done() }.foregroundStyle(.white.opacity(0.85)) }
                }
                Spacer()
                Group {
                    if page == 0 { BrainSparkLogo(size: 150) }
                    else {
                        Image(systemName: slide.symbol)
                            .font(.system(size: 84, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                    .id("icon\(page)")
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.5).combined(with: .opacity))
                VStack(spacing: 12) {
                    Text(slide.title).font(.system(.largeTitle, design: .rounded).weight(.black)).multilineTextAlignment(.center)
                    Text(slide.text).font(.title3).multilineTextAlignment(.center).opacity(0.92)
                }
                .foregroundStyle(.white).frame(maxWidth: 520)
                .id("text\(page)")
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                Spacer()
                HStack(spacing: 8) {
                    ForEach(slides.indices, id: \.self) { i in
                        Capsule().fill(.white.opacity(i == page ? 1 : 0.4)).frame(width: i == page ? 24 : 8, height: 8)
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: page)
                .accessibilityElement().accessibilityLabel("Faqja \(page + 1) nga \(slides.count)")
                Button { next() } label: {
                    Text(page == slides.count - 1 ? "Fillo" : "Vazhdo")
                        .font(.headline).frame(maxWidth: 360).padding(.vertical, 14)
                        .background(.white, in: Capsule()).foregroundStyle(slide.colors.last ?? .black)
                }
                .buttonStyle(.springy)
            }
            .padding(28)
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            if value.translation.width < -40 { next() }
            else if value.translation.width > 40 && page > 0 { go(page - 1) }
        })
    }

    private func next() { if page < slides.count - 1 { go(page + 1) } else { done() } }
    private func go(_ index: Int) {
        Haptics.tap()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { page = index }
    }
    private func done() { Haptics.success(); finish() }
}


/// Logoja e BrainSpark (e njëjta pamje si ikona: atom xhami gjysmë në ujë), që noton lehtë lart e poshtë.
struct BrainSparkLogo: View {
    var size: CGFloat = 120
    @State private var bob = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Image("BrainSparkLogo").resizable().scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.8), .white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2))
            .shadow(color: Color(red: 0.55, green: 0.3, blue: 0.95).opacity(0.4), radius: size * 0.15, y: size * 0.08)
            .offset(y: bob ? -size * 0.03 : size * 0.03)
            .accessibilityLabel("BrainSpark")
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { bob = true }
            }
    }
}
