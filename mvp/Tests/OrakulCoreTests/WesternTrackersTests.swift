import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OrakulCore

/// Западные трекеры в облаке: Linear и Trello.
///
/// Проверяется то, что нельзя увидеть чтением кода: форма запроса совпадает с
/// документацией вендора, а разбор — с примерами ответа оттуда же.
@Suite struct WesternTrackersTests {

    static func stub(_ data: Data, seen: (@Sendable (URLRequest) -> Void)? = nil)
        -> WesternTrackers.HTTP {
        { request in
            seen?(request)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200,
                                          httpVersion: nil, headerFields: [:])!)
        }
    }

    final class Seen: @unchecked Sendable {
        private var requests: [URLRequest] = []
        func add(_ request: URLRequest) { requests.append(request) }
        var last: URLRequest? { requests.last }
    }

    // MARK: - Linear

    static let linearAnswer = Data(#"{"data":{"searchIssues":{"nodes":[{"identifier":"ENG-123","title":"Поднять лимиты выгрузки","description":"Решили на созвоне в четверг","state":{"name":"In Progress"}}]}}}"#.utf8)

    @Test("Linear: обозначение задачи идёт как есть, без решётки")
    func linearKeepsTheIdentifier() async throws {
        // «#ENG-123» человек в своём трекере не найдёт: там такого нет.
        let tracker = WesternTrackers(service: .linear, token: "lin_api_ключ",
                                      http: Self.stub(Self.linearAnswer))
        let item = try #require(try await tracker.search("лимиты").first)
        #expect(item.key == "ENG-123")
        #expect(item.title == "Поднять лимиты выгрузки")
        #expect(item.context == "Решили на созвоне в четверг")
        #expect(item.state == "In Progress")
    }

    @Test("Linear: ключ уезжает без слова Bearer")
    func linearSendsRawKey() async throws {
        // С Bearer ходят токены OAuth. Перепутать — получить 401, неотличимый
        // от истёкшего ключа, и отправить человека выпускать новый зря.
        let seen = Seen()
        let tracker = WesternTrackers(service: .linear, token: "lin_api_ключ",
                                      http: Self.stub(Self.linearAnswer, seen: { seen.add($0) }))
        _ = try await tracker.search("лимиты")
        let request = try #require(seen.last)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "lin_api_ключ")
        #expect(request.url?.absoluteString == "https://api.linear.app/graphql")
        #expect(request.httpMethod == "POST")
        let body = String(data: try #require(request.httpBody), encoding: .utf8) ?? ""
        #expect(body.contains(#"searchIssues(term: \"лимиты\""#), "тело: «\(body)»")
        #expect((try? JSONSerialization.jsonObject(with: Data(body.utf8))) != nil,
                "тело перестало быть JSON: «\(body)»")
    }

    @Test("Linear: отказ кодом 200 доносит слова сервиса")
    func linearVendorError() async throws {
        let refusal = Data(#"{"errors":[{"message":"Authentication required","extensions":{"code":"AUTHENTICATION_ERROR"}}]}"#.utf8)
        let tracker = WesternTrackers(service: .linear, token: "плохой",
                                      http: Self.stub(refusal))
        await #expect(throws: WesternTrackers.ConnectorError.vendor(
            code: "AUTHENTICATION_ERROR", description: "Authentication required")) {
            _ = try await tracker.search("лимиты")
        }
    }

    // MARK: - Trello

    static let trelloAnswer = Data(#"{"cards":[{"id":"5e568d33e9b5e88bb99996d0","idShort":42,"name":"Тарифы с декабря","desc":"Годовой не трогаем","url":"https://trello.com/c/abc"}],"boards":[],"members":[]}"#.utf8)

    @Test("Trello: карточка приходит с номером доски и описанием")
    func trelloParsesCards() async throws {
        let tracker = WesternTrackers(service: .trello, token: "токен",
                                      values: ["key": "ключ"],
                                      http: Self.stub(Self.trelloAnswer))
        let item = try #require(try await tracker.search("тарифы").first)
        #expect(item.key == "#42")
        #expect(item.title == "Тарифы с декабря")
        #expect(item.context == "Годовой не трогаем")
    }

    @Test("Trello: секреты уезжают заголовком, а не в адресе")
    func trelloSendsSecretsInAHeader() async throws {
        // В адресе они попадут в журнал прокси и в историю обращений.
        let seen = Seen()
        let tracker = WesternTrackers(service: .trello, token: "секрет-токен",
                                      values: ["key": "ключ-приложения"],
                                      http: Self.stub(Self.trelloAnswer, seen: { seen.add($0) }))
        _ = try await tracker.search("тарифы")
        let request = try #require(seen.last)
        let address = request.url?.absoluteString ?? ""
        #expect(!address.contains("секрет-токен"), "токен уехал в адресе: «\(address)»")
        #expect(!address.contains("ключ-приложения"))
        #expect(request.value(forHTTPHeaderField: "Authorization")
                == "OAuth oauth_consumer_key=\"ключ-приложения\", oauth_token=\"секрет-токен\"")
    }

    @Test("Trello: без partial=true «тариф» не находит «тарифы»")
    func trelloAsksForPartialMatches() async throws {
        // По умолчанию Trello ищет целые слова. Человек, набравший половину
        // слова, получил бы пусто и решил, что поиск сломан.
        let seen = Seen()
        let tracker = WesternTrackers(service: .trello, token: "токен",
                                      values: ["key": "ключ"],
                                      http: Self.stub(Self.trelloAnswer, seen: { seen.add($0) }))
        _ = try await tracker.search("тариф")
        let query = try #require(seen.last?.url?.query)
        #expect(query.contains("partial=true"))
        #expect(query.contains("modelTypes=cards"), "иначе в выдачу лезут доски и участники")
    }

    @Test("Trello без ключа приложения — не подключён")
    func trelloNeedsItsKey() {
        let tracker = WesternTrackers(service: .trello, token: "токен",
                                      http: { _ in (Data(), stubHTTPResponse()) })
        #expect(!tracker.isConfigured)
        #expect(WesternTrackers(service: .trello, token: "токен", values: ["key": "ключ"],
                                http: { _ in (Data(), stubHTTPResponse()) }).isConfigured)
    }

    // MARK: - Общее

    @Test("у обоих сервисов поиск свой, поэтому приписки об охвате нет")
    func bothSearchThemselves() async throws {
        let linear = WesternTrackers(service: .linear, token: "ключ",
                                     http: Self.stub(Self.linearAnswer))
        #expect(try await linear.run("лимиты").coverage == .searched)
        let trello = WesternTrackers(service: .trello, token: "токен", values: ["key": "ключ"],
                                     http: Self.stub(Self.trelloAnswer))
        #expect(try await trello.run("тарифы").coverage.note().isEmpty)
    }

    @Test("адрес сервиса не спрашивают у человека")
    func hostIsKnownInAdvance() async throws {
        // Облачный сервис один на всех. Спросить адрес — значит просить ввести
        // то, что мы знаем, а потом разбираться с опечаткой.
        let seen = Seen()
        let tracker = WesternTrackers(service: .trello, token: "токен", values: ["key": "ключ"],
                                      http: Self.stub(Self.trelloAnswer, seen: { seen.add($0) }))
        _ = try await tracker.search("тарифы")
        #expect(seen.last?.url?.host == "api.trello.com")
    }

    @Test("403 — недостающее право, а не плохой ключ")
    func forbiddenIsItsOwnAnswer() async {
        let tracker = WesternTrackers(service: .trello, token: "токен", values: ["key": "ключ"],
                                      http: { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 403,
                                     httpVersion: nil, headerFields: [:])!)
        })
        await #expect(throws: WesternTrackers.ConnectorError.forbidden) {
            _ = try await tracker.search("тарифы")
        }
    }

    @Test("каждый западный трекер описан манифестом")
    func everyServiceHasAManifest() throws {
        let manifests = try ConnectorManifest.bundled()
        for service in WesternTrackers.Service.allCases {
            let manifest = try #require(manifests.first { $0.id == service.rawValue },
                                        "у «\(service.rawValue)» нет описания — запрос собрать не из чего")
            #expect(manifest.title == service.title)
        }
    }
}
