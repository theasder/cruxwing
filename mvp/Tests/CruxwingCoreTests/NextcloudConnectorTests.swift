import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CruxwingCore

/// Nextcloud — единый поиск OCS (роадмап, §7.4).
///
/// Две особенности, которых нет у остальных: сервер принимает только Basic, и
/// человек сам выбирает, где искать — провайдер стоит в адресе.
@Suite struct NextcloudConnectorTests {

    static func stub(_ data: Data, seen: (@Sendable (URLRequest) -> Void)? = nil)
        -> ManifestConnector.HTTP {
        { request in
            seen?(request)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200,
                                          httpVersion: nil, headerFields: [:])!)
        }
    }

    static func manifest() throws -> ConnectorManifest {
        try #require(try ConnectorManifest.bundled().first { $0.id == "nextcloud" })
    }

    /// Ответ из руководства разработчика Nextcloud.
    static let sample = Data(#"{"ocs":{"meta":{"status":"ok","statuscode":200,"message":"OK"},"data":{"name":"Messages","isPaginated":false,"entries":[{"thumbnailUrl":"","title":"Тарифы с декабря","subline":"Аня: годовой не трогаем","resourceUrl":"/call/abc#message_9","icon":"","rounded":false,"attributes":[]}],"cursor":null}}}"#.utf8)

    @Test("сообщение из Talk доходит с текстом, а не только со ссылкой")
    func parsesUnifiedSearch() async throws {
        let connector = ManifestConnector(manifest: try Self.manifest(), token: "ivan:пароль",
                                          host: "https://cloud.company.ru",
                                          values: ["provider": "talk-message"],
                                          http: Self.stub(Self.sample))
        let item = try #require(try await connector.run("тарифы").items.first)
        #expect(item.title == "Тарифы с декабря")
        #expect(item.context == "Аня: годовой не трогаем")
    }

    @Test("пара «имя:пароль» уезжает в Basic закодированной, а не как есть")
    func basicAuthIsEncoded() throws {
        // Сервер принимает только base64. Просить человека закодировать пароль
        // руками значило бы получать в поле неверно закодированное.
        let connector = ManifestConnector(manifest: try Self.manifest(), token: "ivan:пароль",
                                          host: "https://cloud.company.ru",
                                          values: ["provider": "files"],
                                          http: Self.stub(Data("{}".utf8)))
        let request = try connector.makeRequest(query: "тарифы", limit: 10)
        let header = try #require(request.value(forHTTPHeaderField: "Authorization"))
        #expect(header == "Basic " + Data("ivan:пароль".utf8).base64EncodedString())
        // Пароль не должен уехать открытым текстом ни в каком виде.
        #expect(!header.contains("пароль"))
        #expect(request.value(forHTTPHeaderField: "OCS-APIRequest") == "true",
                "без этого заголовка Nextcloud отвечает отказом на правильный запрос")
    }

    @Test("где искать — выбирает человек, и это стоит в адресе")
    func providerTravelsInThePath() throws {
        let connector = ManifestConnector(manifest: try Self.manifest(), token: "ivan:пароль",
                                          host: "https://cloud.company.ru",
                                          values: ["provider": "talk-message"],
                                          http: Self.stub(Data("{}".utf8)))
        let request = try connector.makeRequest(query: "тарифы", limit: 10)
        #expect(request.url?.path == "/ocs/v2.php/search/providers/talk-message/search")
        #expect(request.url?.query?.contains("term=") == true, "слово человека едет в term")
    }

    @Test("без выбранного места поиска Nextcloud не настроен")
    func providerIsRequired() {
        // Иначе в адрес уедет `{provider}` буквами, сервер ответит 404, и
        // человек прочтёт это как поломку сервера.
        let notes = TeamNotes(service: .nextcloud, token: "ivan:пароль", host: "cloud.company.ru",
                              http: { _ in (Data(), stubHTTPResponse()) })
        #expect(!notes.isConfigured)

        let filled = TeamNotes(service: .nextcloud, token: "ivan:пароль", host: "cloud.company.ru",
                               values: ["provider": "files"],
                               http: { _ in (Data(), stubHTTPResponse()) })
        #expect(filled.isConfigured)
    }

    @Test("Nextcloud доходит до человека через базу знаний")
    func reachableThroughTeamNotes() async throws {
        let notes = TeamNotes(service: .nextcloud, token: "ivan:пароль", host: "cloud.company.ru",
                              values: ["provider": "talk-message"],
                              http: { request in
            (Self.sample, HTTPURLResponse(url: request.url!, statusCode: 200,
                                          httpVersion: nil, headerFields: [:])!)
        })
        let hits = try await notes.search("тарифы")
        #expect(hits.first?.context == "Аня: годовой не трогаем")
    }
}
