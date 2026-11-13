import SwiftUI

struct LabGameLinks: View {
    let subject: Subject
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
            gameCard("🧠", "Memoria shkencore", "Kthe kartat dhe gjej çiftet sa më shpejt", game: "memory." + subject.rawValue, unit: "prova", index: 0) { ScienceMemory(subject: subject) }
            gameCard("🔮", "Çfarë ndodh më pas?", "3 jetë, seri 🔥 dhe pikë bonus", game: "prediction." + subject.rawValue, unit: "pikë", index: 1) { PredictionGame(subject: subject) }
            gameCard("🔐", "Misioni me 3 çelësa", "Zgjidh enigmat dhe hap derën e laboratorit", game: "rescue." + subject.rawValue, unit: "gabime", index: 2) { ScienceRescue(subject: subject) }
        }
    }
    private func gameCard<Destination: View>(_ emoji: String, _ title: String, _ detail: String, game: String, unit: String, index: Int,
                                             @ViewBuilder destination: @escaping () -> Destination) -> some View {
        let best = UserDefaults.standard.object(forKey: "best." + game) as? Int
        return NavigationLink { destination().subjectStyle(subject) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(emoji).font(.system(size: 40))
                Text(title).font(.headline)
                Text(detail).font(.caption).opacity(0.85).multilineTextAlignment(.leading)
                if let best { Label("Rekordi: \(best) \(unit)", systemImage: "crown.fill").font(.caption2.bold()).foregroundStyle(Color.sun) }
            }
            .foregroundStyle(.white).padding(14)
            .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
            .background { ZStack { subject.gradient; GlyphField(subject: subject, opacity: 0.12, tint: .white) }.clipShape(RoundedRectangle(cornerRadius: 20)) }
            .shadow(color: subject.color.opacity(0.3), radius: 8, y: 5)
        }
        .buttonStyle(.springy)
        .appearIn(index)
    }
}

private struct MemoryCard: Identifiable {
    let id = UUID()
    let pair: Int
    let text: String
}

/// Memoria: kartat kthehen në 3D, çiftet e gjetura shkëlqejnë, gabimet lëkunden; matet koha dhe provat.
private struct ScienceMemory: View {
    @Environment(\.learnerLevel) private var learnerLevel
    @State private var level = SchoolLevel.basic
    @State private var pairs: [PairClue] = []
    let subject: Subject
    @State private var cards: [MemoryCard] = []
    @State private var opened: [UUID] = []
    @State private var matched: Set<Int> = []
    @State private var wrong: Set<UUID> = []
    @State private var moves = 0
    @State private var started = Date()
    @State private var finishedAt: Date?
    @State private var newRecord = false
    @State private var shake: CGFloat = 0
    private var game: String { "memory." + subject.rawValue }
    private var done: Bool { matched.count == pairs.count && !cards.isEmpty }

