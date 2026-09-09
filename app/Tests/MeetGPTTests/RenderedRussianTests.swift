import Foundation
import SwiftUI
import Testing
import ViewInspector
@testable import MeetGPT
import OrakulCore

/// Что человек видит на экране — по-русски.
///
/// Отличие от `RussianCopyTests`: там считаются литералы в исходниках, здесь —
/// отрисованный текст. Разница не теоретическая. Литерал может никогда не
/// показаться (рельса кредитов закрыта признаком и не рендерится вовсе), а
/// показанная строка может собираться в рантайме и целиком в исходниках не
/// встречаться. Считать надо то, что видно.
@MainActor
@Suite("Русский на экране", .serialized)
struct RenderedRussianTests {

    private func settingsText(_ tab: SettingsTab) throws -> [String] {
        let state = AppState(credentialStore: InMemoryKeychain())
        state.selectedSettingsTab = tab
        let manager = MCPConnectionManager(
            tokenStore: InMemoryKeychain(), notificationCenter: NotificationCenter())
        return try SettingsView()
            .environmentObject(state)
            .environmentObject(manager)
            .inspect()
            .findAll(ViewType.Text.self)
            .compactMap { try? $0.string() }
    }

    /// Марки, адреса и технические имена — не непереведённый текст.
    /// The interface is migrating to English screen by screen (ROADMAP §6.4), so
    /// each screen carries a number that may only fall. Equality, not `<=`: a
    /// ceiling nobody lowers stops meaning anything, and a new Russian string
    /// has to be explained exactly as much as a missed one.
    static let settingsTabsRussian: [SettingsTab: Int] = [
        .general: 3, .transcription: 4, .connectedApps: 4,
    ]
    static let firstRunRussian = 0
    static let mainWindowRussian = 240
    static let keysAndTrackersRussian = 0

