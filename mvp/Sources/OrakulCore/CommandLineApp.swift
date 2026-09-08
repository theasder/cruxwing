import Foundation

/// Командная строка orakul: то, что можно запустить уже сегодня.
///
/// Захвата звука ещё нет, но всё, что происходит с созвоном ПОСЛЕ расшифровки,
/// работает — и это можно попробовать на своих текстах, не дожидаясь
/// приложения. Для проекта, который меряется звёздами, разница между
/// «библиотека с тестами» и «команда, которую можно выполнить» решающая.
///
/// Разбор аргументов и текст вывода живут здесь, а не в `main.swift`: иначе их
/// нельзя проверить тестом, и первым, что сломается у человека, окажется
/// сообщение об ошибке.
public struct CommandLineApp {

    public struct Result: Equatable, Sendable {
        public let output: String
        /// Ненулевой код — «команда не сделала того, что просили».
        public let exitCode: Int32

        public init(output: String, exitCode: Int32) {
            self.output = output
            self.exitCode = exitCode
        }
    }

    let store: SessionStore
    let today: @Sendable () -> String
    let makeIdentifier: @Sendable () -> String
    let readFile: @Sendable (String) -> String?
    let readAudio: @Sendable (String) -> Data?
    /// Чем расшифровывать. Пусто — команда расшифровки объяснит, как настроить.
    let engineCommand: String?

    public init(store: SessionStore,
                today: @escaping @Sendable () -> String = MeetingPipeline.currentDay,
                makeIdentifier: @escaping @Sendable () -> String = { UUID().uuidString },
                readFile: @escaping @Sendable (String) -> String? = {
                    // Не строго UTF-8: русский транскрипт часто приходит в
                    // CP1251 или UTF-16, и отказ читать его выглядел как
                    // «файла нет». Разбор — в TranscriptFile.
                    TranscriptFile.read($0)
                },
                readAudio: @escaping @Sendable (String) -> Data? = {
                    try? Data(contentsOf: URL(fileURLWithPath: $0))
                },
                engineCommand: String? = ProcessInfo.processInfo.environment["ORAKUL_ENGINE"],
                transcriberFactory: (@Sendable (String) -> any Transcriber)? = nil) {
        self.store = store
        self.today = today
        self.makeIdentifier = makeIdentifier
        self.readFile = readFile
        self.readAudio = readAudio
        self.engineCommand = engineCommand
        self.makeTranscriber = transcriberFactory ?? { ExternalTranscriber(command: $0) }
    }

    let makeTranscriber: @Sendable (String) -> any Transcriber

    public static let usage = """
    orakul — search your own calls: Russian speech, no network

      orakul add <file> [title]           put an existing transcript in the archive
      orakul record [seconds] [title]     record from the microphone and transcribe
      orakul transcribe <wav> [title]     transcribe a recording into the archive
      orakul search <question>            what was decided about it
      orakul list                         what the archive holds
      orakul delete <id>                  remove one call
      orakul ask <service> <question>     ask a connected service
      orakul corpus <folder>              check a speech corpus before measuring

    The archive is plain JSON files: they can be read without us.
    Services: \(ConnectorQuery.services.joined(separator: ", ")).
    The token goes in ORAKUL_TOKEN. ORAKUL_HOST is the second thing a service asks
    for: the address of your own server, a Yandex Tracker organisation, a Kaiten
    team address. ORAKUL_SCOPE is where to look: a team in the messenger, the
    repositories for GitHub.
    Transcription runs on your engine: ORAKUL_ENGINE="whisper-cli -l ru -otxt -f {file}"
    """

    /// Имена команд так, как их набирает человек.
    ///
    /// Список нужен подсказке про опечатку, и в нём есть команды, которых нет
    /// в разборе ниже: `записать` и `спросить` выполняются в main.swift и до
    /// `run` не доходят. Человеку всё равно, где внутри нас разложены ветки, —
    /// подсказать «записать» на «записат» обязаны и мы.
    ///
    /// Список и справка разъезжаются молча, поэтому их сверяет проверка:
    /// каждое имя отсюда есть в справке, и каждая команда из справки есть
    /// здесь.
    public static let commandNames = [
        "add", "record", "transcribe", "search", "list", "delete",
        "ask", "corpus",
    ]

