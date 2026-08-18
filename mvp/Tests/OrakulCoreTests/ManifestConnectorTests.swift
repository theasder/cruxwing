import Foundation
import Testing
@testable import OrakulCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Коннектор из данных обязан посылать ТОТ ЖЕ запрос, что написанный руками.
///
/// Это главная проверка всей затеи. Описание данными полезно ровно настолько,
/// насколько ему можно доверить то, что уже работает: если движок ставит другой
/// заголовок или теряет параметр, «опишите сервис в JSON» превращается в
/// приглашение сделать хуже, чем есть.
///
/// Поэтому сверяются не отдельные поля по вкусу, а весь запрос целиком — адрес
/// с параметрами и все заголовки — против `SelfHostedTrackers`, у которого
/// адреса сверены с документацией вендоров (см. шапку того файла).
@Suite("Коннектор из манифеста")
struct ManifestConnectorTests {

    static let host = "https://git.example.ru"
    static let token = "t0ken"

    static func manifest(_ id: String) throws -> ConnectorManifest {
        let all = try ConnectorManifest.bundled()
        return try #require(all.first { $0.id == id }, "манифеста «\(id)» нет среди ресурсов")
    }

    /// Запрос, который построил бы написанный руками коннектор.
    static func handWritten(_ service: SelfHostedTrackers.Service,
                            query: String) async throws -> URLRequest {
        let recorder = Recorder()
        let connector = SelfHostedTrackers(service: service, token: token, host: host) { request in
            recorder.record(request)
            // Пустой массив: разбор здесь не проверяется, только запрос.
            return (Data("[]".utf8), stubHTTPResponse())
        }
        // `legacySearch`, а не `search`: после перехода продакшена на манифест
        // `search` сам ходит через манифест, и сверка превращалась в сравнение
        // манифеста с самим собой — она проходила на любой порче. Поймано
        // мутацией 2026-08-18.
        //
        // Ответ намеренно не той формы, что ждёт Redmine, и он на нём
        // отказывается — правильно отказывается. Здесь нужен только запрос.
        _ = try? await connector.legacySearch(query, host: host)
        return try #require(recorder.last, "коннектор не отправил запроса")
    }

