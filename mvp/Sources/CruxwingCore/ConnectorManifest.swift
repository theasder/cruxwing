import Foundation

/// Коннектор, описанный данными: метод, адрес, параметр поиска, форма ответа.
///
/// Зачем это существует. Рынок трекеров здесь раздроблен (план, §2), значит
/// коннекторов всегда будет не хватать. Сегодня каждый — файл на Swift, и
/// добавить его может только тот, кто собирает macOS-проект. А проверить ответ
/// сервиса может только тот, у кого есть аккаунт в этом сервисе. Это разные
/// люди, и пересекаются они редко.
///
/// Описание данными убирает первое требование, не трогая второе: аккаунт
/// по-прежнему нужен, Mac — уже нет.
///
/// Чего описание НЕ отменяет: правило «не заявляйте того, чего нет». Поле
/// `docs` обязательно и проверяется при разборе — манифест без ссылки на
/// документацию вендора не загружается вовсе. Тот же гейт, что в форме «Новый
/// коннектор», только исполняемый.
///
/// Чего оно не покрывает: сервисы, которым нужен не запрос, а протокол —
/// Битрикс24 с ключом внутри пути, Matrix с телом запроса, MCP с регистрацией
/// клиента. Они остаются кодом, и это нормально: описание обязано покрывать
/// частый случай, а не каждый.
public struct ConnectorManifest: Decodable, Equatable, Sendable {

    public struct Parameter: Decodable, Equatable, Sendable {
        public let name: String
        public let value: String
    }

    public struct Request: Decodable, Equatable, Sendable {
        public let method: String
        public let path: String
        public let query: [Parameter]
        public let headers: [Parameter]
        /// Тело запроса — шаблон JSON строкой, а не объектом.
        ///
        /// Строкой намеренно: у RPC-сервисов вроде Outline поиск это
        /// `POST {"query": "…", "limit": 10}`, и разница между `"10"` и `10`
        /// для них существенна. Шаблон, где кавычки ставит автор манифеста,
        /// сохраняет её; объект в модели пришлось бы описывать типом значения
        /// и всё равно собирать обратно.
        public let body: String?
    }

    /// Условие на строку ответа: путь и значение, при котором строка не берётся.
    public struct Condition: Decodable, Equatable, Sendable {
        public let path: [String]
        /// Совпадение по булеву значению — то, чем сервисы помечают приватность.
        public let equals: Bool
    }

