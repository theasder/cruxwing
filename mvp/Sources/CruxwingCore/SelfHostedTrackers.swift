import Foundation
// URLRequest, URLSession и HTTPURLResponse на Linux и Windows лежат не в
// Foundation, а в FoundationNetworking: swift-corelibs-foundation разнёс их по
// разным модулям. Без этой строки ядро не собирается вне Apple — и `PortabilityTests`
// этого не видел, потому что читает импорты, а не собирает код.
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Открытые трекеры задач, которые команда поднимает у себя.
///
/// Отдельно от `GitHubConnector`: тот ходит только на `api.github.com`, адрес у
/// него зашит. Самостоятельно поднятый GitLab или Gitea живёт на своём домене,
/// и без поля «адрес сервера» подключить его некуда.
///
/// Отдельно от `RussianTrackers`: у тех облако вендора, здесь — сервер команды.
/// Разница видна и пользователю (появляется поле адреса), и в коде (общего
/// хоста нет), так что один общий тип только запутал бы.
///
/// Адреса сверены с документацией 2026-08-12:
///
///   * **GitLab** — `GET /api/v4/search?scope=issues&search=…`, заголовок
///     `PRIVATE-TOKEN`. Ищет по всему, что видит токен; сузить до проекта можно
///     через `/projects/{id}/search`, но на вопрос «мы это уже заводили?» шире
///     полезнее.
///   * **Gitea / Forgejo** — `GET /api/v1/repos/issues/search?q=…`, заголовок
///     `Authorization: token …` — именно слово `token`, а не `Bearer`: так в
///     их `swagger.v1.json`. Forgejo — форк Gitea с тем же API, поэтому
///     отдельной строкой не идёт.
///   * **Redmine** — `GET /search.json?q=…&issues=1`, заголовок
///     `X-Redmine-API-Key`. Единственный из трёх, кто оборачивает выдачу в
///     объект (`{"results": […]}`), а не отдаёт массив; и единственный, кто без
///     `issues=1` ищет заодно по вики, форуму и новостям.
///
/// HTTP приходит снаружи: тест, который ходит в чужой трекер, проверяет чужой
/// трекер, а не наш код.
public struct SelfHostedTrackers {

    public typealias HTTP = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    public static let live: HTTP = { request in
        // Общая сессия с запретом уводить токен на чужой хост: `URLSession`
        // по умолчанию идёт по перенаправлению сама и уносит `Authorization`
        // туда, куда укажет сервис. См. ConnectorSession.
        return try await ConnectorSession.send(request)
    }

    public enum Service: String, CaseIterable, Sendable {
        case gitlab, gitea, redmine, plane, gitflic, jira

        public var title: String {
            switch self {
            case .gitlab: return "GitLab"
            case .gitea:  return "Gitea / Forgejo"
            case .redmine: return "Redmine"
            case .plane:  return "Plane"
            case .gitflic: return "GitFlic"
            case .jira:   return "Self-hosted Jira"
            }
        }

        public var credentialHint: String {
            switch self {
            case .gitlab:
                return "An access token with the read_api scope, plus your GitLab address"
            case .gitea:
                return "A token from your profile settings, plus your Gitea or Forgejo address"
            case .redmine:
                return "The API key from the My account page, plus your Redmine address"
            case .plane:
                // Про перечисление сказано здесь, а не в подсказке об ошибке:
                // человек выбирает сервис до того, как задаст первый вопрос, и
                // «ищет не сервис, а мы» — это то, что меняет его ожидания.
                return "The API key from Plane settings, the server address, and two fields taken from your project URL. Plane has no word search: cruxwing looks through the most recent issues and filters them locally — how many it looked through is written under the answer"
            case .jira:
                // «Data Center», а не просто «Jira»: в облаке путь другой, и
                // человек с облачной Jira, вписав сюда свой адрес, получил бы
                // отказ без объяснения, почему именно.
                return "A personal token (in your profile, the personal access tokens section — available from Jira 8.14 on) plus your server address. This is a self-hosted install, not cloud Jira: the cloud one connects over MCP"
            case .gitflic:
                return "An access token from your GitFlic profile, the address (api.gitflic.ru or your own install), and the owner and project slugs. GitFlic has no word search: cruxwing looks through the project's most recent issues and filters them locally — how many it looked through is written under the answer"
            }
        }

