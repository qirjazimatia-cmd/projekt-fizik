import SwiftUI

// Mjete të përbashkëta për lojërat dhe laboratorët (Juri): pikë që numërohen, zemra, seri 🔥, «+10» që fluturon,
// karta që kthehen, rekorde dhe ekrani i fundit i lojës.

/// Numër që numërohet deri te vlera e re (në vend që të ndryshojë menjëherë).
struct CountingText: View, Animatable {
    var value: Double
    var format: (Int) -> String = { "\($0)" }
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    init(_ value: Int, format: @escaping (Int) -> String = { "\($0)" }) {
        self.value = Double(value); self.format = format
    }
    var body: some View {
        Text(format(Int(value.rounded()))).monospacedDigit()
    }
}

/// Rekordet e lojërave, në këtë pajisje/llogari.
enum BestScores {
    private static func key(_ game: String) -> String { "best." + game }
    static func best(_ game: String) -> Int { UserDefaults.standard.integer(forKey: key(game)) }
    /// Ruan rezultatin; kthen true nëse është rekord i ri.
    @discardableResult
    static func submit(_ game: String, score: Int, lowerIsBetter: Bool = false) -> Bool {
        let old = UserDefaults.standard.object(forKey: key(game)) as? Int
        let better = old.map { lowerIsBetter ? score < $0 : score > $0 } ?? true
        if better { UserDefaults.standard.set(score, forKey: key(game)) }
        return better && (old != nil || score > 0)
    }
}

/// Shiriti sipër lojës: pikët, seria dhe jetët.
struct ScoreHUD: View {
    let score: Int
    var streak: Int = 0
    var lives: Int? = nil
    var maxLives: Int = 3
    var color: Color = .lagoon
    @State private var bump = false

    var body: some View {
        HStack(spacing: 14) {
            Label { CountingText(score).font(.title3.bold()) } icon: { Image(systemName: "star.fill").foregroundStyle(Color.sun) }
                .animation(.easeOut(duration: 0.5), value: score)
                .scaleEffect(bump ? 1.18 : 1)
            if streak > 1 {
                HStack(spacing: 2) {
                    FlameIcon()
                    Text("×\(streak)").font(.headline.bold()).monospacedDigit()
                }
                .foregroundStyle(.orange)
                .transition(.scale.combined(with: .opacity))
            }
            Spacer()
            if let lives {
                HStack(spacing: 3) {
                    ForEach(0..<maxLives, id: \.self) { i in
                        Image(systemName: i < lives ? "heart.fill" : "heart")
                            .foregroundStyle(i < lives ? Color.red : Color.secondary)
                            .scaleEffect(i < lives ? 1 : 0.8)
                            .animation(.spring(response: 0.3, dampingFraction: 0.4), value: lives)
                    }
                }
                .accessibilityElement().accessibilityLabel("\(lives) jetë")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(color.opacity(0.12), in: Capsule())
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: streak)
        .onChange(of: score) { _ in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.4)) { bump = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { withAnimation(.spring()) { bump = false } }
        }
    }
}

/// Flakë që pulson (seria e përgjigjeve / ditëve).
struct FlameIcon: View {
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Image(systemName: "flame.fill")
            .foregroundStyle(LinearGradient(colors: [.yellow, .orange, .red], startPoint: .top, endPoint: .bottom))
            .scaleEffect(pulse ? 1.15 : 0.92, anchor: .bottom)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { pulse = true }
            }
    }
}

/// «+10» që ngrihet dhe zhduket sa herë ndryshon `trigger`.
struct FloatingPoints: ViewModifier {
    let text: String
    let trigger: Int
    var color: Color = .green
    @State private var shown = false
    @State private var lastTrigger = 0
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            Text(text).font(.title2.bold()).foregroundStyle(color)
                .shadow(color: color.opacity(0.4), radius: 6)
                .offset(y: shown ? -44 : 0)
                .opacity(shown ? 0 : (lastTrigger == 0 ? 0 : 1))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onChange(of: trigger) { value in
            lastTrigger = value
            shown = false
            DispatchQueue.main.async { withAnimation(.easeOut(duration: 0.9)) { shown = true } }
        }
    }
}

