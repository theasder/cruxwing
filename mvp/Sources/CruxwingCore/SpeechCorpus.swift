import Foundation

/// Описание корпуса русской речи: что записано, откуда взято и с чьего
/// согласия.
///
/// Зачем формат вообще. Дорожная карта (§6.3) называет главным риском качество
/// распознавания НАШЕЙ речи, и трудность там не в измерении, а в сборе: запись
/// звонка содержит чужие голоса и чужие слова. Пока не сказано, чем считать
/// правильный корпус, каждый собирает свой — и сравнить замеры нельзя.
///
/// Три поля обязательны, и все три про честность, а не про формат:
///
///   * `genre` — доклад или звонок. Смешивать их в одном числе нельзя:
///     переключение языков (план, §6.2) в докладе слабее, и «точность 92%»,
///     посчитанная по докладам, обещает то, чего на звонке не будет;
///   * `consent` — на каком основании запись у нас. У публичного доклада это
///     открытый источник, у звонка — согласие участников. Запись без ответа на этот
///     вопрос в корпус не принимается;
///   * `source` — откуда именно. Без него замер невоспроизводим: цифру нельзя
///     перепроверить, а значит нельзя и оспорить.
public struct SpeechCorpus: Decodable, Equatable, Sendable {

    public enum Genre: String, Decodable, Sendable {
        /// Публичный доклад, митап, запись конференции.
        case talk
        /// Рабочий звонок — то, ради чего всё и делается.
        case call
    }

    public enum Consent: String, Decodable, Sendable {
        /// Запись опубликована самим автором для всех.
        case publicSource = "public"
        /// Участники дали согласие явно.
        case participants
    }

    public struct Item: Decodable, Equatable, Sendable {
        public let id: String
        public let genre: Genre
        public let consent: Consent
        public let source: String
        /// Расшифровка, размеченная человеком. Есть не у всех: без неё WER
        /// не посчитать, и замер честно ограничивается расхождением движков.
        public let reference: String?
        /// Расшифровки движков: имя движка — имя файла.
        public let engines: [String: String]
        public let seconds: Int?
    }

    public let items: [Item]

    public enum CorpusError: Error, Equatable, CustomStringConvertible {
        case unreadable(String)
        case missingFile(item: String, path: String)
        case emptySource(String)
        case noEngines(String)
        case duplicateID(String)

        public var description: String {
            switch self {
            case .unreadable(let path):
                return "The corpus description at «\(path)» could not be parsed. A record requires: id, genre (talk or call), consent (public or participants), source, engines."
            case .missingFile(let item, let path):
                return "Record «\(item)» names a file «\(path)» that does not exist. A measurement over a missing file quietly becomes a measurement over the rest."
            case .emptySource(let item):
                return "Record «\(item)» has an empty source. Without it the measurement is not reproducible: the figure cannot be re-checked, and so cannot be disputed."
            case .noEngines(let item):
                return "Record «\(item)» has no engine transcript at all — there is nothing to measure."
            case .duplicateID(let id):
                return "Record «\(id)» is described twice. The same speech counted twice shifts the average and looks like a larger corpus."
            }
        }
    }

    /// Читает описание и проверяет, что всё названное существует.
    ///
    /// Проверка файлов здесь, а не в разборе: описание может быть верным по
    /// форме и врать по существу — и тогда замер молча посчитает по тем
    /// записям, которые нашлись.
    public static func load(directory: String) throws -> SpeechCorpus {
        let path = directory.hasSuffix("/") ? directory + "corpus.json" : directory + "/corpus.json"
        guard let data = FileManager.default.contents(atPath: path) else {
            throw CorpusError.unreadable(path)
        }
        guard let corpus = try? JSONDecoder().decode(SpeechCorpus.self, from: data) else {
            throw CorpusError.unreadable(path)
        }
        var seen = Set<String>()
        for item in corpus.items {
            guard seen.insert(item.id).inserted else { throw CorpusError.duplicateID(item.id) }
            guard !item.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CorpusError.emptySource(item.id)
            }
            guard !item.engines.isEmpty else { throw CorpusError.noEngines(item.id) }
            for file in item.engines.values + [item.reference].compactMap({ $0 }) {
                let full = directory.hasSuffix("/") ? directory + file : directory + "/" + file
                guard FileManager.default.fileExists(atPath: full) else {
                    throw CorpusError.missingFile(item: item.id, path: file)
                }
            }
        }
        return corpus
    }

    /// Сколько записей каждого жанра. Отчёт без этой разбивки вводит в
    /// заблуждение: доклады читаются ровнее звонков.
    public var countsByGenre: [Genre: Int] {
        items.reduce(into: [:]) { result, item in result[item.genre, default: 0] += 1 }
    }

    /// Записи с человеческой расшифровкой — только по ним можно считать WER.
    public var withReference: [Item] { items.filter { $0.reference != nil } }
}
