import SwiftUI

struct LabGameLinks: View {
    let subject: Subject
    var body: some View {
        NavigationLink { ScienceMemory(subject: subject) } label: {
            Tile(icon: "brain.head.profile", title: "Memoria shkencore", detail: "Zbulo kartat dhe gjej 6 çifte")
        }
        NavigationLink { PredictionGame(subject: subject) } label: {
            Tile(icon: "sparkles", title: "Çfarë ndodh më pas?", detail: "Parashiko, zbulo dhe fito pikë")
        }
        NavigationLink { ScienceRescue(subject: subject) } label: {
            Tile(icon: "lock.open", title: "Misioni me 3 çelësa", detail: "Zgjidh enigmat e nivelit tënd dhe hape laboratorin")
        }
    }
}

private struct MemoryCard: Identifiable {
    let id = UUID()
    let pair: Int
    let text: String
}
private struct ScienceMemory: View {
    @Environment(\.learnerLevel) private var learnerLevel
    @State private var level = SchoolLevel.basic
    @State private var pairs: [PairClue] = []
    let subject: Subject
    @State private var cards: [MemoryCard] = []
    @State private var opened: [UUID] = []
    @State private var matched: Set<Int> = []
    @State private var moves = 0
    var body: some View {
        Page {
            Text("🧠 Memoria shkencore").font(.largeTitle.bold())
            Text("Lidh pyetjen me përgjigjen e saj.")
            if let learnerLevel { Text(learnerLevel.name) } else { LevelPicker(level:$level).onChange(of:level) { _ in restart() } }
            Text("\(matched.count)/\(pairs.count) çifte · \(moves) prova")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 10) {
                ForEach(cards) { card in
                    let visible = opened.contains(card.id) || matched.contains(card.pair)
                    Button { pick(card) } label: {
                        Text(visible ? card.text : "?")
                            .font(visible ? .callout.bold() : .largeTitle.bold())
                            .frame(maxWidth:.infinity,minHeight:90).padding(8)
                            .foregroundStyle(visible ? Color.midnight : Color.white)
                            .background(visible ? (matched.contains(card.pair) ? Color.green.opacity(0.3) : .white) : subject.color,
                                        in:RoundedRectangle(cornerRadius:16))
                    }.buttonStyle(.plain)
                    .disabled(visible || opened.count == 2)
                    .accessibilityLabel(visible ? card.text : "Kartë e mbuluar")
                }
            }
            if matched.count == pairs.count && !cards.isEmpty {
                Text("🏆 I gjete të gjitha çiftet me \(moves) prova!").font(.title2.bold())
            }
            Button("Përziej dhe rifillo") { restart() }.buttonStyle(.bordered)
        }.onAppear { if cards.isEmpty { restart() } }
        .task(id: opened) {
            guard opened.count == 2 else { return }
            do { try await Task.sleep(nanoseconds: 900_000_000) }
            catch { return }
            opened = []
        }
    }
    private func pick(_ card: MemoryCard) {
        guard opened.count < 2, !matched.contains(card.pair), !opened.contains(card.id) else { return }
        if let firstID = opened.first, let first = cards.first(where: { $0.id == firstID }) {
            moves += 1
            if first.pair == card.pair {
                matched.insert(card.pair); opened = []
            } else { opened.append(card.id) }
        } else { opened = [card.id] }
    }
    private func restart() {
        pairs = LevelGameBank.pairs(subject:subject,level:learnerLevel ?? level)
        cards = pairs.enumerated().flatMap { index, pair in
            [MemoryCard(pair:index,text:pair.left), MemoryCard(pair:index,text:pair.right)]
        }.shuffled()
        opened = []; matched = []; moves = 0
    }
}

