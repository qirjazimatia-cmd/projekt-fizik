import XCTest

final class ValidationTests: XCTestCase {
    func testNumericRoundingFractionsAndInvalidInput() {
        XCTAssertEqual(NumericAnswer.parse("1,33"),1.33)
        XCTAssertEqual(NumericAnswer.parse(" 4 / 3 "),4.0/3.0)
        XCTAssertTrue(NumericAnswer.accepts(1.33,expected:4.0/3.0,tolerance:0.005))
        XCTAssertFalse(NumericAnswer.accepts(1.3,expected:4.0/3.0,tolerance:0.005))
        for invalid in ["NaN","inf","1/0","1/2/3","","1e999"] { XCTAssertNil(NumericAnswer.parse(invalid),invalid) }
        XCTAssertTrue(NumericAnswer.accepts(1e-8,expected:1e-8,tolerance:1e-12))
        XCTAssertFalse(NumericAnswer.accepts(0,expected:1e-8,tolerance:1e-12))
    }
    func testEveryLessonAndExerciseIsInItsLevel() throws {
        let bundle=Bundle(for:Self.self)
        let lessonURL=try XCTUnwrap(bundle.url(forResource:"Lessons",withExtension:"json"))
        let exerciseURL=try XCTUnwrap(bundle.url(forResource:"Exercises",withExtension:"json"))
        let lessons=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:lessonURL)) as? [[String:Any]])
        let exercises=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:exerciseURL)) as? [[String:Any]])
        XCTAssertEqual(lessons.count,600);XCTAssertEqual(exercises.count,600)
        let index=Dictionary(uniqueKeysWithValues:exercises.map { ($0["id"] as! String,$0) })
        for lesson in lessons {
            let ids=try XCTUnwrap(lesson["exerciseIDs"] as? [String])
            XCTAssertFalse(ids.isEmpty)
            for id in ids {
                let item=try XCTUnwrap(index[id])
                XCTAssertEqual(item["subject"] as? String,lesson["subject"] as? String)
                XCTAssertEqual(item["level"] as? Int,lesson["level"] as? Int)
            }
            XCTAssertNotNil(lesson["diagram"])
        }
    }

    // Asistenti i mësimeve: kërkimi në pajisje gjen temën e duhur. Pritjet u nxorën nga i njëjti algoritëm (prototip në Python).
    private func assistantIndex() throws -> LessonSearch {
        let url=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"Lessons",withExtension:"json"))
        let lessons=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [[String:Any]])
        return LessonSearch(lessons.map { l in
            let sections=(l["sections"] as? [[String:String]] ?? []).map { ($0["title"] ?? "")+" "+($0["text"] ?? "") }
            let example=l["example"] as? [String:Any] ?? [:]
            return .lesson(id:l["id"] as! String, subject:l["subject"] as! String, level:l["level"] as! Int, title:l["title"] as! String,
                           chapterTitle:l["chapterTitle"] as! String, objectives:l["objectives"] as? [String] ?? [],
                           introduction:l["introduction"] as? String ?? "", sections:sections,
                           example:(example["problem"] as? String ?? "")+" "+(example["steps"] as? [String] ?? []).joined(separator:" "),
                           recap:l["recap"] as? [String] ?? [])
        })
    }
    func testAssistantNormalizesAlbanianText() {
        XCTAssertEqual(LessonSearch.tokens("Çfarë është Fotosinteza? Shpejtësia, ë ç!"),["fotos","shpej"])
    }
    func testAssistantFindsTheRightLesson() throws {
        let index=try assistantIndex()
        let expected=["Si llogaritet shpejtësia mesatare?":"LF1-06","Çfarë është fotosinteza":"LB1-23","teorema e Pitagorës":"LM1-23",
                      "barazimi i ekuacionit kimik":"LK1-22","si funksionon osmoza":"LB2-07","Ligji i dytë i Njutonit":"LF1-13",
                      "energjia kinetike":"LF1-24","pH e acideve":"LK1-29"]
        for (query,id) in expected { XCTAssertEqual(index.search(query).first?.id,id,query) }
        XCTAssertEqual(index.search("shpejtësia mesatare",subject:"Kimi").first?.id,"LK3-01")
        XCTAssertEqual(index.search("shpejtësia mesatare",level:3).first?.id,"LK3-01")
        XCTAssertTrue(index.search("xyzqw kot").isEmpty)
        XCTAssertTrue(index.search("   ").isEmpty)
        XCTAssertLessThanOrEqual(index.search("energjia",limit:5).count,5)
    }

    // Biseda me asistentin: përshëndetje, temë, pyetje vijuese dhe pyetje prove.
    private func tutor() throws -> LessonTutor {
        let url=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"Lessons",withExtension:"json"))
        let raw=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [[String:Any]])
        let lessons:[TutorLesson]=raw.map { l in
            let example=l["example"] as? [String:Any] ?? [:]
            let check=l["check"] as? [String:Any] ?? [:]
            return TutorLesson(id:l["id"] as! String, subject:l["subject"] as! String, title:l["title"] as! String,
                               introduction:l["introduction"] as? String ?? "",
                               sections:(l["sections"] as? [[String:String]] ?? []).map { (title:$0["title"] ?? "",text:$0["text"] ?? "") },
                               problem:example["problem"] as? String ?? "", steps:example["steps"] as? [String] ?? [],
                               conclusion:example["conclusion"] as? String ?? "", pitfall:l["pitfall"] as? String ?? "",
                               recap:l["recap"] as? [String] ?? [], checkPrompt:check["prompt"] as? String ?? "",
                               checkOptions:check["options"] as? [String] ?? [], checkCorrect:check["correct"] as? Int ?? 0,
                               checkWhy:check["why"] as? String ?? "")
        }
        return LessonTutor(search:try assistantIndex(), lessons:lessons)
    }
    func testTutorUnderstandsSmallTalk() {
        XCTAssertEqual(LessonTutor.understand("Përshëndetje!").intent,.greeting)
        XCTAssertEqual(LessonTutor.understand("Si je?").intent,.howAreYou)
        XCTAssertEqual(LessonTutor.understand("Faleminderit shumë").intent,.thanks)
        XCTAssertEqual(LessonTutor.understand("Kush je ti?").intent,.whoAreYou)
        XCTAssertEqual(LessonTutor.understand("S'e kuptova").intent,.simpler)
        XCTAssertEqual(LessonTutor.understand("Më jep një shembull").intent,.example)
        XCTAssertEqual(LessonTutor.understand("Hapi tjetër").intent,.nextStep)
        XCTAssertEqual(LessonTutor.understand("Zgjeroje pak").intent,.more)
        XCTAssertEqual(LessonTutor.understand("Më pyet").intent,.quiz)
        XCTAssertEqual(LessonTutor.understand("Çfarë është fotosinteza?").intent,.topic)
    }
    func testTutorConversation() throws {
        let chat=try tutor()
        XCTAssertNil(chat.reply(to:"Përshëndetje").lessonID)
        XCTAssertNil(chat.reply(to:"Si je?").lessonID)
        XCTAssertNil(chat.reply(to:"më shumë").lessonID, "pa temë, pyet për cilën temë")
        XCTAssertEqual(chat.reply(to:"Çfarë është fotosinteza?").lessonID,"LB1-23")
        let example=chat.reply(to:"shembull")
        XCTAssertEqual(example.lessonID,"LB1-23"); XCTAssertTrue(example.text.contains("Hapi 1"))
        XCTAssertTrue(chat.reply(to:"hapi tjetër").text.contains("Hapi 2"))
        let quiz=chat.reply(to:"më pyet")
        XCTAssertEqual(quiz.title,"Pyetje prove"); XCTAssertEqual(quiz.suggestions,["1","2","3"])
        XCTAssertTrue(chat.reply(to:"1").text.hasPrefix("Saktë!"))
        XCTAssertEqual(chat.reply(to:"pse ndodh osmoza").lessonID,"LB2-07", "temë e re me pyetje vijuese")
        XCTAssertEqual(chat.current?.id,"LB2-07")
        XCTAssertNil(chat.reply(to:"xyzqw kot").title)
        XCTAssertEqual(chat.current?.id,"LB2-07", "fjalë e panjohur nuk e ndryshon temën")
        XCTAssertEqual(chat.start(with:"LM1-23")?.lessonID,"LM1-23")
    }
}
