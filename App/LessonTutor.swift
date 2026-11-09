import Foundation

/// Biseda me asistentin e mësimeve. Kupton përshëndetje dhe bisedë të shkurtër, gjen temën te mësimet
/// dhe e zgjeron sipas kërkesës (më thjesht, shembull hap pas hapi, pse, më shumë, gabimi, pyetje prove).
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
}

enum TutorIntent: Equatable {
    case greeting, howAreYou, thanks, whoAreYou, goodbye
    case simpler, example, nextStep, why, more, mistake, quiz, related
    case topic
}

struct TutorReply: Equatable {
    var title: String? = nil
    var text: String
    var lessonID: String? = nil
    var suggestions: [String] = []
}

final class LessonTutor {
    private let search: LessonSearch
    private let lessons: [String: TutorLesson]
    private(set) var current: TutorLesson?
    private var step = 0
    private var awaitingAnswer = false
    private var lastHits: [String] = []

    static let topicSuggestions = ["Më thjesht", "Shembull", "Pse?", "Më shumë", "Ku gabohet?", "Më pyet"]

    init(search: LessonSearch, lessons: [TutorLesson]) {
        self.search = search
        self.lessons = Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
    }

    // MARK: Kuptimi i mesazhit

    /// Fraza për çdo qëllim, të shkruara pa ë/ç dhe me shkronja të vogla.
    private static let phrases: [(TutorIntent, [String])] = [
        (.howAreYou, ["si je", "si jeni", "si ja kalon", "si ia kalon", "si po ia kalon", "si po shkon", "cfare ben", "si kalon"]),
        (.whoAreYou, ["kush je", "cfare je", "cfare di", "cfare mund te besh", "si te perdor", "si funksionon ky"]),
        (.thanks, ["faleminderit", "flm", "rrofsh", "merci", "thanks", "thank"]),
        (.goodbye, ["mirupafshim", "naten e mire", "shihemi", "bye"]),
        (.greeting, ["pershendetje", "tungjatjeta", "tung", "hello", "hi", "hey", "hej", "ciao", "cao", "mirdita", "miremengjes", "mirembrema", "c kemi", "ckemi", "alo"]),
        (.nextStep, ["hapi tjeter", "hapin tjeter", "vazhdo", "me tutje", "tjetri", "pastaj"]),
        (.simpler, ["me thjesht", "thjeshto", "nuk e kuptova", "nuk e kuptoj", "s e kuptova", "nuk kuptoj", "s kuptoj", "shpjegoje ndryshe", "me ndryshe", "nuk e kam te qarte"]),
        (.example, ["shembull", "shembuj"]),
        (.mistake, ["ku gabohet", "gabim", "kujdes"]),
        (.quiz, ["me pyet", "me bej nje pyetje", "pyetje prove", "testo", "kuiz", "quiz", "provo me"]),
        (.related, ["te ngjashme", "te lidhura", "tjeter teme", "teme tjeter"]),
        (.more, ["me shume", "zgjero", "detaj", "me gjere", "me thelle"]),
        (.why, ["pse", "si ndodh", "si funksionon", "mekanizm"])
    ]
    /// Fjalë mbushëse që nuk tregojnë temë (përveç fjalëve të zakonshme të kërkimit).
    private static let filler: Set<String> = ["shume", "mire", "ok", "okej", "jo", "tani", "pak", "hajde", "bej", "beje", "mua", "na", "dot",
                                              "ndihmo", "ndihme", "temen", "tema", "teme", "mesimin", "mesimi", "kete", "ate", "ndodh", "gje"]

