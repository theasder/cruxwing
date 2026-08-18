import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Западные трекеры в облаке: Linear и Trello.
///
/// Отдельно от `SelfHostedTrackers` не по географии, а по устройству: у тех
/// адрес сервера спрашивают у человека, потому что сервер его собственный.
/// Здесь адрес один и тот же для всех, и спрашивать его — значит просить
/// человека ввести то, что мы и так знаем, а потом разбираться с опечаткой в
/// нём.
///
/// Написан сразу поверх манифестов: запасного пути, написанного руками, у него
/// нет и не будет. Пропавшее описание — поломка сборки, а не повод отвечать
/// человеку «сервис недоступен».
public struct WesternTrackers: Sendable {

    public typealias HTTP = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    public static let live: HTTP = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }

    public enum Service: String, CaseIterable, Sendable {
        case linear, trello

        public var title: String {
            switch self {
            case .linear: return "Linear"
            case .trello: return "Trello"
            }
        }

        /// Адрес известен заранее — сервис облачный.
        var host: String {
            switch self {
            case .linear: return "https://api.linear.app"
            case .trello: return "https://api.trello.com"
            }
        }

        public var credentialHint: String {
            switch self {
            case .linear:
                return "Личный ключ из «Settings → Security & access». Вставляется как есть: Linear ждёт его в заголовке без слова Bearer"
            case .trello:
                return "Два значения из trello.com/power-ups/admin: ключ приложения и токен. Токен — в поле ниже, ключ — в отдельном поле: секрет из них только токен"
            }
        }

        /// Поля, которые человек заполняет сам, — из манифеста, а не из кода.
        public var fields: [ConnectorManifest.Field] {
            (try? ConnectorManifest.bundled().first { $0.id == rawValue })?.parameters ?? []
        }
    }

    public enum ConnectorError: Error, Equatable, LocalizedError {
        case notConfigured
        case unauthorised
        case forbidden
        /// Сервис просит подождать: 429. Чинить нечего, надо переждать.
        case rateLimited(retryAfter: Int?)
        case http(Int)
        /// Сервис отказал своими словами — они и передаются дальше.
        case vendor(code: String, description: String)
        case unreadable
        /// Описание сервиса не нашлось в сборке.
        case manifestMissing

        public var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Трекер не подключён. Откройте «Настройки → Подключённые приложения» и вставьте ключ."
            case .unauthorised:
                return "Трекер не принял ключ. Обычно он истёк или отозван — создайте новый в самом сервисе."
            case .forbidden:
                return "Ключ принят, но прав на поиск у него нет. Права выдаются в самом сервисе, перевыпуск ключа тут не поможет."
            case .rateLimited(let retryAfter):
                let wait = retryAfter.map { " Подождите \($0) с." } ?? ""
                return "Сервис просит обращаться реже — слишком много запросов подряд.\(wait) Токен тут ни при чём: перевыпускать его не нужно."
            case .http(let status):
                return "Трекер ответил ошибкой \(status). Сервис на месте — если это 5xx, подождите и повторите."
            case .vendor(let code, let description):
                let prefix = code.isEmpty ? "" : "\(code) — "
                return "Трекер отказал: \(prefix)\(description)"
            case .unreadable:
                return "Трекер ответил непонятным образом. Возможно, у сервиса изменился формат ответа."
            case .manifestMissing:
                return "Описание этого трекера не нашлось в сборке — запрос собрать не из чего. Это поломка сборки, а не ваших настроек: переустановите приложение."
            }
        }
    }

    public struct Item: Equatable, Sendable {
        /// Номер или обозначение: «#42» у Trello, «ENG-123» у Linear.
        public let key: String
        public let title: String
        public let context: String
        public let state: String
        public let service: Service
    }

    let service: Service
    let token: String
    let values: [String: String]
    let http: HTTP

    public init(service: Service,
                token: String,
                values: [String: String] = [:],
                http: @escaping HTTP) {
        self.service = service
        self.token = token
        self.values = values
        self.http = http
    }

    public var isConfigured: Bool {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return service.fields.allSatisfy {
            !(values[$0.name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    public func search(_ query: String, limit: Int = 10) async throws -> [Item] {
        try await run(query, limit: limit).items
    }

    /// Выдача с охватом — форма общая со всеми источниками. У этих двух
    /// сервисов охват всегда `.searched`: искать по слову они умеют сами.
    public func run(_ query: String, limit: Int = 10) async throws
        -> (items: [Item], coverage: SearchCoverage) {
        guard isConfigured else { throw ConnectorError.notConfigured }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ([], .searched) }

        guard let manifest = try? ConnectorManifest.bundled()
            .first(where: { $0.id == service.rawValue }) else {
            throw ConnectorError.manifestMissing
        }

        let connector = ManifestConnector(manifest: manifest, token: token,
                                          host: service.host, values: values, http: http)
        do {
            let outcome = try await connector.run(trimmed, limit: limit)
            return (outcome.items.map {
                Item(key: $0.key, title: $0.title, context: $0.context,
                     state: $0.state, service: service)
            }, outcome.coverage)
        } catch let error as ManifestConnector.ConnectorError {
            // Тип наружу свой: на нём висят русские тексты с действием, и на
            // них смотрит интерфейс.
            switch error {
            case .notConfigured: throw ConnectorError.notConfigured
            case .unauthorised:  throw ConnectorError.unauthorised
            case .forbidden:     throw ConnectorError.forbidden
            case .rateLimited(let retryAfter):
                throw ConnectorError.rateLimited(retryAfter: retryAfter)
            case .http(let code): throw ConnectorError.http(code)
            case .vendor(let code, let description):
                throw ConnectorError.vendor(code: code, description: description)
            case .unreadable:    throw ConnectorError.unreadable
            }
        }
    }
}
