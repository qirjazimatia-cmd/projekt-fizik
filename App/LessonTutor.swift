import Foundation

/// "Dija": asistenti i mësimeve. Flet natyrshëm, gjen temën te 600 mësimet dhe e zgjeron sipas kërkesës
/// (më thjesht, shembull hap pas hapi, pse, më shumë, gabimi, pyetje prove), jep ushtrime nga banka dhe i kontrollon,
/// llogarit shprehje, bën plan përgatitjeje dhe i përshtatet rolit (nxënës, prind, mësues).
/// Punon në pajisje, pa internet dhe pa model të shkarkuar. Nuk shpik përmbajtje: çdo shpjegim vjen nga mësimet.
/// Nuk varet nga SwiftUI, që testet ta provojnë drejtpërdrejt.
struct TutorLesson {
    let id, subject, title, introduction: String
    let sections: [(title: String, text: String)]
    let problem: String
    let steps: [String]
    let conclusion: String
    let pitfall: String
    let recap: [String]
    let checkPrompt: String
    let checkOptions: [String]
    let checkCorrect: Int
    let checkWhy: String
    var exerciseIDs: [String] = []
}

struct TutorExercise {
    let id, kind, prompt, unit, why, accuracy: String
    let answers, choices: [String]
    let tolerance: Double
}

enum TutorRole { case student, parent, teacher }

enum TutorIntent: Equatable {
    case greeting, howAreYou, thanks, whoAreYou, goodbye, struggle
    case simpler, example, nextStep, why, more, mistake, quiz, related
    case exercise, hint, reveal, plan, summary, teach, helpChild
    case topic
}

struct TutorReply: Equatable, Codable {
    var title: String? = nil
    var text: String
    var lessonID: String? = nil
    var suggestions: [String] = []
}

final class LessonTutor {
    static let name = "Dija"
    private let search: LessonSearch
    private let lessons: [String: TutorLesson]
    private let exercises: [String: TutorExercise]
    let role: TutorRole
    private(set) var current: TutorLesson?
    private var step = 0
    private var turn = 0
    private var exerciseTurn = 0
    private var discussed: [String] = []
    private var lastHits: [String] = []
    private enum Waiting { case none, check, exercise(TutorExercise, tries: Int) }
    private var waiting = Waiting.none

    static let topicSuggestions = ["Më thjesht", "Shembull", "Pse?", "Më jep një ushtrim", "Ku gabohet?", "Më pyet"]

    init(search: LessonSearch, lessons: [TutorLesson], exercises: [TutorExercise] = [], role: TutorRole = .student) {
        self.search = search
        self.lessons = Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
        self.exercises = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        self.role = role
    }

    // MARK: Kuptimi i mesazhit

    /// Fraza për çdo qëllim, të shkruara pa ë/ç dhe me shkronja të vogla. Renditja ka rëndësi: e para që përputhet fiton.
    private static let phrases: [(TutorIntent, [String])] = [
        (.struggle, ["e kam te veshtire", "eshte e veshtire", "me duket e veshtire", "nuk ia dal", "s ia dal", "jam merzitur", "jam i merzitur",
                     "jam e merzitur", "jam lodhur", "jam i lodhur", "jam e lodhur", "nuk po ia dal", "me vjen keq", "jam stresuar"]),
        (.howAreYou, ["si je", "si jeni", "si ja kalon", "si ia kalon", "si po ia kalon", "si po shkon", "cfare ben", "si kalon"]),
        (.whoAreYou, ["kush je", "cfare je", "cfare di", "cfare mund te besh", "si te perdor", "si funksionon ky", "si te quajne", "emri yt"]),
        (.thanks, ["faleminderit", "flm", "rrofsh", "merci", "thanks", "thank"]),
        (.goodbye, ["mirupafshim", "naten e mire", "shihemi", "bye"]),
        (.greeting, ["pershendetje", "tungjatjeta", "tung", "hello", "hi", "hey", "hej", "ciao", "cao", "mirdita", "miremengjes", "mirembrema", "c kemi", "ckemi", "alo"]),
        (.summary, ["permblidh biseden", "cfare folem", "cfare kemi folur", "permbledhje e bisedes", "cfare mesuam"]),
        (.plan, ["kam test", "kam provim", "kam kontrolle", "si te pergatitem", "si te mesoj", "plan pergatitje", "plan studimi", "me ndihmo te pergatitem"]),
        (.teach, ["si ta shpjegoj", "si t ua shpjegoj", "si ta jap", "plan mesimi", "ore mesimi", "si ta zhvilloj"]),
        (.helpChild, ["si ta ndihmoj", "si te ndihmoj", "femija im", "femijes", "djalin tim", "vajzen time", "djali im", "vajza ime"]),
        (.reveal, ["nuk e di", "s e di", "dorezohem", "trego pergjigjen", "me trego zgjidhjen"]),
        (.hint, ["me jep nje ndihme", "nje ndihme", "sugjerim", "hint", "ndihme e vogel"]),
        (.exercise, ["me jep nje ushtrim", "nje ushtrim", "ushtrim", "detyre prove", "praktike"]),
        (.nextStep, ["hapi tjeter", "hapin tjeter", "vazhdo", "me tutje", "tjetri", "pastaj"]),
        (.simpler, ["me thjesht", "thjeshto", "nuk e kuptova", "nuk e kuptoj", "s e kuptova", "nuk kuptoj", "s kuptoj", "shpjegoje ndryshe", "me ndryshe", "nuk e kam te qarte"]),
        (.example, ["shembull", "shembuj"]),
        (.mistake, ["ku gabohet", "gabim", "kujdes"]),
        (.quiz, ["me pyet", "me bej nje pyetje", "pyetje prove", "testo", "kuiz", "quiz", "provo me"]),
        (.related, ["te ngjashme", "te lidhura", "tjeter teme", "teme tjeter"]),
        (.more, ["me shume", "zgjero", "detaj", "me gjere", "me thelle"]),
        (.why, ["pse", "si ndodh", "si funksionon", "mekanizm", "cfare do te thote"])
    ]
    /// Fjalë mbushëse që nuk tregojnë temë (përveç fjalëve të zakonshme të kërkimit).
    private static let filler: Set<String> = ["shume", "mire", "ok", "okej", "jo", "tani", "pak", "hajde", "bej", "beje", "mua", "na", "dot",
                                              "ndihmo", "ndihme", "temen", "tema", "teme", "mesimin", "mesimi", "kete", "ate", "ndodh", "gje",
                                              "neser", "sot", "pasneser", "jave", "javen", "per", "rreth", "lidhje", "dua", "doja", "thuaj",
                                              "tregoni", "trego", "klase", "klasen", "nxenesve", "ua", "klasa",
                                              "femija", "femijen", "femijes", "femijet", "djalin", "vajzen"]

