import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CruxwingCore

/// Wiki.js — вики только с GraphQL (роадмап, §7.4).
///
/// Отдельный набор потому, что она проверяет две вещи, которых у остальных
/// нет: слово человека уезжает внутрь строки GraphQL-запроса, а отказ приходит
/// кодом 200 в массиве `errors`.
@Suite struct WikiJSConnectorTests {

    static func stub(_ data: Data, seen: (@Sendable (URLRequest) -> Void)? = nil)
        -> ManifestConnector.HTTP {
        { request in
            seen?(request)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200,
                                          httpVersion: nil, headerFields: [:])!)
        }
    }

    static func manifest() throws -> ConnectorManifest {
        try #require(try ConnectorManifest.bundled().first { $0.id == "wikijs" })
    }

    static let sample = Data(#"{"data":{"pages":{"search":{"results":[{"id":"42","title":"Тарифы на 2026","description":"Решение по годовому тарифу","path":"dogovory/tarify","locale":"ru"}],"totalHits":1}}}}"#.utf8)

    @Test("страница из GraphQL доходит с заголовком и словами вокруг")
    func parsesSearchResponse() async throws {
        let connector = ManifestConnector(manifest: try Self.manifest(), token: "токен",
                                          host: "https://wiki.company.ru",
                                          http: Self.stub(Self.sample))
        let item = try #require(try await connector.run("тарифы").items.first)
        #expect(item.title == "Тарифы на 2026")
        #expect(item.context == "Решение по годовому тарифу")
        // Номера у страницы вики нет: id строковый, и подставлять «#42» из
        // строки значило бы выдумывать нумерацию, которой в сервисе не видно.
        #expect(item.key == "—")
    }

    @Test("слово человека уезжает внутрь запроса GraphQL")
    func queryTravelsInsideTheGraphQLString() throws {
        let connector = ManifestConnector(manifest: try Self.manifest(), token: "секрет",
                                          host: "https://wiki.company.ru",
                                          http: Self.stub(Data("{}".utf8)))
        let request = try connector.makeRequest(query: "тарифы", limit: 10)
        #expect(request.url?.path == "/graphql")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer секрет")
        let body = String(data: try #require(request.httpBody), encoding: .utf8) ?? ""
        #expect(body.contains(#"search(query: \"тарифы\")"#), "тело ушло как «\(body)»")
        // Тело обязано остаться разбираемым JSON: иначе сервис ответит 400 на
        // совершенно правильный вопрос.
        #expect((try? JSONSerialization.jsonObject(with: Data(body.utf8))) != nil,
                "тело перестало быть JSON: «\(body)»")
    }

    @Test("кавычка в вопросе не рвёт запрос")
    func quoteInQuerySurvives() throws {
        let connector = ManifestConnector(manifest: try Self.manifest(), token: "секрет",
                                          host: "https://wiki.company.ru",
                                          http: Self.stub(Data("{}".utf8)))
        let request = try connector.makeRequest(query: "тариф \"годовой\"", limit: 10)
        let body = String(data: try #require(request.httpBody), encoding: .utf8) ?? ""
        #expect((try? JSONSerialization.jsonObject(with: Data(body.utf8))) != nil,
                "кавычка сломала тело: «\(body)»")
    }

    @Test("отказ приходит кодом 200 — и человек читает слова сервиса, а не наши")
    func graphQLErrorReachesThePerson() async throws {
        // У GraphQL код ответа всегда 200. Без разбора `errors` человек получил
        // бы «ответил непонятным образом» вместо «нет права read:pages» — то
        // есть не узнал бы, что чинить.
        let refusal = Data(#"{"errors":[{"message":"Unauthorized","extensions":{"code":"FORBIDDEN"}}],"data":null}"#.utf8)
        let connector = ManifestConnector(manifest: try Self.manifest(), token: "токен",
                                          host: "https://wiki.company.ru",
                                          http: Self.stub(refusal))
        await #expect(throws: ManifestConnector.ConnectorError.vendor(code: "FORBIDDEN",
                                                                     description: "Unauthorized")) {
            _ = try await connector.run("тарифы")
        }
    }

    @Test("мусор без errors остаётся отказом нашими словами")
    func garbageIsStillUnreadable() async throws {
        let connector = ManifestConnector(manifest: try Self.manifest(), token: "токен",
                                          host: "https://wiki.company.ru",
                                          http: Self.stub(Data(#"{"привет":"мир"}"#.utf8)))
        await #expect(throws: ManifestConnector.ConnectorError.unreadable) {
            _ = try await connector.run("тарифы")
        }
    }

    @Test("путь умеет заходить в массив по номеру")
    func pathIndexesArrays() {
        let root: [String: Any] = ["errors": [["message": "Первая"], ["message": "Вторая"]]]
        #expect(ManifestConnector.scalar(at: ["errors", "0", "message"], in: root) == "Первая")
        #expect(ManifestConnector.scalar(at: ["errors", "1", "message"], in: root) == "Вторая")
        // За границей массива — пусто, а не падение.
        #expect(ManifestConnector.scalar(at: ["errors", "9", "message"], in: root).isEmpty)
    }

    @Test("Wiki.js доходит до человека через базу знаний")
    func reachableThroughTeamNotes() async throws {
        let notes = TeamNotes(service: .wikijs, token: "токен", host: "wiki.company.ru",
                              http: { request in
            (Self.sample, HTTPURLResponse(url: request.url!, statusCode: 200,
                                          httpVersion: nil, headerFields: [:])!)
        })
        #expect(notes.isConfigured)
        let hits = try await notes.search("тарифы")
        #expect(hits.first?.title == "Тарифы на 2026")
    }
}
