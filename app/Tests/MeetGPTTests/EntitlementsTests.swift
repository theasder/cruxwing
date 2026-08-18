import Testing
import Foundation

/// Права приложения против того, что код на самом деле делает.
///
/// Проверка существует из-за поломки, которую набор не видит по построению:
/// тестовый прогон НЕ в песочнице, поэтому security-scoped-закладка в нём
/// создаётся и без права `files.bookmarks.app-scope`. В собранном приложении
/// она не создастся — молча, без ошибки, — и выбранная папка с заметками
/// проживёт до первого перезапуска.
///
/// То же правило, что и с DMG: проверять надо отгружаемое, а не то, что
/// удобно проверять.
@Suite struct EntitlementsTests {

    static var support: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // MeetGPTTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // app
            .appendingPathComponent("Support")
    }

    static var sources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/MeetGPT")
    }

    /// Все файлы прав, какие есть, РАЗОБРАННЫЕ как plist.
    ///
    /// Разбор, а не поиск подстроки: право, закомментированное в XML, при
    /// поиске по тексту выглядит выданным. Первая версия этой проверки так и
    /// работала и прошла на мутации «ключ убран в комментарий» — то есть
    /// подтверждала право, которого в собранном приложении нет.
    ///
    /// Перечислять файлы руками тоже нельзя: новый вариант сборки появится без
    /// права, а проверка промолчит.
    static func entitlementFiles() throws -> [(name: String, keys: Set<String>)] {
        let files = try FileManager.default.contentsOfDirectory(at: support,
                                                                includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "entitlements" }
        return try files.map { url in
            let data = try Data(contentsOf: url)
            let plist = try PropertyListSerialization.propertyList(
                from: data, options: [], format: nil)
            let dictionary = plist as? [String: Any] ?? [:]
            return (url.lastPathComponent, Set(dictionary.keys))
        }
    }

    /// Исполняемый код: комментарии выброшены. Иначе упоминание права в
    /// пояснении сходит за его использование.
    static func swiftCode() throws -> String {
        var code = ""
        guard let walker = FileManager.default.enumerator(at: sources,
                                                          includingPropertiesForKeys: nil) else {
            return code
        }
        for case let url as URL in walker where url.pathExtension == "swift" {
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") { continue }
                code += line + "\n"
            }
        }
        return code
    }

    @Test("код создаёт закладки — значит право на них выдано во всех сборках")
    func bookmarkEntitlementMatchesTheCode() throws {
        let code = try Self.swiftCode()
        let makesBookmarks = code.contains(".withSecurityScope")
        let files = try Self.entitlementFiles()
        #expect(files.count >= 3, "файлов прав нашлось \(files.count) — проверка была бы пустой")

        for file in files {
            let hasBookmarks = file.keys.contains("com.apple.security.files.bookmarks.app-scope")
            #expect(hasBookmarks == makesBookmarks,
                    makesBookmarks
                        ? "«\(file.name)» без права на закладки: выбранная папка не переживёт перезапуск, и это не проявится ни ошибкой, ни в наборе"
                        : "«\(file.name)» выдаёт право на закладки, которым никто не пользуется")
        }
    }

    @Test("выбор папки просит право на выбранные пользователем файлы")
    func userSelectedEntitlementIsPresent() throws {
        // NSOpenPanel без этого права возвращает адрес, который не открыть.
        for file in try Self.entitlementFiles() {
            #expect(file.keys.contains { $0.hasPrefix("com.apple.security.files.user-selected") },
                    "«\(file.name)» не разрешает читать выбранное человеком")
        }
    }

    @Test("права остаются списком того, что нужно, а не всего подряд")
    func noBlanketFileAccess() throws {
        // Полный доступ к диску отменил бы обещание «читаем только выбранную
        // папку», ради которого заметки и делались.
        for file in try Self.entitlementFiles() where file.name.contains("sandbox") {
            #expect(!file.keys.contains { $0.hasPrefix("com.apple.security.files.all") },
                    "«\(file.name)» просит доступ ко всему диску")
        }
    }
}
