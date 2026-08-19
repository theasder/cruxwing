import Foundation
import Testing
@testable import MeetGPT

/// Чем спрашивают подключённые приложения, когда цель звонка не названа.
///
/// Запрос уходит КАЖДОМУ подключённому сервису — включая Fireflies, чей
/// владелец продаёт конкурирующий продукт. Здесь стоял хвост расшифровки:
/// последние 500 знаков дословной беседы, обрезанные до 320 и разосланные всем.
/// Чтобы улучшить слияние их же данными, мы отдавали им кусок разговора.
@Suite("Запрос к подключённым приложениям")
struct GroundingQueryTests {

    @Test("названная цель звонка идёт как есть")
    func statedGoalIsUsed() {
        #expect(AppState.groundingQuery(goal: "сроки по биллингу", digest: "что угодно")
                == "сроки по биллингу")
    }

    @Test("без цели идёт наше краткое изложение, а не разговор")
    func digestIsUsedWithoutGoal() {
        #expect(AppState.groundingQuery(goal: "", digest: "обсуждали тарифы и лимиты")
                == "обсуждали тарифы и лимиты")
        #expect(AppState.groundingQuery(goal: "   ", digest: "обсуждали тарифы")
                == "обсуждали тарифы")
    }

    // Худший исход — пустая строка: сервисы ответили бы «что угодно», и это
    // выглядело бы как работа. Второй по вредности — хвост расшифровки.
    @Test("нечего спросить — не спрашиваем")
    func noQueryMeansNoRequest() {
        #expect(AppState.groundingQuery(goal: "", digest: "") == nil)
        #expect(AppState.groundingQuery(goal: " ", digest: "\n") == nil)
    }

    @Test("расшифровка в запрос не подставляется ни в одной ветке")
    func transcriptNeverBecomesTheQuery() throws {
        let path = #filePath.replacingOccurrences(
            of: "Tests/MeetGPTTests/GroundingQueryTests.swift",
            with: "Sources/MeetGPT/AppState.swift")
        let code = try String(contentsOfFile: path, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("///") }
            .joined(separator: "\n")
        #expect(!code.contains("formatEntries(whisperSnapshot).suffix"),
                "хвост расшифровки снова уходит подключённым сервисам как поисковый запрос")
        #expect(code.contains("groundingQuery(goal:"),
                "выбор запроса перестал идти через одно место")
    }
}
