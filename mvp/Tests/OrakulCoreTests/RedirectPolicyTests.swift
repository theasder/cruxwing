import Testing
import Foundation
@testable import OrakulCore

/// Куда позволено уводить запрос, который несёт токен.
///
/// Проверка существует из-за находки в упражнении с недружелюбным сервисом:
/// `URLSession` по умолчанию идёт по перенаправлению сама и повторяет запрос
/// вместе с `Authorization`. Ответ «302 Location: https://чужой/collect» —
/// это готовый сбор чужих токенов, и сервису для этого не нужно ничего, кроме
/// одной строки в ответе.
@Suite struct RedirectPolicyTests {

    static func url(_ text: String) throws -> URL {
        try #require(URL(string: text))
    }

    @Test("на чужой хост — нет, даже по https")
    func foreignHostIsRefused() throws {
        #expect(!RedirectPolicy.allows(from: try Self.url("https://git.company.ru/api/v4/search"),
                                       to: try Self.url("https://collector.example/collect")))
    }

    @Test("поддомен — тоже чужой хост")
    func subdomainIsForeign() throws {
        // «Почти тот же» домен — самый удобный вид кражи: в журнале он не
        // бросается в глаза.
        #expect(!RedirectPolicy.allows(from: try Self.url("https://api.example.com/search"),
                                       to: try Self.url("https://api.example.com.evil.net/search")))
        #expect(!RedirectPolicy.allows(from: try Self.url("https://api.example.com/search"),
                                       to: try Self.url("https://logs.example.com/search")))
    }

    @Test("тот же хост — можно: так работает обычная нормализация путей")
    func sameHostIsAllowed() throws {
        #expect(RedirectPolicy.allows(from: try Self.url("https://git.company.ru/api/v4/search"),
                                      to: try Self.url("https://git.company.ru/api/v4/search/")))
    }

    @Test("регистр хоста не делает его чужим")
    func hostCaseDoesNotMatter() throws {
        #expect(RedirectPolicy.allows(from: try Self.url("https://Git.Company.RU/api"),
                                      to: try Self.url("https://git.company.ru/api")))
    }

    @Test("https → http запрещён, http → https разрешён")
    func downgradeIsRefused() throws {
        // Понижение — это токен открытым текстом, и тому, кто перенаправляет,
        // ровно этого и надо.
        #expect(!RedirectPolicy.allows(from: try Self.url("https://git.company.ru/api"),
                                       to: try Self.url("http://git.company.ru/api")))
        #expect(RedirectPolicy.allows(from: try Self.url("http://git.company.ru/api"),
                                      to: try Self.url("https://git.company.ru/api")))
    }

    @Test("чужая схема — нет")
    func strangeSchemeIsRefused() throws {
        #expect(!RedirectPolicy.allows(from: try Self.url("https://git.company.ru/api"),
                                       to: try Self.url("ftp://git.company.ru/api")))
        #expect(!RedirectPolicy.allows(from: try Self.url("https://git.company.ru/api"),
                                       to: try Self.url("file:///etc/passwd")))
    }

    @Test("коннекторы ходят через сессию с этим запретом, а не через общую")
    func connectorsUseTheGuardedSession() throws {
        // Структурно: `URLSession.shared` следует за перенаправлением сама и
        // уносит токен. Один забытый коннектор сводит защиту к нулю, поэтому
        // проверяется весь каталог, а не отдельный файл.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/OrakulCore")
        let files = (try? FileManager.default.contentsOfDirectory(at: root,
                                                                  includingPropertiesForKeys: nil)) ?? []
        var offenders: [String] = []
        for file in files where file.pathExtension == "swift" {
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            let code = text.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            if code.contains("URLSession.shared") {
                offenders.append(file.lastPathComponent)
            }
        }
        #expect(offenders.isEmpty,
                "эти коннекторы ходят мимо запрета на чужие перенаправления: \(offenders)")
    }
}