extension View {
    func floatingPoints(_ text: String, trigger: Int, color: Color = .green) -> some View {
        modifier(FloatingPoints(text: text, trigger: trigger, color: color))
    }
}

/// Kartë që kthehet në 3D (loja e memories).
struct FlipCard<Front: View, Back: View>: View {
    let flipped: Bool
    @ViewBuilder let front: () -> Front
    @ViewBuilder let back: () -> Back
    var body: some View {
        ZStack {
            back().opacity(flipped ? 0 : 1)
            front().opacity(flipped ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: flipped)
    }
}

/// Yjet e misionit (1–3), që hyjnë një nga një.
struct StarRow: View {
    let stars: Int
    var size: CGFloat = 34
    /// I vegjël (në lista) shfaqen menjëherë, pa animacion dhe pa dridhje.
    var animated: Bool { size >= 24 }
    @State private var shown = 0
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: i < stars ? "star.fill" : "star")
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(i < stars ? Color.sun : Color.secondary.opacity(0.4))
                    .scaleEffect(i < shown ? 1 : 0.2)
                    .rotationEffect(.degrees(i < shown ? 0 : -90))
            }
        }
        .accessibilityElement().accessibilityLabel("\(stars) nga 3 yje")
        .onAppear {
            guard animated else { shown = 3; return }
            for i in 0..<3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 + Double(i) * 0.18) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) { shown = i + 1 }
                    if i < stars { Haptics.tap() }
                }
            }
        }
    }
}

/// Ekrani i fundit i lojës: titull, pikë që numërohen, rekord, yje dhe konfeti kur shkon mirë.
struct GameOverCard<Actions: View>: View {
    let title: String
    let score: Int
    var unit: String = "pikë"
    var best: Int? = nil
    var newRecord = false
    var stars: Int? = nil
    var celebrate = true
    var color: Color = .lagoon
    @ViewBuilder let actions: () -> Actions
    @State private var counted = 0

    var body: some View {
        VStack(spacing: 14) {
            Text(title).font(.system(.largeTitle, design: .rounded).weight(.black)).multilineTextAlignment(.center)
            if let stars { StarRow(stars: stars) }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                CountingText(counted).font(.system(size: 54, weight: .black, design: .rounded)).foregroundStyle(color)
                Text(unit).font(.title3.bold()).foregroundStyle(.secondary)
            }
            if newRecord {
                Label("Rekord i ri!", systemImage: "crown.fill")
                    .font(.headline).padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Color.sun, in: Capsule()).foregroundStyle(Color.midnight)
                    .transition(.scale.combined(with: .opacity))
            } else if let best {
                Text("Rekordi yt: \(best) \(unit)").font(.subheadline).foregroundStyle(.secondary)
            }
            actions()
        }
        .padding(24).frame(maxWidth: .infinity)
        .glass(cornerRadius: 24)
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(color.opacity(0.3), lineWidth: 2))
        .shadow(color: color.opacity(0.2), radius: 16, y: 8)
        .confetti(celebrate, colors: [color, .sun, .white, .pink])
        .transition(.scale(scale: 0.85).combined(with: .opacity))
        .onAppear {
            if celebrate { Haptics.celebrate() }
            withAnimation(.easeOut(duration: 1.0)) { counted = score }
        }
    }
}

/// Tre pika që kërcejnë: «Bosko po mendon…».
struct TypingDots: View {
    @State private var phase = false
    var color: Color = .secondary
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(color).frame(width: 8, height: 8)
                    .offset(y: phase ? -5 : 3)
                    .animation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true).delay(Double(i) * 0.15), value: phase)
            }
        }
        .onAppear { phase = true }
        .accessibilityHidden(true)
    }
}

/// Kur një vlerë numerike në tekst ndryshon, shifrat rrotullohen (iOS 17+/macOS 14+); më parë zbehet butë.
struct NumericTextTransition: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            content.contentTransition(.numericText())
        } else {
            content.transition(.opacity)
        }
    }
}

extension View {
    func numericTransition() -> some View { modifier(NumericTextTransition()) }
}