        public var hostPrompt: String {
            switch self {
            case .gitlab: return "server address, for example gitlab.company.ru"
            case .gitea:  return "server address, for example git.company.ru"
            case .redmine: return "server address, for example redmine.company.ru"
            case .plane: return "server address, for example api.plane.so"
            case .gitflic: return "address, for example api.gitflic.ru"
            case .jira: return "server address, for example jira.company.ru"
            }
        }

        /// Поля, которые человек заполняет сам, — из манифеста, а не из кода.
        ///
        /// У Plane пространство и проект стоят внутри адреса. Держать их
        /// списком здесь значило бы описывать сервис в двух местах: манифест
        /// уже знает и имена, и примеры.
        public var fields: [ConnectorManifest.Field] {
            ConnectorManifest.usable().first { $0.id == rawValue }?.parameters ?? []
        }

        func host(_ raw: String?) -> String? {
            ConnectorAddress.normalise(raw)
        }
    }

    public enum ConnectorError: Error, Equatable, LocalizedError {
        case notConfigured
        case unauthorised
        /// Сервис описан манифестом, а манифеста в сборке нет.
        ///
        /// Отдельно от `notConfigured` и `unreadable`: человек ничего не
        /// испортил и сервис ничего не ответил — сломана сама сборка. Оба
        /// соседних текста отправили бы его чинить не то: один в настройки,
        /// другой — проверять версию чужого сервера.
        case manifestMissing
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
        /// completed. (MeetGPT.SelfHostedTrackers.ConnectorError error 1.)» — по-английски, с внутренним
        /// путём типа и номером случая. В приложении, где всё остальное
        /// по-русски, это видно ровно тогда, когда человеку нужна помощь.
        public var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "The tracker is not connected. Open Settings → Connected apps and paste a token."
            case .unauthorised:
                return "The tracker rejected the token. Usually it expired or carries the wrong rights — create a new one in the service itself."
            case .manifestMissing:
                return "This tracker has no description in the build, so there is nothing to build a request from. That is a broken build, not your settings: reinstall the application."
            case .tooLarge(let bytes):
                return "The service sent back \(bytes / 1024 / 1024) MB — no search result weighs that much. We will not parse it in the middle of a call."
            case .rateLimited(let retryAfter):
                let wait = retryAfter.map { " Wait \($0)s." } ?? ""
                return "The service asks for fewer requests — too many in a row.\(wait) The token is not the problem: there is no need to reissue it."
            case .http(let status):
                return "The tracker answered with error \(status). The server is up — check the address and the token's rights, and if it is a 5xx, the server itself or the proxy in front of it."
            case .forbidden:
                return "The token is real, but it was never granted search rights. Check the token scope (read_api on GitLab, issue rights on Gitea) and its access to the project. A new token with the same rights will not help."
            case .vendor(let code, let description):
                let prefix = code.isEmpty ? "" : "\(code) — "
                return "The tracker refused: \(prefix)\(VendorText.forPerson(description))"
            case .webPage:
                return "A web page arrived instead of data — usually a sign-in form: the single sign-on session expired, or the address points at the server itself rather than its API."
            case .unreadable:
                return "The tracker answered in a way we could not read. If the server is your own, check its address and version."
            }
        }

    }

    public struct Item: Equatable, Sendable {
        public let key: String
        public let title: String
        public let state: String
        public let service: Service
    }

    let service: Service
    let token: String
    let hostValue: String?
    /// Значения полей из `service.fields`. Пусто у сервисов, которым хватает
    /// токена и адреса.
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

    public var isConfigured: Bool {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              service.host(hostValue) != nil else { return false }
        // Незаполненное поле — это «не подключён», а не «подключён наполовину».
        // Иначе Plane выглядит настроенным, а первый же вопрос уходит по
        // адресу с `{project}` буквами и возвращает 404.
        return service.fields.allSatisfy {
            !(values[$0.name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Поиск по манифесту, если он для этого сервиса есть.
    ///
    /// Переключено 2026-08-18. До этого запрос и разбор были написаны здесь
    /// руками — код ниже остался запасным путём и не удалён намеренно: если
    /// манифест пропал из ресурсов или не прошёл проверку, коннектор обязан
    /// работать, а не отказывать человеку из-за отсутствующего файла.
    ///
    /// Что делает замену безопасной: `ManifestConnectorTests` сверяет обе
    /// дороги целиком — адрес со всеми параметрами, все заголовки, дедлайн и
    /// разобранные строки, по каждому из трёх сервисов. Это единственная
    /// причина, по которой такое переключение вообще можно делать сразу.
    private func manifestSearch(_ query: String, host: String) async throws
        -> (items: [Item], note: String)? {
        guard let manifest = ConnectorManifest.usable()
            .first(where: { $0.id == service.rawValue })
        else { return nil }

        let connector = ManifestConnector(manifest: manifest, token: token, host: host,
                                          values: values, cache: cache, caseMemory: caseMemory, http: http)
        do {
            let outcome = try await connector.run(query)
            return (outcome.items.map {
                Item(key: $0.key, title: $0.title, state: $0.state, service: service)
            }, outcome.coverage.note())
        } catch let error as ManifestConnector.ConnectorError {
            // Ошибки те же по смыслу, но тип наружу обязан остаться прежним: на
            // нём висят русские тексты с действием, и на них смотрит интерфейс.
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
            // Ни один манифест этой семьи сегодня не объявляет отказ телом. Ветка
            // всё равно раскрыта: `.vendor` кидает общий движок, и молчаливое
            // «непонятный ответ» здесь ждало бы только первого такого манифеста.
            case .vendor(let code, let description):
                throw ConnectorError.vendor(code: code, description: description)
            case .webPage:       throw ConnectorError.webPage
            case .unreadable:    throw ConnectorError.unreadable
            }
        }
    }

    public func search(_ query: String) async throws -> [Item] {
        try await run(query).items
    }

    /// Выдача вместе с охватом.
    ///
    /// `note` пуст почти всегда: сервис ищет сам, и приписка была бы шумом.
    /// Не пуст он у тех, кто искать не умеет, — и тогда это не украшение, а
    /// часть ответа: «не нашлось» и «не нашлось среди последних пятисот из
    /// сорока тысяч» — разные ответы (роадмап, §7.2).
    public func run(_ query: String) async throws -> (items: [Item], note: String) {
        guard isConfigured, let host = service.host(hostValue) else {
            throw ConnectorError.notConfigured
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ([], "") }

        if let outcome = try await manifestSearch(trimmed, host: host) { return outcome }
        return (try await legacySearch(trimmed, host: host), "")
    }

    /// Запрос и разбор, написанные руками, — запасной путь и эталон.
    ///
    /// Не `private` намеренно. После перехода на манифест сверять его стало не
    /// с чем: `search` сам ходит через манифест, и проверка «манифест как
    /// продакшен» сравнивала манифест с манифестом и проходила на любой порче.
    /// Поймано мутацией 2026-08-18 — заменой `Bearer` на `token` в манифесте
    /// Outline, которую никто не заметил.
    ///
    /// Теперь эталон вызывается прямо, и заодно перестаёт быть непроверенным
    /// кодом: запасной путь, который никто не исполняет, — это не запас.
    func legacySearch(_ query: String, host: String) async throws -> [Item] {
        let trimmed = query
        var request: URLRequest
        switch service {
        // Запасного пути у Plane нет и не будет: он не переписан с рук на
        // манифест, а сразу описан данными. Писать ему второй, ручной запрос
        // значило бы держать две дороги там, где первая появилась вчера.
        // Jira здесь по той же причине, и есть вторая: слово уходит внутрь
        // кавычек JQL. Ручной запрос пришлось бы учить тому же экранированию,
        // и второе место, где его можно забыть, дороже отсутствующего
        // запасного пути.
        case .plane, .gitflic, .jira: throw ConnectorError.manifestMissing

        case .gitlab:
            var components = URLComponents(string: "\(host)/api/v4/search")
            components?.queryItems = [
                URLQueryItem(name: "scope", value: "issues"),
                URLQueryItem(name: "search", value: trimmed),
                URLQueryItem(name: "per_page", value: "10"),
            ]
            guard let url = components?.url else { throw ConnectorError.notConfigured }
            request = URLRequest(url: url)
            request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")

        case .redmine:
            var components = URLComponents(string: "\(host)/search.json")
            components?.queryItems = [
                URLQueryItem(name: "q", value: trimmed),
                // Только задачи: Redmine по умолчанию ищет ещё по вики, форуму
                // и новостям, и подсказка тонет в чужом.
                URLQueryItem(name: "issues", value: "1"),
                URLQueryItem(name: "limit", value: "10"),
            ]
            guard let url = components?.url else { throw ConnectorError.notConfigured }
            request = URLRequest(url: url)
            request.setValue(token, forHTTPHeaderField: "X-Redmine-API-Key")

        case .gitea:
            var components = URLComponents(string: "\(host)/api/v1/repos/issues/search")
            components?.queryItems = [
                URLQueryItem(name: "q", value: trimmed),
                // Без этого в выдачу попадают и пулл-реквесты: на вопрос «мы
                // это уже заводили?» они отвечают о другом.
                URLQueryItem(name: "type", value: "issues"),
                URLQueryItem(name: "limit", value: "10"),
            ]
            guard let url = components?.url else { throw ConnectorError.notConfigured }
            request = URLRequest(url: url)
            // Именно «token», а не «Bearer»: так в их спецификации.
            request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        }
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
        // GitLab и Gitea отдают массив верхним уровнем, Redmine — объект с
        // `results`. В обоих случаях неожиданная форма это тело ошибки, и
        // выдать его за пустую выдачу значит сказать «не заводили» там, где мы
        // просто не смогли спросить.
        let rows: [[String: Any]]
        if service == .redmine {
            // Redmine оборачивает выдачу: `{ "results": [...], "total_count": N }`.
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = root["results"] as? [[String: Any]] else {
                throw ConnectorError.unreadable
            }
            rows = results
        } else {
            guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw ConnectorError.unreadable
            }
            rows = array
        }
        let items: [Item] = rows.compactMap { row in
            guard let title = row["title"] as? String, !title.isEmpty else { return nil }
            // GitLab зовёт номер `iid`, Gitea — `number`, Redmine — `id`.
            let number = (row["iid"] as? Int) ?? (row["number"] as? Int)
                ?? (service == .redmine ? row["id"] as? Int : nil)
            let key = number.map { "#\($0)" } ?? "—"
            // Пусто, а не «unknown»: поиск Redmine состояния не отдаёт вовсе, и
            // строка `[#314, unknown]` сообщает человеку, что что-то неизвестно
            // ЕМУ. Неизвестно оно не ему — его просто не спрашивали.
            let state = (row["state"] as? String) ?? ""
            return Item(key: key, title: title, state: state, service: service)
        }
        // Строки пришли, а прочитать не удалось ни одну — это смена формата, а
        // не пустая выдача. То же правило, что в движке манифестов: разбор,
        // написанный руками, ошибается ровно так же, и «ничего не нашлось»
        // здесь было бы враньём на каждый вопрос.
        if items.isEmpty && !rows.isEmpty { throw ConnectorError.unreadable }
        return items
    }
}
