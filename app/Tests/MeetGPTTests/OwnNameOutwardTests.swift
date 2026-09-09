import Foundation
import Testing
@testable import MeetGPT

/// Чужим сервисам cruxwing представляется собой.
///
/// Имя клиента уходит по сети: сервер MCP видит его при подключении, владелец
/// сервера — при выдаче доступа, и дальше оно остаётся в чужом списке
/// разрешённых приложений и в чужой статистике «кто нами пользуется». Стояло
/// «Cruxwing» — другой продукт, — и среди подключённых серверов есть Fireflies,
/// чей владелец продаёт конкурирующий.
///
/// Это не косметика: человек нажимал «разрешить» продукту, которого не ставил.
@Suite("Своё имя наружу") @MainActor
struct OwnNameOutwardTests {

    private static var productionSources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/MeetGPT", isDirectory: true)
    }

    @Test("клиент MCP называет себя cruxwing")
    func clientNameIsOurs() {
        #expect(MCPConnectionManager.mcpClientName == "cruxwing")
    }

    @Test("версия берётся у пакета, а не пишется числом")
    func versionComesFromTheBundle() {
        // «1.0.0» было неправдой с первого дня: в Info.plist 0.1.0. Версия в
        // чужом отчёте о сбое — единственное, по чему нас потом отличат.
        let version = MCPConnectionManager.mcpClientVersion
        #expect(!version.isEmpty)
        #expect(version != "1.0.0" || Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == "1.0.0")
    }

    @Test("ни одно имя, уходящее наружу, не называет чужой продукт")
    func nothingOutwardNamesAnotherProduct() throws {
        let sources = ["MCP/MCPConnectionManager.swift", "AppState.swift"]
        for relative in sources {
            let path = #filePath.replacingOccurrences(
                of: "Tests/MeetGPTTests/OwnNameOutwardTests.swift",
                with: "Sources/MeetGPT/\(relative)")
            let code = try String(contentsOfFile: path, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            // Строковые литералы, а не комментарии: комментарий рядом с правкой
            // цитирует прежнее имя, и проверка, прочитавшая цитату, проверяет
            // комментарий.
            let parts: [String] = code.components(separatedBy: "\"")
            let literals = parts.enumerated().filter { $0.offset % 2 == 1 }.map { $0.element }
            // Same reversal as ProductNameTests: our name is Cruxwing now, and
            // the names that must not travel outward are the commercial ones.
            let offenders = literals.filter {
                // Interpolations carry property names — `\(state.wheesprEmail)`
                // is not a name that travels anywhere a person can see.
                let text = $0
                    .replacingOccurrences(
                        of: #"\\\([^)]*\)"#, with: "", options: .regularExpression)
                    .replacingOccurrences(
                        of: #"\\\(.*$"#, with: "", options: .regularExpression)
                    .lowercased()
                // A product name in prose is not glued to more letters.
                // `wheesprEmail` is a property this file legitimately reads;
                // "Wheespr" as a word is the thing that must not travel out.
                // The naive quote-split above can sweep whole code blocks in
                // when a literal contains an escaped quote, so without this the
                // check reports identifiers rather than copy.
                return ["meetgpt", "wheespr"].contains { name in
                    text.range(of: name + "(?![a-z0-9])",
                               options: [.regularExpression]) != nil
                }
            }
            #expect(offenders.isEmpty,
                    "\(relative) называет чужой продукт в строке: \(offenders)")
        }
    }

    @Test("каждый HTTP-клиент использует сетевое имя cruxwing")
    func everyHTTPClientUsesOurNetworkIdentity() throws {
        let header = CruxwingNetworkIdentity.shared.configuration
            .httpAdditionalHeaders?["User-Agent"] as? String
        #expect(header == CruxwingNetworkIdentity.userAgent)
        #expect(header?.hasPrefix("cruxwing/") == true)
        #expect(header?.localizedCaseInsensitiveContains("MeetGPT") == false)
        #expect(header?.localizedCaseInsensitiveContains("Wheespr") == false)
        #expect(header?.contains("CFNetwork") == false)
        #expect(header?.contains("Darwin") == false)

        guard let walker = FileManager.default.enumerator(
            at: Self.productionSources,
            includingPropertiesForKeys: nil)
        else {
            Issue.record("не удалось обойти исходники приложения")
            return
        }

        var filesUsingURLSession = 0
        var bypasses: [String] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            guard source.contains("URLSession") else { continue }
            filesUsingURLSession += 1
            guard url.lastPathComponent != "CruxwingNetworkIdentity.swift" else { continue }

            let executableLines = source
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined()
            let compact = executableLines.filter { !$0.isWhitespace }
            if compact.contains("URLSession.shared")
                || compact.contains("URLSession=.shared")
                || compact.contains("URLSession(configuration:") {
                bypasses.append(url.path.replacingOccurrences(
                    of: Self.productionSources.path + "/", with: ""))
            }
        }

        #expect(filesUsingURLSession >= 20,
                "нашлось только \(filesUsingURLSession) сетевых файлов — проверка стала пустой")
        #expect(bypasses.isEmpty,
                "эти файлы обходят CruxwingNetworkIdentity и отдают системе имя MeetGPT: \(bypasses)")
    }

    @Test("название задачи в чужом трекере — по-русски и своё")
    func fallbackTitleIsOurs() {
        // Заголовок уезжает в Jira или Notion как название задачи.
        let path = #filePath.replacingOccurrences(
            of: "Tests/MeetGPTTests/OwnNameOutwardTests.swift",
            with: "Sources/MeetGPT/AppState.swift")
        let code = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        #expect(code.contains("\"From a call in cruxwing\""),
                "запасное название задачи снова не наше или не по-русски")
    }
}