    var body: some View {
        Page {
            Text("🧠 Memoria shkencore").font(.system(.largeTitle, design: .rounded).weight(.black))
            Text("Lidh pyetjen me përgjigjen e saj.")
            if let learnerLevel { Text(learnerLevel.name).bold() } else { LevelPicker(level:$level).onChange(of:level) { _ in restart() } }
            HStack {
                Label("\(matched.count)/\(pairs.count)", systemImage: "square.on.square").font(.headline)
                Spacer()
                Label("\(moves) prova", systemImage: "hand.tap").font(.headline).numericTransition()
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = Int((finishedAt ?? context.date).timeIntervalSince(started))
                    Label(String(format: "%d:%02d", seconds / 60, seconds % 60), systemImage: "timer").font(.headline.monospacedDigit())
                }
            }
            .padding(12).background(subject.color.opacity(0.1), in: Capsule())
            .animation(.spring(), value: moves)
            if done {
                GameOverCard(title: "🏆 I gjete të gjitha!", score: moves, unit: "prova",
                             best: BestScores.best(game), newRecord: newRecord, stars: moves <= pairs.count + 2 ? 3 : moves <= pairs.count * 2 ? 2 : 1,
                             color: subject.color) {
                    Button("Luaj përsëri") { withAnimation(.spring()) { restart() } }.buttonStyle(.liquidProminent)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                ForEach(cards) { card in
                    let isMatched = matched.contains(card.pair)
                    let visible = opened.contains(card.id) || isMatched
                    Button { pick(card) } label: {
                        FlipCard(flipped: visible) {
                            Text(card.text).font(.callout.bold()).multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: 96).padding(8)
                                .foregroundStyle(Color.ink)
                                .background(isMatched ? Color.green.opacity(0.25) : Color.card, in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(isMatched ? Color.green : subject.color, lineWidth: 2))
                        } back: {
                            ZStack {
                                subject.gradient
                                Image(systemName: subject.icon).font(.system(size: 34, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                            }
                            .frame(maxWidth: .infinity, minHeight: 96).padding(8)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .scaleEffect(isMatched ? 0.94 : 1)
                        .modifier(Shake(animatableData: wrong.contains(card.id) ? shake : 0))
                        .shadow(color: isMatched ? Color.green.opacity(0.5) : .clear, radius: 8)
                    }.buttonStyle(.plain)
                    .disabled(visible || opened.count == 2)
                    .accessibilityLabel(visible ? card.text : "Kartë e mbuluar")
                }
            }
            Button("Përziej dhe rifillo") { withAnimation(.spring()) { restart() } }.buttonStyle(.liquid)
        }.onAppear { if cards.isEmpty { restart() } }
        .task(id: opened) {
            guard opened.count == 2 else { return }
            do { try await Task.sleep(nanoseconds: 900_000_000) }
            catch { return }
            withAnimation { opened = []; wrong = [] }
        }
    }
    private func pick(_ card: MemoryCard) {
        guard opened.count < 2, !matched.contains(card.pair), !opened.contains(card.id) else { return }
        Haptics.tap()
        if let firstID = opened.first, let first = cards.first(where: { $0.id == firstID }) {
            moves += 1
            if first.pair == card.pair {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) { _ = matched.insert(card.pair) }
                opened = []
                Haptics.success()
                if matched.count == pairs.count {
                    finishedAt = Date()
                    newRecord = BestScores.submit(game, score: moves, lowerIsBetter: true)
                }
            } else {
                opened.append(card.id)
                wrong = [firstID, card.id]
                shake = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { withAnimation(.linear(duration: 0.4)) { shake = 1 } }
                Haptics.error()
            }
        } else { opened = [card.id] }
    }
    private func restart() {
        pairs = LevelGameBank.pairs(subject:subject,level:learnerLevel ?? level)
        cards = pairs.enumerated().flatMap { index, pair in
            [MemoryCard(pair:index,text:pair.left), MemoryCard(pair:index,text:pair.right)]
        }.shuffled()
        opened = []; matched = []; wrong = []; moves = 0; started = Date(); finishedAt = nil; newRecord = false
    }
}

/// Misioni me 3 çelësa: çdo zgjidhje e saktë hap një dry me animacion; në fund dera e laboratorit hapet.
private struct ScienceRescue: View {
    let subject: Subject
    @Environment(\.learnerLevel) private var learnerLevel
    @State private var level = SchoolLevel.basic
    @State private var deck: [Exercise] = []
    @State private var stage = 0
    @State private var misses = 0
    @State private var round = UUID()
    @State private var newRecord = false
    private var game: String { "rescue." + subject.rawValue }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            if deck.isEmpty {
                Page {
                    Text("🔐 Misioni me 3 çelësa").font(.system(.largeTitle, design: .rounded).weight(.black))
                    Image(systemName: "door.left.hand.closed").font(.system(size: 90)).foregroundStyle(subject.gradient)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                    Text("Laboratori hapet me tri zgjidhje. Pas një gabimi merr shpjegimin dhe mund ta provosh përsëri.")
                    if let learnerLevel { Text(learnerLevel.name).bold() }
                    else { LevelPicker(level:$level) }
                    Button("Nis misionin") {
                        withAnimation(.spring()) {
                            deck = Array(Exercise.all.filter { $0.subject == subject.rawValue && $0.level == (learnerLevel ?? level).rawValue }.shuffled().prefix(3))
                            stage = 0; misses = 0; round = UUID(); newRecord = false
                        }
                    }.buttonStyle(.liquidProminent)
                }
            } else if stage == deck.count {
                Page {
                    DoorOpening(color: subject.color)
                    GameOverCard(title: "🔓 Laboratori u hap!", score: misses, unit: "gabime", best: BestScores.best(game), newRecord: newRecord,
                                 stars: misses == 0 ? 3 : misses <= 2 ? 2 : 1, color: subject.color) {
                        Button("Një mision tjetër") { withAnimation(.spring()) { deck = [] } }.buttonStyle(.liquidProminent)
                    }
                }
            } else {
                HStack(spacing: 14) {
                    ForEach(0..<3, id: \.self) { key in
                        Image(systemName:key < stage ? "key.fill" : "lock.fill")
                            .font(.title).foregroundStyle(key < stage ? Color.orange : Color.gray)
                            .rotationEffect(.degrees(key < stage ? -45 : 0))
                            .scaleEffect(key < stage ? 1.15 : 1)
                            .animation(.spring(response: 0.45, dampingFraction: 0.45), value: stage)
                    }
                    Text("\(stage)/3 çelësa").bold()
                    Spacer()
                    if misses > 0 { Label("\(misses)", systemImage: "arrow.counterclockwise").foregroundStyle(.secondary) }
                }.padding(.horizontal).padding(.top, 8)
                let item = deck[stage]
                ExercisePlayer(item:item,advance:{ correct in
                    guard stage < deck.count, deck[stage].id == item.id else { return }
                    withAnimation(.spring()) {
                        if correct { stage += 1 } else { misses += 1 }
                        round = UUID()
                    }
                    if stage == deck.count { newRecord = BestScores.submit(game, score: misses, lowerIsBetter: true) }
                }).id(round)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            }
        }.navigationTitle(subject.rawValue)
    }
}

