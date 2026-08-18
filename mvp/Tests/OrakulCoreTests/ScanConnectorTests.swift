import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OrakulCore

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
        #expect(outcome.coverage.note.contains("все 1"))
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
        #expect(outcome.coverage.note.contains("последние 200"))
        #expect(outcome.coverage.note.contains("40000"))
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
        #expect(outcome.coverage.note.isEmpty, "приписка к обычному поиску — шум в каждой подсказке")
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
    @Test("Plane разбирается по своему же примеру из документации")
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
              "description": "Обсуждали на созвоне",
              "priority": "high", "sequence_id": 123,
              "state": {"id": "550e8400-e29b-41d4-a716-446655440000", "name": "В работе", "group": "started"},
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
        #expect(item.state == "В работе")
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
}