    public struct Response: Decodable, Equatable, Sendable {
        /// Путь до массива строк. Пустой — массив лежит на верхнем уровне
        /// (GitLab, Gitea); `["results"]` — завёрнут (Redmine).
        public let list: [String]
        /// Путь до порядка строк, когда сами строки лежат СЛОВАРЁМ по
        /// идентификатору, а не массивом.
        ///
        /// Так отвечает Mattermost: `{"order": ["id2","id1"], "posts": {"id1":
        /// {...}, "id2": {...}}}`. Порядок здесь — не украшение: это выдача по
        /// совпадению, и словарь в Swift неупорядочен. Разобрать `posts`
        /// значениями значит выдать человеку случайную перестановку и назвать
        /// её «что нашлось» — первым окажется что попало.
        ///
        /// Пусто у всех, кто отдаёт массив; тогда `list` работает как раньше.
        public let order: [String]?
        /// Путь до заголовка. Массив, а не ключ: у Outline он лежит в
        /// `document.title`, то есть на уровень глубже строки.
        public let title: [String]
        /// Путь до слов вокруг совпадения. Есть не у всех: трекеры отдают
        /// задачу, а вики — кусок текста, и в подсказку идёт именно он.
        public let context: [String]?
        /// Путь до автора. У мессенджеров это половина смысла: «кто сказал»
        /// отвечает на вопрос не хуже, чем «что сказано».
        ///
        /// Значение бывает и числом: Пачка отдаёт `user_id` целым, а Mattermost
        /// — строкой. Разбор терпит оба, иначе манифест пришлось бы дополнять
        /// типом поля, а это описание формата, а не сервиса.
        public let author: [String]?
        /// Имена, под которыми может лежать номер, по порядку.
        public let key: [String]
        /// Путь до состояния. В ответе может отсутствовать — тогда пусто, и это
        /// не ошибка: Redmine состояния в поиске не отдаёт вовсе.
        ///
        /// Путь, а не ключ: Plane отдаёт `state: {id, name, group}`, то есть
        /// состояние лежит на уровень глубже строки. Ключом это описать нельзя,
        /// а «показать пусто» означало бы потерять половину смысла выдачи —
        /// «сделано» и «в работе» отвечают на вопрос по-разному.
        public let state: [String]
        /// Флаг успеха в теле ответа, если сервис им пользуется.
        ///
        /// Не всякий сервис говорит об отказе кодом HTTP: WEEEK и Битрикс24
        /// отвечают 200 и кладут отказ в тело (`"success": false`). Коннектор,
        /// который смотрит только на код, покажет отозванный токен как «задач
        /// не нашлось», и человек заведёт вторую задачу поверх существующей.
        /// Это правило §2.2 плана, пункт 5.1, — здесь оно выражается данными.
        public let requireTrue: [String]?
        /// Где сервис пишет СВОИ слова об отказе.
        ///
        /// Без этого отказ пересказывается нашим «сервис ответил непонятным
        /// образом», и человек теряет единственное, что объясняет причину:
        /// «invalid_token — Token revoked» говорит, что делать, а «непонятный
        /// ответ» — нет. Правило §2.2 плана, пункт 5: ошибка пересказывает
        /// слова самого сервиса.
        public let errorCode: [String]?
        public let errorMessage: [String]?
        /// Что доказывает, что пустой ответ понят, а не не разобран.
        ///
        /// GitFlic заворачивает список в `_embedded`, и на проекте без задач
        /// этого ключа в ответе нет вовсе — так устроен Spring HATEOAS. Без
        /// этого поля правило «незнакомая форма — отказ» превращает «задач ещё
        /// нет» в «сервис ответил непонятным образом», и человек идёт чинить
        /// исправный сервер.
        ///
        /// Ослаблением правила это не является: путь обязан существовать в
        /// ответе. У GitFlic это `page.totalElements` — число, которое
        /// присылается всегда, в том числе при нуле задач. Мусор вместо ответа
        /// по-прежнему отказ.
        public let emptyMarker: [String]?
        /// Строки, которые в выдачу не берутся.
        ///
        /// Появилось ради Slack (роадмап, §7.4). Личный токен там даёт доступ
        /// ко ВСЕЙ переписке человека, включая личные сообщения, — сервис не
        /// умеет искать «только в общих каналах». Значит отбор делаем мы: всё,
        /// что помечено как личное, отбрасывается до того, как попадёт в
        /// подсказку.
        ///
        /// Это не то же самое, что не получить данные: они уже пришли в
        /// память. Обещание здесь ровно одно и оно выполнимо — до модели и до
        /// экрана личная переписка не доходит. Так и написано в настройках.
        public let skipWhen: [Condition]?

        /// Убрать разметку из заголовка и слов вокруг совпадения.
        ///
        /// BookStack подсвечивает найденное `<strong>` прямо в тексте: в ответ
        /// человеку это приехало бы как «…once a bunch of <strong>cats</strong>
        /// named tony…». Подсказка на звонке читается вслух, а не в браузере.
        ///
        /// Только там, где сервис сам присылает HTML, и только для двух полей:
        /// снимать теги со всего подряд значило бы портить содержимое, которое
        /// пришло без разметки и с угловыми скобками по делу.
        public let stripTags: Bool?
    }

