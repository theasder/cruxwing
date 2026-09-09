import Foundation
// URLRequest, URLSession и HTTPURLResponse на Linux и Windows лежат не в
// Foundation, а в FoundationNetworking: swift-corelibs-foundation разнёс их по
// разным модулям. Без этой строки ядро не собирается вне Apple — и `PortabilityTests`
// этого не видел, потому что читает импорты, а не собирает код.
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Поиск по базе знаний команды.
///
/// Третий вопрос, отличный от двух других: у трекера спрашивают «заводили ли
/// задачу», у мессенджера — «обсуждали ли это», у базы знаний — «мы это уже
/// описывали». Разница видна на звонке сразу: решение, записанное в вики
/// полгода назад, не найдётся ни в задачах, ни в переписке.
///
/// **Почему это вообще появилось.** `RESEARCH-AND-PLAN` §2.1 закрывал раздел
/// заметок как невозможный: у Яндекс Вики в открытой документации есть выдача
/// страницы по адресу, но не поиск по тексту, а у Teamly публичного описания
/// API мы не нашли. Оба вывода в силе — но они про российские облака, а не про
/// открытые вики, которые команда поднимает у себя. Там поиск есть.
///
/// **Outline** — `POST /api/documents.search`, тело `{"query": …}`, заголовок
/// `Authorization: Bearer`. Проверено по их `spec3.yml` 2026-08-12. В ответе
/// приходит `context` — готовый кусок текста вокруг совпадения: ровно то, что
/// нужно подсказке. Ссылку на документ на звонке никто не откроет, а слова
/// прочитает.
///
/// HTTP приходит снаружи: тест, который ходит в чужую вики, проверяет чужую
/// вики, а не наш код.
public struct TeamNotes {

    public typealias HTTP = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    public static let live: HTTP = { request in
        // Общая сессия с запретом уводить токен на чужой хост: `URLSession`
        // по умолчанию идёт по перенаправлению сама и уносит `Authorization`
        // туда, куда укажет сервис. См. ConnectorSession.
        return try await ConnectorSession.send(request)
    }

    public enum Service: String, CaseIterable, Sendable {
        case outline, bookstack, wikijs, nextcloud

        public var title: String {
            switch self {
            case .outline: return "Outline"
            case .bookstack: return "BookStack"
            case .wikijs: return "Wiki.js"
            case .nextcloud: return "Nextcloud"
            }
        }

        public var credentialHint: String {
            switch self {
            case .outline:
                return "A token from Settings → API tokens. The address is needed only if the wiki is self-hosted; leave it empty for the cloud"
            case .bookstack:
                return "A token from your profile: API Tokens → Create Token gives two halves; paste them separated by a colon, id:secret. Your server address is needed too — BookStack has no cloud"
            case .wikijs:
                return "A token from Administration → API Access with the read:pages right, plus your wiki address. Wiki.js has no cloud — it is self-hosted"
            case .nextcloud:
                return "A username and an app password separated by a colon — «ivan:xxxxx-xxxxx»; better not to paste your ordinary password. The server address is needed, and where to search: «talk-message» searches Talk messages, «files» searches file names"
            }
        }

        public var hostPrompt: String {
            switch self {
            case .outline: return "address, if the server is your own — for example wiki.company.ru"
            case .bookstack: return "your BookStack address, for example wiki.company.ru"
            case .wikijs: return "your Wiki.js address, for example wiki.company.ru"
            case .nextcloud: return "your Nextcloud address, for example cloud.company.ru"
            }
        }

        /// Облачный адрес — там, где облако есть.
        ///
        /// У Outline оно есть, и пустое поле означает «облако», а не ошибку. У
        /// BookStack облака нет вовсе: сервис ставят себе. Пустой адрес там —
        /// именно незаполненная настройка, и подставить ему чужой домен значило
        /// бы слать токен неизвестно куда.
        var cloudHost: String? {
            switch self {
            case .outline: return "https://app.getoutline.com"
            case .bookstack, .wikijs, .nextcloud: return nil
            }
        }

        /// Поля, которые человек заполняет сам, — из манифеста, а не из кода.
        public var fields: [ConnectorManifest.Field] {
            ConnectorManifest.usable().first { $0.id == rawValue }?.parameters ?? []
        }

