import Testing
import Foundation
@testable import MeetGPT
import CruxwingCore

/// Разрешение на папку с заметками.
///
/// Проверяется то, что ломается молча: закладка переживает перезапуск, доступ
/// закрывается, «Убрать» действительно убирает. Диалог выбора папки сюда не
/// входит — окно в наборе не открыть, поэтому он отделён от `remember`.
@Suite struct LocalNotesFolderTests {

    /// Свой отсек настроек на каждую проверку: и чтобы не трогать настройки
    /// живого приложения, и чтобы параллельные проверки не перетирали друг
    /// другу папку.
    static func isolated() -> LocalNotesFolder {
        LocalNotesFolder(defaults: UserDefaults(suiteName: "cruxwing.tests.\(UUID().uuidString)")!)
    }

    final class Vault {
        let root: URL
        init() {
            root = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("cruxwing-folder-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        deinit { try? FileManager.default.removeItem(at: root) }
        func write(_ name: String, _ text: String) {
            try? Data(text.utf8).write(to: root.appendingPathComponent(name))
        }
    }

    @Test("выбранная папка переживает перезапуск")
    func bookmarkSurvivesRestart() {
        // Путь строкой в песочнице бесполезен: система выдаёт доступ к папке,
        // а не к строке с её адресом. Хранится закладка, и это проверяется
        // тем, что после «перезапуска» из неё получается тот же каталог.
        let folder = Self.isolated()
        let vault = Vault()

        #expect(!folder.isConfigured)
        #expect(folder.remember(vault.root))
        #expect(folder.isConfigured)
        #expect(folder.defaults.data(forKey: LocalNotesFolder.defaultsKey) != nil,
                "сохранена не закладка — после перезапуска доступа не будет")

        let access = folder.resolve()
        #expect(access?.url.resolvingSymlinksInPath() == vault.root.resolvingSymlinksInPath())
        access?.release()
    }

    @Test("«Убрать» действительно убирает разрешение")
    func forgetClearsIt() {
        let folder = Self.isolated()
        let vault = Vault()

        _ = folder.remember(vault.root)
        folder.forget()
        #expect(!folder.isConfigured)
        #expect(folder.resolve() == nil)
        #expect(folder.search("что угодно") == nil,
                "папка убрана, а поиск по ней всё равно идёт")
    }

    @Test("поиск идёт по выбранной папке и возвращает охват")
    func searchesTheChosenFolder() throws {
        let folder = Self.isolated()
        let vault = Vault()
        vault.write("созвон.md", "# Созвон\n\nРешили поднять лимиты выгрузки.")
        _ = folder.remember(vault.root)

        let found = try #require(folder.search("лимиты"))
        #expect(found.hits.first?.context == "Решили поднять лимиты выгрузки.")
        #expect(found.coverage == .wholeList(scanned: 1))
    }

    @Test("имя папки показывается человеку, а не путь целиком")
    func showsFolderName() {
        // Полный путь в строке настроек — это адрес домашней папки на экране,
        // который человек показывает коллегам, демонстрируя программу.
        let folder = Self.isolated()
        let vault = Vault()
        _ = folder.remember(vault.root)

        let name = folder.displayName
        #expect(name == vault.root.lastPathComponent)
        #expect(name?.contains("/") == false)
    }

    @Test("без выбранной папки источник не предлагается")
    func notOfferedWhenUnset() {
        let folder = Self.isolated()
        #expect(!folder.isConfigured)
        #expect(folder.displayName == nil)
    }
}