    /// Shkurtimet si "s'e" ose "ç'kemi" bëhen "s e" dhe "c kemi" pas normalizimit.
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
        words.filter { $0.count > 1 && !LessonSearch.stopWords.contains($0) && !filler.contains($0) }
    }

    // MARK: Përgjigjja

    /// Nis bisedën me një mësim të zgjedhur (p.sh. nga ekrani i mësimit).
    func start(with lessonID: String) -> TutorReply? {
        guard let lesson = lessons[lessonID] else { return nil }
        select(lesson)
        return introduce(lesson)
    }

    func reply(to message: String) -> TutorReply {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return TutorReply(text: "Shkruaj një pyetje për një temë, p.sh. \"Çfarë është fotosinteza?\"") }
        if awaitingAnswer, let current, let picked = answerIndex(text, options: current.checkOptions) {
            awaitingAnswer = false
            let right = picked == current.checkCorrect
            let verdict = right ? "Saktë! " : "Jo tamam. Përgjigjja e saktë është \(current.checkCorrect + 1)) \(current.checkOptions[current.checkCorrect]). "
            return TutorReply(text: verdict + current.checkWhy, lessonID: current.id,
                              suggestions: right ? ["Më shumë", "Temë të ngjashme", "Faleminderit"] : ["Më thjesht", "Shembull", "Më pyet"])
        }
        awaitingAnswer = false
        let (intent, rest) = Self.understand(text)
        let topicWords = Self.meaningful(rest)
        switch intent {
        case .greeting where topicWords.isEmpty:
            return TutorReply(text: "Përshëndetje! Jam asistenti i mësimeve. Më pyet për çdo temë të matematikës, fizikës, kimisë ose biologjisë, p.sh. \"Çfarë është fotosinteza?\" ose \"Si llogaritet nxitimi?\"",
                              suggestions: ["Çfarë është fotosinteza?", "Teorema e Pitagorës", "Kush je?"])
        case .howAreYou where topicWords.isEmpty:
            return TutorReply(text: "Mirë jam, faleminderit që pyet! Ti si je? Me cilin mësim po merresh sot?",
                              suggestions: ["Përqindja", "Shpejtësia mesatare", "Kush je?"])
        case .thanks where topicWords.isEmpty:
            return TutorReply(text: "S'ka përse! " + (current == nil ? "Kur të duhet, më pyet për një temë." : "Do të të bëj një pyetje për ta provuar?"),
                              lessonID: current?.id, suggestions: current == nil ? [] : ["Më pyet", "Temë të ngjashme"])
        case .whoAreYou where topicWords.isEmpty:
            return TutorReply(text: "Jam asistenti i mësimeve të ScienceQuest. Punoj në pajisjen tënde, edhe pa internet, dhe shpjegoj nga 600 mësimet e aplikacionit: më thjesht, me shembull hap pas hapi, pse ndodh, ku gabohet zakonisht, dhe të bëj pyetje prove. Nuk jam si Google: nuk di gjëra jashtë mësimeve dhe nuk shpik përgjigje.",
                              suggestions: ["Çfarë është fotosinteza?", "Ligji i dytë i Njutonit"])
        case .goodbye where topicWords.isEmpty:
            return TutorReply(text: "Mirupafshim! Suksese me mësimet.")
        default: break
        }
        // Temë e re kur mesazhi ka fjalë kuptimplota që gjejnë një mësim.
        if !topicWords.isEmpty {
            let hits = search.search(topicWords.joined(separator: " "), limit: 5).map(\.id)
            if let first = hits.first, let lesson = lessons[first] {
                lastHits = hits
                if lesson.id != current?.id { select(lesson) }
                return answer(intent == .topic || intent == .greeting || intent == .howAreYou || intent == .thanks || intent == .whoAreYou || intent == .goodbye ? .topic : intent, lesson)
            }
            if intent == .topic {
                return TutorReply(text: "Këtë nuk e gjeta te mësimet. Pyet për një temë të matematikës, fizikës, kimisë ose biologjisë" +
                                  (current == nil ? ", p.sh. \"energjia kinetike\"." : ", ose shkruaj \"shembull\" ose \"më thjesht\" për temën e fundit: \(current!.title)."),
                                  suggestions: current == nil ? ["Energjia kinetike", "Mitoza"] : ["Shembull", "Më thjesht"])
            }
        }
        guard let lesson = current else {
            return TutorReply(text: "Për cilën temë? Shkruaj p.sh. \"teorema e Pitagorës\" ose \"osmoza\".",
                              suggestions: ["Teorema e Pitagorës", "Osmoza"])
        }
        return answer(intent, lesson)
    }

    private func select(_ lesson: TutorLesson) {
        current = lesson; step = 0; awaitingAnswer = false
    }

    private func introduce(_ lesson: TutorLesson) -> TutorReply {
        TutorReply(title: lesson.title + " · " + lesson.subject,
                   text: lesson.introduction + "\n\nDo ta shpjegoj më thjesht, të të tregoj një shembull hap pas hapi, apo të të bëj një pyetje?",
                   lessonID: lesson.id, suggestions: Self.topicSuggestions)
    }

    private func answer(_ intent: TutorIntent, _ lesson: TutorLesson) -> TutorReply {
        switch intent {
        case .simpler:
            let points = lesson.recap.prefix(3).map { "• " + $0 }.joined(separator: "\n")
            return TutorReply(title: "Më thjesht", text: (points.isEmpty ? lesson.introduction : "Me pak fjalë:\n" + points) + "\n\nTë tregoj një shembull?",
                              lessonID: lesson.id, suggestions: ["Shembull", "Pse?", "Më pyet"])
        case .example:
            step = 0
            return nextStep(lesson, opening: "Shembull: " + lesson.problem + "\n\n")
        case .nextStep:
            return nextStep(lesson, opening: "")
        case .why:
            let first = lesson.sections.first
            return TutorReply(title: first?.title ?? "Pse ndodh", text: (first?.text ?? lesson.introduction) + "\n\nDo më shumë hollësi?",
                              lessonID: lesson.id, suggestions: ["Më shumë", "Shembull", "Ku gabohet?"])
        case .more:
            let full = lesson.sections.map { $0.title + "\n" + $0.text }.joined(separator: "\n\n")
            return TutorReply(title: "Më shumë për " + lesson.title, text: full.isEmpty ? lesson.introduction : full,
                              lessonID: lesson.id, suggestions: ["Shembull", "Ku gabohet?", "Më pyet"])
        case .mistake:
            return TutorReply(title: "Ku gabohet zakonisht", text: lesson.pitfall + "\n\nDo ta provosh me një pyetje?",
                              lessonID: lesson.id, suggestions: ["Më pyet", "Shembull"])
        case .quiz:
            guard !lesson.checkOptions.isEmpty else { return answer(.example, lesson) }
            awaitingAnswer = true
            let options = lesson.checkOptions.enumerated().map { "\($0.offset + 1)) \($0.element)" }.joined(separator: "\n")
            return TutorReply(title: "Pyetje prove", text: lesson.checkPrompt + "\n\n" + options + "\n\nShkruaj numrin e përgjigjes.",
                              lessonID: lesson.id, suggestions: lesson.checkOptions.indices.map { "\($0 + 1)" })
        case .related:
            let titles = lastHits.filter { $0 != lesson.id }.compactMap { lessons[$0]?.title }
            if titles.isEmpty {
                return TutorReply(text: "Nuk kam tema të tjera afër kësaj. Pyet për një temë tjetër.", lessonID: lesson.id)
            }
            return TutorReply(title: "Tema të ngjashme", text: titles.map { "• " + $0 }.joined(separator: "\n") + "\n\nZgjidh njërën.",
                              lessonID: lesson.id, suggestions: Array(titles.prefix(4)))
        default:
            return introduce(lesson)
        }
    }

    private func nextStep(_ lesson: TutorLesson, opening: String) -> TutorReply {
        if step < lesson.steps.count {
            step += 1
            let last = step == lesson.steps.count
            return TutorReply(title: "Hap pas hapi", text: opening + "Hapi \(step): " + lesson.steps[step - 1] +
                              (last ? "\n\n" + lesson.conclusion : "\n\nMendo vetë hapin tjetër, pastaj shkruaj \"hapi tjetër\"."),
                              lessonID: lesson.id, suggestions: last ? ["Më pyet", "Ku gabohet?", "Më shumë"] : ["Hapi tjetër", "Më thjesht"])
        }
        return TutorReply(text: lesson.conclusion + "\n\nKaq ishte shembulli. Do një pyetje për ta provuar?",
                          lessonID: lesson.id, suggestions: ["Më pyet", "Temë të ngjashme"])
    }

    /// Përgjigjja e pyetjes prove: numri (1, 2, 3…) ose teksti i alternativës.
    private func answerIndex(_ text: String, options: [String]) -> Int? {
        let clean = LessonSearch.normalize(text).trimmingCharacters(in: .whitespaces)
        if let number = Int(clean), options.indices.contains(number - 1) { return number - 1 }
        return options.firstIndex { LessonSearch.normalize($0).trimmingCharacters(in: .whitespaces) == clean }
    }
}
