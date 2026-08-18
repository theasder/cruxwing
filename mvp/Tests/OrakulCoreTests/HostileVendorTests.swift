import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OrakulCore

/// Что делает недружелюбный сервис, и что мы на это отвечаем.
///
/// Упражнение конкурента: чужой API можно менять законно и незаметно для нас.
/// Опасны не отказы — отказ видно, — а изменения, после которых orakul
/// продолжает бодро отвечать «ничего не нашлось». Пустая выдача и сломанный
/// разбор снаружи неразличимы, и человек делает вывод про свои данные, а не
/// про наш коннектор.
@Suite struct HostileVendorTests {

    static func stub(_ data: Data) -> ManifestConnector.HTTP {
        { request in
            (data, HTTPURLResponse(url: request.url!, statusCode: 200,
                                   httpVersion: nil, headerFields: [:])!)
        }
    }

    static func manifest(_ id: String) throws -> ConnectorManifest {
        try #require(try ConnectorManifest.bundled().first { $0.id == id })
    }

    @Test("переименованное поле — это поломка разбора, а не пустая выдача")
    func renamedFieldIsNotAnEmptyAnswer() async throws {
        // Приём: вендор переименовал `title` в `heading`. Строки приходят,
        // форма ответа узнаётся, но ни одна строка не даёт ни заголовка, ни
        // слов вокруг совпадения. Молчаливый ответ «ничего не нашлось» здесь —
        // ложь: нашлось три, просто прочитать их мы больше не умеем.
        let renamed = Data(#"""
        [{"number":1,"heading":"Поднять лимиты"},
         {"number":2,"heading":"Починить экспорт"},
         {"number":3,"heading":"Обновить зависимости"}]
        """#.utf8)
        let connector = ManifestConnector(manifest: try Self.manifest("gitea"), token: "т",
                                          host: "https://git.example.com",
                                          http: Self.stub(renamed))
        await #expect(throws: ManifestConnector.ConnectorError.unreadable) {
            _ = try await connector.run("лимиты")
        }
    }

    @Test("настоящая пустая выдача остаётся ответом, а не поломкой")
    func genuinelyEmptyStaysAnAnswer() async throws {
        // Обратная сторона: если сервис честно ответил «ноль строк», это ответ.
        // Иначе борьба с молчаливой поломкой превратится в вечную ошибку на
        // проекте, где просто ничего не нашлось.
        let connector = ManifestConnector(manifest: try Self.manifest("gitea"), token: "т",
                                          host: "https://git.example.com",
                                          http: Self.stub(Data("[]".utf8)))
        let outcome = try await connector.run("лимиты")
        #expect(outcome.items.isEmpty)
    }

    @Test("строка без заголовка среди годных не роняет всю выдачу")
    func onePoorRowAmongGoodOnesIsSkipped() async throws {
        // Мягкое чтение остаётся: одна пустая строка — не смена формата.
        let mixed = Data(#"""
        [{"number":1,"title":""},{"number":2,"title":"Живая задача"}]
        """#.utf8)
        let connector = ManifestConnector(manifest: try Self.manifest("gitea"), token: "т",
                                          host: "https://git.example.com",
                                          http: Self.stub(mixed))
        let outcome = try await connector.run("задача")
        #expect(outcome.items.map(\.title) == ["Живая задача"])
    }

    @Test("исчез признак «есть ещё» — выдача не выдаётся за полную")
    func missingMoreMarkerIsNotAWholeList() async throws {
        // Приём: вендор убрал `next_page_results`. Движок откатывается на
        // «страница короче размера — значит конец», и на полной странице это
        // даёт «просмотрены все» — то есть часть выдаётся за целое ровно там,
        // где §7.2 это запрещает.
        let full = (1...100).map {
            #"{"sequence_id":\#($0),"name":"Задача \#($0)","state":{"name":"В работе"}}"#
        }.joined(separator: ",")
        let page = Data(#"{"total_count":40000,"results":[\#(full)]}"#.utf8)
        let connector = ManifestConnector(manifest: try Self.manifest("plane"), token: "к",
                                          host: "https://api.plane.so",
                                          values: ["workspace": "к", "project": "п"],
                                          http: Self.stub(page))
        let outcome = try await connector.run("которой нет")
        if case .wholeList = outcome.coverage {
            Issue.record("выдача объявлена полной, хотя признак «есть ещё» пропал: \(outcome.coverage)")
        }
    }

    @Test("троттлинг называется троттлингом, а не «ошибкой 429»")
    func throttlingSaysWhatToDo() async throws {
        // Самый дешёвый приём вендора: не блокировать, а придушить. Ответ 429
        // приходит в норме работы, и человеку надо сказать не «ошибка», а
        // «слишком часто, подождите» — иначе он пойдёт перевыпускать токен.
        let connector = ManifestConnector(manifest: try Self.manifest("gitea"), token: "т",
                                          host: "https://git.example.com",
                                          http: { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 429,
                                     httpVersion: nil,
                                     headerFields: ["Retry-After": "120"])!)
        })
        await #expect(throws: ManifestConnector.ConnectorError.rateLimited(retryAfter: 120)) {
            _ = try await connector.run("лимиты")
        }
    }

    // MARK: - Разборы, написанные руками

    /// Тот же приём против кода, который не проходит через движок манифестов.
    /// Разбор руками ошибается ровно так же, а покрытие у него было меньше:
    /// первый разбор этой темы кончился на манифестах, и это было половиной
    /// работы.

    @Test("GitHub: переименованный номер — поломка, а не пустая выдача")
    func gitHubRenamedField() async throws {
        // `number` → `id`. Строки есть, читать нечего.
        let renamed = Data(#"""
        {"items":[{"id":42,"title":"Поднять лимиты","html_url":"https://github.com/a/b/issues/42"}]}
        """#.utf8)
        let connector = GitHubConnector(token: "т", repositories: ["a/b"],
                                        http: { request in
            (renamed, HTTPURLResponse(url: request.url!, statusCode: 200,
                                      httpVersion: nil, headerFields: [:])!)
        })
        await #expect(throws: GitHubConnector.ConnectorError.unreadable) {
            _ = try await connector.search("лимиты")
        }
    }

    @Test("трекер на своём сервере: переименованный заголовок — поломка")
    func selfHostedRenamedField() async throws {
        let renamed = Data(#"[{"iid":42,"heading":"Поднять лимиты","state":"opened"}]"#.utf8)
        let tracker = SelfHostedTrackers(service: .gitlab, token: "т", host: "git.example.com",
                                         http: { request in
            (renamed, HTTPURLResponse(url: request.url!, statusCode: 200,
                                      httpVersion: nil, headerFields: [:])!)
        })
        await #expect(throws: SelfHostedTrackers.ConnectorError.unreadable) {
            _ = try await tracker.legacySearch("лимиты", host: "https://git.example.com")
        }
    }

    @Test("база знаний: переименованные поля — поломка")
    func teamNotesRenamedFields() async throws {
        let renamed = Data(#"{"data":[{"heading":"Тарифы","excerpt":"текст"}]}"#.utf8)
        let notes = TeamNotes(service: .outline, token: "т", host: nil,
                              http: { request in
            (renamed, HTTPURLResponse(url: request.url!, statusCode: 200,
                                      httpVersion: nil, headerFields: [:])!)
        })
        await #expect(throws: TeamNotes.ConnectorError.unreadable) {
            _ = try await notes.legacySearch("тарифы", host: "https://app.getoutline.com")
        }
    }

    @Test("честно пустой ответ у разборов руками остаётся ответом")
    func handWrittenEmptyStaysAnAnswer() async throws {
        // Обратная сторона, без которой защита превратилась бы в вечную ошибку
        // на проекте, где просто ничего не нашлось.
        let tracker = SelfHostedTrackers(service: .gitlab, token: "т", host: "git.example.com",
                                         http: { request in
            (Data("[]".utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
                                              httpVersion: nil, headerFields: [:])!)
        })
        #expect(try await tracker.legacySearch("лимиты", host: "https://git.example.com").isEmpty)
    }

    @Test("российский трекер: переименованные поля — поломка, а не пустая выдача")
    func russianTrackerRenamedFields() throws {
        // Kaiten отдаёт задачи в массиве верхнего уровня. Переименовали и
        // заголовок, и ключ — читать нечего, а строки есть.
        let renamed = Data(#"[{"identifier":"K-1","heading":"Поднять лимиты"}]"#.utf8)
        let tracker = RussianTrackers(service: .kaiten, token: "т", secondary: "команда",
                                      http: { _ in (Data(), stubHTTPResponse()) })
        #expect(throws: RussianTrackers.TrackerError.unreadable(.kaiten)) {
            _ = try tracker.parse(renamed)
        }
    }

    @Test("российский трекер: пустой массив остаётся ответом")
    func russianTrackerEmptyStaysAnAnswer() throws {
        let tracker = RussianTrackers(service: .kaiten, token: "т", secondary: "команда",
                                      http: { _ in (Data(), stubHTTPResponse()) })
        #expect(try tracker.parse(Data("[]".utf8)).isEmpty)
    }
}
