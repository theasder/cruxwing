import Testing
import Foundation
@testable import CruxwingCore

/// Jira Data Center и правило, которое ей понадобилось.
///
/// Все прежние сервисы получают слово как ЗНАЧЕНИЕ параметра: `search=тарифы`.
/// Jira получает его внутри выражения — `jql=text ~ "тарифы"`, — и это первый
/// случай, когда вопрос попадает в чужой ЯЗЫК, а не в чужое поле. Кавычка
/// внутри слова закрывает строку, и остаток становится условием поиска.
///
/// Вопрос собирается из речи на звонке, то есть его текст приходит снаружи.
/// Это та же дверь, что и подмешивание указаний в расшифровку, и закрывать её
/// нужно там же, где она открылась.
@Suite struct JiraConnectorTests {

    private func jira() throws -> ConnectorManifest {
        let found = ConnectorManifest.usable().first { $0.id == "jira" }
        return try #require(found, "манифест Jira не собрался в сборку")
    }

    @Test("слово уходит в JQL, а не в отдельный параметр")
    func theWordTravelsInsideJQL() throws {
        let connector = ManifestConnector(manifest: try jira(), token: "pat",
                                          host: "https://jira.company.ru") { _ in
            (Data("{}".utf8), HTTPURLResponse())
        }
        let request = try connector.makeRequest(query: "тарифы", limit: 10)
        let url = try #require(request.url?.absoluteString)
        let items = URLComponents(string: url)?.queryItems ?? []
        let jql = items.first { $0.name == "jql" }?.value
        #expect(jql == "text ~ \"тарифы\" ORDER BY updated DESC")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer pat")
        // Сортировка не украшение: охват обещает «последние N». Без ORDER BY
        // это обещание было бы неправдой, а неправда про охват — ровно тот
        // случай, который §7.2 разбирает отдельно.
        #expect(jql?.contains("ORDER BY updated DESC") == true)
    }

    @Test("кавычка в вопросе не становится частью запроса")
    func aQuoteCannotEscapeTheString() throws {
        let connector = ManifestConnector(manifest: try jira(), token: "pat",
                                          host: "https://jira.company.ru") { _ in
            (Data("{}".utf8), HTTPURLResponse())
        }
        // Так звучала бы попытка подменить вопрос голосом на звонке.
        let attack = "сроки\" OR project = SECRET AND text ~ \"x"
        let request = try connector.makeRequest(query: attack, limit: 10)
        let jql = URLComponents(string: try #require(request.url?.absoluteString))?
            .queryItems?.first { $0.name == "jql" }?.value ?? ""
        // Ровно две кавычки — те, что поставил манифест. Ни одной от человека.
        #expect(jql.filter { $0 == "\"" }.count == 2)
        #expect(!jql.contains("SECRET\""))
        // Слова остаются словами: мы не выбрасываем вопрос, мы обезоруживаем его.
        #expect(jql.contains("сроки"))
    }

    @Test("служебные знаки становятся пробелом, а не исчезают")
    func reservedCharactersBecomeSpaces() {
        // Вендор пишет прямо: служебные знаки в индекс не попадают. Значит
        // убрать их можно без потери. Но склеить слова нельзя: «Wi-Fi» без
        // дефиса — это «WiFi», слово, которого в индексе нет.
        #expect(ManifestConnector.words(of: "Wi-Fi") == "Wi Fi")
        #expect(ManifestConnector.words(of: "план (черновик)") == "план черновик")
        #expect(ManifestConnector.words(of: "  сроки  ") == "сроки")
    }

    @Test("вопрос из одних знаков не превращается в «отдай всё»")
    func aQuestionOfPunctuationAsksNothing() async throws {
        // `text ~ ""` для сервера означает «всё подряд»: он вернул бы первые
        // задачи, и они встали бы под вопрос, которого никто не задавал.
        var went = false
        let connector = ManifestConnector(manifest: try jira(), token: "pat",
                                          host: "https://jira.company.ru") { _ in
            went = true
            return (Data("{\"issues\":[{\"key\":\"A-1\",\"fields\":{\"summary\":\"чужое\"}}]}".utf8),
                    HTTPURLResponse())
        }
        let outcome = try await connector.run("***", limit: 10)
        #expect(outcome.items.isEmpty)
        #expect(!went, "запрос всё-таки ушёл, и ответ на него выдали бы за находку")
    }

    @Test("ответ разбирается по вложенным полям")
    func nestedFieldsAreRead() async throws {
        let body = """
        {"startAt":0,"maxResults":50,"total":1,"issues":[
          {"id":"10001","key":"ENG-142",
           "fields":{"summary":"Пересмотр тарифов","status":{"name":"In Progress"}}}]}
        """
        let connector = ManifestConnector(manifest: try jira(), token: "pat",
                                          host: "https://jira.company.ru") { _ in
            (Data(body.utf8), HTTPURLResponse())
        }
        let items = try await connector.search("тарифы")
        #expect(items.count == 1)
        #expect(items.first?.title == "Пересмотр тарифов")
        #expect(items.first?.key == "ENG-142")
        #expect(items.first?.state == "In Progress")
    }
}
