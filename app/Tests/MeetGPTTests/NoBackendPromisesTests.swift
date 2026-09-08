import Foundation
import SwiftUI
import Testing
import ViewInspector
@testable import MeetGPT

/// Приложение не предлагает того, чего в этой сборке нет.
///
/// За один день это вылезло четыре раза, и каждый раз по-своему:
///
/// 1. Адрес сервера не зашивался в установщик, а `Config` подставлял вместо
///    пустого значения адрес Cruxwing — чужой, живой и отвечающий. Вход и счёт
///    выглядели рабочими.
/// 2. Строка «вставить ключ провайдера» держалась на признаке входа. Когда
///    подстановку убрали, признак стал означать «вошёл», и единственная нужная
///    строка исчезла заодно с ненужными.
/// 3. Кнопка «Проверить в вебе» звала поиск, который живёт на сервере: без него
///    она молча делала обычную проверку и отвечала «источников: 0».
/// 4. Раздел «Аккаунт» в настройках не был закрыт ничем и обещал «модели без
///    своих ключей» и синхронизацию журнала — и то и другое требует сервера.
///
/// Общее у всех четырёх — не сервер, а то, что проверка стояла не на том месте:
/// на файле сборки, на признаке-соседе, на коде возврата. Здесь проверяется то,
/// что видит человек.
@Suite("Обещания без сервера")
struct NoBackendPromisesTests {

    private static var hasBackend: Bool {
        !Config.backendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var viewsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/MeetGPT/Views")
    }

    /// Все `.swift` под Views, вместе с подпапками.
    private func viewSources() -> [(name: String, text: String)] {
        let root = viewsDirectory
        guard let walker = FileManager.default.enumerator(atPath: root.path) else { return [] }
        var found: [(name: String, text: String)] = []
        for case let entry as String in walker where entry.hasSuffix(".swift") {
            let url = root.appendingPathComponent(entry)
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                found.append((name: entry, text: text))
            }
        }
        return found
    }

    @MainActor
    @Test(
        "вход нигде не предлагается, когда входить некуда",
        .enabled(if: !Self.hasBackend, "This boundary applies to the serverless Orakul build."))
    func noSignInOfferedWithoutABackend() {
        let state = AppState(credentialStore: InMemoryKeychain())

        // Оба признака, на которые смотрят экраны со входом.
        #expect(!state.wheesprAvailable, "предлагается вход в несуществующий аккаунт")
        #expect(!state.ledgerConfigured, "показывается счёт без сервера")
    }

    @MainActor
    @Test(
        "в настройках нет раздела «Аккаунт», когда входить некуда",
        .enabled(if: !Self.hasBackend, "This boundary applies to the serverless Orakul build."))
    func settingsHidesTheAccountSection() throws {
        // Проверяется отрисовка, а не исходник. Первая версия искала
        // «backendBaseURL» по файлу целиком — и проходила даже с убранной
        // защитой: это слово встречается в SettingsView ещё раз, в адресе
        // MCP (строка 686). Проверка была зелёной и не значила ничего — ровно
        // та же ошибка, что и во всех четырёх случаях выше.
        let state = AppState(credentialStore: InMemoryKeychain())
        state.selectedSettingsTab = .accountPrivacy
        let manager = MCPConnectionManager(
            tokenStore: InMemoryKeychain(), notificationCenter: NotificationCenter())
        let rendered = try SettingsView()
            .environmentObject(state)
            .environmentObject(manager)
            .inspect()

        #expect(throws: (any Error).self, "раздел «Аккаунт» показан, а входить некуда") {
            try rendered.find(text: "Signing in is what lets you use models without your own keys and sync the decision log.")
        }
        #expect(throws: (any Error).self, "предлагается удалить несуществующий аккаунт") {
            try rendered.find(viewWithAccessibilityIdentifier: "settings.account.delete")
        }
    }

    @MainActor
    @Test(
        "стартовый экран проверки не предлагает несуществующий веб-поиск",
        .enabled(if: !Self.hasBackend, "This boundary applies to the serverless Orakul build."))
    func defaultFactCheckUIHidesWebSearch() throws {
        // Проверяем то, что видит человек после обычного запуска. Поиск слова
        // `backendBaseURL` по всему файлу проходил даже после удаления защиты.
        let state = AppState(credentialStore: InMemoryKeychain())
        #expect(state.factCheckSearch == nil)
        let rendered = try FactCheckSheet()
            .environmentObject(state)
            .inspect()

        #expect(throws: (any Error).self,
                "кнопка обещает веб-поиск, хотя сервера нет") {
            try rendered.find(button: "Проверить в вебе")
        }
    }

    @MainActor
    @Test("рельса с кредитами не показывается ни в каком виде")
    func creditRailNeverRenders() throws {
        // Механика кредитов осталась от Cruxwing и закрыта признаком
        // `Config.llmViaBackend`, который в orakul всегда false. Удалять её —
        // это ~250 строк внутри живой полосы бюджета, и цена ошибки там выше,
        // чем польза. Поэтому проверяется не отсутствие кода, а отсутствие
        // кредитов на экране: строка «Войдите, чтобы получить кредиты», баланс
        // и подписи для VoiceOver.
        #expect(!Config.llmViaBackend, "маршрут через сервер включился — кредиты оживут")

        let state = AppState(llm: MockLLMGateway(response: ""))
        let manager = MCPConnectionManager(
            tokenStore: InMemoryKeychain(), notificationCenter: NotificationCenter())
        state.mcp = manager
        let rendered = try PromptBudgetBar()
            .environmentObject(state)
            .environmentObject(manager)
            .inspect()

        for phrase in ["Войдите, чтобы получить кредиты и синхронизацию.",
                       "Загружаю баланс кредитов…"] {
            #expect(throws: (any Error).self, "на экране кредиты: \(phrase)") {
                try rendered.find(text: phrase)
            }
        }
    }

    @Test("платных уровней нет ни в одном виде")
    func nothingChargesMoney() {
        // Отдельно от NoTariffsTests: здесь проверяется, что в живые экраны не
        // просочился текст про списание денег. Отдельного paywall-флага больше
        // нет: удалённый экран нельзя случайно оживить переключением Bool.
        for (name, text) in viewSources() {
            #expect(!text.contains("search credits"),
                    "\(name): осталось обещание списывать кредиты")
        }
    }
}