    /// The Russian names the command line still accepts.
    ///
    /// They are not printed in the help text — it names the English ones — but a
    /// typo in them has to be recognised all the same: someone who has typed
    /// `найти` for a year does not care which of the two names we consider
    /// canonical, and "unknown command" with no suggestion is the worst answer
    /// we could give them.
    public static let legacyCommandNames = [
        "добавить", "записать", "расшифровать", "найти", "список", "удалить",
        "спросить", "корпус",
    ]

    /// Выполнить команду. Аргументы — без имени программы.
    public func run(_ arguments: [String]) -> Result {
        guard let command = arguments.first else {
            // Запуск без аргументов — не ошибка, а вопрос «что ты умеешь».
            return Result(output: Self.usage, exitCode: 0)
        }
        let rest = Array(arguments.dropFirst())

        switch command {
        case "добавить", "add":
            return add(rest)
        case "расшифровать", "transcribe":
            return transcribe(rest)
        case "найти", "search":
            return search(rest)
        case "список", "list":
            return list()
        case "удалить", "delete":
            return delete(rest)
        case "помощь", "help", "--help", "-h":
            return Result(output: Self.usage, exitCode: 0)
        default:
            // Промах мимо одной клавиши — и в ответ полотно справки. Формально
            // верно и бесполезно: расстояние в одну опечатку уже посчитано для
            // поиска, тем же и лечится.
            let similar = (Self.commandNames + Self.legacyCommandNames)
                .first { RecallIndex.isOneEditApart(command, $0) }
            let hint = similar.map { "\nDid you mean «\($0)»?" } ?? ""
            return Result(output: "Unknown command «\(command)».\(hint)\n\n\(Self.usage)",
                          exitCode: 2)
        }
    }

    /// Почему файл не прочитался — разными словами для разных причин.
    ///
    /// «Не смог прочитать файл: /tmp» на каталоге — сообщение о следствии.
    /// Причин три, и чинятся они по-разному: каталог вместо файла (укажите
    /// файл внутри), файла нет вовсе (проверьте путь), файл есть, но не
    /// открылся (права или двоичное содержимое). Тот же разбор, что у отказов
    /// коннектора: одно сообщение на три причины отправляет чинить не то.
    static func whyUnreadable(_ path: String) -> String {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        if exists && isDirectory.boolValue {
            return "That is a directory, not a file: \(path)\n"
                + "Name a transcript file inside it."
        }
        if !exists {
            return "No such file: \(path)\nCheck the path."
        }
        return "Could not read the file: \(path)\n"
            + "It exists but did not open: check the permissions, "
            + "and if it is a call recording, transcribe it: orakul transcribe <wav>"
    }

    // MARK: - Команды

    private func add(_ arguments: [String]) -> Result {
        guard let path = arguments.first else {
            return Result(output: "A transcript file is required: orakul add <file>", exitCode: 2)
        }
        guard let raw = readFile(path) else {
            return Result(output: Self.whyUnreadable(path), exitCode: 1)
        }

        let text = RussianLexicon.restore(TranscriptCleanup.strip(raw))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            // Две разные причины пустоты, и человек по ним делает разное.
            //
            // Пустой файл — пустой файл. А вот экспорт субтитров без реплик
            // (шестьдесят девять байт разметки и ни одного слова) после чистки
            // тоже становится пустым — и фраза «Файл пустой» отправляла
            // человека спорить с собственным файлом: он его открывает, видит
            // содержимое и не понимает, кому верить. Пустым файл стал у нас.
            let fileWasEmpty = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return Result(output: fileWasEmpty
                ? "The file is empty, so there is nothing to save."
                : """
                  В файле нет реплик — только разметка и отметки времени.
                  Сохранять нечего: выгрузите расшифровку с текстом.
                  """,
                exitCode: 1)
        }

