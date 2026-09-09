import Testing
import Foundation
@testable import CruxwingCore

/// Знак подстановки для вопроса основой.
///
/// Третий вопрос коннектора — основой: человек сказал «тарифы», в чужой базе
/// лежит «тарифами». Сервису, ищущему по вхождению, основы достаточно. Сервису,
/// сравнивающему слова ЦЕЛИКОМ, она не даёт ничего.
///
/// Измерено на поднятом Mattermost 9.11 (2026-08-20), прямыми запросами к
/// самому сервису: «тарифы» → 2, «тарифами» → 1, «тариф» → 0, «тариф*» → 3.
/// То есть запись с косвенной формой не доезжала до человека вовсе, а вендор
/// описывает звёздочку в конце слова как поиск по началу.
///
/// Полем манифеста, а не правилом движка: у BookStack звёздочки нет — там
/// «тариф*» вернул ноль, и это тоже измерено. Одна догадка на всех починила бы
/// один сервис и сломала другой.
@Suite struct StemSuffixTests {

    private func recorder() -> (ManifestConnector.HTTP, @Sendable () -> [String]) {
        let box = QueryBox()
        let http: ManifestConnector.HTTP = { request in
            let sent = (request.httpBody.map { String(decoding: $0, as: UTF8.self) } ?? "")
                + (request.url?.absoluteString ?? "")
            box.append(sent.removingPercentEncoding ?? sent)
            return (Data("{\"posts\":{},\"order\":[]}".utf8), HTTPURLResponse())
        }
        return (http, { box.all() })
    }

    private final class QueryBox: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func append(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
        func all() -> [String] { lock.lock(); defer { lock.unlock() }; return items }
    }

    @Test("основу спрашивают со знаком подстановки, а слово — без")
    func onlyTheStemCarriesTheWildcard() async throws {
        let manifest = try #require(ConnectorManifest.usable().first { $0.id == "mattermost" })
        #expect(manifest.stemSuffix == "*", "манифест перестал объявлять знак подстановки")

        let (http, sent) = recorder()
        let connector = ManifestConnector(manifest: manifest, token: "t",
                                          host: "https://mm.example",
                                          values: ["team": "t1"], http: http)
        _ = try await connector.run("тарифы", limit: 10)

        let asked = sent()
        #expect(asked.count >= 2, "спрошено \(asked.count) раз — проверять нечего")
        #expect(asked.first?.contains("\"тарифы\"") == true || asked.first?.contains("тарифы") == true)
        #expect(asked.first?.contains("тарифы*") != true, "звёздочка приписана к слову человека")
        #expect(asked.contains { $0.contains("тариф*") }, "вопрос основой ушёл без знака подстановки")
    }

    @Test("знак подстановки переживает очистку вопроса")
    func theWildcardSurvivesTheCleaner() async throws {
        // `words(of:)` убирает `*` наравне с прочими служебными знаками —
        // из речи он приходит мусором. Приписанный до очистки, он был бы съеден,
        // и причина выглядела бы как «сервис не умеет».
        #expect(ManifestConnector.words(of: "тариф*") == "тариф")

        let manifest = try #require(ConnectorManifest.usable().first { $0.id == "mattermost" })
        let (http, sent) = recorder()
        let connector = ManifestConnector(manifest: manifest, token: "t",
                                          host: "https://mm.example",
                                          values: ["team": "t1"], http: http)
        _ = try await connector.run("тарифы", limit: 10)
        #expect(sent().contains { $0.contains("тариф*") })
    }

    @Test("сервисы без объявленного знака спрашивают основой как есть")
    func serviceWithoutTheFieldIsUnchanged() throws {
        // BookStack измерен: там «тариф*» возвращает ноль, а голая основа
        // находит обе страницы. Поле пустое — и это решение, а не пропуск.
        let bookstack = try #require(ConnectorManifest.usable().first { $0.id == "bookstack" })
        #expect(bookstack.stemSuffix == nil)
    }
}