    /// Что человек подставляет в адрес сам.
    ///
    /// Хоста и токена хватает не всем: у Plane задачи лежат по адресу
    /// `/workspaces/{workspace}/projects/{project}/work-items/`, и обе части
    /// знает только владелец аккаунта. Раньше такой сервис был неописуем —
    /// приходилось писать коннектор кодом.
    public struct Field: Decodable, Equatable, Sendable {
        public let name: String
        /// Как назвать это поле человеку. Не `workspace_slug`, а «Пространство».
        public let title: String
        /// Пример значения — короче любого объяснения формата.
        public let example: String
    }

    /// Перечисление вместо поиска — с границей и с обязанностью сказать об этом.
    ///
    /// Решение §7.2 дорожной карты, принято 2026-08-18. До него правило было
    /// одно: нет параметра поиска — нет коннектора. Оно закрыло Pyrus и Яндекс
    /// Вики правильно (у них нет и перечисления), но заодно закрыло Plane,
    /// GitFlic и GitVerse, у которых список задач документирован, а поиска по
    /// слову в документации нет.
    ///
    /// Что изменилось: перечисление принимается, если выполнены три условия, и
    /// все три проверяются кодом, а не обещанием автора манифеста.
    ///
    ///   1. **Граница объявлена.** `pages` × `perPage` строк, не больше;
    ///      потолок держит движок (`ManifestConnector.scanPageLimit`).
    ///   2. **Отбор описан.** `match` перечисляет поля, по которым слово
    ///      ищется у нас. Пустой список — манифест не грузится.
    ///   3. **Охват уезжает вместе с выдачей.** Движок отдаёт `Coverage`, и
    ///      «ничего не нашлось» отличается от «не нашлось среди последних 500
    ///      из 40 000». Второе — другой ответ, и человек имеет право его
    ///      увидеть: ошибка «десять задач из сорока семи» (план, §4) случилась
    ///      ровно потому, что часть выдачи выдали за целое.
    public struct Scan: Decodable, Equatable, Sendable {
        public let pages: Int
        public let perPage: Int
        /// Параметры страницы. `{page}` — номер с нуля, `{perPage}` — размер.
        public let page: [Parameter]
        /// Поля, по которым слово ищется у нас. Пути, а не ключи: заголовок
        /// бывает вложенным.
        public let match: [[String]]
        /// Где сервис говорит, что дальше есть ещё. Без этого поля движок
        /// считает страницу последней, если она пришла короче `perPage`.
        public let more: [String]?
        /// Где сервис называет полный размер списка. Если называет — число
        /// уезжает человеку: «среди последних 500 из 40 000» честнее, чем
        /// «среди последних 500».
        public let total: [String]?
    }

    public let id: String
    public let title: String
    /// Ссылка на документацию вендора. Обязательна.
    public let docs: String
    /// Когда описание проверяли на РАБОТАЮЩЕМ сервисе, а не по документации.
    ///
    /// Полем, а не словом в примечании: перечень §2.2 отмечает такие сервисы
    /// жирным, и проверка искала в примечании слово «живом». У GitLab там
    /// стояло «на поднятом у себя», и проверка молча его пропускала — сильное
    /// утверждение держалось на выборе слова в прозе.
    public let liveCheckedOn: String?
    /// Когда её читали. «Проверено» стареет, и читатель вправе знать, насколько.
    public let verifiedOn: String
    public let note: String?
    public let request: Request
    public let response: Response
    /// Поля, которые заполняет человек. Пусто у большинства сервисов.
    public let parameters: [Field]?
    /// Есть — значит, сервис не ищет, а перечисляет, и отбор делаем мы.
    public let scan: Scan?
    /// Чем сервис обозначает «слово начинается с», если он это умеет.
    ///
    /// Третий вопрос коннектора — основой: человек сказал «тарифы», в чужой
    /// базе лежит «тарифами». У сервиса, ищущего по вхождению, основа находит
    /// оба написания сама. Сервис, сравнивающий слова ЦЕЛИКОМ, по основе не
    /// находит ничего — и там, где вендор описал знак подстановки, основе
    /// нужен он.
    ///
    /// Полем, а не догадкой движка: знак у каждого свой, и у BookStack его
    /// нет вовсе — «тариф*» вернул там ноль, это измерено. Приписывать
    /// звёздочку всем значило бы чинить один сервис и ломать другой.
    public let stemSuffix: String?

