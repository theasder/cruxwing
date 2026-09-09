import Testing
import Foundation
@testable import CruxwingCore

/// Последний коннектор, писанный руками, чей поиск — язык, а не поле.
///
/// Пройденное по манифестам (Jira, Slack, Mattermost, Trello, BookStack) не
/// касалось двух коннекторов, оставшихся кодом. У Яндекс Трекера вопрос
/// уходит внутрь выражения: `Summary: "текст"`.
///
/// Стояла там замена кавычки на апостроф. Экранированием она не была: апостроф
/// в языке Трекера не служебный, поэтому строка просто менялась — спросивший
/// про «"Избранное"» искал уже не своё слово. А обратный слеш не трогался
/// вовсе, хотя именно он экранирует следующий знак: вопрос, кончающийся
/// слешем, съедал закрывающую кавычку.
@Suite struct YandexQueryEscapeTests {

    private func query(for text: String) throws -> String {
        let tracker = RussianTrackers(service: .yandexTracker, token: "т",
                                      secondary: "org") { _ in
            (Data(), HTTPURLResponse())
        }
        let body = try #require(try tracker.body(for: text, limit: 10))
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        return try #require(object["query"] as? String)
    }

    @Test("кавычка экранируется, а не подменяется")
    func aQuoteIsEscapedNotSwapped() throws {
        let text = try query(for: "\"Избранное\"")
        // Вендор: `"` экранируется обратным слешем. Слово при этом остаётся
        // тем же самым — подмена на апостроф меняла бы, что именно ищут.
        #expect(text == "Summary: \"\\\"Избранное\\\"\"")
        #expect(!text.contains("'"), "кавычка снова подменена апострофом")
    }

    @Test("вопрос, кончающийся слешем, не съедает закрывающую кавычку")
    func aTrailingBackslashCannotEndTheString() throws {
        let text = try query(for: "путь C:\\")
        // Без экранирования слеша получилось бы `Summary: "путь C:\"` —
        // закрывающей кавычки нет, и дальше выражение дописывает не человек.
        #expect(text.hasSuffix("\\\\\""))
        #expect(text == "Summary: \"путь C:\\\\\"")
    }

    @Test("слеш экранируется раньше кавычки")
    func theBackslashGoesFirst() throws {
        // Порядок обязателен: сначала кавычки, потом слеши — и добавленный
        // слеш был бы экранирован вторым проходом, превратив `\"` в `\\"`,
        // то есть в слеш и ЗАКРЫВАЮЩУЮ кавычку.
        let text = try query(for: "a\"b")
        #expect(text == "Summary: \"a\\\"b\"")
    }

    @Test("обычное слово доезжает без изменений")
    func anOrdinaryWordIsUntouched() throws {
        #expect(try query(for: "тарифы") == "Summary: \"тарифы\"")
    }
}
