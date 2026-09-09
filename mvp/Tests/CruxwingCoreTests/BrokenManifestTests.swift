import Testing
import Foundation
@testable import CruxwingCore

/// Один негодный манифест не уносит остальные.
///
/// `bundled()` бросает на первом плохом файле, а в работе его читали через
/// `try?` — значит один негодный манифест молча убирал ВСЕ. Каждый сервис,
/// описанный данными, возвращался на рукописный путь: без отделения 403 от 401,
/// без узнавания страницы входа, с угадыванием чужого конверта. Те самые
/// защиты, ради которых манифесты и писались, исчезали тише всего остального.
///
/// Случилось при добавлении Rocket.Chat: подстановку не объявили, файл
/// отвергли, а упала проверка Zulip — за два сервиса от причины.
@Suite struct BrokenManifestTests {

    static let good = #"""
    {"id":"horoshij","title":"Хороший","docs":"https://example.com/api",
     "verifiedOn":"2026-08-21",
     "request":{"method":"GET","path":"/search",
                "query":[{"name":"q","value":"{query}"}],
                "headers":[{"name":"Authorization","value":"Bearer {token}"}]},
     "response":{"list":[],"title":["title"],"key":["id"],"state":[]}}
    """#

    /// Негодный ровно тем, чем был негоден rocketchat.json: подстановка,
    /// которую никто не объявил и не заполнит.
    static let broken = #"""
    {"id":"negodnyj","title":"Негодный","docs":"https://example.com/api",
     "verifiedOn":"2026-08-21",
     "request":{"method":"GET","path":"/search/{nikto-ne-zapolnit}",
                "query":[{"name":"q","value":"{query}"}],
                "headers":[{"name":"Authorization","value":"Bearer {token}"}]},
     "response":{"list":[],"title":["title"],"key":["id"],"state":[]}}
    """#

    static func directory(_ files: [String: String]) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("manifests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (name, body) in files {
            try Data(body.utf8).write(to: root.appendingPathComponent(name))
        }
        return root
    }

    @Test("исправный манифест читается рядом с негодным")
    func goodSurvivesBeside() throws {
        let root = try Self.directory(["horoshij.json": Self.good,
                                       "negodnyj.json": Self.broken])
        defer { try? FileManager.default.removeItem(at: root) }

        let loaded = ConnectorManifest.load(from: root)
        #expect(loaded.manifests.map(\.id) == ["horoshij"],
                "исправный манифест унесло вместе с негодным")
        #expect(loaded.broken.map(\.name) == ["negodnyj.json"])
    }

    @Test("строгое чтение по-прежнему отказывается целиком")
    func strictReadStillRefuses() throws {
        // Это и есть сторож сборки: негодный файл не должен уехать людям.
        // Разница только в том, что в РАБОТЕ исправные продолжают работать.
        let root = try Self.directory(["horoshij.json": Self.good,
                                       "negodnyj.json": Self.broken])
        defer { try? FileManager.default.removeItem(at: root) }
        let loaded = ConnectorManifest.load(from: root)
        #expect(loaded.broken.count == 1)
        // Строгое чтение отказывается ЦЕЛИКОМ, даже когда исправный рядом:
        // негодный файл не должен уехать людям, и падать он обязан в сборке.
        #expect(throws: (any Error).self) { _ = try ConnectorManifest.strict(loaded) }
        // А мягкое отдаёт исправный.
        #expect(loaded.manifests.map(\.id) == ["horoshij"])
    }

    @Test("встроенные читаются обоими способами одинаково")
    func bundledAgreeBothWays() throws {
        // Пока все встроенные исправны, строгое и мягкое чтение дают одно и то
        // же. Разойдутся они ровно в тот день, когда появится негодный файл, —
        // и тогда `bundled()` упадёт в наборе, а `usable()` удержит остальные.
        let strict = try ConnectorManifest.bundled().map(\.id).sorted()
        let usable = ConnectorManifest.usable().map(\.id).sorted()
        #expect(strict == usable)
        #expect(usable.count >= 19, "манифестов нашлось \(usable.count) — чтение сломано")
    }

    @Test("подстановка с дефисом видна проверке")
    func hyphenatedPlaceholderIsSeen() throws {
        // Найдено случайно: заготовка «негодного» манифеста для проверки выше
        // оказалась ГОДНОЙ, потому что `{nikto-ne-zapolnit}` для разбора не был
        // подстановкой вовсе — имена читались без дефиса.
        //
        // Последствие не в проверке, а в адресе: незамеченная подстановка
        // уезжает к вендору буквально, вместе с фигурными скобками. Сервис
        // отвечает 404 на правдоподобный запрос, человек читает «ничего не
        // нашлось». Имена с дефисом обычны: team-id, org-id, project-key.
        let withHyphen = #"""
        {"id":"defis","title":"Дефис","docs":"https://example.com/api",
         "verifiedOn":"2026-08-21",
         "request":{"method":"GET","path":"/teams/{team-id}/search",
                    "query":[{"name":"q","value":"{query}"}],
                    "headers":[{"name":"Authorization","value":"Bearer {token}"}]},
         "response":{"list":[],"title":["title"],"key":["id"],"state":[]}}
        """#
        let root = try Self.directory(["defis.json": withHyphen])
        defer { try? FileManager.default.removeItem(at: root) }
        let loaded = ConnectorManifest.load(from: root)
        #expect(loaded.manifests.isEmpty, "подстановка с дефисом прошла незамеченной")
        #expect(loaded.broken.first?.name == "defis.json")

        // А объявленная — проходит: правило про необъявленные, а не про дефис.
        let declared = withHyphen.replacingOccurrences(
            of: #""response""#,
            with: #""parameters":[{"name":"team-id","title":"Команда","example":"t1"}],"response""#)
        let second = try Self.directory(["defis.json": declared])
        defer { try? FileManager.default.removeItem(at: second) }
        #expect(ConnectorManifest.load(from: second).manifests.map(\.id) == ["defis"])
    }
}