        // Такая расшифровка уже может лежать в архиве.
        //
        // Повторить `добавить` на том же файле — дело одной стрелки вверх, а
        // ещё так делают скрипты при повторном импорте. Дубли не безобидны:
        // ответ показывает не больше трёх встреч (`RecallAnswer`), поэтому три
        // копии одного звонка занимают ВСЕ три места, и человек с полусотней
        // разных звонков видит один и тот же трижды.
        //
        // Сравнивается текст ПОСЛЕ той же обработки, что у новой записи, —
        // иначе одна и та же расшифровка, прочитанная в другой кодировке или с
        // другими переводами строк, не совпала бы сама с собой. Название не
        // сравнивается: планёрки называют одинаково каждую неделю.
        if let existing = store.load().sessions.first(where: { $0.digest == text }) {
            return Result(output: """
            Такая расшифровка уже есть: «\(existing.title)» (\(existing.id))
            Ничего не добавил. Посмотреть архив: orakul список
            """, exitCode: 0)   // в архиве лежит то, чего хотели, — это не сбой
        }

        let title = Self.tidyTitle(arguments.dropFirst().joined(separator: " "))
        let session = RecallIndex.Session(
            id: makeIdentifier(),
            // Без названия берём имя файла: «Созвон» во всём списке не поможет
            // никому, а имя файла человек когда-то выбрал сам.
            title: title.isEmpty
                ? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                : title,
            date: today(),
            digest: text)