    private static func words(_ text: String) -> [String] {
        LessonSearch.normalize(text).split(separator: " ").map(String.init)
    }
    /// Fjala e mesazhit përputhet me fjalën e frazës: e njëjtë, ose fillon me të kur fjala e frazës ka 4+ shkronja ("zgjero" → "zgjeroje").
    private static func matches(_ word: String, _ phraseWord: String) -> Bool {
        phraseWord.count >= 4 ? word.hasPrefix(phraseWord) : word == phraseWord
    }
    /// Gjen qëllimin dhe fjalët që mbeten për kërkimin e temës.
    static func understand(_ text: String) -> (intent: TutorIntent, rest: [String]) {
        let tokens = words(text)
        for (intent, list) in phrases {
            for phrase in list {
                let parts = phrase.split(separator: " ").map(String.init)
                guard parts.count <= tokens.count else { continue }
                for start in 0...(tokens.count - parts.count) where zip(tokens[start..<start + parts.count], parts).allSatisfy({ matches($0, $1) }) {
                    var rest = tokens
                    rest.removeSubrange(start..<start + parts.count)
                    return (intent, rest)
                }
            }
        }
        return (.topic, tokens)
    }
    private static func meaningful(_ words: [String]) -> [String] {
        words.filter { $0.count > 1 && !LessonSearch.stopWords.contains($0) && !filler.contains($0) && Int($0) == nil }
    }

    /// Zgjedh një nga disa formulime, që biseda të mos tingëllojë e përsëritur.
    private func pick(_ options: [String]) -> String {
        turn += 1
        return options[turn % options.count]
    }

    // MARK: Përgjigjja

    /// Nis bisedën me një mësim të zgjedhur (p.sh. nga ekrani i mësimit).
    func start(with lessonID: String) -> TutorReply? {
        guard let lesson = lessons[lessonID] else { return nil }
        select(lesson)
        return introduce(lesson)
    }

    /// Përshëndetja e parë, sipas rolit.
    func welcome() -> TutorReply {
        switch role {
        case .teacher:
            return TutorReply(text: "Përshëndetje! Jam \(Self.name), asistentja e mësimeve. Mund t'ju ndihmoj të përgatitni një orë mësimi, të gjeni pyetje për klasën ose të shpjegoni një temë në mënyrë më të thjeshtë. Për cilën temë po punoni?",
                              suggestions: ["Si ta shpjegoj teoremën e Pitagorës?", "Pyetje për klasën për fotosintezën", "Kush je?"])
        case .parent:
            return TutorReply(text: "Përshëndetje! Jam \(Self.name), asistentja e mësimeve. Mund t'ju shpjegoj çfarë po mëson fëmija dhe si ta ndihmoni në shtëpi, pa pasur nevojë të jeni ekspert. Për cilën temë doni të flasim?",
                              suggestions: ["Si ta ndihmoj fëmijën me përqindjet?", "Çfarë është fotosinteza?", "Kush je?"])
        case .student:
            return TutorReply(text: "Përshëndetje! Jam \(Self.name). Më pyet për çdo temë të matematikës, fizikës, kimisë ose biologjisë dhe e shohim bashkë hap pas hapi. Mund të të jap edhe ushtrime, ta llogaris diçka, ose të të bëj një plan për testin.",
                              suggestions: ["Çfarë është fotosinteza?", "Kam test nesër për përqindjet", "Sa bën 20% e 750?"])
        }
    }

