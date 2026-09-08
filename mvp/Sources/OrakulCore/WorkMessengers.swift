import Foundation
// URLRequest, URLSession и HTTPURLResponse на Linux и Windows лежат не в
// Foundation, а в FoundationNetworking: swift-corelibs-foundation разнёс их по
// разным модулям. Без этой строки ядро не собирается вне Apple — и `PortabilityTests`
// этого не видел, потому что читает импорты, а не собирает код.
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Поиск по рабочим мессенджерам — российским и открытым.
///
/// Зачем отдельно от `RussianTrackers`: у трекера ищут задачу, у мессенджера —
/// сказанное. На звонке это разные вопросы («мы это уже заводили?» и «мы это
/// уже обсуждали?»), и ответ на второй чаще лежит в переписке.
///
/// **Почему эти три.** Каждый адрес взят из документации вендора и сверен с её
/// исходником 2026-08-12, а не угадан:
///
///   * **Пачка** — российская. `GET /search/messages` с параметром `query`,
///     полнотекстовый поиск сразу по всем чатам. Проверено по `openapi.yaml`.
///   * **Mattermost** — открытый, у многих российских команд стоит на своём
///     сервере. `POST /api/v4/teams/{team_id}/posts/search`, тело
///     `{"terms": …, "is_or_search": false}`.
///   * **Zulip** — открытый. `GET /api/v1/messages` с «сужением»
///     `[{"operator":"search",…}]`; авторизация Basic, `почта:ключ`.
///   * **Matrix / Element** — открытый стандарт.
///     `POST /_matrix/client/v3/search`, тело с `search_categories.room_events`.
///   * **Rocket.Chat** — открытый, тоже на своём сервере.
///     `GET /api/v1/chat.search` — но ищет **в одной комнате**, поэтому у него
///     обязательно третье поле. Это не наша прихоть: `roomId` обязателен по
///     документации.
///
/// **Кого здесь нет и почему.** Telegram — Bot API не отдаёт историю чата и не
/// умеет по ней искать, поэтому он реализован отдельным потоком: приложение
/// получает новые сообщения после подключения и ищет в локальном архиве.
/// Этот тип описывает только серверы с настоящим API поиска.
///
/// HTTP приходит снаружи: тест, который ходит в чужой мессенджер, проверяет
/// чужой мессенджер, а не наш код.
public struct WorkMessengers {

    public typealias HTTP = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    /// Настоящая сеть — для приложения. Значение по умолчанию не задано
    /// намеренно: забытый аргумент в тесте молча пошёл бы в чужой сервис.
    public static let live: HTTP = { request in
        // Общая сессия с запретом уводить токен на чужой хост: `URLSession`
        // по умолчанию идёт по перенаправлению сама и уносит `Authorization`
        // туда, куда укажет сервис. См. ConnectorSession.
        return try await ConnectorSession.send(request)
    }

    public enum Service: String, CaseIterable, Sendable {
        case pachca, mattermost, rocketChat, zulip, matrix, slack

        public var title: String {
            switch self {
            case .pachca:     return "Пачка"
            case .mattermost: return "Mattermost"
            case .rocketChat: return "Rocket.Chat"
            case .slack:      return "Slack"
            case .zulip:      return "Zulip"
            case .matrix:     return "Matrix / Element"
            }
        }

        /// Что человек должен раздобыть у себя, чтобы подключение заработало.
        public var credentialHint: String {
            switch self {
            case .slack:
                // Прямо здесь, а не мелким шрифтом: это единственное место,
                // где человек решает, отдавать ли доступ ко всей переписке.
                return "A PERSONAL user token with the search:read scope. Slack does not allow message search from a bot, so the token reaches everything you can see, direct messages included. orakul discards direct messages and private channels before anything reaches a hint, but the token itself is issued for everything"
            case .pachca:
                return "A personal token from Automations → API with the search:messages right"
            case .mattermost:
                return "A personal access token from your profile, plus your server address"
            case .rocketChat:
                return "The token and your user id from your profile, separated by a colon"
            case .zulip:
                return "Your email and API key from settings, separated by a colon, plus your server address"
            case .matrix:
                return "An access token from Settings → Help in Element, plus your server address"
            }
        }

