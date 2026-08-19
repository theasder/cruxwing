import Testing
import Foundation
@testable import MeetGPT

/// Отказ сервиса виден там же, где его настраивают.
///
/// Отказ записывался для четырёх семейств из пяти и показывался у двух. Для
/// Linear, Trello, Plane, GitHub и мессенджеров отозванный токен выглядел как
/// «ничего не нашлось», а российские трекеры не записывали отказ вовсе —
/// `try?` глотал его молча.
///
/// Разница между «в трекере этого нет» и «трекер нам отказал» — это разница
/// между «продукт стал хуже» и «пойди и почини доступ». Вторая ещё и рычаг
/// чужой стороны: доступ отзывают молча, и молчал тогда наш экран.
@Suite struct RefusalIsVisibleTests {

    static func source(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/MeetGPT/\(name)"),
                          encoding: .utf8)
    }

    /// Раздел настроек коннектора узнаётся по подсказке про доступ: где просят
    /// токен, там и настраивают источник.
    @Test("каждый раздел, где просят токен, показывает последний отказ")
    func everyConnectorSectionShowsRefusals() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/MeetGPT/Views")
        let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".swift") }
        var asksForToken: [String] = []
        var showsRefusal: [String] = []
        for file in files.sorted() {
            let text = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            if text.contains("credentialHint") { asksForToken.append(file) }
            if text.contains("ConnectorHealth.shared.refusal") { showsRefusal.append(file) }
        }
        #expect(!asksForToken.isEmpty, "разделы настроек не нашлись — проверка смотрит не туда")
        let silent = asksForToken.filter { !showsRefusal.contains($0) }
        #expect(silent.isEmpty, "просят токен и молчат об отказе: \(silent)")
    }

    @Test("российские трекеры записывают отказ, а не глотают его")
    func russianTrackersRecordRefusals() throws {
        // `try?` здесь стоял и превращал отказ в пустую выдачу. Проверка
        // структурная: поднять пять чужих сервисов ради одного `catch` дороже,
        // чем польза, а поведение записи закрыто набором ConnectorHealthTests.
        let store = try Self.source("MCP/RussianTrackerStore.swift")
        let search = try #require(store.range(of: "func searchText").map { start -> String in
            let tail = String(store[start.lowerBound...])
            guard let end = tail.range(of: "\n    func ") else { return tail }
            return String(tail[..<end.lowerBound])
        })
        #expect(search.contains("ConnectorHealth.shared.record("),
                "отказ снова глотается вместе с try?")
        #expect(!search.contains("try? await client.search"),
                "вернулся try?, который и делал отказ невидимым")
    }

    @Test("телеграм в этом правиле не участвует, и это не забывчивость")
    func telegramHasNoVendorToRefuse() throws {
        // Архив телеграма читается с диска: отказывать там некому. Отдельная
        // проверка, чтобы «у него нет отказов» осталось решением, а не дырой,
        // которую однажды закроют не тем.
        let source = try Self.source("Integrations/TelegramSupergroupSource.swift")
        #expect(!source.contains("URLSession"), "источник пошёл в сеть — значит и отказ возможен")
    }
}
