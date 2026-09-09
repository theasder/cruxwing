import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CruxwingCore

/// Mattermost описан данными — шестой сервис и первый со строками-словарём.
///
/// План (§6.2) держал его в коде с названной причиной: «сообщения приходят
/// словарём по идентификатору». Это не особенность одного вендора, а свойство
/// формата, и теперь оно у формата есть: `list` указывает на словарь, `order` —
/// на массив идентификаторов.
///
/// Порядок здесь важнее, чем кажется. Словарь в Swift неупорядочен, поэтому
/// «разобрать значения» и «сохранить выдачу» — разные вещи: сервис перечисляет
/// в `order` совпадения по убыванию, а `posts` — просто хранилище. Без порядка
/// первым человеку показалось бы случайное сообщение, и он принял бы его за
/// лучшее совпадение.
@Suite struct MattermostManifestTests {

    /// Ответ в форме из справочника вендора: порядок обратный порядку ключей.
    static let sample = Data(#"""
    {"order": ["p3", "p1", "p2"],
     "posts": {
       "p1": {"id": "p1", "message": "Про тарифы говорили в среду", "user_id": "u7"},
       "p2": {"id": "p2", "message": "Тарифы пересчитаем к пятнице", "user_id": "u9"},
       "p3": {"id": "p3", "message": "Тарифы: решение принято", "user_id": "u1"}
     }}
    """#.utf8)

    static func manifest() throws -> ConnectorManifest {
        try #require(try ConnectorManifest.bundled().first { $0.id == "mattermost" })
    }

    static func connector(_ data: Data = sample,
                          seen: (@Sendable (URLRequest) -> Void)? = nil) throws -> ManifestConnector {
        ManifestConnector(manifest: try manifest(), token: "токен",
                          host: "https://chat.company.ru",
                          values: ["team": "9x7k2m4npq"],
                          http: { request in
                              seen?(request)
                              return (data, HTTPURLResponse(url: request.url!, statusCode: 200,
                                                            httpVersion: nil, headerFields: [:])!)
                          })
    }

    @Test("сообщения приходят в порядке совпадения, а не в порядке словаря")
    func orderComesFromTheService() async throws {
        let items = try await Self.connector().run("тарифы").items
        #expect(items.map(\.title) == ["Тарифы: решение принято",
                                       "Про тарифы говорили в среду",
                                       "Тарифы пересчитаем к пятнице"],
                "выдача пришла не в том порядке, который назвал сервис")
    }

    @Test("автор доезжает идентификатором, раз имени в ответе нет")
    func authorIsTheIdentifier() async throws {
        let first = try #require(try await Self.connector().run("тарифы").items.first)
        #expect(first.author == "u1")
    }

    @Test("слово уезжает в теле, а не в адресе")
    func termTravelsInTheBody() async throws {
        let recorder = Recorder()
        _ = try await Self.connector(seen: { recorder.record($0) }).run("тарифы")
        let request = try #require(recorder.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/v4/teams/9x7k2m4npq/posts/search")
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("\"terms\": \"тарифы\""), "слово человека не доехало: \(body)")
        // Ровно то, ради чего оно тут: ИЛИ забивает выдачу сообщениями, где
        // совпало одно случайное слово.
        #expect(body.contains("\"is_or_search\": false"))
    }

    @Test("объявленный порядок пропал — это смена формата, а не пустая выдача")
    func missingOrderIsABreak() async throws {
        // Разобрать словарь «как получится» здесь нельзя: получилась бы
        // случайная перестановка, выданная за выдачу сервиса.
        let noOrder = Data(#"{"posts": {"p1": {"message": "Тарифы", "user_id": "u7"}}}"#.utf8)
        await #expect(throws: (any Error).self) {
            _ = try await Self.connector(noOrder).run("тарифы")
        }
    }
}