    func reply(to message: String) -> TutorReply {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return TutorReply(text: "Shkruaj një pyetje për një temë, p.sh. \"Çfarë është fotosinteza?\"") }
        let (intent, rest) = Self.understand(text)

        // 1. Përgjigje për një pyetje ose ushtrim të hapur.
        if let answer = handleWaiting(text, intent: intent) { return answer }
        waiting = .none

        // 2. Llogaritje e drejtpërdrejtë.
        if let value = TutorMath.evaluate(text) {
            return TutorReply(title: "Llogaritja", text: "\(value.expression) = \(TutorMath.format(value.result))\n\n" +
                              pick(["Do që ta shohim nga cila temë vjen kjo llogaritje?", "Nëse vjen nga një ushtrim, më thuaj temën dhe të ndihmoj me hapat.",
                                    "Ka diçka tjetër që do ta llogarisim?"]),
                              lessonID: current?.id, suggestions: current == nil ? ["Më jep një ushtrim"] : ["Më jep një ushtrim", "Shembull"])
        }

        let topicWords = Self.meaningful(rest)
        if topicWords.isEmpty, let small = smallTalk(intent) { return small }
        if intent == .summary { return summary() }

        // 3. Temë e re kur mesazhi ka fjalë kuptimplota që gjejnë një mësim.
        if !topicWords.isEmpty {
            let hits = search.search(topicWords.joined(separator: " "), limit: 5).map(\.id)
            if let first = hits.first, let lesson = lessons[first] {
                lastHits = hits
                if lesson.id != current?.id { select(lesson) }
                let conversational: Set<TutorIntent> = [.topic, .greeting, .howAreYou, .thanks, .whoAreYou, .goodbye]
                if intent == .struggle { return encourage(lesson) }
                return answer(conversational.contains(intent) ? .topic : intent, lesson)
            }
            if intent == .topic {
                return TutorReply(text: pick(["Këtë nuk e gjeta te mësimet e mia. ", "Hmm, për këtë nuk kam mësim. ", "Nuk e gjej këtë temë. "]) +
                                  "Unë di vetëm atë që është te mësimet e matematikës, fizikës, kimisë dhe biologjisë" +
                                  (current.map { ". Mund të vazhdojmë me \($0.title), ose provo një fjalë tjetër." } ?? ". Provo p.sh. \"energjia kinetike\" ose \"thyesat\"."),
                                  suggestions: current == nil ? ["Energjia kinetike", "Mitoza"] : ["Shembull", "Më jep një ushtrim"])
            }
        }
        if intent == .struggle { return encourage(current) }
        guard let lesson = current else {
            return TutorReply(text: pick(["Për cilën temë? Shkruaj p.sh. \"teorema e Pitagorës\" ose \"osmoza\".",
                                          "Më thuaj temën dhe fillojmë, p.sh. \"thyesat\" ose \"ligji i dytë i Njutonit\"."]),
                              suggestions: ["Teorema e Pitagorës", "Osmoza"])
        }
        return answer(intent, lesson)
    }

    private func smallTalk(_ intent: TutorIntent) -> TutorReply? {
        switch intent {
        case .greeting:
            return turn == 0 ? welcome() : TutorReply(text: pick(["Përshëndetje përsëri! Ku e lamë?", "Hej! Me çfarë vazhdojmë?", "Ç'kemi! Çfarë do të mësojmë tani?"]),
                                                       lessonID: current?.id, suggestions: current == nil ? ["Çfarë është fotosinteza?"] : Self.topicSuggestions)
        case .howAreYou:
            return TutorReply(text: pick(["Mirë jam, faleminderit që pyet! Po ti si je? Me cilin mësim po merresh sot?",
                                          "Shumë mirë, gati për punë! Ti si ia kalon? Çfarë po mëson këto ditë?",
                                          "Mirë, faleminderit! Po ti? Më thuaj nëse ka ndonjë temë që të mundon."]),
                              suggestions: ["Mirë, po mësoj thyesat", "E kam të vështirë fizikën", "Kush je?"])
        case .thanks:
            return TutorReply(text: pick(["S'ka përse! ", "Me kënaqësi! ", "Gjithmonë! "]) +
                              (current == nil ? "Kur të duhet, më pyet për një temë." : "Do ta provosh veten me një ushtrim?"),
                              lessonID: current?.id, suggestions: current == nil ? [] : ["Më jep një ushtrim", "Temë të ngjashme"])
        case .whoAreYou:
            return TutorReply(text: "Jam \(Self.name), asistentja e mësimeve e ScienceQuest. Punoj në pajisjen tënde, edhe pa internet, dhe di gjithçka që është te 600 mësimet dhe 600 ushtrimet e aplikacionit: ta shpjegoj më thjesht, me shembull hap pas hapi, të them pse ndodh dhe ku gabohet zakonisht, të jap ushtrime e t'i kontrolloj, të llogaris dhe të bëj plan për testin.\n\nNuk jam si Google: nuk di gjëra jashtë mësimeve dhe nuk shpik përgjigje. Kur nuk e di, ta them.",
                              suggestions: ["Çfarë është fotosinteza?", "Kam test nesër për përqindjet"])
        case .goodbye:
            return TutorReply(text: pick(["Mirupafshim! Suksese me mësimet.", "Shihemi! Mos harro të pushosh pak.", "Natën e mirë! Bëre punë të mirë sot."]))
        default:
            return nil
        }
    }

    private func select(_ lesson: TutorLesson) {
        if lesson.id != current?.id { exerciseTurn = 0 }
        current = lesson; step = 0; waiting = .none
        if !discussed.contains(lesson.id) { discussed.append(lesson.id) }
    }

    private func introduce(_ lesson: TutorLesson) -> TutorReply {
        switch role {
        case .teacher:
            return TutorReply(title: lesson.title + " · " + lesson.subject,
                              text: lesson.introduction + "\n\nMund t'ju propozoj si ta zhvilloni në klasë, pyetje për nxënësit, ose gabimin që bëjnë më shpesh.",
                              lessonID: lesson.id, suggestions: ["Si ta shpjegoj në klasë?", "Pyetje për klasën", "Ku gabohet?"])
        case .parent:
            return helpChild(lesson)
        case .student:
            let opener = pick(["Le ta marrim me radhë. ", "Mirë, ja ideja. ", "Shumë mirë që pyet. ", ""])
            return TutorReply(title: lesson.title + " · " + lesson.subject,
                              text: opener + lesson.introduction + "\n\n" +
                              pick(["Çfarë do: ta thjeshtoj, një shembull hap pas hapi, apo të provosh veten?",
                                    "Ta shohim me një shembull, apo do ta thjeshtoj më parë?",
                                    "Ku do të ndalemi: te shembulli, te pse ndodh, apo te një ushtrim?"]),
                              lessonID: lesson.id, suggestions: Self.topicSuggestions)
        }
    }

    private func answer(_ intent: TutorIntent, _ lesson: TutorLesson) -> TutorReply {
        switch intent {
        case .simpler:
            let points = lesson.recap.prefix(3).map { "• " + $0 }.joined(separator: "\n")
            return TutorReply(title: "Më thjesht", text: pick(["Me pak fjalë:\n", "Shkurt e shqip:\n", "Thelbi është ky:\n"]) + (points.isEmpty ? lesson.introduction : points) +
                              "\n\n" + pick(["Të tregoj një shembull?", "Ka kuptim kështu? Mund ta shohim edhe me një shembull."]),
                              lessonID: lesson.id, suggestions: ["Shembull", "Pse?", "Më pyet"])
        case .example:
            step = 0
            return nextStep(lesson, opening: "Shembull: " + lesson.problem + "\n\n")
        case .nextStep:
            return nextStep(lesson, opening: "")
        case .why:
            let first = lesson.sections.first
            return TutorReply(title: first?.title ?? "Pse ndodh", text: (first?.text ?? lesson.introduction) + "\n\n" +
                              pick(["Do më shumë hollësi?", "Pyetje të mirë që pyete pse. Vazhdojmë më thellë?"]),
                              lessonID: lesson.id, suggestions: ["Më shumë", "Shembull", "Ku gabohet?"])
        case .more:
            let full = lesson.sections.map { $0.title + "\n" + $0.text }.joined(separator: "\n\n")
            return TutorReply(title: "Më shumë për " + lesson.title, text: full.isEmpty ? lesson.introduction : full,
                              lessonID: lesson.id, suggestions: ["Shembull", "Ku gabohet?", "Më jep një ushtrim"])
        case .mistake:
            return TutorReply(title: "Ku gabohet zakonisht", text: lesson.pitfall + "\n\n" + pick(["Do ta provosh me një pyetje?", "Tani që e di këtë kurth, provo një ushtrim?"]),
                              lessonID: lesson.id, suggestions: ["Më pyet", "Më jep një ushtrim"])
        case .quiz where role == .teacher:
            return classQuestions(lesson)
        case .quiz:
            guard !lesson.checkOptions.isEmpty else { return answer(.exercise, lesson) }
            waiting = .check
            let options = lesson.checkOptions.enumerated().map { "\($0.offset + 1)) \($0.element)" }.joined(separator: "\n")
            return TutorReply(title: "Pyetje prove", text: lesson.checkPrompt + "\n\n" + options + "\n\nShkruaj numrin e përgjigjes.",
                              lessonID: lesson.id, suggestions: lesson.checkOptions.indices.map { "\($0 + 1)" })
        case .exercise:
            return giveExercise(lesson)
        case .hint:
            return TutorReply(title: "Një ndihmë", text: "Fillo kështu: " + (lesson.steps.first ?? lesson.recap.first ?? lesson.introduction),
                              lessonID: lesson.id, suggestions: ["Hapi tjetër", "Më jep një ushtrim"])
        case .reveal:
            return nextStep(lesson, opening: "S'ka problem, e shohim bashkë. Shembull: " + lesson.problem + "\n\n")
        case .plan:
            return plan(lesson)
        case .teach:
            return teachingPlan(lesson)
        case .helpChild:
            return helpChild(lesson)
        case .related:
            let titles = lastHits.filter { $0 != lesson.id }.compactMap { lessons[$0]?.title }
            if titles.isEmpty { return TutorReply(text: "Nuk kam tema të tjera afër kësaj. Pyet për një temë tjetër.", lessonID: lesson.id) }
            return TutorReply(title: "Tema të ngjashme", text: titles.map { "• " + $0 }.joined(separator: "\n") + "\n\nZgjidh njërën.",
                              lessonID: lesson.id, suggestions: Array(titles.prefix(4)))
        case .struggle:
            return encourage(lesson)
        default:
            return introduce(lesson)
        }
    }

    private func nextStep(_ lesson: TutorLesson, opening: String) -> TutorReply {
        if step < lesson.steps.count {
            step += 1
            let last = step == lesson.steps.count
            return TutorReply(title: "Hap pas hapi", text: opening + "Hapi \(step): " + lesson.steps[step - 1] +
                              (last ? "\n\n" + lesson.conclusion + "\n\n" + pick(["E ndoqe? Provo tani një ushtrim vetë.", "Kaq ishte. Gati për një ushtrim?"])
                                    : "\n\n" + pick(["Mendo vetë hapin tjetër, pastaj shkruaj \"hapi tjetër\".", "Para se të vazhdojmë: si mendon se vjen hapi tjetër?"])),
                              lessonID: lesson.id, suggestions: last ? ["Më jep një ushtrim", "Ku gabohet?", "Më pyet"] : ["Hapi tjetër", "Më thjesht"])
        }
        return TutorReply(text: lesson.conclusion + "\n\nKaq ishte shembulli. Do një ushtrim për ta provuar?",
                          lessonID: lesson.id, suggestions: ["Më jep një ushtrim", "Temë të ngjashme"])
    }

    // MARK: Ushtrimet

    private func giveExercise(_ lesson: TutorLesson) -> TutorReply {
        let pool = lesson.exerciseIDs.compactMap { exercises[$0] }
        guard !pool.isEmpty else {
            waiting = .check
            return answer(.quiz, lesson)
        }
        let exercise = pool[exerciseTurn % pool.count]
        exerciseTurn += 1
        waiting = .exercise(exercise, tries: 0)
        var body = exercise.prompt
        if exercise.kind == "select" {
            body += "\n\n" + exercise.choices.enumerated().map { "\($0.offset + 1)) \($0.element)" }.joined(separator: "\n")
            body += exercise.answers.count > 1 ? "\n\nMund të ketë më shumë se një të saktë: shkruaj numrat, p.sh. 1, 3." : "\n\nShkruaj numrin e përgjigjes."
        } else {
            body += "\n\n" + exercise.accuracy + (exercise.unit.isEmpty ? "" : " Njësia: \(exercise.unit).")
        }
        return TutorReply(title: "Ushtrim", text: body, lessonID: lesson.id,
                          suggestions: exercise.kind == "select" ? exercise.choices.indices.map { "\($0 + 1)" } + ["Një ndihmë"] : ["Një ndihmë", "Nuk e di"])
    }

    private func handleWaiting(_ text: String, intent: TutorIntent) -> TutorReply? {
        switch waiting {
        case .none:
            return nil
        case .check:
            guard let lesson = current, let picked = Self.choiceIndices(text, options: lesson.checkOptions)?.first else { return nil }
            waiting = .none
            let right = picked == lesson.checkCorrect
            let verdict = right ? "Saktë! " + pick(["Bravo. ", "Shumë mirë. ", "E qëllove. "]) :
                "Jo tamam. Përgjigjja e saktë është \(lesson.checkCorrect + 1)) \(lesson.checkOptions[lesson.checkCorrect]). "
            return TutorReply(text: verdict + lesson.checkWhy, lessonID: lesson.id,
                              suggestions: right ? ["Më jep një ushtrim", "Temë të ngjashme", "Faleminderit"] : ["Më thjesht", "Shembull", "Më pyet"])
        case .exercise(let exercise, let tries):
            if intent == .hint {
                let lessonHint = current?.steps.first.map { " Mendo si fillon shembulli i mësimit: " + $0 } ?? ""
                return TutorReply(title: "Një ndihmë", text: exercise.accuracy + lessonHint + "\n\nProvo përsëri.", lessonID: current?.id, suggestions: ["Nuk e di"])
            }
            if intent == .reveal {
                waiting = .none
                return TutorReply(title: "Zgjidhja", text: "S'ka problem, ja si zgjidhet: " + exercise.why + "\n\nPërgjigjja: " + exercise.answers.joined(separator: ", ") +
                                  (exercise.unit.isEmpty ? "" : " " + exercise.unit) + "\n\nDo një tjetër?",
                                  lessonID: current?.id, suggestions: ["Më jep një ushtrim", "Shembull"])
            }
            guard let correct = Self.check(exercise, text) else { return nil }
            if correct {
                waiting = .none
                return TutorReply(text: "Saktë! " + pick(["Punë e bukur. ", "E zgjidhe. ", "Bravo, kështu është. "]) + exercise.why,
                                  lessonID: current?.id, suggestions: ["Më jep një ushtrim", "Temë të ngjashme", "Faleminderit"])
            }
            if tries == 0 {
                waiting = .exercise(exercise, tries: 1)
                return TutorReply(text: pick(["Jo ende, por je afër. ", "Hmm, jo tamam. ", "Jo ende. "]) + "Kontrollo sërish hapat. " + exercise.accuracy + "\n\nProvo edhe një herë.",
                                  lessonID: current?.id, suggestions: ["Një ndihmë", "Nuk e di"])
            }
            waiting = .none
            return TutorReply(text: "Jo këtë herë, por s'ka gjë: kështu mësohet. " + exercise.why + "\n\nPërgjigjja: " + exercise.answers.joined(separator: ", ") +
                              (exercise.unit.isEmpty ? "" : " " + exercise.unit), lessonID: current?.id, suggestions: ["Më jep një ushtrim", "Shembull", "Më thjesht"])
        }
    }

    /// `nil` kur mesazhi nuk duket si përgjigje (atëherë trajtohet si bisedë e zakonshme).
    private static func check(_ exercise: TutorExercise, _ text: String) -> Bool? {
        if exercise.kind == "select" {
            guard let picked = choiceIndices(text, options: exercise.choices) else { return nil }
            let expected = Set(exercise.answers.compactMap { answer in exercise.choices.firstIndex(of: answer) })
            return Set(picked) == expected
        }
        guard let value = TutorMath.number(in: text) else { return nil }
        return exercise.answers.contains { answer in
            guard let expected = NumericAnswer.parse(answer) else { return false }
            return NumericAnswer.accepts(value, expected: expected, tolerance: exercise.tolerance)
        }
    }

    /// Numrat e alternativave (1, 2, 3…) ose teksti i një alternative.
    private static func choiceIndices(_ text: String, options: [String]) -> [Int]? {
        let clean = LessonSearch.normalize(text)
        let numbers = clean.split(separator: " ").compactMap { Int($0) }.map { $0 - 1 }
        if !numbers.isEmpty, numbers.allSatisfy({ options.indices.contains($0) }) { return Array(Set(numbers)).sorted() }
        let flat = clean.split(separator: " ").joined(separator: " ")
        if let index = options.firstIndex(where: { LessonSearch.normalize($0).split(separator: " ").joined(separator: " ") == flat }) { return [index] }
        return nil
    }

    // MARK: Plane dhe role

    private func plan(_ lesson: TutorLesson) -> TutorReply {
        TutorReply(title: "Plani për " + lesson.title,
                   text: pick(["Mirë që fillon herët! ", "Bëjmë një plan të shkurtër. ", "S'ka panik, e bëjmë me radhë. "]) +
                   "Ja çfarë do të bëja në 30–40 minuta:\n1) Ideja kryesore (5 min): \"më thjesht\".\n2) Shembulli hap pas hapi (10 min): \"shembull\".\n3) Gabimi i zakonshëm (5 min): \"ku gabohet\".\n4) Ushtrime (15 min): \"më jep një ushtrim\", derisa t'i zgjidhësh dy rresht.\n5) Pyetja e fundit (5 min): \"më pyet\".\n\nFillojmë me hapin e parë?",
                   lessonID: lesson.id, suggestions: ["Më thjesht", "Shembull", "Më jep një ushtrim"])
    }

    private func teachingPlan(_ lesson: TutorLesson) -> TutorReply {
        let steps = lesson.steps.enumerated().map { "   \($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return TutorReply(title: "Si ta zhvilloni: " + lesson.title,
                          text: "1) Hyrja (5 min): " + lesson.introduction + "\n\n2) Ideja kryesore: " + (lesson.recap.first ?? "") +
                          "\n\n3) Shembull në tabelë: " + lesson.problem + "\n" + steps + "\n   " + lesson.conclusion +
                          "\n\n4) Paralajmëroni për gabimin: " + lesson.pitfall +
                          "\n\n5) Kontroll në fund: " + lesson.checkPrompt + " (përgjigjja: " + (lesson.checkOptions.indices.contains(lesson.checkCorrect) ? lesson.checkOptions[lesson.checkCorrect] : "") + ")",
                          lessonID: lesson.id, suggestions: ["Pyetje për klasën", "Ku gabohet?", "Temë të ngjashme"])
    }

    private func classQuestions(_ lesson: TutorLesson) -> TutorReply {
        var lines = ["• " + lesson.checkPrompt + " → " + (lesson.checkOptions.indices.contains(lesson.checkCorrect) ? lesson.checkOptions[lesson.checkCorrect] : "")]
        for exercise in lesson.exerciseIDs.compactMap({ exercises[$0] }) {
            lines.append("• " + exercise.prompt + " → " + exercise.answers.joined(separator: ", ") + (exercise.unit.isEmpty ? "" : " " + exercise.unit))
        }
        return TutorReply(title: "Pyetje për klasën", text: lines.joined(separator: "\n\n") + "\n\nMund t'i përdorni edhe te \"Krijo test\" te Shkolla ime.",
                          lessonID: lesson.id, suggestions: ["Si ta shpjegoj në klasë?", "Temë të ngjashme"])
    }

    private func helpChild(_ lesson: TutorLesson) -> TutorReply {
        let points = lesson.recap.prefix(2).map { "• " + $0 }.joined(separator: "\n")
        return TutorReply(title: lesson.title + " · për prindin",
                          text: "Me pak fjalë, fëmija po mëson këtë:\n" + (points.isEmpty ? lesson.introduction : points) +
                          "\n\nSi ta ndihmoni: kërkojini t'jua shpjegojë me fjalët e veta, pastaj pyeteni: \"" + lesson.checkPrompt + "\"" +
                          (lesson.checkOptions.indices.contains(lesson.checkCorrect) ? " (përgjigjja: " + lesson.checkOptions[lesson.checkCorrect] + ")." : ".") +
                          "\n\nGabimi që bëjnë shpesh: " + lesson.pitfall,
                          lessonID: lesson.id, suggestions: ["Shembull", "Temë të ngjashme"])
    }

    private func encourage(_ lesson: TutorLesson?) -> TutorReply {
        let base = pick(["E kuptoj, ndodh shpesh dhe nuk do të thotë që s'je i zoti. ", "S'ka gjë, të gjithëve na ndodh. ",
                         "Mirë që e the. Të vështirat bëhen të lehta kur i ndajmë në hapa të vegjël. "])
        guard let lesson else {
            return TutorReply(text: base + "Më thuaj cila temë të duket e vështirë dhe e marrim bashkë, ngadalë.", suggestions: ["Thyesat", "Ligji i dytë i Njutonit"])
        }
        let first = lesson.recap.first ?? lesson.introduction
        return TutorReply(title: lesson.title, text: base + "Le të fillojmë me një gjë të vetme: " + first + "\n\nKur të jesh gati, shkruaj \"shembull\" dhe e shohim hap pas hapi.",
                          lessonID: lesson.id, suggestions: ["Shembull", "Më thjesht"])
    }

    private func summary() -> TutorReply {
        let titles = discussed.compactMap { lessons[$0]?.title }
        guard !titles.isEmpty else { return TutorReply(text: "Ende nuk kemi folur për ndonjë temë. Me çfarë fillojmë?", suggestions: ["Çfarë është fotosinteza?"]) }
        return TutorReply(title: "Çfarë folëm", text: titles.map { "• " + $0 }.joined(separator: "\n") + "\n\nDo t'i përsërisim me nga një pyetje?",
                          lessonID: current?.id, suggestions: ["Më pyet", "Më jep një ushtrim"])
    }
}

