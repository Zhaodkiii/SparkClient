#if canImport(XCTest)
import Foundation
import XCTest

final class ChatGuideQuestionJSONParserTests: XCTestCase {
    private let logSampleJSON = """
    [
      {
        "id": 1,
        "title": "久坐程序员怎么护颈椎腰椎？",
        "prompt": "作为需要中度久坐的27岁男性程序员，日常工作中可以通过哪些健康科普类的方法保护颈椎和腰椎，降低久坐带来的健康影响？",
        "category": "popular_science"
      },
      {
        "id": 2,
        "title": "甲状腺囊肿日常要注意什么？",
        "prompt": "体检发现TI-RADS 2类甲状腺左叶囊肿，在日常生活中有哪些健康科普层面的注意事项，帮助做好日常健康管理？",
        "category": "popular_science"
      },
      {
        "id": 3,
        "title": "日常怎么科学控制体重？",
        "prompt": "27岁男性BMI处于超重范围，日常饮食和运动方面有哪些科学的健康科普知识，帮助合理管理体重？",
        "category": "popular_science"
      }
    ]
    """

    func testParsesPlainJSONArray() throws {
        let raw = """
        [
          {
            "id": "daily_steps",
            "title": "每天走多少步合适?",
            "prompt": "请科普每天走多少步比较合适。",
            "category": "popular_science"
          },
          {
            "id": "sleep_quality",
            "title": "怎样改善睡眠质量?",
            "prompt": "请科普怎样改善睡眠质量。",
            "category": "popular_science"
          },
          {
            "id": "hydration",
            "title": "每天应该喝多少水?",
            "prompt": "请科普每天应该喝多少水。",
            "category": "popular_science"
          }
        ]
        """
        let questions = try ChatGuideQuestionJSONParser.parse(raw)
        XCTAssertEqual(questions.count, 3)
        XCTAssertEqual(questions.first?.id, "daily_steps")
    }

    func testParsesNumericIDQuestions() throws {
        let questions = try ChatGuideQuestionJSONParser.parse(logSampleJSON)
        XCTAssertEqual(questions.count, 3)
        XCTAssertEqual(questions.map(\.title), [
            "久坐程序员怎么护颈椎腰椎？",
            "甲状腺囊肿日常要注意什么？",
            "日常怎么科学控制体重？"
        ])
        for question in questions {
            XCTAssertFalse(question.id.allSatisfy(\.isNumber))
            XCTAssertTrue(question.id.hasPrefix("guide_"))
        }
    }

    func testParsesObjectSequenceWithoutArrayWrapper() throws {
        let raw = """
        {
          "id": 1,
          "title": "问题一?",
          "prompt": "问题一完整?",
          "category": "popular_science"
        },
        {
          "id": 2,
          "title": "问题二?",
          "prompt": "问题二完整?",
          "category": "popular_science"
        },
        {
          "id": 3,
          "title": "问题三?",
          "prompt": "问题三完整?",
          "category": "popular_science"
        }
        """
        let questions = try ChatGuideQuestionJSONParser.parse(raw)
        XCTAssertEqual(questions.count, 3)
        XCTAssertTrue(questions.allSatisfy { $0.id.hasPrefix("guide_") })
    }

    func testParsesNumericIDInsideMarkdownFence() throws {
        let raw = """
        ```json
        \(logSampleJSON)
        ```
        """
        let questions = try ChatGuideQuestionJSONParser.parse(raw)
        XCTAssertEqual(questions.count, 3)
        XCTAssertTrue(questions.allSatisfy { $0.id.hasPrefix("guide_") })
    }

    func testParsesWrappedQuestionsWithNumericID() throws {
        let raw = """
        {
          "questions": [
            {"id": 1, "title": "问题一?", "prompt": "问题一完整?", "category": "popular_science"},
            {"id": 2, "title": "问题二?", "prompt": "问题二完整?", "category": "popular_science"},
            {"id": 3, "title": "问题三?", "prompt": "问题三完整?", "category": "popular_science"}
          ]
        }
        """
        let questions = try ChatGuideQuestionJSONParser.parse(raw)
        XCTAssertEqual(questions.count, 3)
        XCTAssertTrue(questions.allSatisfy { $0.id.hasPrefix("guide_") })
    }

    func testNormalizesNumericIDToStableTitleBasedID() throws {
        let raw = """
        [
          {"id": 1, "title": "固定标题?", "prompt": "固定标题完整?", "category": "popular_science"},
          {"id": 2, "title": "问题二?", "prompt": "问题二完整?", "category": "popular_science"},
          {"id": 3, "title": "问题三?", "prompt": "问题三完整?", "category": "popular_science"}
        ]
        """
        let firstPass = try ChatGuideQuestionJSONParser.parse(raw)
        let secondPass = try ChatGuideQuestionJSONParser.parse(raw)
        XCTAssertEqual(firstPass.first?.id, secondPass.first?.id)
        XCTAssertEqual(firstPass.first?.id, "guide_固定标题")
    }

    func testParsesMarkdownWrappedJSON() throws {
        let raw = """
        ```json
        [
          {"id":"a","title":"问题一?","prompt":"问题一完整?","category":"popular_science"},
          {"id":"b","title":"问题二?","prompt":"问题二完整?","category":"popular_science"},
          {"id":"c","title":"问题三?","prompt":"问题三完整?","category":"popular_science"}
        ]
        ```
        """
        let questions = try ChatGuideQuestionJSONParser.parse(raw)
        XCTAssertEqual(questions.count, 3)
    }

    func testParsesWrappedQuestionsObject() throws {
        let raw = """
        {
          "questions": [
            {"title":"问题一?","prompt":"问题一完整?"},
            {"title":"问题二?","prompt":"问题二完整?"},
            {"title":"问题三?","prompt":"问题三完整?"}
          ]
        }
        """
        let questions = try ChatGuideQuestionJSONParser.parse(raw)
        XCTAssertEqual(questions.count, 3)
        XCTAssertEqual(questions.map(\.category), ["popular_science", "popular_science", "popular_science"])
    }

    func testDedupesRepeatedQuestions() throws {
        let raw = """
        [
          {"id":"a","title":"重复问题?","prompt":"重复问题完整?","category":"popular_science"},
          {"id":"b","title":"重复问题?","prompt":"重复问题完整?","category":"popular_science"},
          {"id":"c","title":"问题三?","prompt":"问题三完整?","category":"popular_science"},
          {"id":"d","title":"问题四?","prompt":"问题四完整?","category":"popular_science"}
        ]
        """
        let questions = try ChatGuideQuestionJSONParser.parse(raw)
        XCTAssertEqual(questions.count, 3)
    }

    func testPadsWithPresetWhenLessThanThree() throws {
        let raw = """
        [
          {"id":"only_one","title":"唯一问题?","prompt":"唯一问题完整?","category":"popular_science"}
        ]
        """
        let questions = try ChatGuideQuestionJSONParser.parse(raw)
        XCTAssertEqual(questions.count, 3)
    }

    func testThrowsWhenStillInsufficientAfterPresetPadding() {
        XCTAssertThrowsError(try ChatGuideQuestionJSONParser.parse("not json")) { error in
            XCTAssertEqual(error as? ChatGuideQuestionJSONParserError, .invalidJSON)
        }
    }
}
#endif
