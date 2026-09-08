import Foundation

/// Заметки в папке на этом компьютере: Obsidian или просто каталог с `.md`.
///
/// Единственный источник, который ничего не обещает сети. У всех остальных
/// есть оговорка «токен уходит туда-то»; здесь её нет вовсе — читается диск,
/// и отключённый Wi-Fi ничего не меняет. Для продукта, который повторяет
/// «считается на вашем компьютере», это не ещё один коннектор, а
/// доказательство.
///
/// Чего он намеренно НЕ делает:
///
///   * не индексирует заранее. Индекс — это второй экземпляр ваших заметок,
///     который живёт отдельно и устаревает молча. Папку на несколько тысяч
///     файлов перечитать быстрее, чем объяснить человеку, почему найденное
///     не совпадает с тем, что у него на экране;
///   * не ходит в подпапки, начинающиеся с точки: `.git`, `.obsidian`,
///     `.trash` — это служебные каталоги, и попадание удалённой заметки в
///     ответ выглядит как «программа помнит то, что я стёр»;
///   * не читает всё подряд: только `.md` и `.markdown`. PDF и docx лежат в
///     тех же папках, но это другой разбор и другая цена.
public struct LocalNotes: Sendable {

    /// Границы, за которые чтение диска не выходит.
    ///
    /// Существуют по той же причине, что и `scan` у сервисов (роадмап, §7.2):
    /// хранилище на десять тысяч заметок не должно останавливать ответ на
    /// звонке. Разница в том, что здесь граница честно достижима — а когда она
    /// сработала, охват уезжает человеку.
    public struct Limits: Sendable {
        /// Сколько файлов открываем на один вопрос.
        public let files: Int
        /// Файлы крупнее не открываем: заметок такого размера не бывает, а
        /// экспорт базы или вставленный дамп — бывает.
        public let bytes: Int

        public init(files: Int = 2000, bytes: Int = 1_000_000) {
            self.files = files
            self.bytes = bytes
        }
    }

    public struct Hit: Equatable, Sendable {
        /// Заголовок заметки: первая строка вида `# …`, иначе имя файла.
        public let title: String
        /// Строка, в которой встретилось слово. Это и есть цитата.
        public let context: String
        /// Путь относительно папки — чтобы человек нашёл заметку у себя.
        public let path: String
    }

    public struct Outcome: Equatable, Sendable {
        public let hits: [Hit]
        public let coverage: SearchCoverage
    }

    public enum NotesError: Error, Equatable, LocalizedError {
        case notConfigured
        case unreadable(String)

        public var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "No notes folder is selected. Open Settings → Connected apps and name one."
            case .unreadable(let path):
                return "Could not read the folder «\(path)». Check that it is still there and readable."
            }
        }
    }

    let root: URL
    let limits: Limits

    public init(root: URL, limits: Limits = Limits()) {
        self.root = root
        self.limits = limits
    }

    /// Расширения, которые считаются заметками.
    static let extensions: Set<String> = ["md", "markdown"]

    public func search(_ query: String, limit: Int = 10) throws -> Outcome {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return Outcome(hits: [], coverage: .wholeList(scanned: 0)) }

        let files = try notes()
        // Свежие сначала: на вопрос «что мы решили» ответ чаще в недавней
        // заметке, а граница обрезает хвост — значит обрезать надо старое.
        let ordered = files.sorted { left, right in
            if left.modified != right.modified { return left.modified > right.modified }
            return left.path < right.path       // одинаковая дата — порядок всё равно один и тот же
        }
        let budget = ordered.prefix(limits.files)

        var hits: [Hit] = []
        for file in budget {
            guard file.size <= limits.bytes, let text = read(file.url) else { continue }
            guard let line = firstLine(containing: needle, in: text) else { continue }
            hits.append(Hit(title: heading(in: text) ?? name(of: file.path),
                            context: line,
                            path: file.path))
            if hits.count >= limit { break }
        }

        let scanned = budget.count
        return Outcome(hits: hits,
                       coverage: scanned == ordered.count
                           ? .wholeList(scanned: scanned)
                           : .latest(scanned: scanned, total: ordered.count))
    }

    struct Note: Sendable {
        let url: URL
        /// Путь относительно корня — то, что видит человек.
        let path: String
        let modified: Date
        let size: Int
    }

    /// Обход папки. Служебные каталоги пропускаются целиком, вместе с содержимым.
    func notes() throws -> [Note] {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw NotesError.unreadable(root.path)
        }

        var found: [Note] = []
        var stack = [root]
        while let directory = stack.popLast() {
            let entries = (try? manager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey],
                options: [])) ?? []
            for entry in entries {
                let name = entry.lastPathComponent
                // Точка в начале — служебное. `.obsidian` хранит настройки,
                // `.trash` — удалённое, и последнее в ответе выглядит как
                // «программа помнит то, что я стёр».
                if name.hasPrefix(".") { continue }
                let values = try? entry.resourceValues(
                    forKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey])
                if values?.isDirectory == true {
                    stack.append(entry)
                    continue
                }
                guard Self.extensions.contains(entry.pathExtension.lowercased()) else { continue }
                found.append(Note(url: entry,
                                  path: relative(entry),
                                  modified: values?.contentModificationDate ?? .distantPast,
                                  size: values?.fileSize ?? 0))
            }
        }
        return found
    }

    /// Путь относительно папки — то, что показывают человеку.
    ///
    /// Обе стороны раскрываются от ссылок. На macOS `/var` — ссылка на
    /// `/private/var`, и обход возвращал пути уже раскрытыми, а корень
    /// оставался таким, каким его передали: сравнение не совпадало, и в ответ
    /// уезжал ПОЛНЫЙ путь на диске вместо «созвон.md». Для источника, который
    /// продаётся приватностью, показать человеку (и модели) весь путь до его
    /// домашней папки — не косметика.
    private func relative(_ url: URL) -> String {
        let base = root.resolvingSymlinksInPath().path
        let prefix = base.hasSuffix("/") ? base : base + "/"
        let full = url.resolvingSymlinksInPath().path
        return full.hasPrefix(prefix) ? String(full.dropFirst(prefix.count)) : url.lastPathComponent
    }

    /// Чтение с запасным путём на CP1251.
    ///
    /// Заметки, сделанные на Windows, бывают в однобайтовой кодировке, и
    /// UTF-8-разбор возвращает на них `nil`. Пропустить такой файл значило бы
    /// молча не находить то, что в нём написано; своя таблица уже есть, потому
    /// что расшифровки приходят с той же проблемой.
    private func read(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let text = String(data: data, encoding: .utf8) { return text }
        return CP1251.decode(data)
    }

    /// Строка, в которой встретилось слово. Обрезается по краям, но не в
    /// середине: цитата, из которой вырезали середину, перестаёт быть цитатой.
    private func firstLine(containing needle: String, in text: String) -> String? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.lowercased().contains(needle) else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            return trimmed
        }
        return nil
    }

    private func heading(in text: String) -> String? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                let title = trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                return title.isEmpty ? nil : title
            }
            if !trimmed.isEmpty { return nil }   // текст пошёл раньше заголовка
        }
        return nil
    }

    private func name(of path: String) -> String {
        let file = path.split(separator: "/").last.map(String.init) ?? path
        guard let dot = file.lastIndex(of: ".") else { return file }
        return String(file[file.startIndex..<dot])
    }
}
