import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CruxwingCore

/// Просьба обращаться реже отменяет второй вопрос.
///
/// Второе написание — плата чужому серверу. Тому, кто уже сказал «реже»,
/// платить вдвое нельзя: свой же комментарий про кэш говорит, что троттлинг, на
/// который потом жалуются, отчасти наш собственный.
///
/// Для недружелюбного сервиса это ещё и рычаг. Достаточно отвечать на два
/// написания по-разному — мы решим, что он сравнивает байты, и сами удвоим ему
/// нагрузку, после чего он придушит нас на законных основаниях. Отличить такое
/// от обычного SQLite нечем; перестать давить, когда просят, — можно.
@Suite("Просьба подождать отменяет второй вопрос")
struct SlowDownStopsDoublingTests {

    actor Log {
        private(set) var asked: [String] = []
        func add(_ q: String) { asked.append(q) }
    }

    /// Сервис, который на два написания отвечает по-разному, а с какого-то
    /// момента начинает просить подождать.
    static func service(throttleAfter: Int, log: Log) -> ManifestConnector.HTTP {
        let counter = Counter()
        return { request in
            let asked = URLComponents(string: request.url!.absoluteString)?.queryItems?
                .first { $0.name == "query" }?.value ?? ""
            await log.add(asked)
            let n = await counter.next()
            if n > throttleAfter {
                return (Data(#"{"error":"slow down"}"#.utf8),
                        HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil,
                                        headerFields: ["Retry-After": "60"])!)
            }
            let capital = asked.first?.isUppercase == true
            let title = capital ? "Тарифы и лимиты" : "поднять тарифы"
            let json = #"{"data":[{"id":\#(capital ? 2 : 1),"name":"\#(title)","preview_html":{"name":"\#(title)","content":"…"}}],"total":1}"#
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
                                                     httpVersion: nil, headerFields: [:])!)
        }
    }

    actor Counter {
        private var n = 0
        func next() -> Int { n += 1; return n }
    }

    static func connector(_ memory: ConnectorCaseMemory,
                          _ http: @escaping ManifestConnector.HTTP) throws -> ManifestConnector {
        ManifestConnector(manifest: try #require(try ConnectorManifest.bundled().first { $0.id == "bookstack" }),
                          token: "id:секрет", host: "https://wiki.company.ru",
                          caseMemory: memory, http: http)
    }

    @Test("после 429 второе написание больше не спрашивается")
    func throttlingStopsTheSecondSpelling() async throws {
        let log = Log()
        let memory = ConnectorCaseMemory()
        let http = Self.service(throttleAfter: 2, log: log)

        // Первый вопрос: два обращения, сервис признан сравнивающим байты.
        _ = try await Self.connector(memory, http).run("тарифы")
        #expect(await memory.behaviour(service: "bookstack", host: "https://wiki.company.ru")
                == .comparesBytes)

        // Второй вопрос упирается в 429 и учит нас не давить.
        _ = try? await Self.connector(memory, http).run("сроки")
        #expect(await memory.isSlowedDown(service: "bookstack", host: "https://wiki.company.ru"),
                "сервис попросил реже, а мы этого не запомнили")

        let before = await log.asked.count
        _ = try? await Self.connector(memory, http).run("порядок")
        let after = await log.asked
        #expect(after.count == before + 1,
                "к сервису, попросившему реже, всё ещё уходит два запроса: \(after)")
    }

    @Test("знание про байты сохраняется, просто не используется, пока просят реже")
    func knowledgeSurvivesThePause() async throws {
        let memory = ConnectorCaseMemory()
        await memory.learn(.comparesBytes, service: "bookstack", host: "https://wiki.company.ru")
        await memory.slowDown(service: "bookstack", host: "https://wiki.company.ru")
        // Наружу — «не спрашивай второй раз».
        #expect(await memory.behaviour(service: "bookstack", host: "https://wiki.company.ru")
                == .foldsCase)
        #expect(await memory.isSlowedDown(service: "bookstack", host: "https://wiki.company.ru"))
    }

    @Test("просьба одного сервиса не затыкает другие")
    func slowDownIsPerService() async throws {
        let memory = ConnectorCaseMemory()
        await memory.slowDown(service: "bookstack", host: "https://wiki.company.ru")
        #expect(await memory.behaviour(service: "gitea", host: "https://git.company.ru") == .unknown)
        #expect(await memory.behaviour(service: "bookstack", host: "https://other.company.ru")
                == .unknown, "просьба привязана к хосту, а не к одному лишь названию сервиса")
    }
}