/// SECURITY.md обещает: по умолчанию запуск не обращается к серверу разработчика.
/// Даже пустой адрес — не защита: случайно вернувшаяся настройка сразу оживила бы унаследованные
/// first-party вызовы. При этом опрос раньше настроенных Telegram и Google Calendar может возобновиться и
/// должен быть назван честно. Здесь проверяются и реальный путь запуска, и точная оговорка в документах.
@Suite("Обещание SECURITY.md про сеть при запуске")
struct LaunchSendsNothingTests {
    private var appRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: appRoot.appendingPathComponent(relativePath),
            encoding: .utf8)
    }

    private func startupRestoreBody(in source: String) throws -> String {
        let start = try #require(
            source.range(of: "func loadPersistedConnectionState() async {")?.lowerBound,
            "AppState startup restore function disappeared")
        let tail = source[start...]
        let end = try #require(
            tail.range(of: "\n    deinit {")?.lowerBound,
            "could not bound AppState startup restore function")
        return String(tail[..<end])
    }

    private func contentViewStartupTask(in source: String) throws -> String {
        let start = try #require(
            source.range(of: "        .task {")?.lowerBound,
            "ContentView startup task disappeared")
        let tail = source[start...]
        let end = try #require(
            tail.range(of: "\n        .onChange(of: state.onboardingReplayToken)")?.lowerBound,
            "could not bound ContentView startup task")
        return String(tail[..<end])
    }

    @Test("точка входа и настоящий путь восстановления не зовут сервер разработчика")
    func realStartupPathContainsNoInheritedFirstPartyCalls() throws {
        let appEntry = try source("Sources/MeetGPT/MeetGPTApp.swift")
        let contentView = try source("Sources/MeetGPT/Views/ContentView.swift")
        let state = try source("Sources/MeetGPT/AppState.swift")
        #expect(contentView.contains("state.loadPersistedConnectionState()"),
                "ContentView больше не показывает, какой путь реально исполняется при запуске")

        let surfaces = [
            ("MeetGPTApp.swift", appEntry),
            ("ContentView startup task", try contentViewStartupTask(in: contentView)),
            ("AppState.loadPersistedConnectionState", try startupRestoreBody(in: state)),
        ]
        let forbidden = [
            "PaywallAPI.",
            "wheesprAccessToken(",
            "WheesprAuth.",
            "LLMCatalog.hydrate(",
            "FunnelTracker.",
            "FeedbackUploader.",
            // Подготовка локальной модели может её скачать. Ей место в
            // онбординге и при начале записи, а не в общем `onAppear`.
            "prewarmLocalModelIfNeeded(",
        ]
        for (name, startupSource) in surfaces {
            for call in forbidden {
                #expect(!startupSource.contains(call),
                        "\(name) снова делает first-party вызов при запуске: \(call)")
            }
        }
        let restore = try startupRestoreBody(in: state)
        #expect(restore.contains("managedAccountEnabled = Config.llmViaBackend"),
                "direct BYOK no longer proves that legacy account hydration is disabled")
        #expect(restore.contains("managedAccountEnabled\n                    ? Config.loadWheesprSession"),
                "startup can read an inherited account session without the managed-build gate")
    }

    @Test("документы называют оба опроса, которые могут возобновиться")
    func configuredPollingIsDisclosed() throws {
        let repositoryRoot = appRoot.deletingLastPathComponent()
        let security = try String(
            contentsOf: repositoryRoot.appendingPathComponent("SECURITY.md"),
            encoding: .utf8)
        let readme = try String(
            contentsOf: repositoryRoot.appendingPathComponent("README.md"),
            encoding: .utf8)
        let manager = try source("Sources/MeetGPT/MCP/MCPConnectionManager.swift")
        let state = try source("Sources/MeetGPT/AppState.swift")

        // Не даём документам перечислять мёртвые возможности: оба фоновых пути
        // должны реально оставаться в коде, иначе оговорку надо сужать.
        #expect(manager.contains("await telegramSource.start("))
        #expect(state.contains("startReminderPolling()"))
        #expect(security.contains("Telegram"))
        #expect(security.contains("Google Calendar"))
        #expect(security.contains("may resume on the next"))
        #expect(readme.contains("the resumption at startup of a"))
        #expect(security.contains("no unrequested calls to the developer's server"))
    }

    @Test("манифест конфиденциальности не приписывает orakul сбор данных")
    func privacyManifestDeclaresNoDeveloperCollection() throws {
        let data = try Data(contentsOf: appRoot.appendingPathComponent("Support/PrivacyInfo.xcprivacy"))
        let object = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil)
        let manifest = try #require(object as? [String: Any])
        let collected = try #require(manifest["NSPrivacyCollectedDataTypes"] as? [Any])

        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect(collected.isEmpty,
                "манифест всё ещё объявляет сбор данных разработчиком")
    }
}
