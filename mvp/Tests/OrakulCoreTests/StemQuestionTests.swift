import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OrakulCore

/// Третий вопрос — основой слова.
///
/// Слово в той форме, в какой его произнесли, не то же, что лежит в чужой базе:
/// человек спрашивает «тарифы», в заметке написано «тарифами», и по-русски
/// чужой сервис не склоняет. Измерено на поднятом у себя BookStack 2026-08-19:
/// «тарифы» находит одну страницу из двух, «тарифами» — другую одну, основа
/// «тариф» находит обе. Напрашивавшийся подстановочный знак не работает вовсе:
/// «тариф*» вернул ноль.
@Suite("Вопрос основой слова")
struct StemQuestionTests {

    actor Asked {
        private(set) var all: [String] = []
        func add(_ query: String) { all.append(query) }
    }

    /// Сервис, который ищет по началу слова: так ведёт себя живой BookStack.
    /// «тарифы» не находит «тарифами», а «тариф» находит оба.
    static func prefixSearch(_ titles: [String], asked: Asked) -> ManifestConnector.HTTP {
        { request in
            let query = URLComponents(string: request.url!.absoluteString)?.queryItems?
                .first { $0.name == "query" }?.value ?? ""
            await asked.add(query)
            let hits = query.isEmpty ? [] : titles.enumerated().filter { _, title in
                title.lowercased().split(whereSeparator: { !$0.isLetter })
                    .contains { $0.hasPrefix(query.lowercased()) }
            }
            let rows = hits.map {
                #"{"id":\#($0.offset),"name":"\#($0.element)","preview_html":{"name":"\#($0.element)","content":"..."}}"#
            }.joined(separator: ",")
            let json = #"{"data":[\#(rows)],"total":\#(hits.count)}"#
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
                                                     httpVersion: nil, headerFields: [:])!)
        }
    }

    /// Сервис, который сравнивает слова целиком: «тариф» не находит «тарифы»,
    /// и наоборот. Так ведёт себя обычный полнотекстовый поиск без русской
    /// морфологии — то есть ни один ответ не является надмножеством другого,
    /// и слить их обязательно.
    static func wholeWordSearch(_ titles: [String], asked: Asked) -> ManifestConnector.HTTP {
        { request in
            let query = URLComponents(string: request.url!.absoluteString)?.queryItems?
                .first { $0.name == "query" }?.value ?? ""
            await asked.add(query)
            let hits = query.isEmpty ? [] : titles.enumerated().filter { _, title in
                title.lowercased().split(whereSeparator: { !$0.isLetter })
                    .contains { $0 == Substring(query.lowercased()) }
            }
            let rows = hits.map {
                #"{"id":\#($0.offset),"name":"\#($0.element)","preview_html":{"name":"\#($0.element)","content":"..."}}"#
            }.joined(separator: ",")
            return (Data(#"{"data":[\#(rows)],"total":\#(hits.count)}"#.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: [:])!)
        }
    }

    static func connector(_ http: @escaping ManifestConnector.HTTP,
                          service: String = "bookstack") throws -> ManifestConnector {
        let manifest = try #require(try ConnectorManifest.bundled().first { $0.id == service })
        return ManifestConnector(manifest: manifest, token: "id:секрет",
                                 host: "https://wiki.company.ru", http: http)
    }

    @Test("«тарифы» доносит и запись, где написано «тарифами»")
    func stemFindsTheOtherForm() async throws {
        let asked = Asked()
        let items = try await Self.connector(
            Self.prefixSearch(["Тарифы с декабря", "Лимиты вместе с тарифами"], asked: asked)
        ).run("тарифы").items
        #expect(items.count == 2, "основа «тариф» находит обе формы, слово целиком — одну")
        #expect(await asked.all.contains("тариф"), "основой так и не спросили")
    }

    @Test("вопросов не больше трёх, и третий — основой")
    func asksAtMostThree() async throws {
        let asked = Asked()
        _ = try await Self.connector(
            Self.prefixSearch(["Тарифы с декабря", "Лимиты вместе с тарифами"], asked: asked)
        ).run("тарифы")
        let all = await asked.all
        #expect(all.count <= 3, "спросили \(all.count) раз: \(all)")
        #expect(all.first == "тарифы", "первым уезжает слово человека, а не наша догадка")
        #expect(all.last == "тариф")
    }

    @Test("слово, у которого основы нет, вторым словом не спрашивают")
    func wordWithoutAStemKeepsItsForm() async throws {
        // «дома» разбор оставляет как есть: отсечение окончаний ниже четырёх
        // букв не опускается. Значит и спрашивать нечем — лишнего обращения к
        // чужому серверу быть не должно.
        let asked = Asked()
        _ = try await Self.connector(Self.prefixSearch(["Дома у клиента"], asked: asked)).run("дома")
        #expect(await asked.all.allSatisfy { $0.lowercased() == "дома" })
    }

    @Test("короткая словарная форма — тоже вопрос: «баги» уходит как «баг»")
    func shortDictionaryFormIsStillAsked() async throws {
        // Через словарь основа бывает короче четырёх букв, и это настоящие
        // слова, а не обрубки: «баги» → «баг», «кешам» → «кеш». Порог длины,
        // который здесь сначала стоял, резал 332 таких слова.
        let asked = Asked()
        let items = try await Self.connector(
            Self.prefixSearch(["Багом занимается Аня"], asked: asked)).run("баги").items
        #expect(await asked.all.contains("баг"))
        #expect(!items.isEmpty, "запись про «багом» должна доехать до человека")
    }

    @Test("у перечисления основой не спрашивают — отбор наш")
    func listingConnectorsAreNotAskedTwice() async throws {
        // У Plane отбор идёт у нас, по всем прочитанным страницам. Второй
        // проход по чужому серверу не дал бы ни одной новой находки и удвоил
        // бы объявленную границу.
        let asked = Asked()
        let http: ManifestConnector.HTTP = { request in
            let query = request.url!.absoluteString
            await asked.add(query)
            let json = #"{"total_count":1,"next_page_results":true,"results":[{"name":"Тарифы с декабря","description_html":"<p>x</p>","sequence_id":1,"state":"u"}]}"#
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
                                                     httpVersion: nil, headerFields: [:])!)
        }
        let manifest = try #require(try ConnectorManifest.bundled().first { $0.id == "plane" })
        _ = try await ManifestConnector(manifest: manifest, token: "ключ",
                                        host: "https://plane.company.ru",
                                        values: ["workspace": "w", "project": "p"],
                                        http: http).run("тарифы")
        // Сервис говорит «дальше есть ещё» на каждой странице: значит
        // граница в пять страниц и есть единственное, что останавливает
        // чтение. Шестого запроса — вопроса основой — быть не должно.
        let count = await asked.all.count
        #expect(count == 5, "запросов: \(count)")
    }

    @Test("находки двух вопросов складываются, а не заменяют друг друга")
    func answersAreMergedRatherThanReplaced() async throws {
        // Сервис сравнивает слова целиком: «тарифы» находит одну запись,
        // «тариф» — другую, и ни один ответ не содержит второго. Человеку
        // нужны обе, значит второй ответ добавляется к первому.
        let asked = Asked()
        let items = try await Self.connector(
            Self.wholeWordSearch(["Тарифы с декабря", "Новый тариф для года"], asked: asked)
        ).run("тарифы").items
        #expect(items.count == 2, "получено: \(items.map(\.title))")
        #expect(items.contains { $0.title == "Тарифы с декабря" })
        #expect(items.contains { $0.title == "Новый тариф для года" })
    }

    @Test("полный ответ вторым вопросом не догоняют")
    func fullAnswerIsNotAskedAgain() async throws {
        // Человек просит десять строк; сервис вернул десять. Одиннадцатую он
        // всё равно не увидит, а обращение к чужому серверу стоит — и у Plane
        // это шестьдесят запросов в минуту на всех.
        let asked = Asked()
        let full = (1...10).map { "Тарифы, пункт \($0)" }
        let items = try await Self.connector(Self.prefixSearch(full, asked: asked))
            .run("тарифы", limit: 10).items
        #expect(items.count == 10)
        let all = await asked.all
        #expect(!all.contains("тариф"), "спросили основой, хотя ответ и так полон: \(all)")
    }
}
