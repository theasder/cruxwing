import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OrakulCore

/// Plane — перечисление с границей (роадмап, §7.2 и §7.4).
///
/// Ответ ниже снят 2026-08-19 с Plane, поднятого у себя (`scripts/zhivaya-proba.sh
/// plane`), а не составлен по справочнику. Разница оказалась существенной, и в
/// этом весь смысл живой пробы: справочник обещает у задачи `description` и
/// `state.name`, сервис не отдаёт ни того, ни другого. Коннектор, собранный по
/// обещанию, молча искал по полю, которого нет, — отбор по описанию не
/// срабатывал никогда, а состояние всегда было пустым.
///
/// Поэтому образец правится только вместе с новым снимком с живого сервиса.
@Suite struct PlaneConnectorTests {

    /// Снято с живого Plane; оставлены поля, которые читает манифест.
    static let sample = Data(#"""
    {"total_count": 5, "next_cursor": "100:1:0", "next_page_results": false, "results": [
     {"name": "Поднять тарифы с декабря", "description_html": "<p>Пересмотреть цены</p>",
      "sequence_id": 1, "state": "505c4110-46ec-4ac8-b199-8b3a2f904daf"},
     {"name": "Починить вход по SSO", "description_html": "<p>Не пускает через провайдера</p>",
      "sequence_id": 2, "state": "505c4110-46ec-4ac8-b199-8b3a2f904daf"},
     {"name": "Тарифы: пересчитать лимиты", "description_html": "<p>Лимиты в описании тоже про тарифы</p>",
      "sequence_id": 3, "state": "505c4110-46ec-4ac8-b199-8b3a2f904daf"},
     {"name": "Починить экспорт", "description_html": "<p>Экспорт цен и тарифы за квартал</p>",
      "sequence_id": 4, "state": "505c4110-46ec-4ac8-b199-8b3a2f904daf"},
     {"name": "Обновить прайс", "description_html": "<p>Пересчитать <strong>тари</strong>фы за квартал</p>",
      "sequence_id": 5, "state": "505c4110-46ec-4ac8-b199-8b3a2f904daf"}]}
    """#.utf8)

    static func manifest() throws -> ConnectorManifest {
        try #require(try ConnectorManifest.bundled().first { $0.id == "plane" })
    }

    static func connector(seen: (@Sendable (URLRequest) -> Void)? = nil) throws -> ManifestConnector {
        ManifestConnector(manifest: try manifest(), token: "plane_api_проба",
                          host: "https://plane.company.ru",
                          values: ["workspace": "moya-komanda",
                                   "project": "550e8400-e29b-41d4-a716-446655440000"],
                          http: { request in
                              seen?(request)
                              return (sample, HTTPURLResponse(url: request.url!, statusCode: 200,
                                                              httpVersion: nil, headerFields: [:])!)
                          })
    }

    @Test("задача, где слово только в описании, доходит до человека")
    func findsMatchOnlyInDescription() async throws {
        let items = try await Self.connector().run("тарифы").items
        let names = items.map(\.title)
        // Именно эта строка терялась: в названии слова нет, оно в описании.
        #expect(names.contains("Починить экспорт"))
        #expect(names.contains("Поднять тарифы с декабря"))
        #expect(names.contains("Тарифы: пересчитать лимиты"))
        #expect(!names.contains("Починить вход по SSO"))
    }

    @Test("слово, разорванное подсветкой, всё равно находится")
    func findsWordSplitByMarkup() async throws {
        // Редактор Plane ставит выделение внутри слова, и в ответе приезжает
        // «тари</strong>фы». Сравнение с сырой разметкой такую строку не
        // находит, поэтому разметка снимается ДО сравнения, а не только по
        // дороге к человеку. Строка снята с живого сервиса, а не придумана.
        let items = try await Self.connector().run("тарифы").items
        #expect(items.map(\.title).contains("Обновить прайс"))
    }

    @Test("описание приезжает текстом, а не разметкой")
    func descriptionArrivesWithoutTags() async throws {
        let items = try await Self.connector().run("тарифы").items
        let found = try #require(items.first { $0.title == "Починить экспорт" })
        #expect(found.context == "Экспорт цен и тарифы за квартал")
        #expect(!found.context.contains("<"))
    }

    @Test("состояние пустое, а не строка-идентификатор")
    func stateIsEmptyRatherThanAnIdentifier() async throws {
        // Сервис отдаёт состояние идентификатором; названия лежат за отдельным
        // запросом, которого здесь нет. Показать человеку «505c4110-46ec-…»
        // хуже, чем не показать ничего, — поэтому поле пустое намеренно.
        let items = try await Self.connector().run("тарифы").items
        #expect(!items.isEmpty)
        for item in items {
            #expect(item.state.isEmpty)
            #expect(!item.state.contains("505c4110"))
        }
    }

    @Test("курсор и размер страницы — те, что принимает сервис")
    func cursorMatchesTheLiveService() async throws {
        // Формат «размер:страница:назад» с нумерацией от нуля подтверждён живым
        // сервисом: он вернул next_cursor «100:1:0» на запрос «100:0:0».
        let recorder = Recorder()
        _ = try await Self.connector(seen: { recorder.record($0) }).run("тарифы")
        let first = try #require(recorder.first?.url?.absoluteString)
        #expect(first.contains("cursor=100:0:0") || first.contains("cursor=100%3A0%3A0"))
        #expect(first.contains("per_page=100"))
    }
}
