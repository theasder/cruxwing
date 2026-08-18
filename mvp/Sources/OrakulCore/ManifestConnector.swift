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
        /// Сервис просит подождать: 429. Отдельно от `http` намеренно.
        ///
        /// «Ошибка 429» отправляет человека перевыпускать токен — он видит
        /// слово «ошибка» и делает единственное, что умеет. А чинить тут
        /// нечего: надо подождать, и сервис обычно говорит сколько.
        /// Недружелюбному сервису дешевле придушить, чем заблокировать, так что
        /// это норма работы, а не сбой.
        case rateLimited(retryAfter: Int?)
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

    /// Охват выдачи — общий тип для всех источников (`SearchCoverage`).
    /// Псевдоним оставлен потому, что для читателя коннектора охват — часть
    /// коннектора, а переезд типа в отдельный файл этого не меняет.
    public typealias Coverage = SearchCoverage

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
        if response.statusCode == 429 {
            let header = response.value(forHTTPHeaderField: "Retry-After")
                ?? response.value(forHTTPHeaderField: "retry-after")
            throw ConnectorError.rateLimited(retryAfter: header.flatMap { Int($0) })
        }
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
                let node = Self.follow(more, from: object)
                // Признак объявлен, но его в ответе НЕТ — это смена формата, и
                // «конец списка» отсюда не следует. Второй приём вендора:
                // убрать поле, по которому мы понимаем, что дальше есть ещё.
                // Откат на «страница короче размера» дал бы на полной странице
                // «просмотрены все» — то есть часть, выданную за целое, ровно
                // там, где §7.2 это запрещает.
                //
                // Отказом это не делается намеренно: выдача годная, неизвестна
                // только её полнота. Поэтому охват остаётся `.latest`, и
                // человек читает «просмотрены последние N», а не «все».
                guard node != nil else { break }
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

        let rows = try rows(in: data)
        let items = rows.compactMap(item(from:))
        // Строки пришли, а прочитать не удалось НИ ОДНУ — это смена формата, а
        // не пустая выдача.
        //
        // Приём недружелюбного вендора, против которого это написано:
        // переименовать поле. Отказа нет, форма ответа узнаётся, строки на
        // месте — и orakul бодро отвечает «ничего не нашлось» до конца времён.
        // Человек делает вывод про свои данные, а не про наш коннектор.
        //
        // Мягкое чтение при этом остаётся: одна пустая строка среди годных
        // по-прежнему пропускается. Разница ровно в слове «ни одной».
        if items.isEmpty && !rows.isEmpty { throw ConnectorError.unreadable }
        return items
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
        if rows == nil, let path = manifest.response.errorMessage,
           let object = root as? [String: Any] {
            // Списка нет, зато есть слова сервиса о том, почему. У GraphQL это
            // единственный способ узнать причину: код ответа всегда 200.
            let message = Self.scalar(at: path, in: object)
            if !message.isEmpty {
                let code = manifest.response.errorCode.map { Self.scalar(at: $0, in: object) } ?? ""
                throw ConnectorError.vendor(code: code, description: message)
            }
        }
        if rows == nil, let marker = manifest.response.emptyMarker,
           let object = root as? [String: Any],
           !Self.scalar(at: marker, in: object).isEmpty {
            // Контейнера списка нет, но ответ узнан: сервис прислал своё поле
            // с размером выдачи. Это пустой список, а не непонятный ответ.
            return []
        }
        guard let rows else { throw ConnectorError.unreadable }
        return rows
    }

    /// Текст без разметки: `<strong>кот</strong>` — «кот».
    ///
    /// Разбор простой намеренно: снимается всё между угловыми скобками и
    /// раскрываются четыре сущности, которые ставит подсветка. Полноценный
    /// разбор HTML здесь не нужен — на входе кусок текста с подсветкой, а не
    /// страница, — и он же был бы новой зависимостью в ядре без зависимостей.
    static func withoutTags(_ text: String) -> String {
        var result = ""
        var insideTag = false
        for character in text {
            switch character {
            case "<": insideTag = true
            case ">": insideTag = false
            default: if !insideTag { result.append(character) }
            }
        }
        return result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    /// Строка ответа в выдачу. `nil` — строке нечего сказать человеку либо она
    /// отброшена по условию манифеста (`skipWhen`).
    func item(from row: [String: Any]) -> Item? {
        for condition in manifest.response.skipWhen ?? [] {
            if Self.follow(condition.path, from: row) as? Bool == condition.equals { return nil }
        }
        let clean = { (text: String) in
            manifest.response.stripTags == true ? Self.withoutTags(text) : text
        }
        let title = clean(Self.string(at: manifest.response.title, in: row))
        let context = manifest.response.context.map { clean(Self.string(at: $0, in: row)) } ?? ""
        // Строка, где нет ни заголовка, ни слов вокруг совпадения, не
        // сообщает человеку ничего. Пропускаем её, а не выдачу целиком.
        guard !title.isEmpty || !context.isEmpty else { return nil }
        // Номер или обозначение. Trello нумерует карточки числом (#42), Linear
        // называет задачу строкой (ENG-123). Решётка ставится только к числу:
        // «#ENG-123» человек в своём трекере не найдёт — там такого нет.
        let number = manifest.response.key.lazy.compactMap { row[$0] as? Int }.first
        let label = manifest.response.key.lazy.compactMap { row[$0] as? String }
            .first { !$0.isEmpty }
        let author = manifest.response.author.map { Self.scalar(at: $0, in: row) } ?? ""
        return Item(key: number.map { "#\($0)" } ?? label ?? "—",
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
        let node = follow(path, from: row)
        if let text = node as? String { return text }
        if let number = node as? Int { return String(number) }
        return ""
    }

    /// Шаг пути: ключ словаря или, если шаг — число, элемент массива.
    ///
    /// Массивы понадобились из-за GraphQL: Wiki.js отвечает кодом 200 и кладёт
    /// отказ в `errors[0].message`. Без индекса единственным доступным ответом
    /// было бы наше «непонятный ответ» — то есть ровно то, что правило §2.2
    /// плана запрещает: пересказ вместо слов сервиса.
    static func follow(_ path: [String], from root: Any?) -> Any? {
        var node = root
        for step in path {
            if let index = Int(step), let array = node as? [Any] {
                node = index >= 0 && index < array.count ? array[index] : nil
            } else {
                node = (node as? [String: Any])?[step]
            }
        }
        return node
    }

    /// Значение по пути: `["document","title"]` — на уровень глубже строки.
    static func string(at path: [String], in row: [String: Any]) -> String {
        follow(path, from: row) as? String ?? ""
    }

    private func fill(_ template: String, query: String, limit: Int, page: Int = 0) -> String {
        var filled = template
            .replacingOccurrences(of: "{query}", with: query)
            .replacingOccurrences(of: "{limit}", with: String(limit))
            .replacingOccurrences(of: "{token}", with: token)
            // `{basic}` — тот же токен, но в base64, для заголовка
            // «Authorization: Basic …». Нужен там, где сервер принимает только
            // Basic: у Nextcloud это пара «имя:пароль приложения», и человек
            // вписывает её одной строкой. Считать base64 в манифесте нельзя,
            // а требовать от человека закодировать пароль руками — значит
            // получать в поле то, что он закодировал неправильно.
            .replacingOccurrences(of: "{basic}", with: Data(token.utf8).base64EncodedString())
            .replacingOccurrences(of: "{page}", with: String(page))
            .replacingOccurrences(of: "{perPage}", with: String(manifest.scan?.perPage ?? limit))
        for (name, value) in values {
            filled = filled.replacingOccurrences(of: "{\(name)}", with: value)
        }
        return filled
    }
}