    public enum ManifestError: Error, Equatable, CustomStringConvertible {
        case missingDocumentation(String)
        case noSearchParameter(String)
        case unboundedScan(String)
        case scanWithoutMatch(String)
        case unknownPlaceholder(String, String)
        case secretInAddress(String, String)
        case unreadable(String)

        public var description: String {
            switch self {
            case .missingDocumentation(let id):
                return "Manifest «\(id)» has no link to the vendor documentation. The method, address, search parameter and response shape are checked against it; without it a connector is a guess."
            case .noSearchParameter(let id):
                return "In manifest «\(id)» no parameter substitutes {query}, and there is no scan block either. Listing issues does not count as search until a bound and a filter are declared: filtering only the first page locally answers «nothing matched» over a full archive."
            case .unboundedScan(let id):
                return "In manifest «\(id)» the listing has no bound: pages and perPage must be at least 1, and pages no more than \(ManifestConnector.scanPageLimit). Without a ceiling the connector drains somebody else's tracker in full and still promises nothing."
            case .scanWithoutMatch(let id):
                return "Manifest «\(id)» has a scan block but never says which fields to filter on (match). A listing without a filter is a list, not a search."
            case .unknownPlaceholder(let id, let name):
                return "In manifest «\(id)» the substitution {\(name)} is unknown to anyone. It will go into the address as is, and the service will answer 404 to a request that looks correct. Declare the field in parameters, or remove the substitution."
            case .secretInAddress(let id, let where_):
                return "In manifest «\(id)» a secret sits in \(where_). The request address is visible to everyone along the way: it lands in proxy logs, in the service's own logs and in error reports, and stays there after the token is revoked. A secret travels in a header."
            case .unreadable(let name):
                return "Manifest «\(name)» could not be parsed."
            }
        }
    }

    /// Проверяет то, без чего коннектор не имеет права существовать.
    ///
    /// Обе проверки про честность, а не про формат. Первая: без документации
    /// нечем подтвердить, что метод и параметр не выдуманы. Вторая: параметр
    /// поиска обязан быть, иначе это перечисление, и оно молча врёт на большом
    /// проекте (роадмап, §7.2).
    public func validate() throws {
        guard docs.hasPrefix("http") else { throw ManifestError.missingDocumentation(id) }

        // Слово может ехать и в параметре, и в теле: у Outline поиск это
        // `POST {"query": …}`, параметров у него нет вовсе. Требование то же —
        // слово человека обязано куда-то попасть, иначе это перечисление.
        //
        // `{queryWords}` — то же слово, но очищенное от знаков, ломающих чужой
        // язык поиска: у Jira оно едет внутри выражения JQL, а не отдельным
        // параметром. Для этой проверки разницы нет — важно, что слово
        // человека доезжает. Проверка знала только `{query}` и объявила
        // манифест Jira перечислением без границы; она была права ровно в том,
        // что ничего не знала о втором способе.
        let asks = { (text: String) in
            text.contains("{query}") || text.contains("{queryWords}")
        }
        let inQuery = request.query.contains { asks($0.value) }
        let inBody = request.body.map(asks) ?? false

        if let scan {
            // Перечисление принимается только с границей и с отбором — §7.2.
            guard scan.pages >= 1, scan.perPage >= 1,
                  scan.pages <= ManifestConnector.scanPageLimit else {
                throw ManifestError.unboundedScan(id)
            }
            guard !scan.match.isEmpty, scan.match.allSatisfy({ !$0.isEmpty }) else {
                throw ManifestError.scanWithoutMatch(id)
            }
        } else {
            guard inQuery || inBody else { throw ManifestError.noSearchParameter(id) }
        }

        // Секрет не имеет права оказаться в адресе.
        //
        // Адрес — самая публичная часть запроса: он целиком пишется в журнал
        // прокси, в журнал доступа самого сервиса и в отчёты об ошибках, и
        // живёт там дольше, чем токен. Заголовок в те же журналы не попадает.
        //
        // Сегодня все четырнадцать манифестов передают секрет заголовком, и у
        // Trello это отдельное решение, записанное в его note: у сервиса
        // штатный способ — «?key=…&token=…», и вместо него взят заголовок
        // OAuth. Решение, записанное словами в одном манифесте, следующий автор
        // повторять не обязан — поэтому оно здесь, а не только там.
        for (place, texts) in [
            ("the path", [request.path]),
            ("the query parameters", request.query.flatMap { [$0.name, $0.value] }),
            ("the pagination parameters (scan.page)",
             (scan?.page ?? []).flatMap { [$0.name, $0.value] }),
        ] {
            for text in texts where text.contains("{token}") || text.contains("{basic}") {
                throw ManifestError.secretInAddress(id, place)
            }
        }

        // Подстановка, которой никто не заполнит, уходит в адрес буквально.
        // Проверяется здесь, а не при сборке запроса: на сборке это уже
        // ошибка сервиса — 404 на правильный с виду запрос.
        let declared = Set((parameters ?? []).map(\.name))
        for name in placeholders() where !declared.contains(name) {
            throw ManifestError.unknownPlaceholder(id, name)
        }
    }

