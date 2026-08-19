import Foundation
// URLRequest, URLSession и HTTPURLResponse на Linux и Windows лежат не в
// Foundation, а в FoundationNetworking: swift-corelibs-foundation разнёс их по
// разным модулям. Без этой строки ядро не собирается вне Apple — и `PortabilityTests`
// этого не видел, потому что читает импорты, а не собирает код.
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Коннекторы к российским трекерам — не через MCP.
///
/// MCP-каталог в этом приложении подключается по OAuth 2.1 с динамической
/// регистрацией клиента, и это работает только там, где вендор поднял
/// MCP-сервер. Ни у одного российского трекера его нет. Завести для них строки
/// в MCP-каталоге с выдуманным адресом означало бы показать кнопку
/// «Подключить», которая не может сработать, — ровно та ошибка, за которую
/// пришлось править лендинг.
///
/// Поэтому здесь прямой REST по документации вендора: токен пользователь
/// заводит сам, токен лежит в Связке ключей.
///
/// Pyrus сюда не входит: его API выдаёт реестр конкретной формы
/// (`GET /forms/{id}/register`), но не умеет искать задачи по тексту. WEEEK,
/// напротив, с июня 2026 публично документирует `GET /tm/tasks?search=…` и форму
/// ответа, поэтому подключается тем же прямым REST-путём, что остальные.
///
/// HTTP приходит снаружи: тест, который ходит в чужой трекер, проверяет чужой
/// трекер, а не наш код.
public struct RussianTrackers {

    public typealias HTTP = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    /// Настоящая сеть — для приложения. Тесты передают своё замыкание, поэтому
    /// сюда они не попадают: значение по умолчанию тут не задано намеренно,
    /// иначе забытый аргумент в тесте молча пошёл бы в чужой сервис.
    public static let live: HTTP = { request in
        // Общая сессия с запретом уводить токен на чужой хост: `URLSession`
        // по умолчанию идёт по перенаправлению сама и уносит `Authorization`
        // туда, куда укажет сервис. См. ConnectorSession.
        return try await ConnectorSession.send(request)
    }

    public enum Service: String, CaseIterable, Sendable {
        case yandexTracker, kaiten, yougile, weeek, bitrix24

        public var title: String {
            switch self {
            case .yandexTracker: return "Яндекс Трекер"
            case .kaiten:        return "Kaiten"
            case .yougile:       return "YouGile"
            case .weeek:         return "WEEEK"
            case .bitrix24:      return "Битрикс24"
            }
        }

        /// Что человек должен получить в своём сервисе, чтобы подключение
        /// заработало. Показывается рядом с полем ввода: «нужен токен» без
        /// уточнения, какой именно, — это тупик.
        public var credentialHint: String {
            switch self {
            case .yandexTracker: return "OAuth-токен и идентификатор организации: «Администрирование» → «Организации», поле ID"
            case .kaiten:        return "API-токен из профиля, раздел «API», и адрес вашей команды"
            case .yougile:
                return "API-ключ создаётся через POST /api-v2/auth/keys в интерактивной документации YouGile: нужны логин, пароль и ID компании"
            case .weeek:
                return "Токен доступа из раздела API в настройках рабочего пространства WEEEK"
            case .bitrix24:
                // Вебхук показывают одной строкой вида
                // https://фирма.bitrix24.ru/rest/1/abc.../ — сюда идёт
                // середина, «1/abc...», а адрес портала в поле ниже.
                return "Входящий вебхук: «Разработчикам» → «Другое» → «Входящий вебхук», право «Задачи». Вставьте ссылку целиком — адрес портала возьмётся из неё"
            }
        }