        /// Второе поле. У Пачки его нет — облако одно; у сервисов, которые
        /// поднимают сами, адрес свой у каждой команды.
        public var secondaryPrompt: String? {
            switch self {
            case .pachca:     return nil
            // Slack облачный: адрес один и тот же, спрашивать нечего.
            case .slack:      return nil
            case .mattermost: return "server address, for example chat.company.ru"
            case .rocketChat: return "server address, for example chat.company.ru"
            case .zulip:      return "server address, for example zulip.company.ru"
            case .matrix:     return "server address, for example matrix.company.ru"
            }
        }

        public var needsSecondary: Bool { secondaryPrompt != nil }

        /// Третье поле — где искать.
        ///
        /// Mattermost ищет по команде (`team_id`), Rocket.Chat — по одной
        /// комнате (`roomId`); оба параметра обязательны по документации.
        /// Пачка ищет по всем чатам сразу, и спрашивать её не о чем.
        public var scopePrompt: String? {
            switch self {
            case .pachca:     return nil
            // Slack ищет по всей доступной человеку переписке сразу; сузить
            // область нечем, и поэтому лишнее отбрасывается уже в выдаче.
            case .slack:      return nil
            case .mattermost: return "the team id (team_id)"
            case .rocketChat: return "the room id (roomId)"
            // Zulip и Matrix ищут по всему, что видит человек: сужать не нужно.
            case .zulip:      return nil
            case .matrix:     return nil
            }
        }

        public var needsScope: Bool { scopePrompt != nil }

        /// Второе значение внутри поля токена. У Rocket.Chat это
        /// идентификатор пользователя, у Zulip — почта перед ключом; одного
        /// значения сервер не принимает.
        ///
        /// Держать это здесь обязательно: на неполную пару сервер отвечает тем
        /// же 401, что и на протухший ключ, и без проверки orakul советовал
        /// «создайте новый токен» — то есть отправлял человека перевыпускать
        /// исправный ключ вместо того, чтобы дописать вторую половину.
        public var pairedTokenPrompt: String? {
            switch self {
            case .slack:      return nil
            case .rocketChat: return "the token and user id, separated by a colon"
            case .zulip:      return "email and API key, separated by a colon"
            case .pachca, .mattermost, .matrix: return nil
            }
        }

        public var needsPairedToken: Bool { pairedTokenPrompt != nil }

        /// Пачка живёт в облаке; у остальных адрес даёт пользователь.
        func host(secondary: String?) -> String? {
            switch self {
            case .slack:
                return "https://slack.com"
            case .pachca:
                return "https://api.pachca.com"
            case .mattermost, .rocketChat, .zulip, .matrix:
                return ConnectorAddress.normalise(secondary)
            }
        }
    }

    public enum ConnectorError: Error, Equatable, LocalizedError {
        case notConfigured
        case unauthorised
        /// Пачка отличает неверный токен (401) от исправного токена без права
        /// поиска (403). Совет перевыпустить такой токен скрывает настоящую причину.
        case missingScope(String)
        case forbidden
        /// Пара значений в одном поле, а вписано одно. Отдельно от
        /// `unauthorised`: сервер отвечает на это тем же 401, и общий текст
        /// советовал перевыпустить исправный токен.
        case incompleteToken(String)
        /// Сервер ответил, но ошибкой. Отдельно от `unreadable`:
        /// 502 от обратного прокси — это живой сервер и внятный
        /// ответ, а прежний текст советовал проверить ВЕРСИЮ, то
        /// есть отправлял человека не туда.
        /// Сервис просит подождать: 429. Чинить нечего, надо переждать.
        case rateLimited(retryAfter: Int?)
        /// Ответ больше, чем бывает у поиска.
        case tooLarge(bytes: Int)
        case http(Int)
        case vendor(code: String, description: String)
        case webPage
        case unreadable