    private func expectRussianCount(_ left: [String], _ pinned: Int, _ what: String) {
        let sample = left.sorted().prefix(4).joined(separator: " | ")
        #expect(left.count == pinned,
                "\(what): \(left.count) strings still Russian, pinned at \(pinned). \(sample)")
    }

    /// Vendor names are how their owners spell them, not untranslated copy.
    /// «Пачка» on a settings tab is the messenger's name; translating it would
    /// name a product that does not exist.
    private static let keptRussian = [
        "Пачка", "Яндекс", "Битрикс", "Трекер", "Вики",
    ]

    /// A string rendered on screen that is still Russian.
    private func isRussianSentence(_ text: String) -> Bool {
        var rest = text
        for name in Self.keptRussian {
            rest = rest.replacingOccurrences(of: name, with: "")
        }
        return rest.range(of: "[а-яё]", options: [.regularExpression, .caseInsensitive]) != nil
    }

    @Test("no Russian phrases are left on the settings tabs",
          arguments: [SettingsTab.general, .transcription, .ai,
                      .connectedApps, .accountPrivacy])
    func settingsTabsAreRussian(tab: SettingsTab) throws {
        let strings = try settingsText(tab)
        #expect(!strings.isEmpty, "вкладка \(tab) не отрисовалась — проверка была бы фиктивной")

        expectRussianCount(strings.filter(isRussianSentence),
                           Self.settingsTabsRussian[tab] ?? 0, "settings tab \(tab)")
    }

    @Test("no Russian phrases are left on the first-run screens")
    func firstRunScreensAreRussian() throws {
        // Это первое, что видит человек, и на этих экранах уже находились
        // английские подписи, которые счётчик по исходникам не показывал: он
        // считает литералы в трёх папках, а текст первого запуска собирается и
        // за их пределами.
        let state = AppState(credentialStore: InMemoryKeychain())
        let manager = MCPConnectionManager(
            tokenStore: InMemoryKeychain(), notificationCenter: NotificationCenter())

        let screens: [(String, [String])] = [
            ("проверка захвата",
             try CaptureCheckStep(onContinue: {})
                .environmentObject(state).inspect()
                .findAll(ViewType.Text.self).compactMap { try? $0.string() }),
            ("карточка настройки",
             try SetupCard()
                .environmentObject(state).environmentObject(manager).inspect()
                .findAll(ViewType.Text.self).compactMap { try? $0.string() }),
            ("согласие на запись",
             try RecordingConsentSheet()
                .environmentObject(state).inspect()
                .findAll(ViewType.Text.self).compactMap { try? $0.string() }),
        ]

        var left: [String] = []
        for (name, strings) in screens {
            #expect(!strings.isEmpty, "\(name) не отрисовался — проверка была бы фиктивной")
            left += strings.filter(isRussianSentence)
        }
        expectRussianCount(left, Self.firstRunRussian, "first-run screens")
    }


    @Test("no Russian phrases are left in the main window")
    func mainWindowIsRussian() throws {
        // Архив звонков берётся из временной папки, а не из настоящего.
        //
        // Иначе тест читал бы историю той машины, где запущен: у меня в боковой
        // панели лежат звонки с английскими названиями, и проверка ругалась бы
        // на мои же данные вместо интерфейса. Пустой архив — единственный
        // способ проверить именно интерфейс.
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("orakul-render-\(UUID().uuidString)", isDirectory: true)

        // Своя роль тоже своя у каждой машины: она лежит в UserDefaults, и в
        // тестовом хосте от прошлых прогонов осталось «Head of RevOps». Проверка
        // ругалась бы на чужую строку вместо интерфейса.
        let savedRole = Config.userCustomRole
        let savedContextSets = Config.contextSets
        defer {
            Config.userCustomRole = savedRole
            Config.contextSets = savedContextSets
        }
        Config.userCustomRole = ""
        // Saved context-set names are also user-authored sidebar copy. A
        // parallel test can leave an English fixture in UserDefaults, which
        // made this renderer test fail depending on suite order rather than UI
        // language. Isolate the persisted list before AppState reads it.
        Config.contextSets = []

        let state = AppState(llm: MockLLMGateway(response: ""),
                             sessionStore: SessionStore(root: root))
        let manager = MCPConnectionManager(
            tokenStore: InMemoryKeychain(), notificationCenter: NotificationCenter())
        state.mcp = manager

        let screens: [(String, [String])] = [
            ("боковая панель",
             try Sidebar()
                .environmentObject(state).environmentObject(manager).inspect()
                .findAll(ViewType.Text.self).compactMap { try? $0.string() }),
            ("панель ассистента",
             try AIStudioView()
                .environmentObject(state).environmentObject(manager).inspect()
                .findAll(ViewType.Text.self).compactMap { try? $0.string() }),
        ]

        var left: [String] = []
        for (name, strings) in screens {
            #expect(!strings.isEmpty, "\(name) не отрисовалась — проверка была бы фиктивной")
            left += strings.filter(isRussianSentence)
        }
        expectRussianCount(left, Self.mainWindowRussian, "main window")
    }

    @Test("the keys and trackers screens are in English")
    func keysAndTrackersAreRussian() throws {
        // Два экрана, ради которых orakul вообще открывают: куда вставить ключ
        // и как подключить трекер.
        //
        // Порог по числу строк — не украшение. Соседние экраны при отрисовке в
        // тесте дают ноль текстовых элементов (меню в строке состояния —
        // ровно такой), и проверка на них зелёная, ничего не проверив. Числа
        // ниже — то, что эти экраны дают на самом деле.
        let state = AppState(credentialStore: InMemoryKeychain())
        let manager = MCPConnectionManager(
            tokenStore: InMemoryKeychain(), notificationCenter: NotificationCenter())

        let screens: [(name: String, minimum: Int, strings: [String])] = [
            ("российские трекеры", 6,
             try RussianTrackersSection()
                .environmentObject(state).environmentObject(manager).inspect()
                .findAll(ViewType.Text.self).compactMap { try? $0.string() }),
            ("ключи провайдеров", 12,
             try ProviderKeysSection()
                .environmentObject(state).environmentObject(manager).inspect()
                .findAll(ViewType.Text.self).compactMap { try? $0.string() }),
        ]

        var left: [String] = []
        for (name, minimum, strings) in screens {
            #expect(strings.count >= minimum,
                    "\(name): отрисовано \(strings.count) строк вместо \(minimum)+ — проверка пустая")
            left += strings.filter(isRussianSentence)
        }
        expectRussianCount(left, Self.keysAndTrackersRussian, "keys and trackers")
    }

    @Test("the recording type keeps one label for the screen and one for the prompt")
    func recordingTypeLabelsSplitByAudience() {
        // Одно поле служило двум хозяевам: `label` показывался на плашке записи
        // И подставлялся в модельный промпт «Recording type: …». Пока они были
        // одним значением, перевести экран значило сломать промпт, и тип записи
        // так и оставался английским. Теперь их два, и проверяются оба.
        for kind in RecordingContextKind.allCases {
            #expect(kind.displayLabel.range(of: "[а-яА-ЯёЁ]", options: .regularExpression) == nil,
                    "the recording type is still Russian: \(kind) → \(kind.displayLabel)")
            #expect(kind.label.range(of: "^[A-Za-z / ]+$", options: .regularExpression) != nil,
                    "промпт получит не то имя: \(kind) → \(kind.label)")
        }

        // И то, что видит человек, идёт из русского поля.
        let selection = RecordingContextSelection(mode: .lecture)
        #expect(selection.resolvedDisplayLabel(detected: .meeting) == "Lecture")
        #expect(selection.resolvedLabel(detected: .meeting) == "Lecture")
    }


    @Test("the check catches Russian rather than passing everything")
    func theCheckActuallyCatchesRussian() {
        // Without this the tests above stay green with a broken filter. That
        // has happened here before: a substring check passed with the guard
        // it was protecting deleted.
        #expect(isRussianSentence("Сохранить ответ документом Word"))
        #expect(isRussianSentence("Требует внимания"))
        #expect(isRussianSentence("Скрыть эту встречу"))

        // And it does not complain about what must not be translated.
        #expect(!isRussianSentence("Яндекс Трекер"))
        #expect(!isRussianSentence("platform.openai.com"))
        #expect(!isRussianSentence("Google Calendar"))
        #expect(!isRussianSentence("A key for OpenAI"))
    }
}