    /// Имена всех подстановок манифеста, кроме тех, что заполняет движок.
    func placeholders() -> Set<String> {
        let builtin: Set<String> = ["query", "queryWords", "limit", "token", "basic", "page", "perPage",
                                    "tokenHead", "tokenTail"]
        var texts = [request.path]
        texts += request.query.flatMap { [$0.name, $0.value] }
        texts += request.headers.flatMap { [$0.name, $0.value] }
        texts += (scan?.page ?? []).flatMap { [$0.name, $0.value] }
        if let body = request.body { texts.append(body) }

        // Подстановка — это `{имя}` из букв, цифр и подчёркиваний. Скобка в
        // шаблоне тела JSON («{"query": "{query}"}») подстановкой не является,
        // и первая версия этой проверки спотыкалась ровно об неё: Outline
        // перестал загружаться, потому что его тело начинается с `{"`.
        var found = Set<String>()
        for text in texts {
            let characters = Array(text)
            var index = 0
            while index < characters.count {
                guard characters[index] == "{" else { index += 1; continue }
                var end = index + 1
                // Дефис — тоже имя. Без него `{team-id}` подстановкой не
                // считался: проверка его не видела, объявлять было нечего, и
                // фигурные скобки уезжали в адрес БУКВАЛЬНО — то есть ровно то,
                // ради чего эта проверка и написана. Сервис отвечает 404 на
                // правдоподобный с виду запрос, а человек читает «ничего не
                // нашлось». Имена с дефисом обычны: team-id, org-id, project-key.
                while end < characters.count,
                      characters[end].isLetter || characters[end].isNumber
                        || characters[end] == "_" || characters[end] == "-" {
                    end += 1
                }
                if end < characters.count, characters[end] == "}", end > index + 1 {
                    found.insert(String(characters[(index + 1)..<end]))
                    index = end + 1
                } else {
                    index += 1
                }
            }
        }
        return found.subtracting(builtin)
    }

