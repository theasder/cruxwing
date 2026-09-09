import Testing
import Foundation
@testable import CruxwingCore

/// Секрет в адресе запроса.
///
/// Недружелюбному сервису для этого ничего делать не нужно — достаточно
/// документировать удобный способ «?token=…». Адрес пишется целиком в журнал
/// прокси, в журнал доступа сервиса и в отчёты об ошибках; заголовок туда не
/// попадает. Журналы живут дольше токена, и отзыв ключа их не чистит.
@Suite("Секрет в адресе")
struct SecretInAddressTests {

    /// Манифест-проба. Собирается из кусков, а не правкой строки: подстановка
    /// внутри JSON ломает сам JSON, и тест падает разбором, ничего не проверив.
    static func manifest(extraQuery: (name: String, value: String)? = nil,
                         path: String = "/search",
                         scanPage: String? = nil) throws -> ConnectorManifest {
        var query = #"{"name":"q","value":"{query}"}"#
        if let extra = extraQuery { query += #",{"name":"\#(extra.name)","value":"\#(extra.value)"}"# }
        let scan = scanPage.map { page in
            #","scan":{"pages":2,"perPage":50,"match":[["title"]],"page":[{"name":"page","value":"\#(page)"}]}"#
        } ?? ""
        let json = #"""
        {"id":"проба","title":"Проба","docs":"https://example.com/api",
         "verifiedOn":"2026-08-18",
         "request":{"method":"GET","path":"\#(path)",
           "query":[\#(query)],
           "headers":[{"name":"Authorization","value":"Bearer {token}"}]},
         "response":{"list":["items"],"title":["title"],"context":[],"key":[],"state":[]}\#(scan)}
        """#
        return try JSONDecoder().decode(ConnectorManifest.self, from: Data(json.utf8))
    }

    @Test("токен в параметрах запроса не принимается")
    func tokenInQueryRefused() throws {
        let manifest = try Self.manifest(extraQuery: ("token", "{token}"))
        #expect(throws: ConnectorManifest.ManifestError.self) { try manifest.validate() }
    }

    @Test("токен в пути не принимается")
    func tokenInPathRefused() throws {
        #expect(throws: ConnectorManifest.ManifestError.self) {
            try Self.manifest(path: "/search/{token}").validate()
        }
    }

    @Test("логин с паролем в параметрах запроса не принимается")
    func basicInQueryRefused() throws {
        let manifest = try Self.manifest(extraQuery: ("auth", "{basic}"))
        #expect(throws: ConnectorManifest.ManifestError.self) { try manifest.validate() }
    }

    // Постраничный обход — те же параметры запроса, и про них забывают:
    // проверка, смотрящая только в query, пропустит секрет в scan.page.
    @Test("токен в параметрах постраничного обхода не принимается")
    func tokenInScanPageRefused() throws {
        #expect(throws: ConnectorManifest.ManifestError.self) {
            try Self.manifest(scanPage: "{token}").validate()
        }
    }

    @Test("человеку сказано, где именно секрет и почему это плохо")
    func refusalExplainsItself() throws {
        do {
            try Self.manifest(path: "/search/{token}").validate()
            Issue.record("манифест с секретом в пути принят")
        } catch let error as ConnectorManifest.ManifestError {
            #expect(error.description.contains("proxy logs"))
            #expect(error.description.contains("the path"))
        }
    }

    @Test("обычный манифест по-прежнему принимается")
    func headerManifestPasses() throws {
        try Self.manifest().validate()
    }

    // Утверждение о сегодняшнем дне, а не о будущем: все встроенные манифесты
    // передают секрет заголовком. Если завтра кто-то добавит пятнадцатый с
    // «?token=», загрузка упадёт здесь, а не на живом сервисе.
    @Test("все встроенные манифесты проходят это правило")
    func bundledManifestsPass() throws {
        let bundled = try ConnectorManifest.bundled()
        #expect(bundled.count >= 14)
        for manifest in bundled {
            #expect(throws: Never.self) { try manifest.validate() }
        }
    }
}
