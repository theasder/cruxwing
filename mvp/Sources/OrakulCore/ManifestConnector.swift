import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Исполнитель манифеста: один код на все сервисы, описанные данными.
///
/// Правила взяты не из головы, а из пяти уже написанных коннекторов (план,
/// §2.2) — и это важнее самого движка. Новый сервис получает их даром:
///
///   * **дедлайн 8 секунд** — один зависший сервис стоит одного источника, а
///     не всего ответа;
///   * **ошибки различимы**: `notConfigured` чинится в настройках,
///     `unauthorised` — новым токеном, `http(код)` — ожиданием, `unreadable`
///     означает, что сервис сменил формат;
///   * **успех не значит согласие**: код 2xx с телом незнакомой формы — отказ,
///     а не пустая выдача. Иначе отозванный токен выглядит как «задач нет», и
///     человек заводит вторую задачу поверх существующей;
///   * **мягко читаем**: строка без заголовка пропускается, а не роняет всю
///     выдачу.
///
/// HTTP приходит снаружи по той же причине, что у остальных: тест, который
/// ходит в чужой сервис, проверяет чужой сервис.
public struct ManifestConnector {

    public typealias HTTP = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    public enum ConnectorError: Error, Equatable {
        case notConfigured
        case unauthorised
        /// 403 — токен настоящий, но права на поиск ему не выдали.
        ///
        /// Отдельно от `unauthorised` намеренно: чинится это по-разному. «Токен
        /// не принят» отправляет человека выпускать новый, «нет права» — в
        /// настройки приложения в самом сервисе. Свести их в одно значило бы
        /// советовать заведомо бесполезное действие. Разницу поймал набор
        /// Пачки, когда движок ответил на 403 «неподходящий токен».
        case forbidden
        case http(Int)
        /// Сервис ответил отказом СВОИМИ словами — они и передаются дальше.
        case vendor(code: String, description: String)
        case unreadable
    }

    public struct Item: Equatable, Sendable {
        public let key: String
        public let title: String
        /// Слова вокруг совпадения. Пусто у трекеров: они отдают задачу, а не
        /// кусок текста. У вики это самое ценное — в подсказку идёт именно оно.
        public let context: String
        /// Кто это сказал. Пусто у трекеров.
        public let author: String
        public let state: String
        public let service: String
    }

    /// Насколько выдача покрывает то, о чём спросили.
    ///
    /// Существует потому, что «ничего не нашлось» — три разных ответа, и
    /// разница видна только отсюда:
    ///
    ///   * `.searched` — искал сам сервис. Ничего нет значит ничего нет.
    ///   * `.wholeList` — список кончился раньше границы, мы прочли его весь.
    ///     Ответ такой же надёжный, как первый, и это надо говорить: у команды
    ///     из десяти человек в трекере триста задач, а не сорок тысяч.
    ///   * `.latest` — граница сработала. «Не нашлось среди последних 500 из
    ///     40 000» — другой ответ, и выдать его за первый значит соврать.
    public enum Coverage: Equatable, Sendable {
        case searched
        case wholeList(scanned: Int)
        case latest(scanned: Int, total: Int?)

        /// Словами, как это увидит человек. Пусто там, где сказать нечего:
        /// приписка к обычному поиску была бы шумом в каждой подсказке.
        public var note: String {
            switch self {
            case .searched:
                return ""
            case .wholeList(let scanned):
                return "просмотрены все \(scanned) — сервис не ищет по слову, отбирали у себя"
            case .latest(let scanned, let total):
                let whole = total.map { " из \($0)" } ?? ""
                return "просмотрены последние \(scanned)\(whole) — сервис не ищет по слову, отбирали у себя"
            }
        }
    }

    /// Выдача вместе с тем, чего она стоит.
    public struct Outcome: Equatable, Sendable {
        public let items: [Item]
        public let coverage: Coverage
    }

    /// Дедлайн один на все манифесты и из данных не задаётся: сервис, который
    /// «просит подождать подольше», — ровно тот случай, ради которого дедлайн
    /// и заведён.
    public static let deadline: TimeInterval = 8

    /// Потолок перечисления: страниц на один вопрос, не больше.
    ///
    /// Держит движок, а не манифест. Автор манифеста заинтересован поднять
    /// границу — «а вдруг найдётся», — и упирается в чужой сервис: шестьдесят
    /// запросов в минуту у Plane, и десять страниц это уже шестая часть
    /// минутной квоты человека на один вопрос.
    public static let scanPageLimit = 10

    let manifest: ConnectorManifest
    let token: String
    let host: String
    /// Значения полей из `manifest.parameters` — пространство, проект, репозиторий.
    let values: [String: String]
    let http: HTTP

    public init(manifest: ConnectorManifest,
                token: String,
                host: String,
                values: [String: String] = [:],
                http: @escaping HTTP) {
        self.manifest = manifest
        self.token = token
        self.host = host
        self.values = values
        self.http = http
    }

