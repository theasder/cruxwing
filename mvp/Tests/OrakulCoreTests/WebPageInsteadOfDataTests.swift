import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OrakulCore

/// Веб-страница вместо данных.
///
/// Так выглядит истёкшая сессия за единым входом, портал гостиничного Wi-Fi и
/// «войдите» вместо ответа API. Все три отвечают кодом 200 и страницей входа,
/// то есть выглядят как исправная работа. Для сервиса, который хочет отрезать
/// тихо, это самый дешёвый способ: не 401, а форма входа.
///
/// Разница не в строгости, а в совете. «Ответил непонятно» отправляет человека
/// проверять адрес и версию сервера, хотя адрес верный и чинить надо сессию.
@Suite("Веб-страница вместо данных")
struct WebPageInsteadOfDataTests {

    static func stub(_ body: String) -> ManifestConnector.HTTP {
        { request in
            (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
                                              httpVersion: nil, headerFields: [:])!)
        }
    }

    static func connector(_ body: String) throws -> ManifestConnector {
        let manifest = try #require(try ConnectorManifest.bundled().first { $0.id == "gitea" })
        return ManifestConnector(manifest: manifest, token: "т",
                                 host: "https://git.company.ru", http: stub(body))
    }

    @Test("форма входа вместо данных — это не «непонятный ответ»")
    func loginPageIsItsOwnAnswer() async throws {
        let connector = try Self.connector(
            "<!DOCTYPE html>\n<html><head><title>Вход</title></head><body>…</body></html>")
        do {
            _ = try await connector.run("тарифы")
            Issue.record("страница входа проехала как выдача")
        } catch let error as ManifestConnector.ConnectorError {
            #expect(error == .webPage)
        }
    }

    @Test("портал сети отвечает тем же и распознаётся так же", arguments: [
        "<html><body>Подключитесь к сети отеля</body></html>",
        "  \n<!doctype html><html lang=\"ru\">…",
        "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01//EN\"><html>…",
    ])
    func captivePortalRecognised(body: String) async throws {
        #expect(ManifestConnector.looksLikeWebPage(Data(body.utf8)))
    }

    // Обратная сторона: JSON, внутри которого лежит разметка, остаётся JSON.
    // Задача с процитированным HTML в описании — обычное дело.
    @Test("разметка внутри честного JSON ничего не меняет")
    func htmlInsideJSONIsStillJSON() async throws {
        #expect(!ManifestConnector.looksLikeWebPage(
            Data(#"{"data":[{"title":"<html> в описании","body":"<!doctype html>"}]}"#.utf8)))
    }

    // Ответ, который разобрался, но не той формы, — это смена формата, и путать
    // её с формой входа нельзя: чинится она совсем другим.
    @Test("незнакомая форма JSON остаётся «непонятным ответом»")
    func unknownShapeStaysUnreadable() async throws {
        let connector = try Self.connector(#"{"totally":"different"}"#)
        do {
            _ = try await connector.run("тарифы")
            Issue.record("незнакомая форма проехала как выдача")
        } catch let error as ManifestConnector.ConnectorError {
            #expect(error == .unreadable)
        }
    }

    @Test("человеку сказано про вход и про портал, а не про версию сервера")
    func wordsPointAtTheRealCause() {
        let text = SelfHostedTrackers.ConnectorError.webPage.errorDescription ?? ""
        #expect(text.contains("форма входа"))
        #expect(!text.contains("версию"))
    }

    // Глубоко вложенный JSON — это не размер, а форма: восемь мегабайт скобок
    // проходят предел по размеру целиком. Разбор обязан отказать, а не упасть.
    // Проверяется на той системе, где идёт прогон: на Linux разбор свой.
    @Test("лестница из скобок отвергается разбором, а не роняет процесс")
    func deepNestingRefused() {
        let depth = 100_000
        let bomb = Data((String(repeating: "[", count: depth)
                         + String(repeating: "]", count: depth)).utf8)
        #expect(bomb.count < ManifestConnector.maximumResponseBytes,
                "образец должен проходить предел по размеру, иначе проверяется не то")
        #expect((try? JSONSerialization.jsonObject(with: bomb)) == nil)
    }
}
