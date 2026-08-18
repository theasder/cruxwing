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

    // Крупный, но КОНЕЧНЫЙ ответ (~13 МБ при пределе 8): звонящему возвращается
    // ошибка, и это работает на обеих системах.
    @Test("ответ больше предела не доезжает до звонящего")
    func oversizedNeverReachesTheCaller() async throws {
        do {
            let (data, _) = try await ConnectorSession.send(Self.request("/big"))
            Issue.record("ответ на \(data.count) байт доехал целиком")
        } catch let error as URLError {
            #expect(error.code == .dataLengthExceedsMaximum)
        }
    }

    // А вот БЫСТРЫЙ обрыв бесконечного ответа — только на Apple, и это не
    // придирка к тесту, а свойство системы.
    //
    // Измерено 2026-08-19: на corelibs `cancel()` задачи передачу не
    // останавливает — после отмены пришло ещё 62 450 кусков за пять секунд,
    // после `invalidateAndCancel()` сессии 72 414. Звонящий там получает
    // ошибку сразу, а качает библиотека до предела по времени. Запусти этот
    // тест на Linux — он не проверил бы обрыв, а повесил бы прогон, и
    // «зелёный на обеих системах» означал бы неправду про одну из них.
    #if canImport(Darwin)
    @Test("бесконечный ответ обрывается сразу")
    func endlessResponseIsCutPromptly() async throws {
        let started = Date()
        do {
            _ = try await ConnectorSession.send(Self.request("/endless"))
            Issue.record("бесконечный ответ доехал целиком")
        } catch let error as URLError {
            #expect(error.code == .dataLengthExceedsMaximum)
        }
        #expect(Date().timeIntervalSince(started) < 10,
                "обрыв занял слишком долго — предел работает не сразу")
    }
    #endif

    // Делегат один на всю сессию, а запросов одновременно много. Состояние
    // хранится по номеру задачи; ошибка здесь не роняет набор, а СМЕШИВАЕТ
    // ответы — человек получает чужую задачу в своей выдаче и не может этого
    // заметить. Проверяется тем, что каждый ответ несёт свою метку.
    @Test("двадцать одновременных запросов не перемешиваются")
    func concurrentAnswersStaySeparate() async throws {
        let answers = try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for tag in 1...20 {
                group.addTask {
                    let (data, _) = try await ConnectorSession.send(
                        Self.request("/tagged?tag=\(tag)&delay=0.2"))
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    let rows = json?["data"] as? [[String: Any]]
                    return (tag, rows?.first?["title"] as? String ?? "")
                }
            }
            var seen: [Int: String] = [:]
            for try await (tag, title) in group { seen[tag] = title }
            return seen
        }

        #expect(answers.count == 20)
        for tag in 1...20 {
            #expect(answers[tag] == "\(tag)",
                    "запрос \(tag) получил «\(answers[tag] ?? "ничего")» — ответы перемешались")
        }
    }

    // Смешанная пачка: часть ответов обрывается по пределу, часть обычные.
    // Отмена задачи приходит в делегата тогда же, когда соседние задачи ещё
    // получают куски, — и продолжение каждой обязано сработать ровно один раз.
    // Дважды возобновлённое продолжение роняет процесс, а не набор.
    @Test("обрыв по пределу не задевает соседние запросы")
    func oversizedDoesNotDisturbNeighbours() async throws {
        let outcome = try await withThrowingTaskGroup(of: (Int, Bool).self) { group in
            for index in 1...12 {
                let oversized = index % 3 == 0
                group.addTask {
                    do {
                        let (data, _) = try await ConnectorSession.send(
                            Self.request(oversized ? "/big" : "/tagged?tag=\(index)&delay=0.1"))
                        return (index, data.count <= ManifestConnector.maximumResponseBytes)
                    } catch {
                        return (index, false)
                    }
                }
            }
            var result: [Int: Bool] = [:]
            for try await (index, ok) in group { result[index] = ok }
            return result
        }

        for index in 1...12 where index % 3 != 0 {
            #expect(outcome[index] == true,
                    "обычный запрос \(index) пострадал от соседнего обрыва")
        }
        for index in 1...12 where index % 3 == 0 {
            #expect(outcome[index] == false, "крупный ответ \(index) доехал целиком")
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
