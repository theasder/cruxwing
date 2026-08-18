import Testing
import Foundation
@testable import MeetGPT

/// Граница «данные остаются на машине» — целиком, а не по одному пути.
///
/// §3 роадмапа обещает, что каждая граница ломает сборку или запуск, когда её
/// нарушают. Для этой границы существовала одна проверка на один вызов
/// (`claimDeviceTrial`), а обращений к нашему серверу в коде девятнадцать
/// файлов. Каждый следующий обязан помнить про пустой адрес сам — то есть
/// граница держалась на памяти автора, а не на проверке.
///
/// Сегодня она держится ещё и на том, что адреса в сборке нет вовсе
/// (`build.sh` останавливается на непустом `backendBaseURL`). Эта проверка —
/// второй слой: если адрес однажды появится, обращения к нему не должны
/// начаться молча.
@Suite struct OffDeviceTrafficTests {

    static var sources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/MeetGPT")
    }

    /// Файлы, упоминающие адрес нашего сервера, с их исполняемым кодом.
    static func filesTouchingBackend() throws -> [(name: String, code: String)] {
        var found: [(String, String)] = []
        let walker = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        for case let url as URL in walker! where url.pathExtension == "swift" {
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            guard text.contains("backendBaseURL") else { continue }
            let code = text.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            guard code.contains("backendBaseURL") else { continue }   // только в комментарии — не в счёт
            found.append((url.lastPathComponent, code))
        }
        return found
    }

    @Test("каждое обращение к нашему серверу проверяет, что адрес вообще есть")
    func everyBackendCallChecksForAnAddress() throws {
        // Пустой адрес — рабочее состояние orakul, а не сбой: сервера нет.
        // Файл, который этого не проверяет, соберёт запрос к «/api/…» и
        // отправит его в никуда — либо, что хуже, туда, где этот путь кем-то
        // занят.
        let files = try Self.filesTouchingBackend()
        #expect(files.count >= 10, "файлов нашлось \(files.count) — проверка была бы пустой")

        // Объявление и настройки к вызовам не относятся: они адрес хранят и
        // показывают, а не ходят по нему.
        let declarations: Set<String> = ["Secrets.swift", "Config.swift", "SettingsView.swift",
                                         "CertPinning.swift", "LLMModel.swift"]
        var unguarded: [String] = []
        for file in files where !declarations.contains(file.name) {
            let checksEmptiness = file.code.contains("isEmpty")
                || file.code.contains("llmViaBackend")
                || file.code.contains("backendIsConfigured")
            if !checksEmptiness { unguarded.append(file.name) }
        }
        #expect(unguarded.isEmpty,
                "эти файлы обращаются к серверу, не проверив, что адрес задан: \(unguarded)")
    }

    @Test("телеметрия молчит, когда идти некуда")
    func funnelStaysSilentWithoutAnAddress() async {
        // Поведенчески, а не чтением: пустой адрес — и запрос не уходит.
        // Сессия, которая упала бы при обращении, здесь не нужна: `send`
        // возвращает false до её создания, и это то, что проверяется.
        let sent = await FunnelTracker.send(stage: "app_open", baseURL: "")
        #expect(!sent, "с пустым адресом воронка всё-таки куда-то постучалась")
    }

    @Test("в сборке адреса нет — значит и обращаться некуда")
    func shippedBuildHasNoAddress() {
        // Первый слой, и он же самый надёжный: адреса нет в сгенерированном
        // Secrets.swift, а сборка останавливается, если он там появится.
        #expect(Config.backendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("отзыв не уходит, когда адреса нет — и остаётся в очереди")
    func feedbackStaysQueuedWithoutAnAddress() async {
        // Поведенчески. Найдено проверкой выше: с пустым адресом
        // `URL(string: "/api/feedback")` возвращает НЕ nil — это правильный
        // относительный адрес, — поэтому запрос собирался и падал уже в
        // URLSession. Отзыв не уходил по случайности, а не по решению, а в нём
        // заметка и почта: слова человека о его собственной встрече.
        let sent = await FeedbackUploader.flush(session: .shared)
        #expect(!sent, "отзыв ушёл, хотя сервера у orakul нет")
    }
}
