import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OrakulCore

/// Защиты, проверенные через настоящий сокет.
///
/// Всё, что написано против недружелюбного сервиса, до сих пор проверялось
/// подставным `http`, то есть в обход URLSession. Такой тест не видит разницы
/// между «правило верное» и «правило применяется»: политика перенаправлений
/// может быть безупречной, а делегат — не подключённым, и оба случая зелёные.
///
/// Здесь работает настоящая сессия против сервера из
/// `scripts/vrazhdebnyj-server.py`. Набор включается адресом:
///
///     ORAKUL_HOSTILE_PORT=4801 ORAKUL_COLLECTOR_PORT=4802 \
///     swift test --package-path mvp --filter HostileServiceTests
@Suite("Недружелюбный сервис по-настоящему", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["ORAKUL_HOSTILE_PORT"] != nil))
struct HostileServiceTests {

    static var vendorPort: String {
        ProcessInfo.processInfo.environment["ORAKUL_HOSTILE_PORT"] ?? "4801"
    }
    static var collectorPort: String {
        ProcessInfo.processInfo.environment["ORAKUL_COLLECTOR_PORT"] ?? "4802"
    }

    static func request(_ path: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "http://localhost:\(vendorPort)\(path)")!)
        request.setValue("Bearer секретный-ключ-от-трекера", forHTTPHeaderField: "Authorization")
        return request
    }

    /// Что доехало до чужого хоста.
    static func caught() async throws -> (authorization: String?, hits: Int) {
        let url = URL(string: "http://127.0.0.1:\(collectorPort)/caught")!
        let (data, _) = try await URLSession(configuration: .ephemeral).data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return (json["authorization"] as? String, json["hits"] as? Int ?? 0)
    }

    // Сначала доказываем, что ловушка ловит: проверка «к чужому хосту не
    // ходили», поставленная над сломанным сборщиком, зелена всегда.
    //
    // Заодно здесь записано ИЗМЕРЕННОЕ поведение сессии по умолчанию. Она идёт
    // за перенаправлением на чужой хост — но заголовок Authorization туда НЕ
    // переносит: Foundation его снимает при смене хоста. Проверено 2026-08-19
    // на macOS; до этого в комментарии к ConnectorSession было написано
    // обратное, и написано было рассуждением, а не опытом.
    @Test("ловушка ловит: сессия по умолчанию доходит до чужого хоста")
    func trapCatchesWithDefaultSession() async throws {
        let before = try await Self.caught().hits
        let plain = URLSession(configuration: .ephemeral)  // без нашего делегата
        _ = try? await plain.data(for: Self.request("/redirect-foreign"))
        let after = try await Self.caught()
        #expect(after.hits > before, "сборщик не увидел даже обычную сессию — ловушка сломана")
        // Заголовок сверяется по системам: на macOS Foundation его снимает, на
        // Linux (corelibs 6.0.3) — переносит целиком. Измерено 2026-08-19 на
        // обеих. Утверждать одно поведение для обеих значило бы записать
        // рассуждение вместо опыта — с этого и начался разбор.
        #if canImport(Darwin)
        #expect(after.authorization == nil,
                "Foundation перестал снимать Authorization при смене хоста — цена перенаправления снова токен")
        #else
        #expect(after.authorization != nil,
                "corelibs перестал переносить Authorization — хорошо, но правило держится не на этом")
        #endif
    }

    @Test("наша сессия не уносит токен на чужой хост")
    func tokenNeverReachesForeignHost() async throws {
        let before = try await Self.caught().hits
        _ = try? await ConnectorSession.send(Self.request("/redirect-foreign"))
        let after = try await Self.caught()
        #expect(after.hits == before,
                "чужой хост получил запрос: перенаправление прошло, делегат не сработал")
    }

    @Test("перенаправление на себя разрешено, иначе доказано только «ничего не работает»")
    func sameHostRedirectStillWorks() async throws {
        let (data, response) = try await ConnectorSession.send(Self.request("/redirect-self"))
        #expect(response.statusCode == 200)
        // Сравнение по разобранному JSON, а не по тексту ответа: сервер
        // отдаёт кириллицу экранированной (\u0442…), и поиск подстроки здесь
        // проверял бы форму записи, а не содержимое.
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let rows = json?["data"] as? [[String: Any]]
        #expect(rows?.first?["title"] as? String == "тарифы")
    }

    @Test("бесконечный ответ обрывается, а не съедает память")
    func endlessResponseIsCut() async throws {
        do {
            _ = try await ConnectorSession.send(Self.request("/endless"))
            Issue.record("бесконечный ответ доехал целиком")
        } catch let error as URLError {
            #expect(error.code == .dataLengthExceedsMaximum)
        }
    }

    @Test("форма входа с кодом 200 распознаётся на живом ответе")
    func loginPageOverTheWire() async throws {
        let (data, response) = try await ConnectorSession.send(Self.request("/login-page"))
        #expect(response.statusCode == 200)
        #expect(ManifestConnector.looksLikeWebPage(data))
    }

    @Test("пустой список рядом с жалобой доезжает как отказ")
    func graphQLRefusalOverTheWire() async throws {
        let manifest = try #require(try ConnectorManifest.bundled().first { $0.id == "wikijs" })
        let connector = ManifestConnector(
            manifest: manifest, token: "т",
            host: "http://localhost:\(Self.vendorPort)",
            http: { _ in try await ConnectorSession.send(Self.request("/graphql-refusal")) })
        do {
            _ = try await connector.run("тарифы")
            Issue.record("отказ проехал как пустая выдача")
        } catch let error as ManifestConnector.ConnectorError {
            guard case .vendor(_, let description) = error else {
                Issue.record("отказ стал \(error)")
                return
            }
            #expect(description.contains("Превышен предел"))
        }
    }
}
