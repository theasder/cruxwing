import Testing
import Foundation
@testable import CruxwingCore

/// Заметки на диске (роадмап, §7.4).
///
/// Проверяется не «нашлось что-нибудь», а три обещания: ничего не уходит в
/// сеть по построению, служебные папки не попадают в ответ, и граница по
/// файлам честно называется человеку.
@Suite struct LocalNotesTests {

    /// Папка с заметками, живущая ровно один тест.
    final class Vault {
        let root: URL
        init() {
            root = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("cruxwing-notes-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        deinit { try? FileManager.default.removeItem(at: root) }

        @discardableResult
        func write(_ path: String, _ text: String, modified: Date? = nil) -> URL {
            let url = root.appendingPathComponent(path)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try? Data(text.utf8).write(to: url)
            if let modified {
                try? FileManager.default.setAttributes([.modificationDate: modified],
                                                       ofItemAtPath: url.path)
            }
            return url
        }

        func writeRaw(_ path: String, _ data: Data) {
            let url = root.appendingPathComponent(path)
            try? Data(data).write(to: url)
        }
    }

    @Test("находит строку, в которой встретилось слово, и берёт заголовок заметки")
    func findsTheLineAndTheHeading() throws {
        let vault = Vault()
        vault.write("созвон.md", """
        # Созвон по тарифам

        Аня: годовой не трогаем до декабря.
        Борис: месячный поднимаем на пятнадцать процентов.
        """)
        let hit = try #require(try LocalNotes(root: vault.root).search("месячный").hits.first)
        #expect(hit.title == "Созвон по тарифам")
        #expect(hit.context == "Борис: месячный поднимаем на пятнадцать процентов.")
        #expect(hit.path == "созвон.md")
    }

    @Test("без заголовка именем становится имя файла, а не «без названия»")
    func fallsBackToFileName() throws {
        let vault = Vault()
        vault.write("Планёрка 12 марта.md", "Решили перенести релиз на апрель.")
        let hit = try #require(try LocalNotes(root: vault.root).search("релиз").hits.first)
        #expect(hit.title == "Планёрка 12 марта")
    }

    @Test("служебные папки не попадают в ответ")
    func skipsHiddenFolders() throws {
        // `.trash` — удалённое. Заметка оттуда в ответе читается как
        // «программа помнит то, что я стёр», и это худший вид сюрприза для
        // источника, который обещает приватность.
        let vault = Vault()
        vault.write(".trash/старое.md", "Решили поднять тарифы вдвое.")
        vault.write(".obsidian/workspace.md", "Решили поднять тарифы вдвое.")
        vault.write("живое.md", "Решили тарифы не трогать.")
        let hits = try LocalNotes(root: vault.root).search("тарифы").hits
        #expect(hits.map(\.path) == ["живое.md"])
    }

    @Test("подпапки читаются, а путь остаётся относительным")
    func walksSubfolders() throws {
        let vault = Vault()
        vault.write("проекты/бэкенд/лимиты.md", "Договорились поднять лимиты выгрузки.")
        let hit = try #require(try LocalNotes(root: vault.root).search("лимиты").hits.first)
        #expect(hit.path == "проекты/бэкенд/лимиты.md")
    }

    @Test("не-заметки не читаются")
    func ignoresOtherFiles() throws {
        let vault = Vault()
        vault.write("отчёт.txt", "Решили поднять тарифы.")
        vault.write("данные.json", #"{"решение":"поднять тарифы"}"#)
        #expect(try LocalNotes(root: vault.root).search("тарифы").hits.isEmpty)
    }

    @Test("граница по файлам называется человеку, а не срабатывает молча")
    func boundIsReported() throws {
        let vault = Vault()
        let old = Date(timeIntervalSince1970: 1_000_000)
        for index in 1...10 {
            vault.write("заметка-\(index).md", "Про лимиты номер \(index)",
                        modified: old.addingTimeInterval(Double(index)))
        }
        let notes = LocalNotes(root: vault.root, limits: .init(files: 4))
        let outcome = try notes.search("лимиты")
        #expect(outcome.coverage == .latest(scanned: 4, total: 10))
        #expect(outcome.coverage.note(.folder).contains("4"))
        #expect(outcome.coverage.note(.folder).contains("10"))
        // Свежие сначала: обрезается старое, а не новое.
        #expect(outcome.hits.first?.path == "заметка-10.md")
    }

    @Test("когда прочитано всё, так и сказано")
    func wholeVaultIsReported() throws {
        let vault = Vault()
        vault.write("одна.md", "Про лимиты")
        vault.write("две.md", "Не про то")
        let outcome = try LocalNotes(root: vault.root).search("лимиты")
        #expect(outcome.coverage == .wholeList(scanned: 2))
    }

    @Test("огромный файл пропускается, а не съедает ответ")
    func skipsHugeFiles() throws {
        let vault = Vault()
        vault.write("дамп.md", String(repeating: "лимиты ", count: 50_000))
        vault.write("заметка.md", "Про лимиты коротко")
        let outcome = try LocalNotes(root: vault.root, limits: .init(bytes: 1024)).search("лимиты")
        #expect(outcome.hits.map(\.path) == ["заметка.md"])
        // Пропущенный файл — не пропавшая папка: охват по-прежнему полный,
        // потому что прочитаны все файлы, которые вообще читаются.
        #expect(outcome.coverage == .wholeList(scanned: 2))
    }

    @Test("заметка из Windows читается, а не пропускается молча")
    func readsCP1251Notes() throws {
        // UTF-8-разбор возвращает на ней nil. Пропустить такой файл значило бы
        // не находить то, что в нём написано, и никак об этом не сказать.
        let vault = Vault()
        let text = "# Планёрка\n\nРешили поднять лимиты выгрузки."
        vault.writeRaw("windows.md", try #require(CP1251.encode(text)))
        let hit = try #require(try LocalNotes(root: vault.root).search("лимиты").hits.first)
        #expect(hit.title == "Планёрка")
        #expect(hit.context == "Решили поднять лимиты выгрузки.")
    }

    @Test("несуществующая папка — понятный отказ, а не пустая выдача")
    func missingFolderIsAnError() {
        let missing = URL(fileURLWithPath: "/такой/папки/нет")
        #expect(throws: LocalNotes.NotesError.unreadable("/такой/папки/нет")) {
            _ = try LocalNotes(root: missing).search("лимиты")
        }
    }

    @Test("регистр не мешает")
    func caseInsensitive() throws {
        let vault = Vault()
        vault.write("з.md", "Решили: ТАРИФЫ не трогаем")
        #expect(try LocalNotes(root: vault.root).search("тарифы").hits.count == 1)
    }
}

/// Заметки, спрошенные так же, как любой другой источник.
@Suite struct LocalNotesQueryTests {

    @Test("папка отвечает без токена — в этом её смысл")
    func answersWithoutAToken() async throws {
        let vault = LocalNotesTests.Vault()
        vault.write("созвон.md", "# Созвон\n\nРешили поднять лимиты выгрузки.")
        let answer = await ConnectorQuery.ask(
            .init(service: "заметки", token: "", host: vault.root.path, scope: nil),
            query: "лимиты")
        #expect(!answer.failed, "ответ: «\(answer.text)»")
        #expect(answer.text.contains("Решили поднять лимиты выгрузки."))
        #expect(answer.text.contains("созвон.md"))
    }

    @Test("без папки сказано, чего не хватает, а не «нет токена»")
    func missingFolderIsNamed() async {
        let answer = await ConnectorQuery.ask(
            .init(service: "заметки", token: "", host: nil, scope: nil),
            query: "лимиты")
        #expect(answer.failed)
        #expect(answer.text.contains("folder"), "ответ: «\(answer.text)»")
        #expect(!answer.text.contains("токен"), "токена у заметок нет и быть не может")
    }

    @Test("ничего не найдено — и сказано, среди чего искали")
    func emptyAnswerCarriesCoverage() async throws {
        let vault = LocalNotesTests.Vault()
        vault.write("одна.md", "Совсем про другое")
        let answer = await ConnectorQuery.ask(
            .init(service: "заметки", token: "", host: vault.root.path, scope: nil),
            query: "лимиты")
        #expect(answer.text.contains("nothing matched"))
        #expect(answer.text.contains("file"), "ответ: «\(answer.text)»")
        #expect(!answer.failed)
    }
}
