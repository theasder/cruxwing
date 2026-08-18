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

    /// Дедлайн один на все манифесты и из данных не задаётся: сервис, который
    /// «просит подождать подольше», — ровно тот случай, ради которого дедлайн
    /// и заведён.
    public static let deadline: TimeInterval = 8

    let manifest: ConnectorManifest
    let token: String
    let host: String
    let http: HTTP

    public init(manifest: ConnectorManifest, token: String, host: String, http: @escaping HTTP) {
        self.manifest = manifest
        self.token = token
        self.host = host
        self.http = http
    }

    public var isConfigured: Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Готовый запрос — отдельно от отправки, чтобы его можно было сверить в
    /// тесте, не поднимая сети.
    public func makeRequest(query: String, limit: Int) throws -> URLRequest {
        guard isConfigured else { throw ConnectorError.notConfigured }
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var components = URLComponents(string: trimmedHost + manifest.request.path)
        // Пустой список — это `nil`, а не `[]`: с пустым массивом URLComponents
        // дописывает голый «?» в конец адреса. У сервисов вроде Outline
        // параметров нет вовсе, и такой хвост уходил бы в каждый запрос.
        let items = manifest.request.query.map {
            URLQueryItem(name: $0.name, value: fill($0.value, query: query, limit: limit))
        }
        components?.queryItems = items.isEmpty ? nil : items
        guard let url = components?.url else { throw ConnectorError.notConfigured }

        var request = URLRequest(url: url)
        request.httpMethod = manifest.request.method
        for header in manifest.request.headers {
            request.setValue(fill(header.value, query: query, limit: limit),
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
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isConfigured else { throw ConnectorError.notConfigured }
        guard !trimmed.isEmpty else { return [] }

        let (data, response) = try await http(makeRequest(query: trimmed, limit: limit))
        if response.statusCode == 401 { throw ConnectorError.unauthorised }
        if response.statusCode == 403 { throw ConnectorError.forbidden }
        guard (200..<300).contains(response.statusCode) else {
            throw ConnectorError.http(response.statusCode)
        }
        return try parse(data)
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
        // Незнакомая форма — отказ. Пустой список проходит только тогда, когда
        // форма узнана и строк действительно ноль.
        guard let rows else { throw ConnectorError.unreadable }

        return rows.compactMap { row in
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
                        state: (row[manifest.response.state] as? String) ?? "",
                        service: manifest.id)
        }
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

    private func fill(_ template: String, query: String, limit: Int) -> String {
        template
            .replacingOccurrences(of: "{query}", with: query)
            .replacingOccurrences(of: "{limit}", with: String(limit))
            .replacingOccurrences(of: "{token}", with: token)
    }
}