/// Llogaritje të thjeshta: + − × ÷ (edhe ":"), fuqi (^), kllapa, rrënjë katrore dhe "20% e 750".
enum TutorMath {
    static func format(_ value: Double) -> String {
        if abs(value - value.rounded()) < 1e-9 && abs(value) < 1e15 { return String(Int(value.rounded())) }
        return String(format: "%.6g", value).replacingOccurrences(of: ".", with: ",")
    }
    /// Një numër i vetëm në mesazh (për përgjigjet e ushtrimeve): "9,8", "3/4", "-2".
    static func number(in text: String) -> Double? {
        let tokens = text.replacingOccurrences(of: "−", with: "-").split(whereSeparator: { " \n".contains($0) })
        let numeric = tokens.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "?!.;")) }.compactMap { NumericAnswer.parse($0) }
        return numeric.count == 1 ? numeric[0] : nil
    }
    /// Fjalët që lejohen pranë një shprehjeje ("sa bën 3 + 4?", "llogarit 2^10", "rrënja e 144").
    private static let mathWords: Set<String> = ["sa", "ben", "bejne", "eshte", "jane", "llogarit", "llogarite", "llogaris", "del", "rrenja", "katrore",
                                                 "e", "me", "behet", "na", "pra", "mund", "te", "ma", "per", "shuma", "prodhimi", "x"]
    static func evaluate(_ text: String) -> (expression: String, result: Double)? {
        let lower = text.lowercased()
        if let percent = percentOf(lower) { return percent }
        // Vetëm kur mesazhi është një llogaritje: çdo fjalë tjetër e bën bisedë të zakonshme.
        let letters = LessonSearch.normalize(lower).split(separator: " ").map(String.init).filter { $0.contains(where: { $0.isLetter }) }
        guard letters.allSatisfy({ mathWords.contains($0) || $0 == "sqrt" }) else { return nil }
        var s = lower.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "·", with: "*").replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
        for phrase in ["rrënja katrore e", "rrenja katrore e", "rrënja katrore", "rrenja katrore", "rrënja e", "rrenja e", "rrënja", "rrenja", "sqrt"] {
            s = s.replacingOccurrences(of: phrase, with: "√")
        }
        s = s.replacingOccurrences(of: #"([\d)])\s*:\s*"#, with: "$1/", options: .regularExpression)
            .replacingOccurrences(of: #"([\d)])\s*x\s*(?=[\d(√])"#, with: "$1*", options: .regularExpression)
            .replacingOccurrences(of: #"(\d),(\d)"#, with: "$1.$2", options: .regularExpression)
        let allowed = Set("0123456789.+-*/^()√")
        let compact = String(s.filter { allowed.contains($0) })
        guard compact.contains(where: { "+-*/^√".contains($0) }), compact.contains(where: { $0.isNumber }) else { return nil }
        // Një numër negativ i vetëm ("-5") nuk është llogaritje.
        if compact.hasPrefix("-"), !compact.dropFirst().contains(where: { "+-*/^√".contains($0) }) { return nil }
        var parser = Parser(Array(compact))
        guard let value = parser.parse(), value.isFinite else { return nil }
        let shown = compact.replacingOccurrences(of: "*", with: " × ").replacingOccurrences(of: "/", with: " : ")
            .replacingOccurrences(of: "+", with: " + ").replacingOccurrences(of: "-", with: " − ").replacingOccurrences(of: ".", with: ",")
        return (shown.trimmingCharacters(in: .whitespaces), value)
    }
    private static func percentOf(_ text: String) -> (expression: String, result: Double)? {
        guard let match = text.range(of: #"(\d+(?:[.,]\d+)?)\s*%\s*(?:e|i|te|të|nga)?\s*(\d+(?:[.,]\d+)?)"#, options: .regularExpression) else { return nil }
        let numbers = text[match].split(whereSeparator: { !"0123456789.,".contains($0) }).compactMap { NumericAnswer.parse(String($0)) }
        guard numbers.count == 2 else { return nil }
        return (expression: "\(format(numbers[0]))% e \(format(numbers[1]))", result: numbers[0] / 100 * numbers[1])
    }
    private struct Parser {
        let chars: [Character]
        var i = 0
        init(_ chars: [Character]) { self.chars = chars }
        mutating func parse() -> Double? {
            guard let value = expression(), i == chars.count else { return nil }
            return value
        }
        private mutating func expression() -> Double? {
            guard var value = term() else { return nil }
            while i < chars.count, chars[i] == "+" || chars[i] == "-" {
                let op = chars[i]; i += 1
                guard let rhs = term() else { return nil }
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }
        private mutating func term() -> Double? {
            guard var value = power() else { return nil }
            while i < chars.count, chars[i] == "*" || chars[i] == "/" {
                let op = chars[i]; i += 1
                guard let rhs = power() else { return nil }
                if op == "/" { guard rhs != 0 else { return nil }; value /= rhs } else { value *= rhs }
            }
            return value
        }
        private mutating func power() -> Double? {
            guard let base = unary() else { return nil }
            if i < chars.count, chars[i] == "^" {
                i += 1
                guard let exponent = power() else { return nil }
                return pow(base, exponent)
            }
            return base
        }
        private mutating func unary() -> Double? {
            guard i < chars.count else { return nil }
            if chars[i] == "-" { i += 1; return unary().map { -$0 } }
            if chars[i] == "+" { i += 1; return unary() }
            if chars[i] == "√" { i += 1; guard let v = unary(), v >= 0 else { return nil }; return v.squareRoot() }
            return primary()
        }
        private mutating func primary() -> Double? {
            guard i < chars.count else { return nil }
            if chars[i] == "(" {
                i += 1
                guard let value = expression(), i < chars.count, chars[i] == ")" else { return nil }
                i += 1
                return value
            }
            let start = i
            while i < chars.count, chars[i].isNumber || chars[i] == "." { i += 1 }
            guard i > start else { return nil }
            return Double(String(chars[start..<i]))
        }
    }
}
