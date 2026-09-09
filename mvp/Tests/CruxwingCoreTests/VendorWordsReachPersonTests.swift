import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CruxwingCore

/// Слова сервиса обязаны дойти через обёртку семьи, а не только до движка.
///
/// Движок различает отказ телом (`.vendor`) и непонятный ответ (`.unreadable`)
/// — это было проверено набором. Проверено НА ДВИЖКЕ. А приложение зовёт не
/// движок, а обёртку семьи, и она у двух семей заворачивала `.vendor` обратно в
/// `.unreadable`. Проверки были зелёные, потому что смотрели на слой, который
/// человек не видит.
///
/// Нашлось это на живом Wiki.js 2 в контейнере 2026-08-19: при снятом доступе
/// он отвечает кодом 200 и `errors[0].message = «Forbidden»`, а коннектор
/// говорил «непонятный ответ» и отправлял человека проверять адрес и версию
/// сервера. Адрес верный, версия ни при чём, доступ снят.
@Suite("Слова сервиса доходят до человека")
struct VendorWordsReachPersonTests {

    static func stub(_ json: String) -> ManifestConnector.HTTP {
        { request in
            (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
                                              httpVersion: nil, headerFields: [:])!)
        }
    }

    /// Ровно то, что прислал живой Wiki.js со снятым доступом.
    static let wikiRefusal = """
    {"data":{"pages":null},
     "errors":[{"message":"Forbidden","path":["pages","search"],
                "extensions":{"code":"INTERNAL_SERVER_ERROR"}}]}
    """

    @Test("вики: отказ доезжает словами сервиса, а не «непонятным ответом»")
    func wikiRefusalKeepsItsWords() async throws {
        let notes = TeamNotes(service: .wikijs, token: "т", host: "https://wiki.company.ru",
                              http: Self.stub(Self.wikiRefusal))
        do {
            _ = try await notes.search("тарифы")
            Issue.record("отказ проехал как выдача")
        } catch let error as TeamNotes.ConnectorError {
            guard case .vendor(_, let description) = error else {
                Issue.record("отказ стал \(error) — слова сервиса потерялись в обёртке семьи")
                return
            }
            #expect(description == "Forbidden")
            #expect(error.errorDescription?.contains("Forbidden") == true,
                    "человек не увидит слова сервиса")
        }
    }

    // Slack объявляет requireTrue: ["ok"] и errorCode: ["error"] — он отказывает
    // телом с кодом 200. «invalid_auth» отправляет человека выпускать токен;
    // «непонятный ответ» отправлял его проверять адрес и версию сервера.
    @Test("мессенджер: код отказа доезжает")
    func messengerRefusalKeepsItsCode() async throws {
        let chat = WorkMessengers(service: .slack, token: "т",
                                  http: Self.stub(#"{"ok":false,"error":"invalid_auth"}"#))
        do {
            _ = try await chat.search("тарифы")
            Issue.record("отказ проехал как выдача")
        } catch let error as WorkMessengers.ConnectorError {
            guard case .vendor(let code, _) = error else {
                Issue.record("отказ стал \(error) — код сервиса потерялся в обёртке семьи")
                return
            }
            #expect(code == "invalid_auth")
            #expect(error.errorDescription?.contains("invalid_auth") == true)
        }
    }

    // Обратная сторона: непонятный ответ обязан остаться непонятным. Обёртка,
    // объявляющая отказом всё подряд, врёт в другую сторону.
    @Test("незнакомая форма остаётся непонятным ответом")
    func unknownShapeStaysUnreadable() async throws {
        let notes = TeamNotes(service: .wikijs, token: "т", host: "https://wiki.company.ru",
                              http: Self.stub(#"{"totally":"different"}"#))
        do {
            _ = try await notes.search("тарифы")
            Issue.record("незнакомая форма проехала как выдача")
        } catch let error as TeamNotes.ConnectorError {
            #expect(error == .unreadable)
        }
    }
}