    @Test("манифест шлёт тот же запрос, что и написанный руками коннектор",
          arguments: [("gitea", SelfHostedTrackers.Service.gitea),
                      ("gitlab", SelfHostedTrackers.Service.gitlab),
                      ("redmine", SelfHostedTrackers.Service.redmine)])
    func requestMatchesHandWritten(id: String, service: SelfHostedTrackers.Service) async throws {
        let query = "лимиты"
        let expected = try await Self.handWritten(service, query: query)
        let actual = try ManifestConnector(manifest: Self.manifest(id), token: Self.token,
                                           host: Self.host, http: { _ in
            (Data("[]".utf8), stubHTTPResponse())
        }).makeRequest(query: query, limit: 10)

        #expect(actual.url == expected.url, "адрес разошёлся у «\(id)»")
        #expect(actual.httpMethod == expected.httpMethod)
        // Заголовки сравниваются целиком: потерянный `PRIVATE-TOKEN` или
        // `Bearer` вместо `token` дают 401, неотличимый от плохого токена.
        #expect(actual.allHTTPHeaderFields == expected.allHTTPHeaderFields,
                "заголовки разошлись у «\(id)»")
        #expect(actual.timeoutInterval == 8)
    }

    @Test("разбор ответа совпадает с написанным руками",
          arguments: [("gitea", SelfHostedTrackers.Service.gitea,
                       #"[{"number":314,"title":"Поднять лимиты","state":"open"}]"#),
                      ("gitlab", SelfHostedTrackers.Service.gitlab,
                       #"[{"iid":314,"title":"Поднять лимиты","state":"opened"}]"#),
                      ("redmine", SelfHostedTrackers.Service.redmine,
                       #"{"results":[{"id":314,"title":"Поднять лимиты"}]}"#)])
    func parseMatchesHandWritten(id: String, service: SelfHostedTrackers.Service,
                                 json: String) async throws {
        let data = Data(json.utf8)
        let handWritten = try await SelfHostedTrackers(service: service, token: Self.token,
                                                       host: Self.host, http: { _ in
            (data, stubHTTPResponse())
        }).legacySearch("лимиты", host: Self.host)

        let fromManifest = try ManifestConnector(manifest: Self.manifest(id), token: Self.token,
                                                 host: Self.host, http: { _ in
            (data, stubHTTPResponse())
        }).parse(data)

        #expect(fromManifest.map(\.key) == handWritten.map(\.key))
        #expect(fromManifest.map(\.title) == handWritten.map(\.title))
        #expect(fromManifest.map(\.state) == handWritten.map(\.state))
    }

    /// Outline — первый сервис, у которого поиск идёт телом запроса, а
    /// заголовок лежит глубже строки. Сверяется с написанным руками так же
    /// целиком, как и трекеры.
    @Test("Outline из манифеста совпадает с написанным руками")
    func outlineMatchesHandWritten() async throws {
        let json = #"{"data":[{"context":"…по тарифам решили…","document":{"title":"Тарифы"}}]}"#
        let data = Data(json.utf8)
        let recorder = Recorder()
        let handWritten = try await TeamNotes(service: .outline, token: Self.token,
                                              host: "wiki.company.ru", http: { request in
            recorder.record(request)
            return (data, stubHTTPResponse())
        }).legacySearch("тарифы", host: "https://wiki.company.ru")
        let expected = try #require(recorder.last)

        let connector = ManifestConnector(manifest: try Self.manifest("outline"),
                                          token: Self.token, host: "https://wiki.company.ru",
                                          http: { _ in (data, stubHTTPResponse()) })
        let actual = try connector.makeRequest(query: "тарифы", limit: 10)

        #expect(actual.url == expected.url)
        #expect(actual.httpMethod == expected.httpMethod)
        #expect(actual.allHTTPHeaderFields == expected.allHTTPHeaderFields)
        // Тело сравнивается разобранным, а не байтами: порядок ключей в JSON
        // не значит ничего, и сравнение строк ловило бы перестановку.
        let actualBody = try #require(actual.httpBody)
        let expectedBody = try #require(expected.httpBody)
        let a = try #require(JSONSerialization.jsonObject(with: actualBody) as? [String: Any])
        let b = try #require(JSONSerialization.jsonObject(with: expectedBody) as? [String: Any])
        #expect(a["query"] as? String == b["query"] as? String)
        #expect(a["limit"] as? Int == b["limit"] as? Int)

        let hits = try connector.parse(data)
        #expect(hits.map(\.title) == handWritten.map(\.title))
        #expect(hits.map(\.context) == handWritten.map(\.context))
    }

    @Test("кавычка в вопросе не рвёт тело запроса")
    func quoteInQueryKeepsBodyValid() throws {
        let connector = ManifestConnector(manifest: try Self.manifest("outline"),
                                          token: Self.token, host: "https://wiki.company.ru",
                                          http: { _ in (Data(), stubHTTPResponse()) })
        // Человек спрашивает про «прод» в кавычках — без экранирования тело
        // становится битым JSON, сервис отвечает 400, и это выглядит как
        // «ничего не нашлось» на совершенно правильный вопрос.
        let request = try connector.makeRequest(query: #"что решили по "проду""#, limit: 10)
        let body = try #require(request.httpBody)
        let parsed = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(parsed["query"] as? String == #"что решили по "проду""#)
    }

    /// Пачка — первый русский сервис, описанный данными, и первый, у кого
    /// автор приходит числом.
    @Test("Пачка из манифеста совпадает с написанным руками")
    func pachcaMatchesHandWritten() async throws {
        let json = #"{"data":[{"content":"по тарифам решили","user_id":42}]}"#
        let data = Data(json.utf8)
        let recorder = Recorder()
        let handWritten = try await WorkMessengers(service: .pachca, token: Self.token,
                                                   secondary: nil, scope: nil, http: { request in
            recorder.record(request)
            return (data, stubHTTPResponse())
        }).legacySearch("тарифы", host: "https://api.pachca.com")
        let expected = try #require(recorder.last)

        let connector = ManifestConnector(manifest: try Self.manifest("pachca"),
                                          token: Self.token, host: "https://api.pachca.com",
                                          http: { _ in (data, stubHTTPResponse()) })
        let actual = try connector.makeRequest(query: "тарифы", limit: 10)

        #expect(actual.url == expected.url)
        #expect(actual.allHTTPHeaderFields == expected.allHTTPHeaderFields)

        let hits = try connector.parse(data)
        #expect(hits.map(\.title) == handWritten.map(\.text))
        // Автор пришёл числом и обязан доехать строкой, а не пропасть.
        #expect(hits.map(\.author) == handWritten.map { $0.author ?? "" })
        #expect(hits.first?.author == "42")
    }

    @Test("403 — это недостающее право, а не плохой токен")
    func forbiddenIsNotUnauthorised() async throws {
        // Разные починки: «выпустите новый токен» против «выдайте право в
        // настройках сервиса». Совет не тот стоит человеку получаса.
        let connector = ManifestConnector(manifest: try Self.manifest("pachca"),
                                          token: Self.token, host: "https://api.pachca.com",
                                          http: { _ in (Data(), stubHTTPResponse(status: 403)) })
        await #expect(throws: ManifestConnector.ConnectorError.forbidden) {
            try await connector.search("тарифы")
        }
    }

    /// WEEEK — первый российский трекер, описанный данными, и первый сервис,
    /// который отвечает отказом с кодом 200.
    @Test("WEEEK из манифеста совпадает с написанным руками")
    func weeekMatchesHandWritten() async throws {
        let json = #"{"success":true,"tasks":[{"id":42,"title":"Поднять лимиты"}]}"#
        let data = Data(json.utf8)
        let recorder = Recorder()
        let handWritten = try await RussianTrackers(service: .weeek, token: Self.token,
                                                    secondary: nil, destination: nil,
                                                    http: { request in
            recorder.record(request)
            return (data, stubHTTPResponse())
        }).legacySearch("лимиты", limit: 10)
        let expected = try #require(recorder.last)

        let connector = ManifestConnector(manifest: try Self.manifest("weeek"),
                                          token: Self.token,
                                          host: "https://api.weeek.net/public/v1",
                                          http: { _ in (data, stubHTTPResponse()) })
        let actual = try connector.makeRequest(query: "лимиты", limit: 10)

        #expect(actual.url == expected.url)
        // Заголовки сверяются по авторизации, а не целиком, и это ЕДИНСТВЕННОЕ
        // расхождение из проверенных: написанный руками путь ставит
        // `Content-Type: application/json` даже на GET без тела. Заголовок там
        // ничего не значит, и повторять его в манифесте — значит копировать
        // огрех, а не поведение. Расхождение названо здесь, чтобы оно осталось
        // решением, а не находкой следующего человека.
        #expect(actual.value(forHTTPHeaderField: "Authorization")
                == expected.value(forHTTPHeaderField: "Authorization"))
        #expect(actual.httpBody == nil && expected.httpBody == nil,
                "GET с телом — это уже другой запрос, а не тот же самый")

        let issues = try connector.parse(data)
        #expect(issues.map(\.title) == handWritten.map(\.title))
        #expect(issues.map { $0.key.hasPrefix("#") ? String($0.key.dropFirst()) : $0.key }
                == handWritten.map(\.key))
    }

    @Test("отказ с кодом 200 доносит слова сервиса, а не наше «не понял»")
    func vendorRefusalKeepsItsWords() throws {
        // WEEEK отвечает 200 и кладёт отказ в тело. «Сервис ответил непонятным
        // образом» отправляет человека проверять адрес и версию; «invalid_token
        // — Token revoked» отправляет выпускать новый токен. Разница в том,
        // потратит он вечер или минуту.
        let connector = ManifestConnector(manifest: try Self.manifest("weeek"),
                                          token: Self.token,
                                          host: "https://api.weeek.net/public/v1",
                                          http: { _ in (Data(), stubHTTPResponse()) })
        #expect(throws: ManifestConnector.ConnectorError.vendor(
            code: "invalid_token", description: "Token revoked")) {
            try connector.parse(Data(#"{"success":false,"error":"invalid_token","message":"Token revoked"}"#.utf8))
        }
    }

    @Test("незнакомая форма ответа — отказ, а не пустая выдача")
    func unknownShapeIsRefusal() throws {
        let connector = ManifestConnector(manifest: try Self.manifest("gitea"), token: Self.token,
                                          host: Self.host, http: { _ in
            (Data(), stubHTTPResponse())
        })
        // Тело ошибки вместо списка. Вернуть [] означало бы сказать «задач нет»
        // там, где мы просто не смогли спросить, — и человек заведёт вторую
        // задачу поверх существующей.
        #expect(throws: ManifestConnector.ConnectorError.unreadable) {
            try connector.parse(Data(#"{"message":"token expired"}"#.utf8))
        }
        // А узнанная форма с нулём строк — честный ноль.
        #expect(try connector.parse(Data("[]".utf8)).isEmpty)
    }

    @Test("строка без заголовка пропускается, остальные доходят")
    func rowWithoutTitleIsSkipped() throws {
        let connector = ManifestConnector(manifest: try Self.manifest("gitea"), token: Self.token,
                                          host: Self.host, http: { _ in
            (Data(), stubHTTPResponse())
        })
        let items = try connector.parse(Data(#"""
        [{"number":1,"title":""},{"number":2,"title":"Живая задача"}]
        """#.utf8))
        #expect(items.map(\.title) == ["Живая задача"])
    }

    @Test("каждый манифест либо ищет словом, либо перечисляет с границей")
    func everyManifestPassesTheGate() throws {
        let manifests = try ConnectorManifest.bundled()
        #expect(manifests.count >= 3,
                "манифестов нашлось \(manifests.count) — проверка была бы пустой")
        for manifest in manifests {
            #expect(manifest.docs.hasPrefix("http"), "«\(manifest.id)» без документации")
            // Слово может ехать параметром или телом — у Outline параметров
            // нет вовсе. С 2026-08-18 (§7.2) допустим и третий случай:
            // перечисление, но только объявленное границей и отбором.
            let inQuery = manifest.request.query.contains { $0.value.contains("{query}") }
            let inBody = manifest.request.body?.contains("{query}") ?? false
            if let scan = manifest.scan {
                #expect(!scan.match.isEmpty, "«\(manifest.id)»: перечисление без отбора")
                #expect(scan.pages >= 1 && scan.pages <= ManifestConnector.scanPageLimit,
                        "«\(manifest.id)»: перечисление без границы")
            } else {
                #expect(inQuery || inBody, "«\(manifest.id)» без параметра поиска")
            }
            #expect(manifest.verifiedOn.count == 10,
                    "«\(manifest.id)»: дата проверки не в виде ГГГГ-ММ-ДД")
        }
    }

    @Test("сервис, который только перечисляет, без границы не загружается")
    func scanWithoutBoundIsRejected() throws {
        // Без потолка коннектор выкачивает чужой трекер целиком — и всё равно
        // не обещает найти. Число берётся из движка, а не из манифеста.
        let json = #"""
        {"id":"безграничный","title":"Безграничный","docs":"https://example.com/api",
         "verifiedOn":"2026-08-18",
         "request":{"method":"GET","path":"/items","query":[],"headers":[]},
         "scan":{"pages":99,"perPage":100,"page":[],"match":[["name"]]},
         "response":{"list":["results"],"title":["name"],"key":["id"],"state":[]}}
        """#
        let manifest = try JSONDecoder().decode(ConnectorManifest.self, from: Data(json.utf8))
        #expect(throws: ConnectorManifest.ManifestError.unboundedScan("безграничный")) {
            try manifest.validate()
        }
    }

    @Test("перечисление без отбора — это список, а не поиск")
    func scanWithoutMatchIsRejected() throws {
        let json = #"""
        {"id":"списочный","title":"Списочный","docs":"https://example.com/api",
         "verifiedOn":"2026-08-18",
         "request":{"method":"GET","path":"/items","query":[],"headers":[]},
         "scan":{"pages":3,"perPage":50,"page":[],"match":[]},
         "response":{"list":["results"],"title":["name"],"key":["id"],"state":[]}}
        """#
        let manifest = try JSONDecoder().decode(ConnectorManifest.self, from: Data(json.utf8))
        #expect(throws: ConnectorManifest.ManifestError.scanWithoutMatch("списочный")) {
            try manifest.validate()
        }
    }

    @Test("подстановка, которую некому заполнить, не загружается")
    func unknownPlaceholderIsRejected() throws {
        // Иначе `{project}` уедет в адрес буквой, сервис ответит 404, и человек
        // прочтёт это как поломку, а не как незаполненную настройку.
        let json = #"""
        {"id":"дырявый","title":"Дырявый","docs":"https://example.com/api",
         "verifiedOn":"2026-08-18",
         "request":{"method":"GET","path":"/p/{project}/items",
                    "query":[{"name":"q","value":"{query}"}],"headers":[]},
         "response":{"list":[],"title":["name"],"key":["id"],"state":[]}}
        """#
        let manifest = try JSONDecoder().decode(ConnectorManifest.self, from: Data(json.utf8))
        #expect(throws: ConnectorManifest.ManifestError.unknownPlaceholder("дырявый", "project")) {
            try manifest.validate()
        }
    }

    @Test("манифест без документации не загружается")
    func manifestWithoutDocsIsRejected() throws {
        let json = #"""
        {"id":"выдуманный","title":"Выдуманный","docs":"","verifiedOn":"2026-08-18",
         "request":{"method":"GET","path":"/search","query":[{"name":"q","value":"{query}"}],"headers":[]},
         "response":{"list":[],"title":["title"],"key":["id"],"state":["state"]}}
        """#
        let manifest = try JSONDecoder().decode(ConnectorManifest.self, from: Data(json.utf8))
        #expect(throws: ConnectorManifest.ManifestError.missingDocumentation("выдуманный")) {
            try manifest.validate()
        }
    }

    @Test("манифест без параметра поиска не загружается")
    func manifestWithoutSearchIsRejected() throws {
        // Перечисление задач — не поиск. Это правило уже сняло Pyrus и Яндекс
        // Вики; здесь оно исполняется, а не пересказывается.
        let json = #"""
        {"id":"перечисление","title":"Перечисление","docs":"https://example.ru/api",
         "verifiedOn":"2026-08-18",
         "request":{"method":"GET","path":"/tasks","query":[{"name":"limit","value":"{limit}"}],"headers":[]},
         "response":{"list":[],"title":["title"],"key":["id"],"state":["state"]}}
        """#
        let manifest = try JSONDecoder().decode(ConnectorManifest.self, from: Data(json.utf8))
        #expect(throws: ConnectorManifest.ManifestError.noSearchParameter("перечисление")) {
            try manifest.validate()
        }
    }
}
