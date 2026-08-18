import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OrakulCore

/// Отказ, приехавший рядом с пустым списком.
///
/// У GraphQL код ответа всегда 200, а отказ лежит в `errors`. Штатная форма
/// такого ответа — не «нет списка», а «список есть, он пуст, и рядом жалоба».
/// Именно так отвечают Wiki.js, Linear и сам Fireflies.
///
/// Разница видна только человеку и только в словах: «искали, ничего не нашли»
/// — это вывод про его вики, а «сервис отказался отвечать» — вывод про наш
/// коннектор. Первое он проверять не пойдёт.
@Suite("Отказ с кодом 200")
struct GraphQLRefusalTests {

    static func stub(_ json: String) -> ManifestConnector.HTTP {
        { request in
            (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
                                              httpVersion: nil, headerFields: [:])!)
        }
    }

    static func connector(_ json: String) throws -> ManifestConnector {
        let manifest = try #require(try ConnectorManifest.bundled().first { $0.id == "wikijs" })
        return ManifestConnector(manifest: manifest, token: "т",
                                 host: "https://wiki.company.ru", http: stub(json))
    }

    /// Ровно то, что присылает Wiki.js, когда отказывает: список на месте и пуст.
    static let refusalBesideEmptyList = """
    {"data":{"pages":{"search":{"results":[],"totalHits":0}}},
     "errors":[{"message":"Превышен предел обращений, попробуйте через минуту",
                "extensions":{"code":"RATE_LIMITED"}}]}
    """

    @Test("пустой список рядом с жалобой — это отказ, а не «ничего не нашлось»")
    func refusalIsNotEmptiness() async throws {
        let connector = try Self.connector(Self.refusalBesideEmptyList)
        await #expect(throws: ManifestConnector.ConnectorError.self) {
            _ = try await connector.run("тарифы")
        }
    }

    @Test("человек видит слова сервиса, а не наш пересказ")
    func vendorWordsReachThePerson() async throws {
        let connector = try Self.connector(Self.refusalBesideEmptyList)
        do {
            _ = try await connector.run("тарифы")
            Issue.record("отказ проехал как обычная выдача")
        } catch let error as ManifestConnector.ConnectorError {
            guard case .vendor(let code, let description) = error else {
                Issue.record("отказ стал \(error) — слова сервиса потерялись")
                return
            }
            #expect(description == "Превышен предел обращений, попробуйте через минуту")
            #expect(code == "RATE_LIMITED")
        }
    }

    // Обратная сторона: пустая выдача обязана остаться пустой выдачей. Сторож,
    // который на каждый пустой ответ кричит «отказ», хуже прежнего — он врёт
    // чаще, потому что пустых ответов больше, чем отказов.
    @Test("пустой список без жалобы остаётся пустым списком")
    func emptyStaysEmpty() async throws {
        let connector = try Self.connector(
            """
            {"data":{"pages":{"search":{"results":[],"totalHits":0}}}}
            """)
        let outcome = try await connector.run("тарифы")
        #expect(outcome.items.isEmpty)
        #expect(outcome.coverage == .searched)
    }

    @Test("пустой список с пустой жалобой — тоже пустой список")
    func emptyComplaintIsNotAComplaint() async throws {
        let connector = try Self.connector(
            """
            {"data":{"pages":{"search":{"results":[],"totalHits":0}}},"errors":[]}
            """)
        #expect(try await connector.run("тарифы").items.isEmpty)
    }

    @Test("найденное по-прежнему доезжает")
    func resultsStillArrive() async throws {
        let connector = try Self.connector(
            """
            {"data":{"pages":{"search":{"results":[
              {"id":"7","title":"Тарифы и лимиты","description":"порог по местам",
               "path":"tarify","locale":"ru"}],"totalHits":1}}}}
            """)
        let outcome = try await connector.run("тарифы")
        #expect(outcome.items.count == 1)
        #expect(outcome.items.first?.title == "Тарифы и лимиты")
    }
}