        /// Второе поле, если одного токена мало. У двух сервисов оно значит
        /// разное — организацию у Яндекса, адрес команды у Kaiten, — поэтому
        /// подпись хранится здесь, а не в интерфейсе: там она разъедется с тем,
        /// как значение используется.
        public var secondaryPrompt: String? {
            switch self {
            // Один токен обслуживает несколько организаций; без X-Org-ID
            // запрос уходит в никуда с 403.
            case .yandexTracker: return "идентификатор организации"
            // У Kaiten нет общего адреса API: он свой у каждой команды.
            case .kaiten:        return "адрес команды, например team.kaiten.ru"
            // Портал у каждой фирмы свой, общего адреса API нет.
            // Заполнять не нужно, если вебхук вставлен целиком: адрес
            // возьмётся из ссылки. Поле остаётся для тех, кто вписывает
            // середину руками, и для порталов на своём домене.
            case .bitrix24:      return "адрес портала, если вставили не ссылку целиком"
            case .yougile, .weeek: return nil
            }
        }

        public var needsSecondary: Bool { secondaryPrompt != nil }

        /// Куда класть заведённую задачу. Третье поле, и без него завести
        /// задачу нельзя ни в одном из пяти сервисов: у каждого своё
        /// обязательное «место» и своё для него слово.
        ///
        /// Проверено по документации вендоров: Яндекс требует `queue`, Kaiten —
        /// `board_id`, YouGile ставит задачу в колонку. У YouGile документация
        /// расходится, обязательна ли колонка; требуем всё равно — задача без
        /// колонки не попадает на доску, то есть для человека пропадает, а
        /// лишний верный параметр никогда не ошибка.
        public var destinationPrompt: String? {
            switch self {
            case .yandexTracker: return "ключ очереди, например TREK"
            case .kaiten:        return "номер доски, например 4"
            case .yougile:       return "идентификатор колонки"
            case .weeek:         return "номер проекта, например 42"
            case .bitrix24:      return "номер ответственного, например 1"
            }
        }

        var needsDestination: Bool { destinationPrompt != nil }

        /// Адрес API. У Kaiten он собирается из домена команды — общего хоста
        /// у сервиса нет.
        func host(secondary: String?) -> String {
            switch self {
            case .yandexTracker: return "https://api.tracker.yandex.net/v3"
            case .kaiten:
                // Люди вставляют адрес из строки браузера целиком, вместе со
                // схемой и путём до доски. Берём только хост: остальное дало бы
                // .../boards/5/api/latest и 404, который нечем объяснить.
                let domain = (secondary ?? "")
                    .replacingOccurrences(of: "https://", with: "")
                    .replacingOccurrences(of: "http://", with: "")
                    .split(separator: "/").first
                    .map(String.init) ?? ""
                return "https://\(domain.trimmingCharacters(in: .whitespaces))/api/latest"
            case .yougile:       return "https://yougile.com/api-v2"
            case .weeek:         return "https://api.weeek.net/public/v1"
            case .bitrix24:
                // Тот же случай, что у Kaiten: адрес копируют из строки
                // браузера вместе со схемой и путём до раздела.
                let domain = (secondary ?? "")
                    .replacingOccurrences(of: "https://", with: "")
                    .replacingOccurrences(of: "http://", with: "")
                    .split(separator: "/").first
                    .map(String.init) ?? ""
                return "https://\(domain.trimmingCharacters(in: .whitespaces))/rest"
            }
        }
    }

    public struct Issue: Equatable, Sendable {
        public let key: String
        public let title: String
        public let url: URL?
    }

    public enum TrackerError: Error, Equatable, LocalizedError {
        case notConfigured(Service)
        case unauthorised(Service)
        case forbidden(Service)
        /// Сервис просит обращаться реже: 429. Чинить нечего, надо переждать.
        case rateLimited(Service, retryAfter: Int?)
        /// Ответ больше, чем бывает у поиска.
        case tooLarge(Service, bytes: Int)
        case http(Service, Int)
        /// Сервис ответил успехом, а внутри — отказ.
        ///
        /// Битрикс так и работает: HTTP 200 и `{"error": …,
        /// "error_description": …}` в теле. Без этой ветки отозванный вебхук
        /// или нехватка права «Задачи» выглядели бы как «ничего не нашлось» —
        /// то есть продукт уверенно сообщал бы об исходе поиска, которого не
        /// было.
        case vendor(Service, code: String, description: String)
        case webPage(Service)
        case unreadable(Service)