        do {
            try store.save(session)
        } catch {
            return Result(output: "Could not save. \(Self.explain(error))", exitCode: 1)
        }
        return Result(output: "Added: «\(session.title)» (\(session.id))", exitCode: 0)
    }

    /// Отказ файловой системы — по-русски и с действием.
    ///
    /// Было `"Could not save: \(error)"`, и человек получал
    /// `Error Domain=NSCocoaErrorDomain Code=513 "You don\u{2019}t have permission
    /// to save the file..."` — внутренности по-английски ровно там, где нужна
    /// помощь. Ту же ошибку продукт уже исправлял в коннекторах; в командной
    /// строке она осталась.
    static func explain(_ error: Error) -> String {
        let code = (error as NSError).code
        let domain = (error as NSError).domain
        guard domain == NSCocoaErrorDomain else {
            return "The system replied: \(error.localizedDescription)"
        }
        switch code {
        case 513, 257:
            return "No permission to write to the archive. Check the directory permissions "
                + "or name another one in ORAKUL_HOME."
        case 640:
            return "The disk is full."
        case 4, 260:
            return "Archive not found. Check ORAKUL_HOME."
        case 642:
            return "The archive directory is read-only."
        default:
            return "The system replied: \(error.localizedDescription)"
        }
    }

    /// Название встречи в том виде, в каком его можно печатать строкой.
    ///
    /// `orakul список` — построчный вывод: дата, идентификатор, название. Оно
    /// приходит от человека как есть, и в нём попадается лишнее:
    ///
    /// - **Перевод строки** разрывает запись надвое, и вторая половина
    ///   выглядит как ещё одна встреча — без даты и идентификатора, но
    ///   отличить её нельзя ни глазом, ни скриптом. Архив у нас открытый, и
    ///   список зовут разбирать.
    /// - **Триста символов** (скрипт взял первую строку расшифровки) — и
    ///   столбцы перестают быть столбцами.
    ///
    /// Пробелы схлопываются, длина ограничивается, обрезка ПОКАЗЫВАЕТСЯ
    /// многоточием: молча потерянный кусок названия — это потерянный кусок
    /// названия.
    static let titleLimit = 120

    static func tidyTitle(_ raw: String) -> String {
        let flattened = raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        guard flattened.count > titleLimit else { return flattened }
        return String(flattened.prefix(titleLimit - 1)) + "…"
    }

    private func transcribe(_ arguments: [String]) -> Result {
        guard let path = arguments.first else {
            return Result(output: "A recording file is required: orakul transcribe <wav>", exitCode: 2)
        }
        // Файл проверяется раньше движка: имя файла — это то, что человек
        // только что напечатал, а движок — настройка. При опечатке в имени и
        // ненастроенном движке продукт рассказывал про движок, человек его
        // настраивал и лишь потом узнавал, что файла нет. Два захода вместо
        // одного, и первый — не про его ошибку.
        guard let data = readAudio(path) else {
            return Result(output: "Could not read the recording: \(path)", exitCode: 1)
        }
        guard let command = engineCommand, !command.isEmpty else {
            // Молча ничего не делать здесь нельзя: человек ждёт расшифровку и
            // должен узнать, чего именно не хватает.
            return Result(output: """
            Не настроен движок распознавания. orakul не возит свою модель — он \
            запускает вашу:

              export ORAKUL_ENGINE="whisper-cli -m model.bin -l ru -otxt -f {file}"
            """, exitCode: 2)
        }

        let samples: [Float]
        do {
            samples = try WAVFile.decode(data)
        } catch WAVFile.DecodeError.unsupportedSampleRate(let rate) {
            // Пересчитывать частоту молча — значит тихо ухудшить распознавание.
            return Result(output: """
            Запись на \(rate) Гц, а движку нужно 16000. Переведите её заранее:

              ffmpeg -i \(path) -ar 16000 -ac 1 запись-16k.wav
            """, exitCode: 1)
        } catch {
            return Result(output: "Unrecognised recording format: WAV, PCM 16-bit required.", exitCode: 1)
        }

        let title = arguments.dropFirst().joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pipeline = MeetingPipeline(transcriber: makeTranscriber(command), store: store,
                                       today: today, makeIdentifier: makeIdentifier)

        // Расшифровка асинхронная, командная строка — нет. Ждём здесь, иначе
        // программа завершится раньше движка.
        let outcome = Semaphore<Result>()
        Task {
            do {
                let session = try await pipeline.record(
                    samples: samples,
                    title: title.isEmpty
                        ? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                        : title)
                outcome.set(Result(output: "Transcribed: «\(session.title)» (\(session.id))",
                                   exitCode: 0))
            } catch {
                outcome.set(Result(output: "Could not transcribe: \(error)", exitCode: 1))
            }
        }
        return outcome.wait()
    }

    private func search(_ arguments: [String]) -> Result {
        let query = arguments.joined(separator: " ")
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return Result(output: "A question is required: orakul search what did we decide about pricing", exitCode: 2)
        }
        // Ответ собирает RecallAnswer — тот же текст, что увидит пользователь
        // приложения. Двух разных «форматов ответа» у продукта быть не должно,
        // поэтому и разницу «архив пуст» против «не говорили» проводит он же,
        // а не эта команда: у приложения на первом запуске ровно тот же случай.
        // Архив читается ОДИН раз: и чтобы отличить пустой от непустого, и
        // чтобы узнать, что не открылось. Дважды — это дважды обойти папку.
        let archive = store.load()
        let index = store.index()
        let hits = index.search(query)
        // Похожие слова ищутся, только когда не нашлось ничего: обход словаря
        // на пути, где ответ уже есть, — работа впустую.
        let answer = RecallAnswer.compose(query: query,
                                          hits: hits,
                                          archiveIsEmpty: archive.sessions.isEmpty,
                                          unreadable: archive.skipped,
                                          suggestions: hits.isEmpty
                                              ? index.nearMisses(for: query) : [])
        // Ничего не нашлось — это результат, а не сбой: код возврата нулевой.
        return Result(output: answer, exitCode: 0)
    }

    private func list() -> Result {
        let archive = store.load()
        guard !archive.sessions.isEmpty else {
            return Result(output: "The archive is empty. Add a transcript: orakul add <file>",
                          exitCode: 0)
        }
        // Порядок — свежие сверху. Раньше список шёл в порядке имён файлов, то
        // есть по случайному идентификатору: сорок звонков одного дня выпадали
        // вперемешку, и найти вчерашний было нечем, кроме глаз. Внутри одного
        // дня — по названию: времени в записи нет, а стабильный порядок лучше
        // случайного.
        let ordered = archive.sessions.sorted {
            $0.date == $1.date ? $0.title.localizedCompare($1.title) == .orderedAscending
                               : $0.date > $1.date
        }
        var lines = ordered.map { "\($0.date)  \($0.id)  \($0.title)" }
        if !archive.skipped.isEmpty {
            // Пропущенные файлы обязаны быть видны: молчание здесь означает
            // тихо потерянную встречу.
            lines.append("")
            lines.append("Could not read: \(archive.skipped.joined(separator: ", "))")
        }
        return Result(output: lines.joined(separator: "\n"), exitCode: 0)
    }

    private func delete(_ arguments: [String]) -> Result {
        guard let id = arguments.first else {
            return Result(output: "An id is required: orakul delete <id>",
                          exitCode: 2)
        }
        // Человек копирует идентификатор из `список`, где он в тридцать шесть
        // знаков. Разрешаем начало — как git с хешами коммитов.
        //
        // Осторожно именно здесь: удаление не отменить. Поэтому начало короче
        // четырёх знаков не принимается вовсе, а если под него подходит больше
        // одного звонка, ничего не удаляется — вместо угадывания показывается
        // список подходящих.
        let resolved: String
        switch resolveIdentifier(id) {
        case .exact(let full):
            resolved = full
        case .tooShort:
            return Result(output: """
            Слишком короткое начало идентификатора: \(id)
            Нужно хотя бы четыре знака — удаление не отменить.
            """, exitCode: 2)
        case .ambiguous(let matches):
            return Result(output: """
            Под «\(id)» подходит несколько звонков — уточните:
            \(matches.joined(separator: "\n"))
            """, exitCode: 2)
        case .none:
            return Result(output: """
            Такого звонка нет: \(id)
            Посмотреть, что есть: orakul список
            """, exitCode: 1)
        }

        do {
            guard try store.delete(id: resolved) else {
                return Result(output: """
                Такого звонка нет: \(id)
                Посмотреть, что есть: orakul список
                """, exitCode: 1)
            }
        } catch {
            return Result(output: "Could not delete. \(Self.explain(error))", exitCode: 1)
        }
        return Result(output: "Deleted: \(resolved)", exitCode: 0)
    }

    /// Во что превращается начало идентификатора.
    enum IdentifierMatch: Equatable {
        case exact(String)
        case ambiguous([String])
        case tooShort
        case none
    }

    /// Полное совпадение важнее начала: если человек вставил идентификатор
    /// целиком, он не должен зависеть от того, чьим началом тот оказался.
    ///
    /// Пока идентификаторы — UUID одной длины, эта ветка недостижима: полный
    /// идентификатор не может быть началом другого. Проверкой её не закрыть,
    /// и придумывать для неё случай я не стал — она стоит здесь на случай
    /// идентификаторов разной длины, где полный вдруг окажется чьим-то
    /// началом. Мутация это подтверждает: снятие ветки ничего не ломает.
    func resolveIdentifier(_ input: String) -> IdentifierMatch {
        let needle = input.trimmingCharacters(in: .whitespaces).uppercased()
        guard !needle.isEmpty else { return .none }

        let ids = store.load().sessions.map(\.id)
        if let exact = ids.first(where: { $0.uppercased() == needle }) { return .exact(exact) }
        guard needle.count >= 4 else { return .tooShort }

        let matches = ids.filter { $0.uppercased().hasPrefix(needle) }
        switch matches.count {
        case 0:  return .none
        case 1:  return .exact(matches[0])
        default: return .ambiguous(matches.sorted())
        }
    }
}

/// Мостик из асинхронного мира в синхронную командную строку.
private final class Semaphore<Value>: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private var value: Value?

    func set(_ newValue: Value) {
        value = newValue
        semaphore.signal()
    }

    func wait() -> Value {
        semaphore.wait()
        return value!
    }
}
