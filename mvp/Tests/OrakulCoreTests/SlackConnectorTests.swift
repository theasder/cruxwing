import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OrakulCore

/// Slack — решение §7.4 дорожной карты, принято 2026-08-18.
///
/// Технической задачи тут почти нет: метод документирован и прост. Вопрос был
/// продуктовый — личный токен даёт доступ ко ВСЕЙ переписке человека, включая
/// личные сообщения, потому что ботом Slack искать по сообщениям не разрешает.
///
/// Решение: подключаем, но личное до подсказки не доходит — и в настройках
/// написано прямо, на что выдаётся токен. Проверки ниже про вторую половину
/// этого обещания: первую проверить кодом нельзя, её можно только написать
/// честно.
@Suite struct SlackConnectorTests {

    static func stub(_ data: Data, seen: (@Sendable (URLRequest) -> Void)? = nil)
        -> ManifestConnector.HTTP {
        { request in
            seen?(request)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200,
                                          httpVersion: nil, headerFields: [:])!)
        }
    }

    static func manifest() throws -> ConnectorManifest {
        try #require(try ConnectorManifest.bundled().first { $0.id == "slack" })
    }

    /// Ответ по образцу из документации вендора: общий канал, закрытый канал и
    /// групповая личная переписка рядом.
    static let mixed = Data(#"""
    {"ok": true, "query": "тарифы", "messages": {"total": 3, "matches": [
      {"type": "message", "channel": {"id": "C1", "name": "general", "is_private": false, "is_mpim": false},
       "text": "решили поднять тарифы с декабря", "username": "anya", "ts": "1508284197.000015",
       "permalink": "https://team.slack.com/archives/C1/p1"},
      {"type": "message", "channel": {"id": "C2", "name": "salaries", "is_private": true, "is_mpim": false},
       "text": "тарифы по зарплатам обсудим отдельно", "username": "boss", "ts": "1508284198.000015",
       "permalink": "https://team.slack.com/archives/C2/p2"},
      {"type": "message", "channel": {"id": "G1", "name": "mpdm-anya--boss", "is_private": false, "is_mpim": true},
       "text": "личное про тарифы", "username": "boss", "ts": "1508284199.000015",
       "permalink": "https://team.slack.com/archives/G1/p3"}
    ]}}
    """#.utf8)

    @Test("личная переписка не доходит до подсказки")
    func privateConversationsAreDropped() async throws {
        // Главная проверка всего решения. Slack фильтра «только общие каналы»
        // не предлагает, поэтому отбор делаем мы — и если он отвалится, чужая
        // личная переписка уедет в подсказку, а оттуда в модель.
        let connector = ManifestConnector(manifest: try Self.manifest(), token: "xoxp-токен",
                                          host: "https://slack.com",
                                          http: Self.stub(Self.mixed))
        let items = try await connector.run("тарифы").items
        #expect(items.map(\.title) == ["решили поднять тарифы с декабря"])
        #expect(!items.contains { $0.title.contains("зарплатам") }, "закрытый канал уехал в выдачу")
        #expect(!items.contains { $0.title.contains("личное") }, "личная переписка уехала в выдачу")
    }

    @Test("автор сообщения сохраняется: «кто сказал» — половина ответа")
    func authorSurvives() async throws {
        let connector = ManifestConnector(manifest: try Self.manifest(), token: "xoxp-токен",
                                          host: "https://slack.com",
                                          http: Self.stub(Self.mixed))
        let item = try #require(try await connector.run("тарифы").items.first)
        #expect(item.author == "anya")
    }

    @Test("отказ приходит кодом 200 — и человек читает слова Slack")
    func refusalIsReadable() async throws {
        // `{"ok": false}` с кодом 200. Коннектор, смотрящий только на код,
        // показал бы отозванный токен как «ничего не нашлось».
        let refusal = Data(#"{"ok": false, "error": "not_allowed_token_type"}"#.utf8)
        let connector = ManifestConnector(manifest: try Self.manifest(), token: "xoxb-бот",
                                          host: "https://slack.com",
                                          http: Self.stub(refusal))
        await #expect(throws: ManifestConnector.ConnectorError.vendor(
            code: "not_allowed_token_type", description: "")) {
            _ = try await connector.run("тарифы")
        }
    }

    @Test("запрос совпадает с документацией")
    func requestMatchesTheDocs() throws {
        let connector = ManifestConnector(manifest: try Self.manifest(), token: "xoxp-секрет",
                                          host: "https://slack.com",
                                          http: Self.stub(Data("{}".utf8)))
        let request = try connector.makeRequest(query: "тарифы", limit: 10)
        #expect(request.url?.path == "/api/search.messages")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer xoxp-секрет")
        let query = request.url?.query ?? ""
        #expect(query.contains("count=10"), "count у Slack — до ста")
        #expect(query.contains("sort=timestamp"), "свежие сначала: на звонке важнее последнее")
    }

    @Test("подсказка в настройках говорит, на что выдаётся токен")
    func hintNamesTheRealScope() {
        // Единственное место, где человек решает, отдавать ли доступ ко всей
        // переписке. Умолчать здесь — это и есть тот случай, ради которого
        // §7.4 называл вопрос продуктовым.
        let hint = WorkMessengers.Service.slack.credentialHint
        #expect(hint.contains("личн"), "не сказано, что токен личный: «\(hint)»")
        #expect(hint.contains("search:read"), "не названо право, которое надо выдать")
        for word in ["включая личные сообщения", "отбрасывает"] {
            #expect(hint.contains(word), "в подсказке нет «\(word)»: «\(hint)»")
        }
    }

    @Test("Slack не спрашивает ни адреса, ни второй половины токена")
    func nothingExtraIsAsked() {
        // Облачный сервис с одним адресом. Лишнее поле — лишняя опечатка.
        #expect(WorkMessengers.Service.slack.secondaryPrompt == nil)
        #expect(WorkMessengers.Service.slack.scopePrompt == nil)
        #expect(WorkMessengers.Service.slack.pairedTokenPrompt == nil)
    }

    @Test("Slack доходит до человека через мессенджеры")
    func reachableThroughMessengers() async throws {
        let messenger = WorkMessengers(service: .slack, token: "xoxp-токен", secondary: nil,
                                       scope: nil, http: { request in
            (Self.mixed, HTTPURLResponse(url: request.url!, statusCode: 200,
                                         httpVersion: nil, headerFields: [:])!)
        })
        #expect(messenger.isConfigured)
        let hits = try await messenger.search("тарифы")
        #expect(hits.count == 1, "через мессенджеры уехало лишнее: \(hits.map(\.text))")
        #expect(hits.first?.text.contains("декабря") == true)
    }
}
