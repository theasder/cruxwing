import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CruxwingCore

/// Перечисление вместо поиска — решение §7.2 дорожной карты, 2026-08-18.
///
/// Проверяется не то, что коннектор что-то находит, а то, что он не выдаёт
/// часть за целое. Ошибка «десять задач из сорока семи» (план, §4) случилась
/// именно так, и здесь она стоила бы дороже: человек спрашивает «что решили»,
/// получает «ничего не нашлось» и заводит вторую задачу поверх существующей.
@Suite struct ScanConnectorTests {

    /// Манифест перечисляющего сервиса. Форма ответа — Plane, как в справочнике.
    static func manifest(pages: Int = 5, perPage: Int = 100, more: Bool = true) -> ConnectorManifest {
        let moreLine = more ? #""more":["next_page_results"],"# : ""
        let json = #"""
        {"id":"перечислитель","title":"Перечислитель","docs":"https://example.com/api",
         "verifiedOn":"2026-08-18",
         "request":{"method":"GET","path":"/items","query":[],"headers":[]},
         "scan":{"pages":\#(pages),"perPage":\#(perPage),
                 "page":[{"name":"cursor","value":"{perPage}:{page}:0"}],
                 "match":[["name"],["description"]],\#(moreLine)
                 "total":["total_count"]},
         "response":{"list":["results"],"title":["name"],"context":["description"],
                     "key":["sequence_id"],"state":["state","name"]}}
        """#
        return try! JSONDecoder().decode(ConnectorManifest.self, from: Data(json.utf8))
    }

    static func page(_ rows: [String], more: Bool, total: Int) -> Data {
        Data(#"{"total_count":\#(total),"next_page_results":\#(more),"results":[\#(rows.joined(separator: ","))]}"#.utf8)
    }

    static func row(_ number: Int, _ name: String, description: String = "") -> String {
        #"{"sequence_id":\#(number),"name":"\#(name)","description":"\#(description)","state":{"name":"В работе"}}"#
    }

    static func stub(_ pages: [Data], seen: (@Sendable (URLRequest) -> Void)? = nil)
        -> ManifestConnector.HTTP {
        let box = Box(pages)
        return { request in
            seen?(request)
            let data = box.next()
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200,
                                          httpVersion: nil, headerFields: [:])!)
        }
    }

    final class Box: @unchecked Sendable {
        private var pages: [Data]
        private var index = 0
        init(_ pages: [Data]) { self.pages = pages }
        func next() -> Data {
            defer { index += 1 }
            return pages[min(index, pages.count - 1)]
        }
        var calls: Int { index }
    }

    @Test("отбор идёт по описанным полям, а не по всей строке")
    func filtersOnDeclaredFields() async throws {
        let http = Self.stub([Self.page([
            Self.row(1, "Поднять лимиты"),
            Self.row(2, "Починить экспорт", description: "лимиты выгрузки тоже"),
            Self.row(3, "Обновить зависимости")
        ], more: false, total: 3)])
        let connector = ManifestConnector(manifest: Self.manifest(), token: "t",
                                          host: "https://example.com", http: http)
        let outcome = try await connector.run("лимиты")
        #expect(outcome.items.map(\.key) == ["#1", "#2"])
        #expect(outcome.items.first?.state == "В работе", "состояние лежит на уровень глубже строки")
    }

    @Test("список кончился — это полный ответ, и так и сказано")
    func exhaustedListIsComplete() async throws {
        let http = Self.stub([Self.page([Self.row(1, "Поднять лимиты")], more: false, total: 1)])
        let connector = ManifestConnector(manifest: Self.manifest(), token: "t",
                                          host: "https://example.com", http: http)
        let outcome = try await connector.run("лимиты")
        #expect(outcome.coverage == .wholeList(scanned: 1))
        #expect(outcome.coverage.note().contains("all 1"))
    }

    @Test("граница сработала — выдача называет и охват, и полный размер")
    func boundedScanTellsTheTruth() async throws {
        // Сервис говорит «дальше есть ещё» на каждой странице: сорок тысяч
        // задач, две страницы по сто — ответ про двести, а не про сорок тысяч.
        let full = (1...100).map { Self.row($0, "Задача \($0)") }
        let http = Self.stub([Self.page(full, more: true, total: 40000)])
        let connector = ManifestConnector(manifest: Self.manifest(pages: 2), token: "t",
                                          host: "https://example.com", http: http)
        let outcome = try await connector.run("которой нет")
        #expect(outcome.items.isEmpty)
        #expect(outcome.coverage == .latest(scanned: 200, total: 40000))
        #expect(outcome.coverage.note().contains("the most recent 200"))
        #expect(outcome.coverage.note().contains("40000"))
    }

    @Test("страниц читается не больше объявленного")
    func stopsAtTheDeclaredBound() async throws {
        let full = (1...100).map { Self.row($0, "Задача \($0)") }
        let box = Box([Self.page(full, more: true, total: 40000)])
        let http: ManifestConnector.HTTP = { request in
            (box.next(), HTTPURLResponse(url: request.url!, statusCode: 200,
                                         httpVersion: nil, headerFields: [:])!)
        }
        let connector = ManifestConnector(manifest: Self.manifest(pages: 3), token: "t",
                                          host: "https://example.com", http: http)
        _ = try await connector.run("которой нет")
        #expect(box.calls == 3, "прочитано страниц: \(box.calls), объявлено 3")
    }

    @Test("потолок движка сильнее числа в манифесте")
    func engineCapBeatsTheManifest() throws {
        // Автор манифеста заинтересован поднять границу — «а вдруг найдётся».
        // Упирается он не в нас, а в чужой сервис: у Plane шестьдесят запросов
        // в минуту на клиента.
        #expect(throws: ConnectorManifest.ManifestError.self) {
            try Self.manifest(pages: ManifestConnector.scanPageLimit + 1).validate()
        }
    }

    @Test("без признака «есть ещё» конец списка виден по короткой странице")
    func shortPageEndsTheWalk() async throws {
        let http = Self.stub([Data(#"{"total_count":2,"results":[\#(Self.row(1, "Лимиты"))]}"#.utf8)])
        let connector = ManifestConnector(manifest: Self.manifest(perPage: 100, more: false),
                                          token: "t", host: "https://example.com", http: http)
        let outcome = try await connector.run("лимиты")
        #expect(outcome.coverage == .wholeList(scanned: 1))
    }

    @Test("страница подставляется в запрос, а не остаётся шаблоном")
    func pageReachesTheRequest() async throws {
        let seen = Seen()
        let full = (1...100).map { Self.row($0, "Задача \($0)") }
        let http = Self.stub([Self.page(full, more: true, total: 500)], seen: { seen.add($0.url?.query ?? "") })
        let connector = ManifestConnector(manifest: Self.manifest(pages: 2), token: "t",
                                          host: "https://example.com", http: http)
        _ = try await connector.run("что-нибудь")
        #expect(seen.all == ["cursor=100:0:0", "cursor=100:1:0"])
    }

    final class Seen: @unchecked Sendable {
        private var queries: [String] = []
        func add(_ q: String) { queries.append(q) }
        var all: [String] { queries.map { $0.replacingOccurrences(of: "%3A", with: ":") } }
    }

    @Test("обычный поиск охвата не приписывает")
    func searchingServiceSaysNothing() async throws {
        let json = #"""
        {"id":"ищущий","title":"Ищущий","docs":"https://example.com/api","verifiedOn":"2026-08-18",
         "request":{"method":"GET","path":"/search","query":[{"name":"q","value":"{query}"}],"headers":[]},
         "response":{"list":[],"title":["title"],"key":["id"],"state":[]}}
        """#
        let manifest = try JSONDecoder().decode(ConnectorManifest.self, from: Data(json.utf8))
        let http = Self.stub([Data(#"[{"id":1,"title":"Поднять лимиты"}]"#.utf8)])
        let connector = ManifestConnector(manifest: manifest, token: "t",
                                          host: "https://example.com", http: http)
        let outcome = try await connector.run("лимиты")
        #expect(outcome.coverage == .searched)
        #expect(outcome.coverage.note().isEmpty, "приписка к обычному поиску — шум в каждой подсказке")
    }

    @Test("незаполненное поле — не «настроено наполовину»")
    func missingFieldIsNotConfigured() throws {
        let json = #"""
        {"id":"полевой","title":"Полевой","docs":"https://example.com/api","verifiedOn":"2026-08-18",
         "parameters":[{"name":"project","title":"Проект","example":"abc"}],
         "request":{"method":"GET","path":"/p/{project}/search",
                    "query":[{"name":"q","value":"{query}"}],"headers":[]},
         "response":{"list":[],"title":["title"],"key":["id"],"state":[]}}
        """#
        let manifest = try JSONDecoder().decode(ConnectorManifest.self, from: Data(json.utf8))
        try manifest.validate()
        let http = Self.stub([Data("[]".utf8)])
        let empty = ManifestConnector(manifest: manifest, token: "t",
                                      host: "https://example.com", http: http)
        #expect(!empty.isConfigured, "без значения поля адрес соберётся с {project} буквой")

        let filled = ManifestConnector(manifest: manifest, token: "t", host: "https://example.com",
                                       values: ["project": "moya-komanda"], http: http)
        #expect(filled.isConfigured)
        let request = try filled.makeRequest(query: "лимиты", limit: 10)
        #expect(request.url?.path == "/p/moya-komanda/search")
    }

    /// Ответ, скопированный из справочника Plane (читан 2026-08-18), а не
    /// придуманный под наш разбор. Придуманный проверяет, что разбор согласен
    /// сам с собой; этот — что он согласен с сервисом.
    /// Ответ в форме, которую отдаёт ЖИВОЙ Plane, а не в той, что напечатана в
    /// справочнике. Раньше здесь стоял пример из документации — с полями
    /// `description` и `state.name`, которых сервис не присылает, — и проверка
    /// была зелёной ровно потому, что описывала несуществующее. Живая проба
    /// 2026-08-19 это показала; §7.4 плана записывает находку.
    @Test("Plane разбирается по ответу живого сервиса")
    func planeParsesTheVendorSample() async throws {
        let sample = #"""
        {
          "grouped_by": "state", "sub_grouped_by": "priority", "total_count": 150,
          "next_cursor": "20:1:0", "prev_cursor": "20:0:0",
          "next_page_results": true, "prev_page_results": false,
          "count": 20, "total_pages": 8, "total_results": 150, "extra_stats": null,
          "results": [
            {
              "id": "550e8400-e29b-41d4-a716-446655440000",
              "name": "Поднять лимиты выгрузки",
              "description_html": "<p>Обсуждали на созвоне</p>",
              "priority": "high", "sequence_id": 123,
              "state": "505c4110-46ec-4ac8-b199-8b3a2f904daf",
              "assignees": [], "labels": [], "created_at": "2024-01-01T00:00:00Z"
            }
          ]
        }
        """#
        let plane = try #require(try ConnectorManifest.bundled().first { $0.id == "plane" })
        let connector = ManifestConnector(manifest: plane, token: "ключ",
                                          host: "https://api.plane.so",
                                          values: ["workspace": "moya-komanda", "project": "проект"],
                                          http: Self.stub([Data(sample.utf8)]))
        // Заглушка отдаёт одну и ту же страницу на все пять чтений: граница
        // plane.json — пять страниц, и видно, что движок её и держит.
        let outcome = try await connector.run("лимиты")
        let item = try #require(outcome.items.first)
        #expect(item.key == "#123", "номер задачи — sequence_id, а не uuid")
        #expect(item.title == "Поднять лимиты выгрузки")
        // Состояние приходит идентификатором, названия в этом ответе нет.
        #expect(item.state == "")
        #expect(item.context == "Обсуждали на созвоне")
        // Сервис сказал «дальше есть ещё» — значит выдача неполная, и это
        // должно доехать до человека вместе со ста пятьюдесятью.
        #expect(outcome.coverage == .latest(scanned: 5, total: 150))
    }

    @Test("адрес Plane собирается из полей, которые заполняет человек")
    func planeAddressUsesTheFields() throws {
        let plane = try #require(try ConnectorManifest.bundled().first { $0.id == "plane" })
        let connector = ManifestConnector(manifest: plane, token: "ключ",
                                          host: "https://api.plane.so",
                                          values: ["workspace": "moya-komanda",
                                                   "project": "550e8400-e29b-41d4-a716-446655440000"],
                                          http: Self.stub([Data("{}".utf8)]))
        let request = try connector.makeRequest(query: "лимиты", limit: 10, page: 2)
        // Косая черта на конце обязана уехать в запрос: Plane на Django, и
        // адрес без неё — другой адрес. `url.path` её срезает, поэтому
        // проверяется строка целиком, а не разобранный путь.
        let address = try #require(request.url?.absoluteString)
        #expect(address.contains("/projects/550e8400-e29b-41d4-a716-446655440000/work-items/?"),
                "адрес ушёл как «\(address)»")
        #expect(request.value(forHTTPHeaderField: "X-API-Key") == "ключ")
        let query = request.url?.query?.replacingOccurrences(of: "%3A", with: ":") ?? ""
        #expect(query.contains("cursor=100:2:0"), "курсор Plane — «размер:страница:назад»")
        #expect(query.contains("per_page=100"))
        // Слова человека в запросе нет вовсе — в этом и смысл: сервис не ищет.
        #expect(!query.contains("лимиты") && !query.contains("%D0%BB"))
    }

    // MARK: - Plane как настоящий трекер, а не файл в ресурсах

    @Test("Plane доходит до человека через обычный поиск по трекеру")
    func planeIsReachableAsATracker() async throws {
        let page = Self.page([Self.row(7, "Поднять лимиты выгрузки")], more: false, total: 1)
        let tracker = SelfHostedTrackers(
            service: .plane, token: "ключ", host: "api.plane.so",
            values: ["workspace": "moya-komanda", "project": "проект"],
            http: { request in
                (page, HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: [:])!)
            })
        #expect(tracker.isConfigured)
        let outcome = try await tracker.run("лимиты")
        #expect(outcome.items.map(\.key) == ["#7"])
        #expect(outcome.note.contains("looked through all"))
    }

    @Test("токен и адрес есть, а поля пустые — это «не подключён»")
    func planeWithoutFieldsIsNotConfigured() {
        let tracker = SelfHostedTrackers(service: .plane, token: "ключ", host: "api.plane.so",
                                         http: { _ in (Data(), stubHTTPResponse()) })
        // Иначе первый же вопрос уходит по адресу с {project} буквами, сервис
        // отвечает 404, и человек читает это как поломку сервиса.
        #expect(!tracker.isConfigured)
    }

    @Test("поля Plane описаны манифестом, а не списком в коде")
    func planeFieldsComeFromTheManifest() {
        let names = SelfHostedTrackers.Service.plane.fields.map(\.name)
        #expect(names == ["workspace", "project"])
        #expect(SelfHostedTrackers.Service.gitea.fields.isEmpty,
                "у сервиса, которому хватает адреса, лишних полей быть не должно")
        for field in SelfHostedTrackers.Service.plane.fields {
            #expect(!field.title.isEmpty && !field.example.isEmpty,
                    "поле «\(field.name)» нечем объяснить человеку")
        }
    }

    @Test("«ничего не нашлось» у Plane договаривает, среди чего искали")
    func emptyAnswerCarriesCoverage() async throws {
        // Самый важный случай во всём §7.2. Пустой ответ без охвата читается
        // как «в трекере этого нет» — а смотрели мы последние пятьсот из сорока
        // тысяч.
        let full = (1...100).map { Self.row($0, "Задача \($0)") }
        let page = Self.page(full, more: true, total: 40000)
        let answer = await ConnectorQuery.ask(
            .init(service: "plane", token: "ключ", host: "api.plane.so", scope: nil,
                  values: ["workspace": "moya-komanda", "project": "проект"]),
            query: "которой там нет",
            trackerHTTP: { request in
                (page, HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: [:])!)
            })
        #expect(answer.text.contains("nothing matched"))
        #expect(answer.text.contains("the most recent 500"), "ответ: «\(answer.text)»")
        #expect(answer.text.contains("40000"))
        #expect(!answer.failed, "пустая выдача — ответ, а не сбой")
    }

    @Test("у трекера, который ищет сам, приписки нет")
    func searchingTrackerAnswersAsBefore() async throws {
        let answer = await ConnectorQuery.ask(
            .init(service: "gitea", token: "ключ", host: "git.company.ru", scope: nil),
            query: "лимиты",
            trackerHTTP: { request in
                (Data(#"[{"number":42,"title":"Поднять лимиты","state":"open"}]"#.utf8),
                 HTTPURLResponse(url: request.url!, statusCode: 200,
                                 httpVersion: nil, headerFields: [:])!)
            })
        #expect(answer.text.contains("Поднять лимиты"))
        #expect(!answer.text.contains("отбирали у себя"))
    }

    // MARK: - GitFlic: список в конверте, которого при нуле задач нет

    /// Ответ, собранный из примеров документации GitFlic (читана 2026-08-18):
    /// конверт `_embedded.issueModelList`, номер в `localId`, состояние —
    /// `status.title` по-русски, размер выдачи — в `page`.
    static func gitflicPage(_ rows: [String], size: Int, total: Int, number: Int) -> Data {
        Data(#"""
        {"_embedded":{"issueModelList":[\#(rows.joined(separator: ","))]},
         "page":{"size":\#(size),"totalElements":\#(total),"totalPages":2,"number":\#(number)}}
        """#.utf8)
    }

    static func gitflicRow(_ localId: Int, _ title: String, description: String = "",
                           status: String = "Завершена") -> String {
        #"""
        {"id":"522d58b6-aaaa-aaaa-aaaa-a3ccba39032b","localId":\#(localId),
         "description":"\#(description)","title":"\#(title)",
         "status":{"id":"COMPLETED","title":"\#(status)","hexColor":"28A745","isDeleted":false},
         "projectAlias":"backend","userAlias":"moya-komanda"}
        """#
    }

    static func gitflic() throws -> ConnectorManifest {
        try #require(try ConnectorManifest.bundled().first { $0.id == "gitflic" })
    }

    @Test("GitFlic разбирается по своему же примеру из документации")
    func gitflicParsesTheVendorSample() async throws {
        let page = Self.gitflicPage([Self.gitflicRow(19, "Поднять лимиты", description: "Обсуждали на созвоне")],
                                    size: 50, total: 1, number: 0)
        let connector = ManifestConnector(manifest: try Self.gitflic(), token: "токен",
                                          host: "https://api.gitflic.ru",
                                          values: ["owner": "moya-komanda", "project": "backend"],
                                          http: Self.stub([page]))
        let outcome = try await connector.run("лимиты")
        let item = try #require(outcome.items.first)
        #expect(item.key == "#19", "номер задачи — localId, а не UUID")
        #expect(item.title == "Поднять лимиты")
        #expect(item.state == "Завершена")
        #expect(item.context == "Обсуждали на созвоне")
        #expect(outcome.coverage == .wholeList(scanned: 1))
    }

    @Test("проект без задач — это пустая выдача, а не непонятный ответ")
    func gitflicEmptyProjectIsAnAnswer() async throws {
        // Spring не присылает `_embedded`, когда список пуст. Без разбора этого
        // случая человек с новым проектом получил бы «сервис ответил непонятным
        // образом» и пошёл чинить исправный сервер.
        let empty = Data(#"{"page":{"size":50,"totalElements":0,"totalPages":0,"number":0}}"#.utf8)
        let connector = ManifestConnector(manifest: try Self.gitflic(), token: "токен",
                                          host: "https://api.gitflic.ru",
                                          values: ["owner": "moya-komanda", "project": "backend"],
                                          http: Self.stub([empty]))
        let outcome = try await connector.run("лимиты")
        #expect(outcome.items.isEmpty)
        #expect(outcome.coverage == .wholeList(scanned: 0))
    }

    @Test("мусор вместо ответа остаётся отказом")
    func gitflicGarbageIsStillRefused() async throws {
        // Послабление про пустой конверт не должно превращаться в «принимаем
        // что угодно»: без `page` ответ не узнан.
        let connector = ManifestConnector(manifest: try Self.gitflic(), token: "токен",
                                          host: "https://api.gitflic.ru",
                                          values: ["owner": "moya-komanda", "project": "backend"],
                                          http: Self.stub([Data(#"{"сообщение":"обслуживание"}"#.utf8)]))
        await #expect(throws: ManifestConnector.ConnectorError.unreadable) {
            _ = try await connector.run("лимиты")
        }
    }

    @Test("GitFlic шлёт «token», а не «Bearer», и нумерует страницы с нуля")
    func gitflicRequestMatchesTheDocs() throws {
        let connector = ManifestConnector(manifest: try Self.gitflic(), token: "секрет",
                                          host: "https://api.gitflic.ru",
                                          values: ["owner": "moya-komanda", "project": "backend"],
                                          http: Self.stub([Data("{}".utf8)]))
        let request = try connector.makeRequest(query: "лимиты", limit: 10, page: 0)
        #expect(request.url?.path == "/project/moya-komanda/backend/issue")
        // С «Bearer» GitFlic отвечает отказом, неотличимым от плохого токена.
        #expect(request.value(forHTTPHeaderField: "Authorization") == "token секрет")
        let query = request.url?.query ?? ""
        #expect(query.contains("page=0"), "первая страница у GitFlic — нулевая")
        #expect(query.contains("size=50"))
    }

    @Test("граница GitFlic укладывается в лимит запросов сервиса")
    func gitflicBoundFitsTheRateLimit() throws {
        // 500 запросов в час на gitflic.ru. Пять страниц на вопрос — один
        // процент часового лимита; поднять границу означало бы тратить чужую
        // квоту на «а вдруг найдётся».
        let scan = try #require(try Self.gitflic().scan)
        #expect(scan.pages * scan.perPage <= 500,
                "за один вопрос выкачивается \(scan.pages * scan.perPage) задач")
        #expect(scan.pages <= ManifestConnector.scanPageLimit)
    }
}
