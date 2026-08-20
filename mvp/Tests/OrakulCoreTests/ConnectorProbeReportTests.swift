import Foundation
import Testing
@testable import OrakulCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Отчёт о живой проверке вставляют в ПУБЛИЧНЫЙ пулл-реквест.
///
/// Значит, единственное свойство, ради которого стоит писать этот набор, —
/// секрет не выходит наружу ни одним путём. Проверяются все три, которыми он
/// туда попадает: заголовок, адрес и текст чужой ошибки.
@Suite("Отчёт о проверке коннектора")
struct ConnectorProbeReportTests {

    // ASCII, как настоящие токены. Кириллица здесь врала: в адресе она
    // уезжает процентной кодировкой, и проверка «строки нет в отчёте»
    // проходила потому, что искала не то, что там лежит.
    static let token = "SECRET-tok-9f3a"

    static func request(url: String, headers: [String: String] = [:],
                        body: String? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let body { request.httpBody = Data(body.utf8) }
        return request
    }

    @Test("токен из заголовка в отчёт не попадает")
    func headerTokenIsHidden() {
        let outcome = ConnectorProbeReport.Outcome(
            service: "gitea",
            request: Self.request(url: "https://git.company.ru/api/v1/repos/issues/search?q=тарифы",
                                  headers: ["Authorization": "token \(Self.token)"]),
            status: 200, rows: 3, firstTitle: "#7 Починить экспорт", failure: nil)

        let text = ConnectorProbeReport.render(outcome, token: Self.token)
        #expect(!text.contains(Self.token), "токен утёк в отчёт:\n\(text)")
        #expect(text.contains("Authorization: ***"))
        // И полезное осталось: без запроса и ответа отчёт не нужен.
        #expect(text.contains("/api/v1/repos/issues/search"))
        #expect(text.contains("Форма узнана, строк: 3"))
    }

    @Test("ключ внутри адреса тоже вычищается")
    func tokenInsidePathIsHidden() {
        // У вебхука Битрикс24 ключ лежит в ПУТИ, а не в заголовке. Проверка по
        // именам заголовков такой случай не видит вовсе.
        let outcome = ConnectorProbeReport.Outcome(
            service: "bitrix24",
            request: Self.request(url: "https://firma.bitrix24.ru/rest/1/\(Self.token)/tasks.task.list"),
            status: 200, rows: 0, firstTitle: nil, failure: nil)

        let text = ConnectorProbeReport.render(outcome, token: Self.token)
        #expect(!text.contains(Self.token), "ключ из адреса утёк в отчёт:\n\(text)")
    }

    @Test("процентная кодировка ключа — тоже утечка")
    func percentEncodedTokenIsHidden() {
        // Нелатинский ключ в адресе выглядит как «%D0%A1%D0%95…». Читать его
        // глазами нельзя, раскодировать — можно кем угодно.
        let cyrillic = "КЛЮЧ-секрет-2f8c"
        let encoded = cyrillic.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let outcome = ConnectorProbeReport.Outcome(
            service: "bitrix24",
            request: Self.request(url: "https://firma.bitrix24.ru/rest/1/\(encoded)/tasks.task.list"),
            status: 200, rows: 0, firstTitle: nil, failure: nil)

        let text = ConnectorProbeReport.render(outcome, token: cyrillic)
        #expect(!text.contains(encoded), "закодированный ключ утёк в отчёт:\n\(text)")
        #expect(!text.contains(cyrillic))
    }

    @Test("токен, вернувшийся в тексте ошибки сервиса, тоже не проходит")
    func tokenEchoedByServiceIsHidden() {
        // Сервисы охотно повторяют присланный ключ в сообщении об ошибке. Это
        // не наш текст, и списком мест его не поймать — ловится значением.
        let outcome = ConnectorProbeReport.Outcome(
            service: "redmine", request: nil, status: 401, rows: nil, firstTitle: nil,
            failure: "Invalid API key \(Self.token) for user 12")

        let text = ConnectorProbeReport.render(outcome, token: Self.token)
        #expect(!text.contains(Self.token), "сервис вернул ключ, и он уехал в отчёт:\n\(text)")
        #expect(text.contains("Не получилось"))
    }

