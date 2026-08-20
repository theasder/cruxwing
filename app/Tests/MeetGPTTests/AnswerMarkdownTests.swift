import Testing
import Foundation
@testable import MeetGPT

/// Куда уводит ответ на экране.
///
/// Ответ рисуется как встроенный markdown, а тот понимает `[слова](адрес)`.
/// Слова видит человек, адреса не видит никто — `Text` рисует обычную ссылку,
/// и нажатие уводит браузер туда, куда сказано в скобках.
///
/// Написать такое может не только модель. Ответ строится на находках
/// подключённых сервисов: заголовок задачи, страница вики, строка расшифровки
/// от сервиса, который продаёт конкурирующий продукт. Достаточно, чтобы модель
/// перенесла строку в ответ, — а переносить цитаты её и просят.
@Suite struct AnswerMarkdownTests {

    private func parsed(_ text: String) throws -> AttributedString {
        try #require(try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
    }

    @Test("разметка ответа действительно делает ссылку — иначе чинить нечего")
    func theRiskIsReal() throws {
        // Проверка самой предпосылки. Без неё всё ниже проверяло бы защиту от
        // того, чего не бывает.
        let attr = try parsed("Подробности: [Открыть задачу](https://chuzhoy.example/login)")
        #expect(attr.runs.contains { $0.link != nil })
        #expect(!String(attr.characters).contains("chuzhoy.example"),
                "адрес и так виден — тогда прятать нечего")
    }

    @Test("переход снимается, а адрес показывается")
    func theAddressBecomesVisible() throws {
        let safe = AnswerMarkdown.withoutHiddenLinks(
            try parsed("Подробности: [Открыть задачу](https://chuzhoy.example/login)"))
        #expect(!safe.runs.contains { $0.link != nil }, "нажатие всё ещё уводит")
        #expect(String(safe.characters).contains("Открыть задачу"), "слова потерялись")
        #expect(String(safe.characters).contains("https://chuzhoy.example/login"),
                "адрес по-прежнему спрятан")
    }

    @Test("адрес, уже написанный словами, не удваивается")
    func aVisibleAddressIsNotRepeated() throws {
        let safe = AnswerMarkdown.withoutHiddenLinks(
            try parsed("[https://tracker.example/CRX-42](https://tracker.example/CRX-42)"))
        let text = String(safe.characters)
        #expect(text == "https://tracker.example/CRX-42")
    }

    @Test("две ссылки в строке обрабатываются обе")
    func everyLinkIsHandled() throws {
        // Правка сдвигает границы соседних отрезков: обход по ходу правки
        // пропускал бы каждую вторую.
        let safe = AnswerMarkdown.withoutHiddenLinks(
            try parsed("[раз](https://a.example/1) и [два](https://b.example/2)"))
        #expect(!safe.runs.contains { $0.link != nil })
        let text = String(safe.characters)
        #expect(text.contains("https://a.example/1"))
        #expect(text.contains("https://b.example/2"))
    }

    @Test("обычный текст не трогается")
    func plainTextIsUntouched() throws {
        let safe = AnswerMarkdown.withoutHiddenLinks(
            try parsed("Решили поднять **тарифы** с декабря"))
        #expect(String(safe.characters) == "Решили поднять тарифы с декабря")
    }

    @Test("вид ответа зовёт это правило")
    func theAnswerViewUsesIt() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/MeetGPT/Views/AIResponseView.swift"),
                                encoding: .utf8)
        #expect(source.contains("AnswerMarkdown.withoutHiddenLinks(attr)"),
                "разбор снова отдаёт разметку как есть")
    }
}