        /// По-русски, с названием сервиса и с действием.
        ///
        /// Без `LocalizedError` наружу шло «The operation couldn’t be
        /// completed. (MeetGPT.RussianTrackers.TrackerError error 1.)»:
        /// по-английски и без единого намёка, какой из подключённых трекеров
        /// отказал. При трёх подключённых это делает сообщение бесполезным.
        public var errorDescription: String? {
            switch self {
            case .tooLarge(let service, let bytes):
                return "\(service.title) прислал ответ на \(bytes / 1024 / 1024) МБ — столько выдача поиска не весит. Разбирать его посреди звонка мы не станем."
            case .rateLimited(let service, let retryAfter):
                let wait = retryAfter.map { " Подождите \($0) с." } ?? ""
                return "\(service.title) просит обращаться реже — слишком много запросов подряд.\(wait) Токен тут ни при чём: перевыпускать его не нужно."
            case .notConfigured(let service):
                return "\(service.title) не подключён. Вставьте токен в «Настройки → Подключённые приложения»."
            case .unauthorised(let service):
                return "\(service.title) не принял токен: истёк или не хватает прав. Создайте новый в самом сервисе."
            case .vendor(let service, let code, let description):
                let detail = description.isEmpty ? code : description
                return "\(service.title) отказал: \(detail). Если это Битрикс24 — проверьте, что вебхук не удалён и у него есть право «Задачи»."
            case .http(let service, let status):
                return "\(service.title) ответил ошибкой \(status). Если это 404 — проверьте очередь или доску в настройках."
            case .forbidden(let service):
                return "\(service.title): токен настоящий, но права на поиск ему не выдали. Право выдают в настройках приложения или вебхука в самом сервисе — новый токен не поможет."
            case .webPage(let service):
                return "\(service.title) прислал веб-страницу вместо данных — обычно это форма входа. Токен мог истечь, а если вы в гостинице или в кафе, то сеть требует входа в свой портал."
            case .unreadable(let service):
                return "\(service.title) вернул ответ, который не удалось разобрать."
            }
        }

    }

    let service: Service
    let token: String
    let secondary: String?
    /// Куда класть заведённую задачу: очередь, доска или колонка. Для чтения не
    /// нужна, поэтому необязательна — трекер можно подключить только на чтение.
    let destination: String?
    /// Кэш ответов. Свой по умолчанию: общий принадлежит сеансу, а сеанс —
    /// это приложение (см. ConnectorCache).
    let cache: ConnectorCache
    /// Знание про регистр идёт рядом с кэшем и по той же причине: оно про
    /// сеанс. Общий по умолчанию сюда не ставится намеренно — общий кэш
    /// однажды уже переносил ответы между наборами, идущими рядом.
    let caseMemory: ConnectorCaseMemory
    let http: HTTP

    public init(service: Service, token: String, secondary: String? = nil,
                destination: String? = nil,
                cache: ConnectorCache = ConnectorCache(),
                caseMemory: ConnectorCaseMemory = ConnectorCaseMemory(),
                http: @escaping HTTP) {
        self.service = service
        // Битрикс показывает вебхук одной строкой целиком. Человек копирует её
        // целиком — это нормальное поведение, а не ошибка ввода. Требовать
        // вырезать середину и отдельно вписать портал значит закладывать самый
        // вероятный способ ошибиться в саму форму.
        let parsed = Self.splitBitrixWebhook(service: service, token: token)
        self.token = parsed.token
        self.secondary = parsed.host ?? secondary
        self.destination = destination
        self.cache = cache
        self.caseMemory = caseMemory
        self.http = http
    }

    /// Разбирает вставленную целиком ссылку вебхука на портал и учётную часть.
    ///
    /// Возвращает исходный токен, если это не Битрикс или если вставлена не
    /// ссылка: у остальных четырёх сервисов токен — обычная строка, и трогать её
    /// нельзя.
    static func splitBitrixWebhook(service: Service,
                                   token: String) -> (token: String, host: String?) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard service == .bitrix24, trimmed.contains("/rest/") else { return (token, nil) }

