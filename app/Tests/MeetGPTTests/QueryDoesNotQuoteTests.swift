import Testing
import Foundation
@testable import MeetGPT

/// Поисковый запрос не выносит встречу дословно.
///
/// Запрос, собранный моделью из расшифровки, уезжает в КАЖДОЕ подключённое
/// приложение — включая сервис конкурента, который продаёт расшифровки. Набор
/// терминов — это поиск. Кусок фразы — это содержание встречи у того, у кого
/// его быть не должно, и продукт обещает обратное.
///
/// До этой проверки запрос ограничивался только длиной (300 знаков) и запретом
/// переносов строки: 299 знаков дословной речи проходили.
@Suite struct QueryDoesNotQuoteTests {

    static let transcript = """
    Аня: коллеги, мы решили поднять тарифы с декабря на пятнадцать процентов \
    для клиентов из Германии, и это надо успеть до конца квартала.
    Борис: тогда пересчитаю лимиты и вернусь в среду.
    """

    @Test("набор терминов проходит")
    func keywordsPass() {
        // Ради этого запрос и существует: слова встречи в нём обязаны быть.
        for query in ["тарифы декабрь Германия",
                      "лимиты пересчёт квартал",
                      "тарифы клиенты Германия пересчёт лимитов"] {
            #expect(!PromptWorkflows.looksLikeAQuote(query, of: Self.transcript),
                    "отвергнут обычный набор терминов: «\(query)»")
        }
    }

    @Test("кусок фразы не проходит")
    func quotedClauseIsRefused() {
        let quote = "мы решили поднять тарифы с декабря на пятнадцать процентов для клиентов"
        #expect(PromptWorkflows.looksLikeAQuote(quote, of: Self.transcript),
                "дословный кусок встречи уехал бы в чужое приложение")
    }

    @Test("цитата с другого места расшифровки тоже не проходит")
    func quoteFromAnywhereCounts() {
        // Совпадение ищется по всей расшифровке, а не только в начале.
        let quote = "тогда пересчитаю лимиты и вернусь в среду а потом посмотрим"
        #expect(PromptWorkflows.looksLikeAQuote(quote, of: Self.transcript))
    }

    @Test("порог — подряд идущие слова, а не общее совпадение")
    func scatteredWordsAreNotAQuote() {
        // Восемь слов встречи вразбивку — это и есть хороший поисковый запрос.
        // Требовать их отсутствия значило бы запретить искать по встрече вообще.
        let scattered = "тарифы декабрь процентов клиентов Германии лимиты квартал среда"
        #expect(!PromptWorkflows.looksLikeAQuote(scattered, of: Self.transcript))
    }

    @Test("короткая строка не считается цитатой")
    func shortRunsPass() {
        // «поднять тарифы с декабря» — четыре слова, узнаваемых как термины,
        // а не как фраза. Порог должен пропускать их, иначе поиск обеднеет.
        #expect(!PromptWorkflows.looksLikeAQuote("поднять тарифы с декабря", of: Self.transcript))
    }

    @Test("пустая расшифровка ничего не запрещает")
    func emptyTranscriptForbidsNothing() {
        #expect(!PromptWorkflows.looksLikeAQuote("тарифы декабрь", of: ""))
    }

    @Test("шесть слов подряд — цитата, и это всё правило")
    func sixWordsAreTheWholeRule() {
        // Рядом стоял второй порог — сначала по знакам, потом по числу
        // содержательных слов. Первый мерил длину и пропускал фразу; второй
        // почти никогда не срабатывал (у любых шести слов живой речи найдётся
        // три длиннее трёх букв), и мутация, снявшая его, набор проходила.
        // Осталось одно правило, и оно объяснимо вслух.
        //
        // «и это надо успеть до конца» — шесть слов подряд со встречи, и да,
        // это цитата. Отказ здесь стоит широкого запроса по цели звонка;
        // пропуск стоил бы сказанного на встрече у чужого сервиса.
        #expect(PromptWorkflows.looksLikeAQuote("и это надо успеть до конца", of: Self.transcript))
        // А пять слов подряд — ещё термины.
        #expect(!PromptWorkflows.looksLikeAQuote("это надо успеть до конца", of: Self.transcript))
    }

    @Test("приложение спрашивает сторожа, а не только имеет его")
    func theAppCallsTheGuard() throws {
        // Структурно: чтобы вызвать вывод запроса по-настоящему, нужны
        // подключённые приложения, расшифровка длиннее трёхсот знаков и модель
        // — дороже пользы. Правило же простое и проверяется прямо: вывод
        // запроса сначала чистит ответ модели, а потом отказывается от цитаты.
        // Сторож, который написан и не позван, уже случался в этом коде.
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/MeetGPT/AppState.swift"), encoding: .utf8)
        let derive = try #require(source.range(of: "func deriveGroundingQuery").map { start -> String in
            let tail = String(source[start.lowerBound...])
            guard let end = tail.range(of: "\n    /// ") else { return tail }
            return String(tail[..<end.lowerBound])
        })
        #expect(derive.contains("sanitizeDerivedQuery"), "ответ модели больше не чистится")
        #expect(derive.contains("looksLikeAQuote"),
                "вывод запроса не спрашивает про цитату — встреча уедет дословно")
        let sanitize = try #require(derive.range(of: "sanitizeDerivedQuery"))
        let quote = try #require(derive.range(of: "looksLikeAQuote"))
        #expect(sanitize.lowerBound < quote.lowerBound,
                "порядок обратный: цитату проверяют раньше чистки")
    }
}