    @Test("токен из двух половин вычищается по частям")
    func halvesAreHidden() {
        // У Zulip токен это `почта:ключ`, у вебхука — `id/код`. В запрос уезжает
        // то одна половина, то другая, и целиком строка в выводе не встречается.
        let paired = "bot@company.ru:kluch-2f8c"
        let outcome = ConnectorProbeReport.Outcome(
            service: "zulip",
            request: Self.request(url: "https://zulip.company.ru/api/v1/messages?user=bot@company.ru"),
            status: 200, rows: 1, firstTitle: "по тарифам", failure: "ключ kluch-2f8c отклонён")

        let text = ConnectorProbeReport.render(outcome, token: paired)
        #expect(!text.contains("kluch-2f8c"), "половина токена утекла:\n\(text)")
        #expect(!text.contains("bot@company.ru"), "вторая половина утекла:\n\(text)")
    }

    @Test("короткая строка не превращает отчёт в звёздочки")
    func shortTokenDoesNotEatTheReport() {
        // Пустой или очень короткий токен — не секрет, а промах в настройке.
        // Замена по нему затёрла бы половину осмысленного текста.
        let outcome = ConnectorProbeReport.Outcome(
            service: "gitea", request: Self.request(url: "https://git.company.ru/api"),
            status: 401, rows: nil, firstTitle: nil, failure: "нет прав")
        let text = ConnectorProbeReport.render(outcome, token: "ab")
        #expect(text.contains("https://git.company.ru/api"))
        #expect(text.contains("нет прав"))
    }
}

/// Отчёт кладут в ОТКРЫТЫЙ пулл-реквест, и внизу его прямо написано, что это
/// можно. Значит всё напечатанное читает кто угодно — включая тех, кто продаёт
/// конкурирующий продукт.
///
/// Токен вычищался четырьмя способами: по имени заголовка, по значению, по
/// половинам составного ключа, по процентному кодированию. А рядом печаталась
/// первая строка выдачи целиком — настоящий заголовок задачи из трекера того,
/// кто прислал отчёт. Секретом его никто не считал.
@Suite struct ProbeReportKeepsTheirDataTests {

    private func report(firstTitle: String?) -> String {
        ConnectorProbeReport.render(
            ConnectorProbeReport.Outcome(
                service: "redmine", request: nil, status: 200,
                rows: 3, firstTitle: firstTitle, failure: nil),
            token: "kluch")
    }

    @Test("заголовок чужой задачи в отчёт не попадает")
    func theTitleItselfIsNotPrinted() {
        let text = report(firstTitle: "Пересмотр тарифов для клиента с декабря")
        #expect(!text.contains("Пересмотр"))
        #expect(!text.contains("клиента"))
    }

    @Test("но доказательство, что поле прочитано, остаётся")
    func theProofRemains() {
        // Мейнтейнеру нужен не текст, а то, что прочитано ТО поле: строка
        // непустая, такой-то длины и такой-то азбукой.
        let text = report(firstTitle: "Пересмотр тарифов")
        #expect(text.contains("Заголовок первой строки прочитан"))
        #expect(text.contains("17 знаков"))
        #expect(text.contains("кириллица"))
    }

    @Test("азбука различается — она и отличает прочитанное от подставленного")
    func theAlphabetIsTold() {
        #expect(ConnectorProbeReport.shape(of: "Fix export").contains("латиница"))
        #expect(ConnectorProbeReport.shape(of: "Починить export").contains("кириллица и латиница"))
        #expect(ConnectorProbeReport.shape(of: "#7 — 42").contains("без букв"))
    }

    @Test("заголовок нигде не печатается напрямую")
    func theTitleIsNeverPrintedDirectly() throws {
        // Поведенческие проверки выше смотрят на один заголовок. Печать можно
        // вернуть в другом месте — во второй строке, в отладочном выводе, — и
        // они этого не увидят: они спрашивают про свой пример, а не про правило.
        //
        // CONTRIBUTING теперь обещает человеку, что его задача в отчёт не
        // попадёт. Обещание в документе, которое держится на одном примере в
        // тесте, — это обещание до первой правки.
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/OrakulCore/ConnectorProbeReport.swift"),
                                encoding: .utf8)
        let printsTitle = source.contains("\\(title)")
            || source.contains("\\(outcome.firstTitle")
        #expect(!printsTitle, "заголовок снова печатается в отчёт как есть")
        #expect(source.contains("shape(of: title)"),
                "доказательство прочитанного поля пропало")
    }

    @Test("пустой выдачи это не касается")
    func anEmptyAnswerIsUnchanged() {
        // Ноль строк — тоже результат, и он отличается от «форму не узнали».
        let text = report(firstTitle: nil)
        #expect(text.contains("Форма узнана, строк: 3"))
        #expect(!text.contains("Заголовок первой строки"))
    }
}