        let withoutScheme = trimmed
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        let parts = withoutScheme.split(separator: "/", omittingEmptySubsequences: true)
        guard let host = parts.first, let restIndex = parts.firstIndex(of: "rest") else {
            return (token, nil)
        }
        // После `rest` идут номер пользователя и код. Дальше может стоять имя
        // метода — его отбрасываем: адрес метода orakul подставляет сам.
        let credentials = parts[parts.index(after: restIndex)...]
            .prefix(2)
            .joined(separator: "/")
        guard credentials.contains("/") else { return (token, nil) }
        return (credentials, String(host))
    }

    // MARK: - Запросы

    /// Задачи по тексту: ключ, заголовок и ссылка, по которой человек откроет
    /// задачу сам.
    public func search(_ query: String, limit: Int = 10) async throws -> [Issue] {
        guard !token.isEmpty, !(service.needsSecondary && (secondary ?? "").isEmpty) else {
            throw TrackerError.notConfigured(service)
        }
        if let issues = try await manifestSearch(query, limit: limit) { return issues }
        return try await legacySearch(query, limit: limit)
    }

    /// Поиск по манифесту — для тех сервисов, что описаны данными.
    ///
    /// Пока это WEEEK: обычный GET с параметром поиска и Bearer-токеном. У
    /// остальных четырёх есть по своей особенности — POST с телом у Яндекса,
    /// ключ внутри пути у Битрикса, второе поле у Kaiten, — и они остаются
    /// кодом, пока описание данными их не покрывает.
    private func manifestSearch(_ query: String, limit: Int) async throws -> [Issue]? {
        guard let manifest = try? ConnectorManifest.bundled()
            .first(where: { $0.id == service.rawValue })
        else { return nil }

        // Кэш и память передаются, а не теряются.
        //
        // Их здесь не было, и у единственного трекера, описанного манифестом
        // (WEEEK), это стоило дорого: движок брал СВЕЖИЕ кэш и память на каждый
        // поиск. Значит кэш на полторы минуты не работал ни разу — один и тот же
        // вопрос уходил к вендору столько раз, сколько его задали, — а плата за
        // знание про регистр бралась не один раз на сервис, а на КАЖДЫЙ поиск:
        // второе написание спрашивалось всегда. Мы сами удваивали нагрузку тому,
        // на чей троттлинг потом жалуются.
        //
        // Остальные четыре семейства передавали их с самого начала; это
        // расхождение и нашлось, когда набор попробовал подложить свою память.
        let connector = ManifestConnector(manifest: manifest, token: token,
                                          host: service.host(secondary: secondary),
                                          cache: cache, caseMemory: caseMemory, http: http)
        do {
            return try await connector.search(query, limit: limit).map {
                Issue(key: $0.key.hasPrefix("#") ? String($0.key.dropFirst()) : $0.key,
                      title: $0.title, url: nil)
            }
        } catch let error as ManifestConnector.ConnectorError {
            switch error {
            case .notConfigured:  throw TrackerError.notConfigured(service)
            case .unauthorised: throw TrackerError.unauthorised(service)
            // 403 отделён от 401: первое чинится новым токеном, второе — выдачей
            // права. Совет «перевыпустите токен» на 403 бесполезен.
            case .forbidden: throw TrackerError.forbidden(service)
            case .tooLarge(let bytes):
                throw TrackerError.tooLarge(service, bytes: bytes)
            case .rateLimited(let retryAfter):
                throw TrackerError.rateLimited(service, retryAfter: retryAfter)
            case .http(let code): throw TrackerError.http(service, code)
            // Слова сервиса доходят до человека как есть: «invalid_token —
            // Token revoked» объясняет причину, а наше «непонятный ответ» нет.
            case .vendor(let code, let description):
                throw TrackerError.vendor(service, code: code, description: description)
            case .webPage:        throw TrackerError.webPage(service)
            case .unreadable:     throw TrackerError.unreadable(service)
            }
        }
    }

    /// Написанный руками путь — запас и эталон для сверки, см. `SelfHostedTrackers`.
    func legacySearch(_ query: String, limit: Int = 10) async throws -> [Issue] {
        var request = URLRequest(url: try endpoint(for: query, limit: limit))
        request.timeoutInterval = 8   // тот же бюджет, что у остальных источников
        for (field, value) in headers() { request.setValue(value, forHTTPHeaderField: field) }
        if let body = try body(for: query, limit: limit) {
            request.httpMethod = "POST"
            request.httpBody = body
        }

        let (data, response) = try await http(request)
        switch response.statusCode {
        case 200...299: break
        case 401, 403:  throw TrackerError.unauthorised(service)
        default:        throw TrackerError.http(service, response.statusCode)
        }
        // Верхняя граница ещё раз, уже после разбора: у четырёх сервисов размер
        // задаётся параметром и это ничего не меняет, а у Битрикса страница
        // всегда пятьдесят и урезать выдачу больше негде.
        return Array(try parse(data).prefix(limit))
    }

    public func headers() -> [String: String] {
        switch service {
        case .yandexTracker:
            var fields = ["Authorization": "OAuth \(token)",
                          "Content-Type": "application/json"]
            if let secondary { fields[Self.orgHeader(for: secondary)] = secondary }
            return fields
        case .kaiten:
            return ["Authorization": "Bearer \(token)"]
        case .yougile, .weeek:
            // YouGile's API contract requires JSON content type on every
            // request, including GET. WEEEK uses the same header set.
            return ["Authorization": "Bearer \(token)",
                    "Content-Type": "application/json"]
        // У Битрикса ключа в заголовке нет вовсе: вебхук — это адрес, и права
        // проверяются по нему. Заголовок остаётся один, про формат тела.
        case .bitrix24:
            return ["Content-Type": "application/json"]
        }
    }

    /// Заголовков организации у Трекера два, и они не взаимозаменяемы:
    /// `X-Org-ID` — организация в Яндекс 360, `X-Cloud-Org-ID` — в Yandex
    /// Cloud Organization. Отправленный не тот даёт отказ, по которому не
    /// догадаться, что дело в заголовке, а не в токене.
    ///
    /// Спрашивать тип организации у человека незачем: идентификаторы разной
    /// формы. У Яндекс 360 это число, у Cloud — двадцать знаков, начинающихся
    /// с `bpf` (`bpf3crucp1v28b74p3rk`). По форме и выбираем.
    static func orgHeader(for organisation: String) -> String {
        let value = organisation.trimmingCharacters(in: .whitespaces)
        let isNumeric = !value.isEmpty && value.allSatisfy(\.isNumber)
        return isNumeric ? "X-Org-ID" : "X-Cloud-Org-ID"
    }

    func endpoint(for query: String, limit: Int) throws -> URL {
        let path: String
        let queryItems: [URLQueryItem]
        switch service {
        // Поиск у Яндекса — POST с телом; в адресе остаётся только размер
        // страницы. Строка запроса уезжает в body, см. body(for:limit:).
        case .yandexTracker:
            path = "/issues/_search"
            queryItems = [.init(name: "perPage", value: String(limit))]
        case .kaiten:
            path = "/cards"
            queryItems = [.init(name: "query", value: query),
                          .init(name: "limit", value: String(limit))]
        case .yougile:
            // GET /tasks remains in the current schema only as deprecated.
            path = "/task-list"
            queryItems = [.init(name: "title", value: query),
                          .init(name: "limit", value: String(limit))]
        case .weeek:
            path = "/tm/tasks"
            queryItems = [.init(name: "search", value: query),
                          .init(name: "perPage", value: String(limit))]
        // У Битрикса ключ едет в адресе, а не в заголовке: вебхук — это
        // и есть номер пользователя с кодом внутри пути. Размер страницы
        // всегда пятьдесят и не настраивается, поэтому limit урезает
        // выдачу уже здесь, после разбора.
        case .bitrix24:
            path = "/\(token)/tasks.task.list"
            queryItems = []
        }
        guard var components = URLComponents(
            string: service.host(secondary: secondary) + path) else {
            throw TrackerError.unreadable(service)
        }
        // URLComponents treats the user's words as one value. In contrast,
        // `.urlQueryAllowed` leaves `&` and `=` untouched and lets a task title
        // silently become extra API parameters.
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else { throw TrackerError.unreadable(service) }
        return url
    }

    // MARK: - Завести задачу

    /// Заводит задачу в трекере и возвращает её — с ключом и ссылкой, чтобы
    /// человек мог сразу открыть, что получилось.
    ///
    /// Отдельно от `search`: чтение можно повторить, запись — нет. Поэтому тут
    /// нет мягкого разбора «ну хоть что-то»: если ответ непонятен, это ошибка,
    /// а не пустой результат. Молча «завести» задачу, которой нет, — худшее,
    /// что может сделать кнопка после звонка.
    public func createIssue(title: String, description: String? = nil) async throws -> Issue {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty,
              !(service.needsSecondary && (secondary ?? "").isEmpty),
              !(service.needsDestination && (destination ?? "").isEmpty),
              !trimmed.isEmpty
        else { throw TrackerError.notConfigured(service) }

        var request = URLRequest(url: try createEndpoint())
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        for (field, value) in headers() { request.setValue(value, forHTTPHeaderField: field) }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try createBody(title: trimmed, description: description)

        let (data, response) = try await http(request)
        switch response.statusCode {
        case 200...299: break
        case 401, 403:  throw TrackerError.unauthorised(service)
        default:        throw TrackerError.http(service, response.statusCode)
        }
        return try parseCreated(data)
    }

    func createEndpoint() throws -> URL {
        let path: String
        switch service {
        case .yandexTracker: path = "/issues/"
        case .kaiten:        path = "/cards"
        case .yougile:       path = "/tasks"
        case .weeek:         path = "/tm/tasks"
        case .bitrix24:      path = "/\(token)/tasks.task.add"
        }
        guard let url = URL(string: service.host(secondary: secondary) + path) else {
            throw TrackerError.unreadable(service)
        }
        return url
    }

    /// Тело — по документации вендора, с обязательными полями и без лишних.
    func createBody(title: String, description: String?) throws -> Data {
        let place = destination ?? ""
        var payload: [String: Any]
        switch service {
        case .yandexTracker:
            payload = ["summary": title, "queue": place]
            if let description { payload["description"] = description }
        case .kaiten:
            // board_id — целое. Строка тут даёт 400, а сообщение об этом
            // приходит на английском и посреди звонка.
            //
            // Раньше стояло `Int(place) ?? 0`, и это была тихая подмена: поле
            // доски в настройках — обычная строка, подсказка «номер доски,
            // например 4» ничего не проверяет, и человек, вписавший НАЗВАНИЕ
            // доски, отправлял в чужой трекер запись с доской номер ноль. Для
            // чтения такая подмена стоила бы пустой выдачи, для записи — 400
            // посреди звонка или карточки не там, где ждали.
            guard let board = Int(place.trimmingCharacters(in: .whitespaces)) else {
                throw TrackerError.notConfigured(service)
            }
            payload = ["title": title, "board_id": board]
            if let description { payload["description"] = description }
        case .yougile:
            payload = ["title": title, "columnId": place]
            if let description { payload["description"] = description }
        case .weeek:
            // WEEEK requires at least one location. The project id is numeric;
            // replacing an invalid value with zero could file the task nowhere
            // (or into an unintended project), so reject it before the network.
            guard let project = Int(place.trimmingCharacters(in: .whitespaces)) else {
                throw TrackerError.notConfigured(service)
            }
            payload = ["title": title, "locations": [["projectId": project]]]
            if let description { payload["description"] = description }
        case .bitrix24:
            // Задача без ответственного в Битриксе не заводится, поэтому
            // третье поле здесь — номер человека, а не доски или колонки.
            // Строка вместо номера даёт ту же тихую подмену, что стоила
            // Kaiten доски номер ноль, — отсюда та же проверка.
            guard let responsible = Int(place.trimmingCharacters(in: .whitespaces)) else {
                throw TrackerError.notConfigured(service)
            }
            var fields: [String: Any] = ["TITLE": title, "RESPONSIBLE_ID": responsible]
            if let description { fields["DESCRIPTION"] = description }
            payload = ["fields": fields]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            throw TrackerError.unreadable(service)
        }
        return data
    }

    /// Ответ на создание: ключ и ссылка. У Яндекса это `key` (`TREK-42`), у
    /// остальных числовой `id`.
    func parseCreated(_ data: Data) throws -> Issue {
        guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw TrackerError.unreadable(service) }
        try rejectVendorFailure(envelope)

        let object: [String: Any]
        if service == .weeek {
            guard envelope["success"] as? Bool == true,
                  let task = envelope["task"] as? [String: Any] else {
                throw TrackerError.unreadable(service)
            }
            object = task
        } else {
            object = envelope
        }
        let key = (object["key"] as? String) ?? (object["id"].map { "\($0)" }) ?? ""
        guard !key.isEmpty else { throw TrackerError.unreadable(service) }
        let title = (object["summary"] as? String) ?? (object["title"] as? String) ?? ""
        return Issue(key: key, title: title, url: issueURL(key: key, raw: object))
    }

    /// Ссылка из ответа сервиса — или её отсутствие.
    ///
    /// Пустую строку в `URL(string:)` подставлять нельзя, и это не мелочь: на
    /// Apple такой вызов возвращает nil, а в swift-corelibs-foundation —
    /// непустой URL, указывающий в никуда. Задача без ссылки выглядела бы
    /// задачей со ссылкой, и человек нажимал бы на пустоту. Разница поймана
    /// прогоном набора на Linux 2026-08-17, а не рассуждением.
    static func link(_ value: Any?) -> URL? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return URL(string: text)
    }

    private func issueURL(key: String, raw: [String: Any]) -> URL? {
        if let url = Self.link(raw["url"]) { return url }
        switch service {
        case .yandexTracker: return URL(string: "https://tracker.yandex.ru/\(key)")
        case .kaiten:
            let host = service.host(secondary: secondary)
                .replacingOccurrences(of: "/api/latest", with: "")
            return URL(string: "\(host)/ticket/\(key)")
        case .yougile: return nil
        case .weeek: return nil
        case .bitrix24:
            let portal = service.host(secondary: secondary)
                .replacingOccurrences(of: "/rest", with: "")
            return URL(string: "\(portal)/company/personal/user/1/tasks/task/view/\(key)/")
        }
    }

    /// Тело запроса — только там, где вендор требует POST. nil значит GET.
    func body(for query: String, limit: Int) throws -> Data? {
        switch service {
        case .yandexTracker:
            // `query` — язык запросов Трекера; текст в кавычках ищется по
            // сводке и описанию.
            let escaped = query.replacingOccurrences(of: "\"", with: "'")
            let payload = ["query": "Summary: \"\(escaped)\""]
            guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
                throw TrackerError.unreadable(service)
            }
            return data
        case .kaiten, .yougile, .weeek:
            return nil
        case .bitrix24:
            // Документация метода: TITLE ищется по шаблону, где `%` и `_` —
            // подстановочные знаки, и они ставятся В ЗНАЧЕНИЕ, а не приставкой
            // к имени поля. Приставка `%TITLE` — общий приём Битрикса, но для
            // этого метода он в документации не показан, поэтому здесь ровно
            // то, что описано.
            //
            // Размер страницы всегда пятьдесят и параметром не задаётся —
            // `limit` поэтому применяется после разбора, а не тут.
            let payload: [String: Any] = [
                "filter": ["TITLE": "%\(query)%"],
                "select": ["ID", "TITLE", "STATUS"],
                "start": 0,
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
                throw TrackerError.unreadable(service)
            }
            return data
        }
    }

    /// Разбор ответа. У каждого сервиса свои имена полей, поэтому разбираем
    /// мягко: задача без заголовка — это задача без заголовка, а не сбой всего
    /// списка. Тот же принцип, что в архиве: один битый элемент не уносит
    /// остальные.
    func parse(_ data: Data) throws -> [Issue] {
        let root = try? JSONSerialization.jsonObject(with: data)
        // Проверяется до разбора списка: у Битрикса отказ приезжает с кодом
        // 200, и если сначала искать задачи, отказ станет пустой выдачей.
        if let object = root as? [String: Any] {
            try rejectVendorFailure(object)
            if service == .weeek, object["success"] as? Bool != true {
                throw TrackerError.unreadable(service)
            }
        }
        let rows: [[String: Any]]
        if let array = root as? [[String: Any]] {
            rows = array
        } else if let object = root as? [String: Any] {
            // Битрикс кладёт список на этаж глубже: {"result": {"tasks": []}}.
            // Разворачиваем `result` до поиска ключей, иначе выдача пустая, а
            // ответ при этом совершенно исправный.
            let unwrapped = (object["result"] as? [String: Any]) ?? object
            // YouGile отдаёт список под "content", Яндекс — массивом,
            // Kaiten — массивом; "tasks"/"data" оставлены на случай смены формы.
            // Ни одного знакомого ключа — это не «задач нет», а «мы не поняли
            // ответ». Пустой список сказал бы человеку, что в трекере ничего
            // не нашлось, хотя правда в том, что спросить не получилось.
            //
            // Так устроены остальные четыре семейства коннекторов: у заметок
            // и своих серверов на неожиданную форму стоит `throw`, и у
            // GitHub отдельно ловится конверт ошибки. Здесь эта же дисциплина
            // держалась на `?? []` — то есть не держалась.
            //
            // Пустая выдача остаётся пустой выдачей: `{"content": []}` и
            // `[]` — знакомая форма с нулём строк, и они проходят.
            guard let list = (unwrapped["content"] as? [[String: Any]])
                ?? (unwrapped["tasks"] as? [[String: Any]])
                ?? (unwrapped["data"] as? [[String: Any]])
                ?? (object["result"] as? [[String: Any]]) else {
                throw TrackerError.unreadable(service)
            }
            rows = list
        } else {
            throw TrackerError.unreadable(service)
        }

        let items: [Issue] = rows.compactMap { row in
            // Битрикс отдаёт поля прописными: ID, TITLE. Строчные варианты
            // остаются первыми — у четырёх остальных сервисов они и приходят.
            let key = (row["key"] as? String)
                ?? (row["id"].map { "\($0)" })
                ?? (row["ID"].map { "\($0)" })
                ?? ""
            let title = (row["summary"] as? String)
                ?? (row["title"] as? String)
                ?? (row["name"] as? String)
                ?? (row["TITLE"] as? String)
                ?? "Без названия"
            guard !key.isEmpty else { return nil }
            return Issue(key: key, title: title, url: Self.link(row["url"]))
        }
        // Строки пришли, а прочитать не удалось ни одну — это смена формата, а
        // не пустая выдача. То же правило, что в движке манифестов: разбор,
        // написанный руками, ошибается ровно так же, и «ничего не нашлось»
        // здесь было бы враньём на каждый вопрос.
        if items.isEmpty && !rows.isEmpty { throw TrackerError.unreadable(service) }
        return items
    }

    /// Some APIs return a syntactically successful envelope with a vendor-level
    /// failure. Treating it as an empty task list would invite duplicate work.
    private func rejectVendorFailure(_ object: [String: Any]) throws {
        let successIsFalse = object["success"] as? Bool == false
        guard object["error"] != nil || successIsFalse else { return }

        let code: String
        let description: String
        if let error = object["error"] as? String {
            code = error
            description = (object["error_description"] as? String)
                ?? (object["message"] as? String) ?? ""
        } else if let error = object["error"] as? [String: Any] {
            code = (error["code"] as? String) ?? "vendor_error"
            description = (error["message"] as? String)
                ?? (error["description"] as? String) ?? ""
        } else {
            code = "success_false"
            description = (object["message"] as? String) ?? ""
        }
        throw TrackerError.vendor(service, code: code, description: description)
    }
}
