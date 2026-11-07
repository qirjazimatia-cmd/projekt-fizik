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
}
