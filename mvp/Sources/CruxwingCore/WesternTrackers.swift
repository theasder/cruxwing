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
        // Общая сессия с запретом уводить токен на чужой хост: `URLSession`
        // по умолчанию идёт по перенаправлению сама и уносит `Authorization`
        // туда, куда укажет сервис. См. ConnectorSession.
        return try await ConnectorSession.send(request)
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
                return "A personal key from Settings → Security & access. Paste it as is: Linear expects it in the header without the word Bearer"
            case .trello:
                return "Two values from trello.com/power-ups/admin: the application key and the token. The token goes in the field below, the key in its own field — only the token is secret"
            }
        }

        /// Поля, которые человек заполняет сам, — из манифеста, а не из кода.
        public var fields: [ConnectorManifest.Field] {
            ConnectorManifest.usable().first { $0.id == rawValue }?.parameters ?? []
        }
    }

    public enum ConnectorError: Error, Equatable, LocalizedError {
        case notConfigured
        case unauthorised
        case forbidden
        /// Сервис просит подождать: 429. Чинить нечего, надо переждать.
        case rateLimited(retryAfter: Int?)
        /// Ответ больше, чем бывает у поиска.
        case tooLarge(bytes: Int)
        case http(Int)
        /// Сервис отказал своими словами — они и передаются дальше.
        case vendor(code: String, description: String)
        case webPage
        case unreadable
        /// Описание сервиса не нашлось в сборке.
        case manifestMissing

        public var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "The tracker is not connected. Open Settings → Connected apps and paste a key."
            case .unauthorised:
                return "The tracker rejected the key. Usually it expired or was revoked — create a new one in the service itself."
            case .forbidden:
                return "The key was accepted, but it carries no search rights. Rights are granted in the service itself; reissuing the key will not help."
            case .tooLarge(let bytes):
                return "The service sent back \(bytes / 1024 / 1024) MB — no search result weighs that much. We will not parse it in the middle of a call."
            case .rateLimited(let retryAfter):
                let wait = retryAfter.map { " Wait \($0)s." } ?? ""
                return "The service asks for fewer requests — too many in a row.\(wait) The token is not the problem: there is no need to reissue it."
            case .http(let status):
                return "The tracker answered with error \(status). The service is up — if it is a 5xx, wait and retry."
            case .vendor(let code, let description):
                let prefix = code.isEmpty ? "" : "\(code) — "
                return "The tracker refused: \(prefix)\(VendorText.forPerson(description))"
            case .webPage:
                return "A web page arrived instead of data — usually a sign-in form. The token may have expired, and on hotel or cafe networks the network itself demands a sign-in."
            case .unreadable:
                return "The tracker answered in a way we could not read. The service may have changed its response format."
            case .manifestMissing:
                return "This tracker has no description in the build, so there is nothing to build a request from. That is a broken build, not your settings: reinstall the application."
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
    /// Кэш ответов. Свой по умолчанию: общий принадлежит сеансу, а сеанс —
    /// это приложение (см. ConnectorCache).
    let cache: ConnectorCache
    /// Знание про регистр идёт рядом с кэшем и по той же причине: оно про
    /// сеанс. Общий по умолчанию сюда не ставится намеренно — общий кэш
    /// однажды уже переносил ответы между наборами, идущими рядом.
    let caseMemory: ConnectorCaseMemory
    let http: HTTP

    public init(service: Service,
                token: String,
                values: [String: String] = [:],
                cache: ConnectorCache = ConnectorCache(),
                caseMemory: ConnectorCaseMemory = ConnectorCaseMemory(),
                http: @escaping HTTP) {
        self.service = service
        self.token = token
        self.values = values
        self.cache = cache
        self.caseMemory = caseMemory
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

        guard let manifest = ConnectorManifest.usable()
            .first(where: { $0.id == service.rawValue }) else {
            throw ConnectorError.manifestMissing
        }

        let connector = ManifestConnector(manifest: manifest, token: token,
                                          host: service.host, values: values, cache: cache, caseMemory: caseMemory, http: http)
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
            case .tooLarge(let bytes):
                throw ConnectorError.tooLarge(bytes: bytes)
            case .rateLimited(let retryAfter):
                throw ConnectorError.rateLimited(retryAfter: retryAfter)
            case .http(let code): throw ConnectorError.http(code)
            case .vendor(let code, let description):
                throw ConnectorError.vendor(code: code, description: description)
            case .webPage:       throw ConnectorError.webPage
            case .unreadable:    throw ConnectorError.unreadable
            }
        }
    }
}