    public var isConfigured: Bool {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        // Незаполненное поле — не «настроено наполовину». Без него в адрес
        // уедет `{project}` буквой, и сервис ответит 404: человек прочтёт это
        // как «сломалось», хотя он просто не дозаполнил настройки.
        return (manifest.parameters ?? []).allSatisfy { field in
            !(values[field.name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Готовый запрос — отдельно от отправки, чтобы его можно было сверить в
    /// тесте, не поднимая сети.
    public func makeRequest(query: String, limit: Int, page: Int = 0) throws -> URLRequest {
        guard isConfigured else { throw ConnectorError.notConfigured }
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // Путь тоже с подстановками: у Plane номер проекта стоит внутри адреса,
        // а не в параметрах.
        var components = URLComponents(
            string: trimmedHost + fill(manifest.request.path, query: query, limit: limit, page: page))
        // Пустой список — это `nil`, а не `[]`: с пустым массивом URLComponents
        // дописывает голый «?» в конец адреса. У сервисов вроде Outline
        // параметров нет вовсе, и такой хвост уходил бы в каждый запрос.
        let items = (manifest.request.query + (manifest.scan?.page ?? [])).map {
            URLQueryItem(name: $0.name, value: fill($0.value, query: query, limit: limit, page: page))
        }
        components?.queryItems = items.isEmpty ? nil : items
        guard let url = components?.url else { throw ConnectorError.notConfigured }

        var request = URLRequest(url: url)
        request.httpMethod = manifest.request.method
        for header in manifest.request.headers {
            request.setValue(fill(header.value, query: query, limit: limit, page: page),
                             forHTTPHeaderField: header.name)
        }
        if let template = manifest.request.body {
            let filled = fill(template, query: escapedForJSON(query), limit: limit)
            request.httpBody = Data(filled.utf8)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }
        request.timeoutInterval = Self.deadline
        return request
    }

    /// Кавычка и обратный слэш в слове человека рвут шаблон тела.
    ///
    /// Экранируется только то, что попадает В JSON: сам шаблон пишет автор
    /// манифеста, и портить его нельзя. Без этого запрос с кавычкой уходил бы
    /// битым JSON, а сервис отвечал бы 400 — то есть «ничего не нашлось» на
    /// совершенно правильный вопрос.
    private func escapedForJSON(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "\"", with: "\\\"")
    }

    public func search(_ query: String, limit: Int = 10) async throws -> [Item] {
        try await run(query, limit: limit).items
    }

    /// Выдача вместе с охватом. `search` — то же самое без охвата, для тех, кто
    /// его всё равно не показывает.
    public func run(_ query: String, limit: Int = 10) async throws -> Outcome {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isConfigured else { throw ConnectorError.notConfigured }
        guard !trimmed.isEmpty else {
            return Outcome(items: [], coverage: manifest.scan == nil ? .searched : .wholeList(scanned: 0))
        }
        if let scan = manifest.scan { return try await walk(scan, query: trimmed, limit: limit) }
        return Outcome(items: try parse(try await fetch(query: trimmed, limit: limit)),
                       coverage: .searched)
    }

    /// Один запрос: отправить, разобрать коды, отдать байты.
    private func fetch(query: String, limit: Int, page: Int = 0) async throws -> Data {
        let (data, response) = try await http(makeRequest(query: query, limit: limit, page: page))
        if response.statusCode == 401 { throw ConnectorError.unauthorised }
        if response.statusCode == 403 { throw ConnectorError.forbidden }
        guard (200..<300).contains(response.statusCode) else {
            throw ConnectorError.http(response.statusCode)
        }
        return data
    }

    /// Перечисление с границей: страницы подряд, отбор у себя, честный охват.
    ///
    /// Порядок важен. Границу проверяем ПОСЛЕ страницы, а не до: иначе при
    /// `pages: 1` не читается ни одной. Признак «есть ещё» берём у сервиса, а
    /// когда он молчит — по длине страницы: короткая страница значит конец
    /// списка. Ошибиться тут можно только в одну сторону — сказать «прочли
    /// всё», прочитав часть, — поэтому сомнение трактуется как `.latest`.
    private func walk(_ scan: ConnectorManifest.Scan,
                      query: String,
                      limit: Int) async throws -> Outcome {
        let pages = min(scan.pages, Self.scanPageLimit)
        let needle = query.lowercased()
        var matched: [Item] = []
        var scanned = 0
        var total: Int?
        var exhausted = false

        for page in 0..<pages {
            let data = try await fetch(query: query, limit: limit, page: page)
            let rows = try rows(in: data)
            scanned += rows.count
            if total == nil, let path = scan.total {
                total = (try? JSONSerialization.jsonObject(with: data))
                    .flatMap { $0 as? [String: Any] }
                    .flatMap { Int(Self.scalar(at: path, in: $0)) }
            }
            matched += rows.filter { row in
                scan.match.contains { path in
                    Self.string(at: path, in: row).lowercased().contains(needle)
                }
            }.compactMap(item(from:))

            if let more = scan.more {
                let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
                var node: Any? = object
                for step in more { node = (node as? [String: Any])?[step] }
                if node as? Bool != true { exhausted = true; break }
            } else if rows.count < scan.perPage {
                exhausted = true
                break
            }
        }

        return Outcome(items: Array(matched.prefix(limit)),
                       coverage: exhausted ? .wholeList(scanned: scanned)
                                           : .latest(scanned: scanned, total: total))
    }

    /// Разбор ответа по манифесту.
    ///
    /// Отдельным методом, потому что это половина коннектора, и проверять её
    /// удобнее на байтах, чем через сеть.
    public func parse(_ data: Data) throws -> [Item] {
        let root = try? JSONSerialization.jsonObject(with: data)

        // Флаг успеха проверяется ДО разбора списка: у сервисов, отвечающих
        // отказом с кодом 200, порядок решает, станет ли отказ пустой выдачей.
        if let flag = manifest.response.requireTrue {
            var node: Any? = root
            for step in flag { node = (node as? [String: Any])?[step] }
            if node as? Bool != true {
                // Сначала слова сервиса, и только если их нет — наше «не понял».
                let object = (root as? [String: Any]) ?? [:]
                let code = manifest.response.errorCode.map { Self.scalar(at: $0, in: object) } ?? ""
                let message = manifest.response.errorMessage
                    .map { Self.scalar(at: $0, in: object) } ?? ""
                if !code.isEmpty || !message.isEmpty {
                    throw ConnectorError.vendor(code: code, description: message)
                }
                throw ConnectorError.unreadable
            }
        }

        return try rows(in: data).compactMap(item(from:))
    }

    /// Строки ответа по манифесту. Незнакомая форма — отказ, а не пустая выдача.
    func rows(in data: Data) throws -> [[String: Any]] {
        let root = try? JSONSerialization.jsonObject(with: data)
        let rows: [[String: Any]]?
        if manifest.response.list.isEmpty {
            rows = root as? [[String: Any]]
        } else {
            var node: Any? = root
            for step in manifest.response.list {
                node = (node as? [String: Any])?[step]
            }
            rows = node as? [[String: Any]]
        }
        guard let rows else { throw ConnectorError.unreadable }
        return rows
    }

    /// Строка ответа в выдачу. `nil` — строке нечего сказать человеку.
    func item(from row: [String: Any]) -> Item? {
        let title = Self.string(at: manifest.response.title, in: row)
        let context = manifest.response.context.map { Self.string(at: $0, in: row) } ?? ""
        // Строка, где нет ни заголовка, ни слов вокруг совпадения, не
        // сообщает человеку ничего. Пропускаем её, а не выдачу целиком.
        guard !title.isEmpty || !context.isEmpty else { return nil }
        let number = manifest.response.key.lazy.compactMap { row[$0] as? Int }.first
        let author = manifest.response.author.map { Self.scalar(at: $0, in: row) } ?? ""
        return Item(key: number.map { "#\($0)" } ?? "—",
                    title: title,
                    context: context,
                    author: author,
                    state: Self.scalar(at: manifest.response.state, in: row),
                    service: manifest.id)
    }

    /// Значение по пути, число или строка.
    ///
    /// Идентификаторы приходят и так и так: Пачка отдаёт `user_id` целым,
    /// Mattermost — строкой. Требовать в манифесте тип поля значило бы
    /// описывать формат JSON вместо сервиса.
    static func scalar(at path: [String], in row: [String: Any]) -> String {
        var node: Any? = row
        for step in path { node = (node as? [String: Any])?[step] }
        if let text = node as? String { return text }
        if let number = node as? Int { return String(number) }
        return ""
    }

    /// Значение по пути: `["document","title"]` — на уровень глубже строки.
    static func string(at path: [String], in row: [String: Any]) -> String {
        var node: Any? = row
        for step in path { node = (node as? [String: Any])?[step] }
        return (node as? String) ?? ""
    }

    private func fill(_ template: String, query: String, limit: Int, page: Int = 0) -> String {
        var filled = template
            .replacingOccurrences(of: "{query}", with: query)
            .replacingOccurrences(of: "{limit}", with: String(limit))
            .replacingOccurrences(of: "{token}", with: token)
            .replacingOccurrences(of: "{page}", with: String(page))
            .replacingOccurrences(of: "{perPage}", with: String(manifest.scan?.perPage ?? limit))
        for (name, value) in values {
            filled = filled.replacingOccurrences(of: "{\(name)}", with: value)
        }
        return filled
    }
}
