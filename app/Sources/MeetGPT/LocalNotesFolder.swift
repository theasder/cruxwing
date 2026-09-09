import Foundation
import AppKit
import OrakulCore

/// Папка с заметками, выбранная человеком.
///
/// Хранится закладкой, а не путём. Приложение в песочнице: путь, сохранённый
/// строкой, после перезапуска открыть нельзя — система выдаёт доступ к
/// конкретной папке, а не к строке с её адресом. Закладка это разрешение и
/// переносит через перезапуск.
///
/// В `UserDefaults`, а не в Связке ключей: это не секрет, а разрешение. В
/// Связке ключей ему было бы не место — и человек, разбирающий, что у него
/// хранится, нашёл бы там путь к своим заметкам.
/// Тип, а не набор статических функций: хранилище приходит извне, и подменять
/// его глобально нельзя. Общая изменяемая статика уже подводила здесь —
/// параллельные проверки перетирали друг другу папку, и падения выглядели как
/// поломка закладок. Тот же капкан ловили на `ProviderKeyStore` и на сроке MCP.
struct LocalNotesFolder {

    static let defaultsKey = "notes.local.bookmark"

    /// Настройки живого приложения. Наборы делают свой экземпляр.
    static let live = LocalNotesFolder(defaults: .standard)

    let defaults: UserDefaults

    /// Что показать человеку: имя выбранной папки. `nil` — не выбрана.
    var displayName: String? {
        guard let url = resolve()?.url else { return nil }
        return url.lastPathComponent
    }

    var isConfigured: Bool { defaults.data(forKey: Self.defaultsKey) != nil }

    /// Диалог выбора папки. Возвращает `true`, если человек выбрал.
    ///
    /// `NSOpenPanel` здесь, а не в представлении: выбор папки и создание
    /// закладки — одно действие, и разделять их значит получить состояние, где
    /// папка выбрана, а разрешения на неё нет.
    @MainActor
    func choose() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "A notes folder — Obsidian, or any directory of .md files"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return remember(url)
    }

    /// Сохранить разрешение на папку. Отдельно от диалога — чтобы это можно
    /// было проверить набором, не открывая окон.
    func remember(_ url: URL) -> Bool {
        guard let bookmark = try? url.bookmarkData(options: [.withSecurityScope],
                                                   includingResourceValuesForKeys: nil,
                                                   relativeTo: nil) else { return false }
        defaults.set(bookmark, forKey: Self.defaultsKey)
        return true
    }

    func forget() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    /// Папка и признак того, что доступ к ней открыт.
    ///
    /// Доступ обязательно закрывать: разрешения, открытые и не закрытые,
    /// накапливаются, и система в какой-то момент перестаёт выдавать новые —
    /// поломка проявится через час работы, а не сразу.
    struct Access {
        let url: URL
        let needsRelease: Bool

        func release() {
            if needsRelease { url.stopAccessingSecurityScopedResource() }
        }
    }

    func resolve() -> Access? {
        guard let bookmark = defaults.data(forKey: Self.defaultsKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark,
                                 options: [.withSecurityScope],
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return nil }
        // Устаревшая закладка — папку переместили или переименовали. Система
        // отдаёт по ней рабочий адрес, но просит перевыпустить: без этого
        // разрешение однажды перестанет действовать, и «заметки перестали
        // находиться» случится без единого действия человека.
        if stale { _ = remember(url) }
        let opened = url.startAccessingSecurityScopedResource()
        return Access(url: url, needsRelease: opened)
    }

    /// Поиск по выбранной папке. `nil` — папка не выбрана.
    func search(_ query: String, limit: Int = 10)
        -> (hits: [LocalNotes.Hit], coverage: SearchCoverage)? {
        guard let access = resolve() else { return nil }
        defer { access.release() }
        guard let outcome = try? LocalNotes(root: access.url).search(query, limit: limit) else {
            return nil
        }
        return (outcome.hits, outcome.coverage)
    }
}
