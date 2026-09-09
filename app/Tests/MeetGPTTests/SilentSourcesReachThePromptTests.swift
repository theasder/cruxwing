import Testing
import Foundation
import CruxwingCore
@testable import MeetGPT

/// Источник, который НЕ ОТВЕТИЛ, — не то же самое, что ответивший пусто.
///
/// Отказы записываются и показываются человеку — в настройках, на строке
/// сервиса. До запроса они не доезжали никогда. Значит звонок, на котором
/// трекер тянул, вики отказала, а мессенджер придушили, давал ответ,
/// построенный на одной расшифровке, и выглядел он в точности как проверенный
/// по источникам.
///
/// Недружелюбному сервису для этого хватает бездействия: ни отказа, ни ошибки,
/// просто тишина — которую мы выдавали за отсутствие.
@MainActor
@Suite struct SilentSourcesReachThePromptTests {

    /// Своя память на каждую проверку, а не общая на процесс: соседи пишут в
    /// `ConnectorHealth.shared` из параллельных наборов, и проверка, читающая
    /// её, зависела бы от порядка запуска. Этот капкан репозиторий уже разбирал
    /// на общем кэше.
    private func health() -> ConnectorHealth { ConnectorHealth() }

    @Test("молчание источников попадает в запрос")
    func silenceReachesThePrompt() async throws {
        let health = health()
        let started = Date()
        await health.record(service: "redmine",
                            error: SelfHostedTrackers.ConnectorError.unauthorised)
        let snippet = try #require(
            await MCPConnectionManager.silentSourcesSnippet(since: started, health: health))
        #expect(snippet.text.contains("redmine"))
        #expect(snippet.text.contains("Did not answer this question"))
        #expect(snippet.text.contains("does not mean there is nothing there"))
    }

    @Test("вчерашний отказ в сегодняшний ответ не едет")
    func staleRefusalsStayOut() async throws {
        // ConnectorHealth живёт весь сеанс. Без отсечки по времени ответ нёс бы
        // отказ сервиса, который сейчас работает, — и человек чинил бы то, что
        // не сломано.
        let health = health()
        await health.record(service: "redmine",
                            error: SelfHostedTrackers.ConnectorError.unauthorised)
        let laterStart = Date().addingTimeInterval(1)
        #expect(await MCPConnectionManager.silentSourcesSnippet(
            since: laterStart, health: health) == nil)
    }

    @Test("когда все ответили, лишней строки нет")
    func nothingIsAddedWhenAllAnswered() async {
        #expect(await MCPConnectionManager.silentSourcesSnippet(
            since: Date(), health: health()) == nil)
    }

    @Test("слова сервиса чистятся, как и везде")
    func vendorWordsAreCleaned() async throws {
        // Текст отказа пишет чужой сервис, и на экран он попадает через
        // `VendorText`. В запрос — через ту же дверь: переносы рисуют структуру,
        // абзац вытесняет наши слова.
        // Ошибка НЕ из семьи коннекторов: `record` принимает любую, и её текст
        // через `VendorText` ещё не проходил. Первая редакция брала отказ вики
        // — а он чистится внутри самой семьи, поэтому мутация, снявшая чистку
        // здесь, проверку прошла: строка была чистой до неё.
        struct Raw: Error, LocalizedError {
            var errorDescription: String? { "первая\nвторая\nтретья" }
        }
        let health = health()
        let started = Date()
        await health.record(service: "wikijs", error: Raw())
        let snippet = try #require(
            await MCPConnectionManager.silentSourcesSnippet(since: started, health: health))
        #expect(!snippet.text.contains("\n"))
    }

    @Test("веер зовёт это правило")
    func theFanOutCallsIt() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/MeetGPT/MCP/MCPGrounding.swift"), encoding: .utf8)
        #expect(source.contains("Self.silentSourcesSnippet(since: startedAt)"),
                "молчание источников снова никуда не едет")
    }
}
