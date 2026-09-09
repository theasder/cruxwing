import Testing
import Foundation
@testable import MeetGPT

/// Граница «данные остаются на машине» — целиком, а не по одному пути.
///
/// §3 роадмапа обещает, что каждая граница ломает сборку или запуск, когда её
/// нарушают. Для этой границы когда-то существовала одна проверка на один
/// вызов, хотя обращений к нашему серверу было много. Каждый следующий обязан
/// был помнить про пустой адрес сам — то есть граница держалась на памяти
/// автора, а не на проверке.
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
        // Пустой адрес — рабочее состояние cruxwing, а не сбой: сервера нет.
        // Файл, который этого не проверяет, соберёт запрос к «/api/…» и
        // отправит его в никуда — либо, что хуже, туда, где этот путь кем-то
        // занят.
        let files = try Self.filesTouchingBackend()
        #expect(files.count >= 10, "файлов нашлось \(files.count) — проверка была бы пустой")

        // Объявление и настройки к вызовам не относятся: они адрес хранят и
        // показывают, а не ходят по нему.
        let declarations: Set<String> = ["Secrets.swift", "LocalSecrets.generated.swift",
                                         "Config.swift", "SettingsView.swift",
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

    @Test("в сборке адреса нет — значит и обращаться некуда")
    func shippedBuildHasNoAddress() {
        // Первый слой, и он же самый надёжный: адреса нет в сгенерированном
        // Secrets.swift, а сборка останавливается, если он там появится.
        #expect(Config.backendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("в приложении нет first-party телеметрии и отправки отзывов")
    func firstPartyCollectionCodeIsAbsent() throws {
        let removedPaths = [
            "Integrations/AnalyticsEvent.swift",
            "Integrations/FunnelTracker.swift",
            "Integrations/SurfaceTracking.swift",
            "Integrations/StoreKitBridge.swift",
            "Integrations/StoreKitPurchaser.swift",
            "Views/Paywall/PaywallView.swift",
            "Feedback/FeedbackUploader.swift",
            "Feedback/FirstMeetingFeedbackSheet.swift",
            "Feedback/FirstMeetingPrompt.swift",
        ]
        for path in removedPaths {
            #expect(!FileManager.default.fileExists(atPath: Self.sources.appendingPathComponent(path).path),
                    "унаследованный сбор данных снова компилируется: \(path)")
        }

        let production = try Self.allProductionSource()
        for forbidden in ["/api/funnel", "/api/feedback", "/api/billing/storekit",
                          "/api/billing/checkout", "/api/promo", "/api/subscribe",
                          "/api/trial/device-claim",
                          "FunnelTracker.", "FeedbackUploader.", "trackSurface(",
                          "import StoreKit", "shouldShowPaywall", "paywallChoiceMade",
                          "postTrialPromptShown", "LiveTestPromoRedemptionReceipt",
                          "livetest.redeem"] {
            #expect(!production.contains(forbidden),
                    "унаследованный first-party сбор данных вернулся: \(forbidden)")
        }
    }

    private static func allProductionSource() throws -> String {
        guard let walker = FileManager.default.enumerator(
            at: sources, includingPropertiesForKeys: nil
        ) else { return "" }
        var chunks: [String] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            chunks.append(try String(contentsOf: url, encoding: .utf8))
        }
        return chunks.joined(separator: "\n")
    }
}