        func host(_ raw: String?) -> String? {
            ConnectorAddress.normalise(raw) ?? cloudHost
        }
    }

    public enum ConnectorError: Error, Equatable, LocalizedError {
        case notConfigured
        case unauthorised
        /// Сервер ответил, но ошибкой. Отдельно от `unreadable`:
        /// 502 от обратного прокси — это живой сервер и внятный
        /// ответ, а прежний текст советовал проверить ВЕРСИЮ, то
        /// есть отправлял человека не туда.
        /// Сервис просит подождать: 429. Чинить нечего, надо переждать.
        case rateLimited(retryAfter: Int?)
        /// Ответ больше, чем бывает у поиска.
        case tooLarge(bytes: Int)
        case http(Int)
        case forbidden
        case vendor(code: String, description: String)
        case webPage
        case unreadable

        /// По-русски и с действием.
        ///
        /// Без `LocalizedError` Swift печатает «The operation couldn’t be
        /// completed. (MeetGPT.TeamNotes.ConnectorError error 1.)» — по-английски, с внутренним
        /// путём типа и номером случая. В приложении, где всё остальное
        /// по-русски, это видно ровно тогда, когда человеку нужна помощь.
        public var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "The knowledge base is not connected. Open Settings → Connected apps and paste a token."
            case .unauthorised:
                return "The knowledge base rejected the token. Usually it expired or carries the wrong rights — create a new one in the service itself."
            case .tooLarge(let bytes):
                return "The service sent back \(bytes / 1024 / 1024) MB — no search result weighs that much. We will not parse it in the middle of a call."
            case .rateLimited(let retryAfter):
                let wait = retryAfter.map { " Wait \($0)s." } ?? ""
                return "The service asks for fewer requests — too many in a row.\(wait) The token is not the problem: there is no need to reissue it."
            case .http(let status):
                return "The knowledge base answered with error \(status). The server is up — check the address and the token's rights, and if it is a 5xx, the server itself or the proxy in front of it."
            case .forbidden:
                return "The token is real, but it was never granted search rights. That is fixed in the service itself — in the token rights or the space access — not by issuing a new token."
            case .vendor(let code, let description):
                let prefix = code.isEmpty ? "" : "\(code) — "
                return "The wiki refused: \(prefix)\(VendorText.forPerson(description))"
            case .webPage:
                return "A web page arrived instead of data — usually a sign-in form. The token may have expired, and on hotel or cafe networks the network itself demands a sign-in."
            case .unreadable:
                return "The knowledge base answered in a way we could not read. If the server is your own, check its address and version."
            }
        }

    }

    /// Один найденный кусок текста.
    public struct Hit: Equatable, Sendable {
        public let title: String
        /// Слова вокруг совпадения — они и попадают в подсказку.
        public let context: String
        public let service: Service
    }

    let service: Service
    let token: String
    let hostValue: String?
    /// Значения полей из `service.fields`: у Nextcloud это «где искать».
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
                host: String?,
                values: [String: String] = [:],
                cache: ConnectorCache = ConnectorCache(),
                caseMemory: ConnectorCaseMemory = ConnectorCaseMemory(),
                http: @escaping HTTP) {
        self.service = service
        self.token = token
        self.hostValue = host
        self.values = values
        self.cache = cache
        self.caseMemory = caseMemory
        self.http = http
    }

    /// Адрес обязателен не у всех: у Outline пустое поле значит облако. А поля,
    /// которые сервис требует помимо токена, обязательны всегда — без них
    /// адрес не собрать.
    public var isConfigured: Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && service.host(hostValue) != nil
            && service.fields.allSatisfy {
                !(values[$0.name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
    }

    /// Поиск по манифесту, если он есть. Переключено 2026-08-18.
    ///
    /// Outline — первый сервис, где описание данными пришлось расширить:
    /// поиск у него это `POST` со словом в ТЕЛЕ, а заголовок лежит на уровень
    /// глубже строки (`document.title`). Расширение сделано ради него не
    /// случайно: у Yonote, первого кандидата в очереди (роадмап, §7.3), API той
    /// же формы, и если он подтвердится, коннектор к нему станет файлом JSON,
    /// а не файлом Swift.
    ///
    /// Написанный руками путь ниже остаётся запасным: коннектор не должен
    /// отказывать человеку из-за пропавшего файла ресурсов.
    private func manifestSearch(_ query: String, host: String) async throws -> [Hit]? {
        guard let manifest = ConnectorManifest.usable()
            .first(where: { $0.id == service.rawValue })
        else { return nil }

        let connector = ManifestConnector(manifest: manifest, token: token, host: host,
                                          values: values, cache: cache, caseMemory: caseMemory, http: http)
        do {
            return try await connector.search(query).map {
                Hit(title: $0.title.isEmpty ? "Untitled" : $0.title,
                    context: $0.context, service: service)
            }
        } catch let error as ManifestConnector.ConnectorError {
            switch error {
            case .notConfigured: throw ConnectorError.notConfigured
            case .unauthorised:  throw ConnectorError.unauthorised
            // У этих сервисов 403 и 401 человек чинит одинаково — новым токеном.
            // 403 — не то же самое, что «токен не принят». Движок их разделяет
            // намеренно, и свести обратно здесь значит посоветовать человеку
            // заведомо бесполезное: выпустить новый токен вместо выдачи права.
            case .forbidden:     throw ConnectorError.forbidden
            case .tooLarge(let bytes):
                throw ConnectorError.tooLarge(bytes: bytes)
            case .rateLimited(let retryAfter):
                throw ConnectorError.rateLimited(retryAfter: retryAfter)
            case .http(let code): throw ConnectorError.http(code)
            // Свои слова сервиса у этих трёх в отдельный случай не выделены:
            // их отказы приходят кодом HTTP, а не телом с флагом. Если такой
            // сервис появится, ветку надо будет раскрыть, а не оставить общей.
            // Доказано на живом сервисе 2026-08-19: Wiki.js отвечает 200 и
            // errors[0].message = «Forbidden», когда доступ сняли.
            case .vendor(let code, let description):
                throw ConnectorError.vendor(code: code, description: description)
            case .webPage:       throw ConnectorError.webPage
            case .unreadable:    throw ConnectorError.unreadable
            }
        }
    }

    public func search(_ query: String) async throws -> [Hit] {
        guard isConfigured else { throw ConnectorError.notConfigured }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        guard let host = service.host(hostValue) else { throw ConnectorError.notConfigured }
        if let hits = try await manifestSearch(trimmed, host: host) { return hits }
        return try await legacySearch(trimmed, host: host)
    }

    /// Написанный руками путь — запас и эталон для сверки с манифестом.
    /// Причина, по которой он вызывается напрямую, — в `SelfHostedTrackers`.
    func legacySearch(_ query: String, host: String) async throws -> [Hit] {
        let trimmed = query
        guard let url = URL(string: "\(host)/api/documents.search") else {
            throw ConnectorError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: ["query": trimmed, "limit": 10])
        request.timeoutInterval = 8

        let (data, response) = try await http(request)
        if response.statusCode == 401 || response.statusCode == 403 {
            throw ConnectorError.unauthorised
        }
        // Всё прочее, кроме успеха, — ошибка сервера, а не мусор в
        // ответе. Раньше сюда проваливались 404, 500 и 502, и разбор
        // JSON объявлял их «непонятным ответом».
        guard (200..<300).contains(response.statusCode) else {
            throw ConnectorError.http(response.statusCode)
        }
        // `{ "data": [ { "context": …, "document": { "title": … } } ] }`.
        // Объект без `data` — это тело ошибки, и выдать его за пустую выдачу
        // значит сказать «не описывали» там, где мы не смогли спросить.
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["data"] as? [[String: Any]] else {
            throw ConnectorError.unreadable
        }
        let hits: [Hit] = rows.compactMap { row in
            let context = (row["context"] as? String) ?? ""
            let title = ((row["document"] as? [String: Any])?["title"] as? String) ?? ""
            guard !context.isEmpty || !title.isEmpty else { return nil }
            return Hit(title: title.isEmpty ? "Untitled" : title,
                       context: context, service: service)
        }
        // Строки пришли, а прочитать не удалось ни одну — это смена формата, а
        // не пустая выдача. То же правило, что в движке манифестов: разбор,
        // написанный руками, ошибается ровно так же, и «ничего не нашлось»
        // здесь было бы враньём на каждый вопрос.
        if hits.isEmpty && !rows.isEmpty { throw ConnectorError.unreadable }
        return hits
    }
}
