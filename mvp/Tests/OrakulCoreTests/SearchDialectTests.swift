import Testing
import Foundation
@testable import OrakulCore

/// Сервисы, чей параметр поиска — язык, а не строка.
///
/// Jira была первой, но не единственной. У Slack, Mattermost, Trello и
/// BookStack параметр поиска тоже разбирается как выражение: `in:`, `from:`,
/// `before:`, `@участник`, `#метка`, `[tag=value]`, точная фраза в кавычках.
/// Всё это документировано вендорами.
///
/// Опасно это ровно потому, откуда берётся вопрос: его собирают из речи на
/// звонке. В русской речи двоеточие после слова — обычное дело («Тарифы:
/// пересмотр», «Сроки: до пятницы»), и такой кусок сервис читает как
/// УКАЗАНИЕ, а не как искомое слово. Ответ приходит другой, ошибки нет, и
/// человек видит уверенное «ничего не нашлось» там, где нашлось бы.
@Suite struct SearchDialectTests {

    /// Сервисы, у которых это проверено по документации вендора.
    static let dialects = ["slack", "trello", "bookstack", "mattermost", "jira", "rocketChat"]

    private func manifest(_ id: String) throws -> ConnectorManifest {
        try #require(ConnectorManifest.usable().first { $0.id == id }, "нет манифеста «\(id)»")
    }

    @Test("параметр поиска у языковых сервисов берёт очищённое слово",
          arguments: SearchDialectTests.dialects)
    func dialectsAskForCleanedWords(id: String) throws {
        let manifest = try manifest(id)
        var texts = manifest.request.query.map(\.value)
        texts.append(manifest.request.body ?? "")
        #expect(texts.contains { $0.contains("{queryWords}") },
                "«\(id)» снова отдаёт вопрос как есть в чужой язык поиска")
        #expect(!texts.contains { $0.contains("{query}") },
                "«\(id)»: сырой вопрос всё ещё куда-то едет")
    }

    @Test("указание, произнесённое вслух, доезжает словами",
          arguments: SearchDialectTests.dialects)
    func aSpokenModifierArrivesAsWords(id: String) async throws {
        let manifest = try manifest(id)
        var seen: URLRequest?
        let connector = ManifestConnector(manifest: manifest, token: "t:t",
                                          host: "https://example.test",
                                          values: ["team": "t", "room": "r", "key": "k",
                                                   "workspace": "w", "project": "p"]) { request in
            seen = request
            return (Data("{}".utf8), HTTPURLResponse())
        }
        // Так звучит обычная русская фраза со звонка — и так же звучит попытка
        // подменить вопрос: различить их по тексту нельзя, поэтому обе
        // обезоруживаются одинаково.
        _ = try? await connector.run("Сроки: from:artem \"до пятницы\"", limit: 10)
        let request = try #require(seen, "«\(id)»: запрос не ушёл")
        let sent = (request.url?.absoluteString ?? "")
            + (request.httpBody.map { String(decoding: $0, as: UTF8.self) } ?? "")
        let decoded = sent.removingPercentEncoding ?? sent
        #expect(!decoded.contains("from:"), "«\(id)»: указание доехало указанием")
        #expect(!decoded.contains("Сроки:"), "«\(id)»: двоеточие доехало и меняет вопрос")
        // Слова остаются: вопрос обезоруживают, а не выбрасывают.
        #expect(decoded.contains("Сроки"), "«\(id)»: от вопроса ничего не осталось")
        #expect(decoded.contains("пятницы"), "«\(id)»: хвост вопроса потерялся")
    }

    @Test("сервисы с обычной строкой не трогали")
    func literalServicesAreUnchanged() throws {
        // Границу видно только вместе с тем, что за неё не попало. Zulip
        // собирает выражение МЫ САМИ — `narrow` с оператором `search`, — и
        // внутри операнда текст уже обычная строка. У Redmine, Gitea и
        // Nextcloud параметр литеральный по документации.
        //
        // Rocket.Chat стоял здесь один день. Тогда перечня операторов у
        // вендора найти не удалось, и правило репозитория одно для чтения и
        // для защиты: не нашли — остаётся вопросом, а не догадкой. Нашлось —
        // в его собственном хранилище документации, — и он переехал наверх.
        // Вопрос закрывается фактом, а не сроком давности.
        for id in ["zulip", "redmine", "gitea", "nextcloud"] {
            let manifest = try manifest(id)
            var texts = manifest.request.query.map(\.value)
            texts.append(manifest.request.body ?? "")
            #expect(texts.contains { $0.contains("{query}") },
                    "«\(id)» перевели на очистку без повода и разбора")
        }
    }
}