    /// Все манифесты из ресурсов пакета, разобранные и проверенные.
    ///
    /// Порядок — по имени файла, чтобы прогон был воспроизводим: у
    /// `urls(forResourcesWithExtension:)` порядок файловой системы, а он разный
    /// на разных машинах.
    /// `Bundle.module` не может стоять значением по умолчанию: SwiftPM делает
    /// его внутренним для модуля, а функция публичная. Отсюда `nil` снаружи и
    /// подстановка внутри — разница видна только в объявлении.
    public static func bundled(in bundle: Bundle? = nil) throws -> [ConnectorManifest] {
        let bundle = bundle ?? .module
        // Каталог перечисляется руками, а не через
        // `bundle.urls(forResourcesWithExtension:subdirectory:)`: на Apple тот
        // отдаёт `[URL]`, в swift-corelibs-foundation — `[NSURL]`, и ядро на
        // Linux не собирается. По той же причине путь дальше трогается только
        // строками: `lastPathComponent` и `pathExtension` там необязательные.
        // Три разницы в одной функции — и все три видно исключительно сборкой,
        // а не чтением кода.
        guard let root = bundle.resourceURL?.appendingPathComponent("connectors") else { return [] }
        return try strict(load(from: root))
    }

    /// Строгость отдельной функцией — чтобы её можно было проверить.
    ///
    /// Пока все встроенные манифесты исправны, строгое и мягкое чтение дают
    /// одно и то же, и утверждение «строгое по-прежнему бросает» держалось на
    /// чтении кода: мутация, снявшая `throw`, набор проходила. Здесь она
    /// проверяется на подставленном разборе, а не на счастливом стечении.
    static func strict(_ loaded: Loaded) throws -> [ConnectorManifest] {
        if let failure = loaded.broken.first { throw failure.error }
        return loaded.manifests
    }

    /// Что удалось прочитать — и что не удалось, по отдельности.
    public struct Loaded: Sendable {
        public let manifests: [ConnectorManifest]
        public let broken: [(name: String, error: any Error)]
    }

    /// Чтение, которое НЕ роняет исправные описания вместе с одним негодным.
    ///
    /// `bundled()` бросает на первом же плохом файле, а все, кто зовёт его в
    /// работе, читают через `try?` — то есть один негодный манифест молча
    /// убирал ВСЕ. Каждый сервис, описанный данными, тихо возвращался на
    /// рукописный путь: без отделения 403 от 401, без узнавания страницы входа
    /// вместо данных, с угадыванием чужого конверта. Ровно те защиты, ради
    /// которых манифесты и появились, исчезали тише всего.
    ///
    /// Случилось это при добавлении Rocket.Chat: новая подстановка не была
    /// объявлена, проверка файл отвергла, а видимым симптомом стала потеря
    /// снятия разметки у Zulip — поломка за два сервиса от причины.
    ///
    /// Строгость никуда не делась: `bundled()` по-прежнему бросает, и набор
    /// держит на нём обещание «все встроенные манифесты исправны». Разница в
    /// том, что в работе исправные девятнадцать продолжают работать.
    public static func load(from directory: URL) -> Loaded {
        let urls = ((try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.absoluteString.hasSuffix(".json") }
        let decoder = JSONDecoder()
        var manifests: [ConnectorManifest] = []
        var broken: [(name: String, error: any Error)] = []
        for url in urls.sorted(by: { $0.absoluteString < $1.absoluteString }) {
            let name = url.absoluteString.split(separator: "/").last.map(String.init)
                ?? url.absoluteString
            do {
                let data = try Data(contentsOf: url)
                guard let manifest = try? decoder.decode(ConnectorManifest.self, from: data) else {
                    throw ManifestError.unreadable(name)
                }
                try manifest.validate()
                manifests.append(manifest)
            } catch {
                broken.append((name: name, error: error))
            }
        }
        return Loaded(manifests: manifests, broken: broken)
    }

    /// То же чтение для работы: исправные описания без падения на негодном.
    public static func usable(in bundle: Bundle? = nil) -> [ConnectorManifest] {
        let bundle = bundle ?? .module
        guard let root = bundle.resourceURL?.appendingPathComponent("connectors") else { return [] }
        return load(from: root).manifests
    }
}