private struct ScienceRescue: View {
    let subject: Subject
    @Environment(\.learnerLevel) private var learnerLevel
    @State private var level = SchoolLevel.basic
    @State private var deck: [Exercise] = []
    @State private var stage = 0
    @State private var misses = 0
    @State private var round = UUID()
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            if deck.isEmpty {
                Page {
                    Text("🔐 Misioni me 3 çelësa").font(.largeTitle.bold())
                    Text("Laboratori hapet me tri zgjidhje. Pas një gabimi merr shpjegimin dhe mund ta provosh përsëri.")
                    if let learnerLevel { Text(learnerLevel.name).bold() }
                    else { LevelPicker(level:$level) }
                    Button("Nis misionin") {
                        deck = Array(Exercise.all.filter { $0.subject == subject.rawValue && $0.level == (learnerLevel ?? level).rawValue }.shuffled().prefix(3))
                        stage = 0; misses = 0; round = UUID()
                    }.buttonStyle(.borderedProminent)
                }
            } else if stage == deck.count {
                Page {
                    Text("🔓 Laboratori u hap!").font(.largeTitle.bold())
                    Text("More të tre çelësat · \(misses) riprovime")
                    Button("Një mision tjetër") { deck = [] }.buttonStyle(.borderedProminent)
                }
            } else {
                HStack {
                    ForEach(0..<3, id: \.self) { key in
                        Image(systemName:key < stage ? "key.fill" : "lock.fill")
                            .font(.title).foregroundStyle(key < stage ? Color.orange : Color.gray)
                    }
                    Text("\(stage)/3 çelësa").bold()
                }.padding(.horizontal)
                let item = deck[stage]
                ExercisePlayer(item:item,advance:{ correct in
                    guard stage < deck.count, deck[stage].id == item.id else { return }
                    if correct { stage += 1 }
                    else { misses += 1 }
                    round = UUID()
                }).id(round)
            }
        }.navigationTitle(subject.rawValue)
    }
}

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
    var body: some View {
        Page {
            Text("🔮 Çfarë ndodh më pas?").font(.largeTitle.bold())
            if deck.isEmpty {
                if let learnerLevel { Text(learnerLevel.name) } else { LevelPicker(level:$level) }
                Text("Pyetje nga temat e nivelit të zgjedhur; alternativa dhe përzgjedhje të reja në çdo lojë.")
                Button("Fillo sfidën") { restart() }.buttonStyle(.borderedProminent)
            } else if index < deck.count {
                let question = deck[index]
                Text("\(index+1)/\(deck.count) · \(score) pikë · 🔥 \(streak) radhazi")
                Text(question.prompt).font(.title2.bold())
                ForEach(question.options.indices,id: \.self) { option in
                    Button {
                        guard chosen == nil else { return }
                        chosen = option
                        if option == question.correct { streak += 1; score += 10 + min(streak-1,5)*2 }
                        else { streak = 0 }
                    } label: {
                        HStack {
                            Text(question.options[option])
                            Spacer()
                            if chosen != nil && option == question.correct { Image(systemName:"checkmark.circle.fill") }
                        }.padding().frame(maxWidth:.infinity,alignment:.leading)
                        .background(chosen == option ? subject.color.opacity(0.2) : Color.card,in:RoundedRectangle(cornerRadius:14))
                    }.buttonStyle(.plain).disabled(chosen != nil)
                }
                if let chosen {
                    SectionText(heading:chosen == question.correct ? "E parashikove!" : "Zbulo arsyen",text:question.why)
                    Button(index+1 == deck.count ? "Shiko rezultatin" : "Sfida tjetër") {
                        index += 1; self.chosen = nil
                    }.buttonStyle(.borderedProminent)
                }
            } else if !deck.isEmpty {
                Text("🌟 \(score) pikë").font(.largeTitle.bold())
                Button("Luaj përsëri") { restart() }.buttonStyle(.borderedProminent)
            }
        }
    }
    private func restart() {
        let seen = Set(recent.split(separator:"|").map(String.init))
        let pool = StudyLesson.matching(subject:subject,level:learnerLevel ?? level)
        let fresh = pool.filter { !seen.contains($0.id) }.shuffled()
        let rest = pool.filter { seen.contains($0.id) }.shuffled()
        let selected = Array((fresh + rest).prefix(10))
        deck = selected.map { $0.check.question.shuffledOptions() }
        recent = selected.map(\.id).joined(separator:"|")
        index = 0; chosen = nil; score = 0; streak = 0
    }
}

