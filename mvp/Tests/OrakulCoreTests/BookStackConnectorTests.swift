import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OrakulCore

/// BookStack — открытая вики, которую ставят себе (роадмап, §7.4).
///
/// Ценность её не в списке страниц, а в том, что поиск возвращает слова вокруг
/// совпадения: подсказке на звонке нужна цитата, а не ссылка «посмотрите тут».
@Suite struct BookStackConnectorTests {

    static func stub(_ data: Data, seen: (@Sendable (URLRequest) -> Void)? = nil)
        -> ManifestConnector.HTTP {
        { request in
            seen?(request)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200,
                                          httpVersion: nil, headerFields: [:])!)
        }
    }

    static func manifest() throws -> ConnectorManifest {
        try #require(try ConnectorManifest.bundled().first { $0.id == "bookstack" })
    }

    /// Ответ из документации вендора: подсветка совпадения стоит прямо в тексте.
    static let sample = Data(#"""
    {"data":[
      {"id":396,"name":"Тарифы и лимиты","slug":"tarify","book_id":1,"type":"page",
       "url":"https://wiki.company.ru/books/dogovory/page/tarify",
       "preview_html":{"name":"<strong>Тарифы</strong> и лимиты",
                       "content":"…договорились поднять <strong>тарифы</strong> с декабря…"},
       "tags":[]}
    ],"total":1}
    """#.utf8)

    @Test("подсветка не доезжает до человека, а слова вокруг совпадения — доезжают")
    func highlightIsStrippedFromTheAnswer() async throws {
        let connector = ManifestConnector(manifest: try Self.manifest(), token: "id:секрет",
                                          host: "https://wiki.company.ru",
                                          http: Self.stub(Self.sample))
        let item = try #require(try await connector.run("тарифы").items.first)
        #expect(item.title == "Тарифы и лимиты")
        #expect(item.context == "…договорились поднять тарифы с декабря…")
        #expect(!item.context.contains("<"), "разметка уехала в подсказку: «\(item.context)»")
    }

    @Test("строка без подсветки не пропадает из выдачи")
    func rowWithoutPreviewSurvives() async throws {
        // Заголовок берётся из `name`, а не из подсвеченной копии, и разница
        // видна ровно здесь: `preview_html` есть не в каждой строке — у полки
        // или книги без совпадения в тексте подсвечивать нечего. Если брать
        // заголовок оттуда, такая строка теряет и заголовок, и слова вокруг,
        // то есть пропадает из ответа целиком и молча.
        //
        // Первая версия этой проверки сравнивала два поля, которые после
        // снятия тегов совпадают, и проходила при любом выборе пути. Показала
        // мутация.
        let withoutPreview = Data(#"{"data":[{"id":12,"name":"Договоры с подрядчиками","type":"book","url":"https://wiki.company.ru/books/dogovory"}],"total":1}"#.utf8)
        let connector = ManifestConnector(manifest: try Self.manifest(), token: "id:секрет",
                                          host: "https://wiki.company.ru",
                                          http: Self.stub(withoutPreview))
        let item = try #require(try await connector.run("договоры").items.first)
        #expect(item.title == "Договоры с подрядчиками")
        #expect(item.context.isEmpty)
    }

    @Test("сущности HTML раскрываются, а не остаются кодом")
    func entitiesAreDecoded() {
        #expect(ManifestConnector.withoutTags("<b>А</b> &amp; Б &quot;в&quot;") == "А & Б \"в\"")
        #expect(ManifestConnector.withoutTags("без разметки") == "без разметки")
        // Угловая скобка внутри текста — не тег. Разбор простой, и это его
        // предел: он записан здесь, чтобы не считать его ошибкой потом.
        #expect(ManifestConnector.withoutTags("5 &lt; 7") == "5 < 7")
    }

    @Test("BookStack ищет сам — приписки об охвате нет")
    func bookstackSearchesItself() async throws {
        let connector = ManifestConnector(manifest: try Self.manifest(), token: "id:секрет",
                                          host: "https://wiki.company.ru",
                                          http: Self.stub(Self.sample))
        #expect(try await connector.run("тарифы").coverage == .searched)
    }

    @Test("запрос совпадает с документацией: слово, счётчик и токен из двух половин")
    func requestMatchesTheDocs() throws {
        let connector = ManifestConnector(manifest: try Self.manifest(), token: "идентификатор:секрет",
                                          host: "https://wiki.company.ru",
                                          http: Self.stub(Data("{}".utf8)))
        let request = try connector.makeRequest(query: "тарифы", limit: 10)
        #expect(request.url?.path == "/api/search")
        // Две половины через двоеточие — одна строка заголовка, а не Basic-логин.
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Token идентификатор:секрет")
        let query = request.url?.query ?? ""
        #expect(query.contains("count=10"), "счётчик у BookStack — count, максимум 100")
        #expect(query.contains("query="), "слово человека обязано уехать в query")
    }

    @Test("без адреса BookStack не настроен: облака у него нет")
    func bookstackRequiresAHost() async {
        // У Outline пустой адрес значит облако. Подставить BookStack чужой
        // домен значило бы отправить токен неизвестно кому.
        let notes = TeamNotes(service: .bookstack, token: "id:секрет", host: nil,
                              http: { _ in (Data(), stubHTTPResponse()) })
        #expect(!notes.isConfigured)

        let outline = TeamNotes(service: .outline, token: "токен", host: nil,
                                http: { _ in (Data(), stubHTTPResponse()) })
        #expect(outline.isConfigured, "у Outline облако есть, и пустой адрес — это оно")
    }

    @Test("BookStack доходит до человека через базу знаний")
    func reachableThroughTeamNotes() async throws {
        let notes = TeamNotes(service: .bookstack, token: "id:секрет", host: "wiki.company.ru",
                              http: { request in
            (Self.sample, HTTPURLResponse(url: request.url!, statusCode: 200,
                                          httpVersion: nil, headerFields: [:])!)
        })
        let hits = try await notes.search("тарифы")
        #expect(hits.first?.title == "Тарифы и лимиты")
        #expect(hits.first?.context.contains("поднять тарифы") == true)
    }
}