        /// По-русски и с действием.
        ///
        /// Без `LocalizedError` Swift печатает «The operation couldn’t be
        /// completed. (MeetGPT.WorkMessengers.ConnectorError error 1.)» — по-английски, с внутренним
        /// путём типа и номером случая. В приложении, где всё остальное
        /// по-русски, это видно ровно тогда, когда человеку нужна помощь.
        public var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "The messenger is not connected. Open Settings → Connected apps and paste a token."
            case .unauthorised:
                return "The messenger rejected the token. Usually it expired or carries the wrong rights — create a new one in the service itself."
            case .forbidden:
                return "The token is real, but it was never granted the message-search right. That right is granted in the app settings inside the messenger itself — a new token will not help."
            case .missingScope(let scope):
                return "The token was accepted, but it lacks the \(scope) right. Add that right in the token settings."
            case .incompleteToken(let expected):
                return "The token field needs two values: \(expected). It currently holds one — the service will refuse however many times the token is reissued."
            case .tooLarge(let bytes):
                return "The service sent back \(bytes / 1024 / 1024) MB — no search result weighs that much. We will not parse it in the middle of a call."
            case .rateLimited(let retryAfter):
                let wait = retryAfter.map { " Wait \($0)s." } ?? ""
                return "The service asks for fewer requests — too many in a row.\(wait) The token is not the problem: there is no need to reissue it."
            case .http(let status):
                return "The messenger answered with error \(status). The server is up — check the address and the token's rights, and if it is a 5xx, the server itself or the proxy in front of it."
            case .vendor(let code, let description):
                let prefix = code.isEmpty ? "" : "\(code) — "
                return "The messenger refused: \(prefix)\(VendorText.forPerson(description))"
            case .webPage:
                return "A web page arrived instead of data — usually a sign-in form. The token may have expired, and on hotel or cafe networks the network itself demands a sign-in."
            case .unreadable:
                return "The messenger answered in a way we could not read. If the server is your own, check its address and version."
            }
        }

    }

    /// Одно найденное сообщение.
    public struct Hit: Equatable, Sendable {
        /// Кто написал. Сервисы отдают идентификатор, а не имя, — показываем
        /// то, что пришло, и не выдумываем.
        public let author: String?
        public let text: String
        public let service: Service
    }

    let service: Service
    let token: String
    let secondary: String?
    let scope: String?
    /// Кэш ответов. Свой по умолчанию: общий принадлежит сеансу, а сеанс —
    /// это приложение (см. ConnectorCache).
    let cache: ConnectorCache
    /// Знание про регистр идёт рядом с кэшем и по той же причине: оно про
    /// сеанс. Общий по умолчанию сюда не ставится намеренно — общий кэш
    /// однажды уже переносил ответы между наборами, идущими рядом.
    let caseMemory: ConnectorCaseMemory
    let http: HTTP

    public init(service: Service, token: String, secondary: String? = nil,
                scope: String? = nil,
                cache: ConnectorCache = ConnectorCache(),
                caseMemory: ConnectorCaseMemory = ConnectorCaseMemory(),
                http: @escaping HTTP) {
        self.service = service
        self.token = token
        self.secondary = secondary
        self.scope = scope
        self.cache = cache
        self.caseMemory = caseMemory
        self.http = http
    }

    public var isConfigured: Bool { basicsFilled && hasBothTokenHalves }

    /// Всё, кроме второй половины токена: сам токен, адрес сервера и место
    /// поиска. Отдельно от `isConfigured`, чтобы `search` мог сказать
    /// «не подключён» тому, кто ничего не вписал, и назвать недостающую
    /// половину тому, кто вписал одно значение из двух.
    var basicsFilled: Bool {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              service.host(secondary: secondary) != nil else { return false }
        guard service.needsScope else { return true }
        return !(scope?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
    }

    /// Обе половины на месте — или пара этому сервису не нужна.
    var hasBothTokenHalves: Bool {
        guard service.needsPairedToken else { return true }
        let parts = token.split(separator: ":", maxSplits: 1)
        return parts.count == 2 && parts.allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    public func search(_ query: String) async throws -> [Hit] {
        guard basicsFilled, let host = service.host(secondary: secondary) else {
            throw ConnectorError.notConfigured
        }
        guard hasBothTokenHalves else {
            throw ConnectorError.incompleteToken(service.pairedTokenPrompt ?? "")
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if let hits = try await manifestSearch(trimmed, host: host) { return hits }
        return try await legacySearch(trimmed, host: host)
    }

    /// Поиск по манифесту — для тех сервисов, что уже описаны данными.
    ///
    /// Пачка описана, остальные четыре нет, и это не «руки не дошли»: Mattermost
    /// возвращает сообщения СЛОВАРЁМ по идентификаторам, Zulip требует
    /// Basic-авторизации из двух половин, Matrix — вложенного тела, Rocket.Chat
    /// — двух заголовков сразу. Каждый из них — отдельное свойство формата, а
    /// описание обязано покрывать частый случай, не каждый (роадмап, §6.2).
    private func manifestSearch(_ query: String, host: String) async throws -> [Hit]? {
        guard let manifest = ConnectorManifest.usable()
            .first(where: { $0.id == service.rawValue })
        else { return nil }

        // Область (у Mattermost — команда) уезжает под тем именем, которым её
        // назвал САМ манифест.
        //
        // Без этого манифест с параметром в пути не работал вовсе: движок не
        // получал `team`, подстановка оставалась неразрешённой, и поиск отвечал
        // «не настроено» — при настроенном сервисе. Поймал существующий набор в
        // ту же минуту, когда манифест появился.
        //
        // Имя берётся из манифеста, а не пишется здесь: описание сервиса на то и
        // описание, чтобы код не знал заранее, как вендор зовёт свою команду.
        // ПЕРВОЕ поле, и других у мессенджера быть не может: человек
        // заполняет здесь ровно одну строку, и второе описанное поле уехало бы
        // в никуда — пустая подстановка, «не настроено» при настроенном
        // сервисе, то есть ровно тот отказ, который этот же комментарий выше
        // разбирает как уже случившийся.
        //
        // Молчаливой потери тут не будет: `messengerManifestsDeclareAtMostOneField`
        // роняет набор на манифесте с двумя полями и говорит, почему.
        var values: [String: String] = [:]
        if let field = manifest.parameters?.first, let scope, !scope.isEmpty {
            values[field.name] = scope
        }
        let connector = ManifestConnector(manifest: manifest, token: token, host: host,
                                          values: values, cache: cache, caseMemory: caseMemory, http: http)
        do {
            return try await connector.search(query).map {
                Hit(author: $0.author.isEmpty ? nil : $0.author, text: $0.title, service: service)
            }
        } catch let error as ManifestConnector.ConnectorError {
            switch error {
            case .notConfigured: throw ConnectorError.notConfigured
            case .unauthorised:  throw ConnectorError.unauthorised
            case .forbidden:
                // Право `search:messages` выдают отдельно от токена, и человеку
                // надо идти в настройки приложения, а не выпускать новый токен.
                if service == .pachca { throw ConnectorError.missingScope("search:messages") }
                // У остальных мессенджеров право называется по-своему, поэтому
                // назвать его мы не можем — но и сводить 403 к «токен не принят»
                // нельзя: совет «перевыпустите токен» на нехватку права заведомо
                // не сработает, а человек послушается и потратит вечер.
                throw ConnectorError.forbidden
            case .tooLarge(let bytes):
                throw ConnectorError.tooLarge(bytes: bytes)
            case .rateLimited(let retryAfter):
                throw ConnectorError.rateLimited(retryAfter: retryAfter)
            case .http(let code): throw ConnectorError.http(code)
            // Свои слова сервиса у этих трёх в отдельный случай не выделены:
            // их отказы приходят кодом HTTP, а не телом с флагом. Если такой
            // сервис появится, ветку надо будет раскрыть, а не оставить общей.
            // Slack объявляет requireTrue: ["ok"] and errorCode: ["error"], то есть
            // отказывает телом с кодом 200: «invalid_auth», «not_in_channel».
            case .vendor(let code, let description):
                throw ConnectorError.vendor(code: code, description: description)
            case .webPage:       throw ConnectorError.webPage
            case .unreadable:    throw ConnectorError.unreadable
            }
        }
    }

    /// Написанный руками путь — запас и эталон для сверки, см. `SelfHostedTrackers`.
    func legacySearch(_ query: String, host: String) async throws -> [Hit] {
        let trimmed = query
        var request = try makeRequest(host: host, query: trimmed)
        request.timeoutInterval = 8

        let (data, response) = try await http(request)
        if response.statusCode == 401 {
            throw ConnectorError.unauthorised
        }
        if response.statusCode == 403 {
            if service == .pachca { throw ConnectorError.missingScope("search:messages") }
            throw ConnectorError.unauthorised
        }
        // Всё прочее, кроме успеха, — ошибка сервера, а не мусор в
        // ответе. Раньше сюда проваливались 404, 500 и 502, и разбор
        // JSON объявлял их «непонятным ответом».
        guard (200..<300).contains(response.statusCode) else {
            throw ConnectorError.http(response.statusCode)
        }
        return try parse(data)
    }

    private func makeRequest(host: String, query: String) throws -> URLRequest {
        let place = scope?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch service {
        // Запасного пути у Slack нет и не будет: он описан манифестом сразу.
        // Пропавшее описание — поломка сборки, а не повод сказать человеку
        // «сервис недоступен».
        case .slack: throw ConnectorError.unreadable
        case .pachca:
            var components = URLComponents(string: "\(host)/api/shared/v1/search/messages")
            components?.queryItems = [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "limit", value: "10"),
                URLQueryItem(name: "sort", value: "created_at"),
                URLQueryItem(name: "order", value: "desc"),
            ]
            guard let url = components?.url else { throw ConnectorError.notConfigured }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return request

        case .mattermost:
            guard let url = URL(string: "\(host)/api/v4/teams/\(place)/posts/search") else {
                throw ConnectorError.notConfigured
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            // `is_or_search: false` — это И, а не ИЛИ. При ИЛИ выдача забивается
            // сообщениями, где совпало одно случайное слово, а подсказка из
            // случайных сообщений хуже пустой.
            request.httpBody = try? JSONSerialization.data(
                withJSONObject: ["terms": query, "is_or_search": false])
            return request

        case .zulip:
            // Zulip ищет через «сужение» — список фильтров в JSON. Оператор
            // `search` и есть полнотекстовый поиск по содержимому сообщений.
            let narrow = #"[{"operator":"search","operand":"\#(query)"}]"#
            var components = URLComponents(string: "\(host)/api/v1/messages")
            components?.queryItems = [
                URLQueryItem(name: "anchor", value: "newest"),
                URLQueryItem(name: "num_before", value: "10"),
                URLQueryItem(name: "num_after", value: "0"),
                URLQueryItem(name: "narrow", value: narrow),
            ]
            guard let url = components?.url else { throw ConnectorError.notConfigured }
            var request = URLRequest(url: url)
            // Basic-авторизация: email and API key, separated by a colon — так у Zulip.
            let credentials = Data(token.utf8).base64EncodedString()
            request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
            return request

        case .matrix:
            // Полнотекстовый поиск по событиям комнат. Тело вложенное: сервер
            // умеет искать в нескольких «категориях», нам нужна одна.
            guard let url = URL(string: "\(host)/_matrix/client/v3/search") else {
                throw ConnectorError.notConfigured
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: [
                "search_categories": [
                    "room_events": [
                        "search_term": query,
                        // По свежести, а не по релевантности: на звонке важнее
                        // «когда решили», чем «где слово встретилось чаще».
                        "order_by": "recent",
                    ],
                ],
            ])
            return request

        case .rocketChat:
            var components = URLComponents(string: "\(host)/api/v1/chat.search")
            components?.queryItems = [
                URLQueryItem(name: "roomId", value: place),
                URLQueryItem(name: "searchText", value: query),
                URLQueryItem(name: "count", value: "10"),
            ]
            guard let url = components?.url else { throw ConnectorError.notConfigured }
            var request = URLRequest(url: url)
            // Единственный из трёх, кому нужны ДВА значения: токен и
            // идентификатор пользователя. Одного токена мало, поэтому они
            // хранятся в одном поле через двоеточие — четвёртая строка в
            // настройках гарантированно осталась бы незаполненной.
            let parts = token.split(separator: ":", maxSplits: 1)
            request.setValue(String(parts.first ?? ""), forHTTPHeaderField: "X-Auth-Token")
            request.setValue(parts.count == 2 ? String(parts[1]) : "",
                             forHTTPHeaderField: "X-User-Id")
            return request
        }
    }

    private func parse(_ data: Data) throws -> [Hit] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConnectorError.unreadable
        }
        switch service {
        // Разбор у Slack тоже в манифесте — см. makeRequest выше.
        case .slack: throw ConnectorError.unreadable
        case .pachca:
            // `{ "data": [Message], "meta": … }`. Поля Message обязательны по
            // спецификации: id, chat_id, content, user_id, created_at.
            guard let rows = root["data"] as? [[String: Any]] else {
                throw ConnectorError.unreadable
            }
            return rows.compactMap { row in
                guard let text = row["content"] as? String, !text.isEmpty else { return nil }
                let author = (row["user_id"] as? Int).map(String.init)
                return Hit(author: author, text: text, service: .pachca)
            }

        case .mattermost:
            // `{ "order": [id], "posts": { id: Post } }`. Порядок берётся из
            // `order`: словарь `posts` неупорядочен, и без него выдача каждый
            // раз приходила бы в новом порядке.
            guard let posts = root["posts"] as? [String: Any] else {
                throw ConnectorError.unreadable
            }
            let order = (root["order"] as? [String]) ?? Array(posts.keys)
            return order.compactMap { id in
                guard let post = posts[id] as? [String: Any],
                      let text = post["message"] as? String, !text.isEmpty else { return nil }
                return Hit(author: post["user_id"] as? String, text: text, service: .mattermost)
            }

        case .zulip:
            // `{ "messages": [ { content, sender_full_name } ], "result": "success" }`.
            guard let rows = root["messages"] as? [[String: Any]] else {
                throw ConnectorError.unreadable
            }
            return rows.compactMap { row in
                guard let text = row["content"] as? String, !text.isEmpty else { return nil }
                return Hit(author: row["sender_full_name"] as? String,
                           text: text, service: .zulip)
            }

        case .matrix:
            // `{ search_categories: { room_events: { results: [ { result: {
            //    content: { body }, sender } } ] } } }` — вложенность родная,
            // не наша: сервер умеет искать в нескольких категориях сразу.
            guard let categories = root["search_categories"] as? [String: Any],
                  let events = categories["room_events"] as? [String: Any],
                  let rows = events["results"] as? [[String: Any]] else {
                throw ConnectorError.unreadable
            }
            return rows.compactMap { row in
                guard let result = row["result"] as? [String: Any],
                      let content = result["content"] as? [String: Any],
                      let text = content["body"] as? String, !text.isEmpty else { return nil }
                return Hit(author: result["sender"] as? String, text: text, service: .matrix)
            }

        case .rocketChat:
            // `{ "messages": [ { msg, u: { username } } ], "success": true }`.
            guard let rows = root["messages"] as? [[String: Any]] else {
                throw ConnectorError.unreadable
            }
            return rows.compactMap { row in
                guard let text = row["msg"] as? String, !text.isEmpty else { return nil }
                let author = (row["u"] as? [String: Any])?["username"] as? String
                return Hit(author: author, text: text, service: .rocketChat)
            }
        }
    }
}