/// Dera që hapet (animacion i shkurtër në fund të misionit).
struct DoorOpening: View {
    let color: Color
    @State private var open = false
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(LinearGradient(colors: [.yellow.opacity(0.9), .white], startPoint: .bottom, endPoint: .top))
                .frame(width: 110, height: 170)
                .opacity(open ? 1 : 0.3)
            RoundedRectangle(cornerRadius: 8).fill(color)
                .overlay(alignment: .trailing) { Circle().fill(Color.sun).frame(width: 12).padding(10) }
                .frame(width: 110, height: 170)
                .rotation3DEffect(.degrees(open ? -75 : 0), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.5)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .onAppear { withAnimation(.spring(response: 0.9, dampingFraction: 0.7).delay(0.2)) { open = true } }
        .accessibilityHidden(true)
    }
}

/// «Çfarë ndodh më pas?»: 3 jetë, seri me bonus, «+pikë» që fluturojnë dhe rekord.
private struct PredictionGame: View {
    @Environment(\.learnerLevel) private var learnerLevel
    @State private var level = SchoolLevel.basic
    @AppStorage("gamePredictionRecent.v7") private var recent = ""
    let subject: Subject
    @State private var deck: [Question] = []
    @State private var index = 0
    @State private var chosen: Int?
    @State private var score = 0
    @State private var streak = 0
    @State private var lives = 3
    @State private var gained = 0
    @State private var popTrigger = 0
    @State private var newRecord = false
    private var game: String { "prediction." + subject.rawValue }
    private var over: Bool { !deck.isEmpty && (index >= deck.count || lives == 0) }

