import Testing
import Foundation
@testable import MeetGPT

/// Сведение не дописывает строк, которых не было.
///
/// Источник B — расшифровка Fireflies: текст сервиса, который продаёт
/// конкурирующий продукт. Он уезжает в запрос, переписывающий запись
/// СОБСТВЕННОЙ встречи человека. Невидимые знаки оттуда снимаются на общей
/// воронке MCP; указание, вписанное обычными буквами, она не ловит — и не
/// должна: это работа проверки результата.
///
/// В системном указании есть правило «ничего не выдумывать». Указание — не
/// сторож: оно говорит модели, как себя вести, и ничего не проверяет.
@Suite struct NoInventedLinesTests {

    static func entry(_ text: String) -> TranscriptEntry {
        TranscriptEntry(source: .system, text: text, timestamp: Date(), speaker: nil)
    }

    @Test("строка, которой нет ни в одном источнике, найдена")
    func inventedLineIsFound() {
        let whisper = "Аня: обсудили сроки поставки и лимиты выгрузки"
        let fireflies = "Аня: обсудили сроки поставки и лимиты выгрузки, вернёмся в среду"
        let entries = [Self.entry("обсудили сроки поставки"),
                       Self.entry("клиент согласился на трёхлетний контракт")]
        let found = TranscriptEnhancementService.unsupportedEntries(
            entries, whisper: whisper, fireflies: fireflies)
        #expect(found.count == 1)
        #expect(found.first?.text.contains("трёхлетний") == true)
    }

    @Test("переформулировка сведения проходит")
    func rewordingIsAllowed() {
        // Сведение чинит огрехи распознавания и собирает предложения — ради
        // этого оно и существует. Требовать совпадения слов значило бы
        // запретить саму работу.
        let whisper = "ана обсудили сроки постаки и лимиты выгруски"
        let fireflies = "Аня: обсудили сроки поставки и лимиты выгрузки"
        let entries = [Self.entry("Аня: обсудили сроки поставки и лимиты выгрузки")]
        #expect(TranscriptEnhancementService.unsupportedEntries(
            entries, whisper: whisper, fireflies: fireflies).isEmpty)
    }

    @Test("короткая реплика без содержательных слов не считается выдумкой")
    func shortRepliesAreNotInventions() {
        // «да», «ага», «угу» — сверять в них нечего, и объявлять их выдумкой
        // значит ломать обычную запись разговора.
        let entries = [Self.entry("да"), Self.entry("ага")]
        #expect(TranscriptEnhancementService.unsupportedEntries(
            entries, whisper: "обсудили сроки", fireflies: "обсудили сроки").isEmpty)
    }

    @Test("пустые источники ничего не запрещают")
    func emptySourcesForbidNothing() {
        // Иначе первая же пустая сторона объявила бы выдумкой всё сведение.
        #expect(TranscriptEnhancementService.unsupportedEntries(
            [Self.entry("что угодно")], whisper: "", fireflies: "").isEmpty)
    }

    @Test("отказ называет число дописанных строк")
    func theRefusalSaysHowMany() {
        let message = TranscriptEnhancementError.invented(2).errorDescription ?? ""
        #expect(message.contains("2"))
        #expect(message.contains("Fireflies"))
        #expect(message.contains("оставлена как была"),
                "человек должен знать, что его запись не тронули")
    }

    @Test("сведение с дописанной строкой отвергается целиком")
    func enhancementWithAnInventedLineIsRefused() async throws {
        // Сторож, написанный и не позванный, в этом коде уже случался. Здесь
        // проверяется, что он стоит НА ПУТИ: модель возвращает разбираемый
        // ответ, в котором одна строка не встречается ни у Whisper, ни у
        // Fireflies, — и сведение не применяется.
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let whisper = [TranscriptEntry(source: .system, text: "обсудили сроки поставки",
                                       timestamp: start.addingTimeInterval(10))]
        let fireflies = FirefliesTranscript(title: "Звонок",
                                            text: "Аня: обсудили сроки поставки.")
        let llm = MockLLMGateway(response: """
        {"summary":"свели",
         "entries":[
           {"offsetSec":10,"speaker":"Аня","source":"system","text":"обсудили сроки поставки"},
           {"offsetSec":20,"speaker":"Аня","source":"system","text":"клиент согласился на трёхлетний контракт"}
         ]}
        """)
        await #expect(throws: TranscriptEnhancementError.invented(1)) {
            _ = try await TranscriptEnhancementService.enhance(
                whisper: whisper, fireflies: fireflies, sessionStart: start,
                llm: llm,
                model: LLMCatalog.model(id: "gpt-5.4-mini") ?? LLMCatalog.defaultModel(for: .free))
        }
    }
}
