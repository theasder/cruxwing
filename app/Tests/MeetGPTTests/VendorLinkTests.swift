import Testing
import Foundation
@testable import MeetGPT

/// Куда пойдёт браузер человека после выгрузки.
///
/// Ссылку называет чужой сервер, а открывает её cruxwing — сам, без второго
/// нажатия. Значит выбор адреса принадлежит серверу, и единственное, что стоит
/// между человеком и чужой страницей входа, — эта проверка.
///
/// Прежняя выглядела как проверка и ею не была: строка начинается с `https://`
/// и СОДЕРЖИТ «notion.so». Содержит её и чужой хост с таким началом, и чужой
/// хост с таким хвостом в параметрах.
@Suite struct VendorLinkTests {
    private let notion = ["notion.so", "notion.site"]

    @Test("настоящий адрес сервиса открывается")
    func theRealHostIsAccepted() throws {
        let url = try #require(VendorLink.first(in: "Created: https://www.notion.so/Zapiska-1a2b",
                                                allowing: notion))
        #expect(url.absoluteString == "https://www.notion.so/Zapiska-1a2b")
        // Своё пространство у Notion живёт на поддомене notion.site.
        #expect(VendorLink.first(in: "https://acme.notion.site/page", allowing: notion) != nil)
    }

    @Test("чужой хост с нужным именем в начале не открывается")
    func aLookalikePrefixIsRefused() {
        // Хозяин здесь chuzhoy.ru, а «notion.so» — просто первая метка.
        #expect(VendorLink.first(in: "https://notion.so.chuzhoy.ru/login", allowing: notion) == nil)
    }

    @Test("чужой домен, кончающийся нужным именем, не открывается")
    func aLookalikeSuffixIsRefused() {
        // Найдено мутацией: без точки перед доменом проверка принимает
        // `podnotion.so` — чужое имя, которое просто кончается тем же. Такой
        // домен регистрируется за минуту и стоит рубль.
        #expect(VendorLink.first(in: "https://podnotion.so/login", allowing: notion) == nil)
        #expect(VendorLink.first(in: "https://ne-notion.site/x", allowing: notion) == nil)
    }

    @Test("чужой хост с нужным именем в параметрах не открывается")
    func aNameInsideTheQueryIsRefused() {
        #expect(VendorLink.first(in: "https://chuzhoy.ru/vhod?next=notion.so", allowing: notion) == nil)
    }

    @Test("не https — не открывается")
    func plainHTTPIsRefused() {
        // http отдал бы человека посреднику на пути к настоящей странице.
        #expect(VendorLink.first(in: "http://www.notion.so/page", allowing: notion) == nil)
    }

    @Test("file и javascript адресами сервиса не считаются")
    func nonWebSchemesAreRefused() {
        // У них нет хозяина, и без явного условия сравнивать было бы нечего.
        #expect(VendorLink.belongs(URL(string: "file:///Applications/Terminal.app")!, to: notion) == false)
        #expect(VendorLink.belongs(URL(string: "javascript:alert(1)")!, to: notion) == false)
    }

    @Test("ссылка из JSON приезжает экранированной и всё равно узнаётся")
    func escapedJSONLinkIsFound() {
        let body = "{\"url\":\"https:\\/\\/www.notion.so\\/Stranica-9f\"}"
        #expect(VendorLink.first(in: body, allowing: notion)?.host == "www.notion.so")
    }

    @Test("выгрузка в Notion спрашивает именно это правило")
    func theExportUsesTheRule() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/MeetGPT/AppState.swift"), encoding: .utf8)
        #expect(source.contains("VendorLink.first(in: text, allowing: [\"notion.so\", \"notion.site\"])"),
                "выгрузка снова разбирает адрес сама")
        #expect(!source.contains("s.contains(\"notion.so\")"),
                "вернулась проверка вхождением: чужой хост с таким именем её проходит")
    }
}
