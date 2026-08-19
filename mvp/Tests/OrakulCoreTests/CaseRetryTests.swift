import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OrakulCore

/// Второй запрос тем же словом с другой буквы.
///
/// Измерено на живых установках: Redmine и Nextcloud с базой по умолчанию
/// (SQLite) сравнивают строки побайтово выше ASCII, и «тарифы» не находит
/// «Тарифы». Расшифровка отдаёт слова строчными — так говорят, — поэтому на
/// маленькой самостоятельной установке половина ответов пропадала молча, и
/// выглядело это не как чужая база, а как продукт, который не находит.
@Suite("Повтор с другим регистром")
struct CaseRetryTests {

    /// Сервис, отвечающий как SQLite: совпадение только при точном регистре.
    static func caseSensitive(_ титул: String, seen: SeenQueries) -> ManifestConnector.HTTP {
        { request in
            let url = request.url!.absoluteString
            let asked = URLComponents(string: url)?.queryItems?
                .first { $0.name == "q" || $0.name == "search" || $0.name == "query" }?.value ?? ""
            await seen.add(asked)
            let hit = титул.contains(asked) && !asked.isEmpty
            let json = hit
                ? #"{"data":[{"id":1,"name":"\#(титул)","preview_html":{"name":"\#(титул)","content":"..."}}],"total":1}"#
                : #"{"data":[],"total":0}"#
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
                                                     httpVersion: nil, headerFields: [:])!)
        }
    }

    actor SeenQueries {
        private(set) var all: [String] = []
        func add(_ q: String) { all.append(q) }
    }

    static func connector(_ http: @escaping ManifestConnector.HTTP) throws -> ManifestConnector {
        let manifest = try #require(try ConnectorManifest.bundled().first { $0.id == "bookstack" })
        return ManifestConnector(manifest: manifest, token: "id:секрет",
                                 host: "https://wiki.company.ru", http: http)
    }

    @Test("строчное слово находит запись с заглавной")
    func lowercaseFindsCapitalised() async throws {
        let seen = SeenQueries()
        let connector = try Self.connector(Self.caseSensitive("Тарифы и лимиты", seen: seen))
        let outcome = try await connector.run("тарифы")
        #expect(outcome.items.first?.title == "Тарифы и лимиты")
        let asked = await seen.all
        #expect(asked == ["тарифы", "Тарифы"], "второй запрос ушёл не тем словом: \(asked)")
    }

    @Test("на обычном пути второго запроса нет")
    func noSecondRequestWhenFound() async throws {
        let seen = SeenQueries()
        let connector = try Self.connector(Self.caseSensitive("тарифы и лимиты", seen: seen))
        _ = try await connector.run("тарифы")
        let asked = await seen.all
        #expect(asked.count == 1, "лишнее обращение к чужому серверу там, где ответ уже найден")
    }

    @Test("латиница второго запроса не заслуживает")
    func latinDoesNotRetry() async throws {
        let seen = SeenQueries()
        let connector = try Self.connector(Self.caseSensitive("Roadmap", seen: seen))
        _ = try await connector.run("roadmap")
        let asked = await seen.all
        #expect(asked == ["roadmap"],
                "у латиницы регистр приводит сама база — второй запрос это плата ни за что")
    }

    @Test("пусто и во второй раз — остаётся пусто, а не выдумывается")
    func stillEmptyStaysEmpty() async throws {
        let connector = try Self.connector(Self.caseSensitive("совсем другое", seen: SeenQueries()))
        #expect(try await connector.run("тарифы").items.isEmpty)
    }

    @Test("вариант слова строится по первой букве", arguments: [
        ("тарифы", "Тарифы"), ("Тарифы", "тарифы"),
        ("сроки по проекту", "Сроки по проекту"),
    ])
    func variantIsBuiltFromFirstLetter(word: String, expected: String) {
        #expect(ManifestConnector.caseVariant(of: word) == expected)
    }

    @Test("у слов без кириллицы варианта нет", arguments: ["roadmap", "SSO", "42", ""])
    func noVariantWithoutCyrillic(word: String) {
        #expect(ManifestConnector.caseVariant(of: word) == nil)
    }
}
