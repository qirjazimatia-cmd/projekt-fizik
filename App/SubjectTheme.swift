import SwiftUI

// Pamja sipas lëndës (kërkesa e Juri-t): kur hyn te Matematika, Fizika, Kimia ose Biologjia, faqet marrin ngjyrat,
// sfondin dhe simbolet e asaj lënde, që lëndët të mos duken njësoj.

private struct SubjectThemeKey: EnvironmentKey { static let defaultValue: Subject? = nil }

extension EnvironmentValues {
    /// Lënda e faqes aktuale. `nil` jashtë lëndëve (Krye, Profili, Eventet...).
    var subjectTheme: Subject? {
        get { self[SubjectThemeKey.self] }
        set { self[SubjectThemeKey.self] = newValue }
    }
}

extension View {
    /// I jep kësaj pjese të app-it ngjyrat dhe sfondin e lëndës.
    func subjectStyle(_ subject: Subject) -> some View {
        environment(\.subjectTheme, subject).tint(subject.color)
    }
}

/// Simbol dekorativ në sfond: tekst (π, H₂O) ose ikonë SF Symbols.
enum SubjectGlyph: Hashable {
    case text(String)
    case symbol(String)
}

extension Subject {
    /// Ngjyra kryesore (më e ndritshme në pamjen e errët, që të lexohet mirë).
    var color: Color {
        switch self {
        case .physics: return Color(light: Color(red: 0.13, green: 0.32, blue: 0.86), dark: Color(red: 0.45, green: 0.64, blue: 1.0))
        case .math: return Color(light: Color(red: 0.62, green: 0.12, blue: 0.47), dark: Color(red: 0.96, green: 0.48, blue: 0.80))
        case .chemistry: return Color(light: Color(red: 0.78, green: 0.29, blue: 0.05), dark: Color(red: 1.0, green: 0.58, blue: 0.32))
        case .biology: return Color(light: Color(red: 0.11, green: 0.50, blue: 0.24), dark: Color(red: 0.42, green: 0.86, blue: 0.50))
        }
    }

    /// Ngjyra e dytë e gradientit të banerit.
    var deep: Color {
        switch self {
        case .physics: return Color(red: 0.05, green: 0.10, blue: 0.40)
        case .math: return Color(red: 0.33, green: 0.05, blue: 0.42)
        case .chemistry: return Color(red: 0.55, green: 0.08, blue: 0.10)
        case .biology: return Color(red: 0.02, green: 0.30, blue: 0.30)
        }
    }

    /// Sfondi i faqeve të lëndës: një nuancë e lehtë e ngjyrës.
    var paper: Color {
        switch self {
        case .physics: return Color(light: Color(red: 0.93, green: 0.95, blue: 1.0), dark: Color(red: 0.04, green: 0.07, blue: 0.15))
        case .math: return Color(light: Color(red: 0.99, green: 0.93, blue: 0.97), dark: Color(red: 0.11, green: 0.05, blue: 0.10))
        case .chemistry: return Color(light: Color(red: 1.0, green: 0.95, blue: 0.91), dark: Color(red: 0.13, green: 0.07, blue: 0.04))
        case .biology: return Color(light: Color(red: 0.93, green: 0.98, blue: 0.93), dark: Color(red: 0.04, green: 0.10, blue: 0.06))
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [color, deep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Simbolet që shfaqen lehtë në sfond.
    var glyphs: [SubjectGlyph] {
        switch self {
        case .math: return [.text("π"), .text("∑"), .text("√x"), .text("x²"), .text("∞"), .text("÷"), .text("%"), .text("∫"), .text("△"), .text("±")]
        case .physics: return [.symbol("atom"), .symbol("bolt.fill"), .symbol("waveform"), .symbol("lightbulb.fill"), .symbol("speedometer"),
                               .symbol("sun.max.fill"), .text("F=ma"), .text("E"), .symbol("arrow.up.right"), .text("Ω")]
        case .chemistry: return [.text("H₂O"), .text("CO₂"), .text("NaCl"), .text("pH"), .symbol("testtube.2"), .symbol("flame.fill"),
                                 .symbol("drop.fill"), .symbol("hexagon"), .text("O₂"), .text("e⁻")]
        case .biology: return [.symbol("leaf.fill"), .symbol("heart.fill"), .symbol("eye.fill"), .symbol("ladybug.fill"), .symbol("hare.fill"),
                               .symbol("drop.fill"), .text("DNA"), .symbol("lungs.fill"), .symbol("allergens"), .text("🌱")]
        }
    }

    /// Një fjali e shkurtër që e dallon lëndën në baner.
    var motto: String {
        switch self {
        case .math: return "Numra, forma dhe logjikë"
        case .physics: return "Si lëviz dhe si funksionon bota"
        case .chemistry: return "Substancat dhe si ndryshojnë"
        case .biology: return "Jeta, nga qeliza te njeriu"
        }
    }
}

/// Sfondi i faqeve: brenda një lënde merr nuancën dhe simbolet e saj; jashtë lëndëve mbetet si më parë.
struct PageBackground: View {
    @Environment(\.subjectTheme) private var subject
    var body: some View {
        if let subject {
            ZStack {
                subject.paper
                GlyphField(subject: subject, opacity: 0.07)
            }
        } else {
            Color.paper
        }
    }
}

/// Simbole të shpërndara që lëvizin ngadalë (ndalen kur pajisja ka «Reduce Motion»).
struct GlyphField: View {
    let subject: Subject
    var opacity: Double = 0.07
    var tint: Color? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        GeometryReader { geometry in
            let glyphs = subject.glyphs
            let columns = max(3, Int(geometry.size.width / 120))
            let rows = max(3, Int(geometry.size.height / 140))
            ForEach(0..<(columns * rows), id: \.self) { index in
                let row = index / columns, column = index % columns
                let seed = Double((index * 37 + row * 11) % 97) / 97
                let x = (Double(column) + 0.25 + 0.5 * seed) / Double(columns) * geometry.size.width
                let y = (Double(row) + 0.2 + 0.6 * Double((index * 53) % 89) / 89) / Double(rows) * geometry.size.height
                glyphView(glyphs[index % glyphs.count], size: 22 + 18 * seed)
                    .rotationEffect(.degrees(-20 + 40 * seed + (drift ? 8 : 0)))
                    .offset(y: drift ? -6 + 12 * seed : 0)
                    .position(x: x, y: y)
            }
        }
        .foregroundStyle(tint ?? subject.color)
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) { drift = true }
        }
    }

    @ViewBuilder private func glyphView(_ glyph: SubjectGlyph, size: Double) -> some View {
        switch glyph {
        case .text(let text): Text(text).font(.system(size: size, weight: .heavy, design: .rounded))
        case .symbol(let name): Image(systemName: name).font(.system(size: size, weight: .semibold))
        }
    }
}