    var body: some View {
        Page {
            Text("🔮 Çfarë ndodh më pas?").font(.system(.largeTitle, design: .rounded).weight(.black))
            if deck.isEmpty {
                if let learnerLevel { Text(learnerLevel.name).bold() } else { LevelPicker(level:$level) }
                Text("10 pyetje, 3 jetë. Çdo përgjigje e saktë radhazi jep më shumë pikë. Rekordi: \(BestScores.best(game)) pikë.")
                Button("Fillo sfidën") { withAnimation(.spring()) { restart() } }.buttonStyle(.liquidProminent)
            } else if over {
                GameOverCard(title: lives == 0 ? "💥 Mbaruan jetët" : "🌟 Sfida mbaroi", score: score, best: BestScores.best(game),
                             newRecord: newRecord, celebrate: lives > 0 || newRecord, color: subject.color) {
                    Button("Luaj përsëri") { withAnimation(.spring()) { restart() } }.buttonStyle(.liquidProminent)
                }
            } else {
                let question = deck[index]
                ScoreHUD(score: score, streak: streak, lives: lives, color: subject.color)
                    .floatingPoints("+\(gained)", trigger: popTrigger)
                ProgressView(value: Double(index), total: Double(deck.count)).tint(subject.color)
                    .animation(.easeInOut, value: index)
                VStack(alignment: .leading, spacing: 12) {
                    Text(question.prompt).font(.title2.bold())
                    ForEach(question.options.indices,id: \.self) { option in
                        Button {
                            guard chosen == nil else { return }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) { chosen = option }
                            if option == question.correct {
                                streak += 1
                                gained = 10 + min(streak-1,5)*2
                                withAnimation(.easeOut(duration: 0.5)) { score += gained }
                                popTrigger += 1
                                Haptics.success()
                            } else {
                                streak = 0
                                withAnimation(.spring()) { lives -= 1 }
                                Haptics.error()
                            }
                        } label: {
                            HStack {
                                Text(question.options[option])
                                Spacer()
                                if chosen != nil && option == question.correct { Image(systemName:"checkmark.circle.fill").foregroundStyle(.green).transition(.scale) }
                                if chosen == option && option != question.correct { Image(systemName:"xmark.circle.fill").foregroundStyle(.orange).transition(.scale) }
                            }.padding().frame(maxWidth:.infinity,alignment:.leading)
                            .background(background(option, question), in:RoundedRectangle(cornerRadius:14))
                            .overlay(RoundedRectangle(cornerRadius:14).stroke(chosen == option ? subject.color : .clear, lineWidth: 2))
                        }.buttonStyle(.springy).disabled(chosen != nil)
                    }
                    if let chosen {
                        AnswerBanner(correct: chosen == question.correct, heading: chosen == question.correct ? "E parashikove!" : "Zbulo arsyen", text: question.why)
                        Button(index+1 == deck.count || lives == 0 ? "Shiko rezultatin" : "Sfida tjetër") { next() }.buttonStyle(.liquidProminent)
                    }
                }
                .id(index)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            }
        }
    }
    private func background(_ option: Int, _ question: Question) -> Color {
        guard let chosen else { return Color.card }
        if option == question.correct { return Color.green.opacity(0.2) }
        if option == chosen { return Color.orange.opacity(0.2) }
        return Color.card
    }
    private func next() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            if lives == 0 { index = deck.count } else { index += 1 }
            chosen = nil
        }
        if over { newRecord = BestScores.submit(game, score: score) }
    }
    private func restart() {
        let seen = Set(recent.split(separator:"|").map(String.init))
        let pool = StudyLesson.matching(subject:subject,level:learnerLevel ?? level)
        let fresh = pool.filter { !seen.contains($0.id) }.shuffled()
        let rest = pool.filter { seen.contains($0.id) }.shuffled()
        let selected = Array((fresh + rest).prefix(10))
        deck = selected.map { $0.check.question.shuffledOptions() }
        recent = selected.map(\.id).joined(separator:"|")
        index = 0; chosen = nil; score = 0; streak = 0; lives = 3; newRecord = false
    }
}

