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
        /// Ответ больше, чем бывает у поиска.
        ///
        /// Сервису не нужно врать, чтобы навредить: достаточно ответить
        /// двумястами мегабайтами. Дальше их надо разобрать — во время живого
        /// звонка, на машине человека. Ответ на вопрос «что решили» столько не
        /// весит ни у одного сервиса; всё, что весит, — либо ошибка на их
        /// стороне, либо расчёт на нашу доверчивость.
        case tooLarge(bytes: Int)
        case http(Int)
        /// Сервис ответил отказом СВОИМИ словами — они и передаются дальше.
        case vendor(code: String, description: String)
        /// Вместо данных пришла веб-страница.
        ///
        /// Отдельно от `unreadable`, потому что чинится совсем другим. «Ответил
        /// непонятно» отправляет человека проверять адрес и версию сервера, а
        /// здесь адрес почти всегда верный: так выглядит истёкшая сессия за
        /// единым входом, портал гостиничного Wi-Fi и страница «войдите» вместо
        /// ответа API. Все три отвечают кодом 200 и страницей входа — то есть
        /// выглядят как исправная работа.
        ///
        /// Для недружелюбного сервиса это ещё и самый дешёвый способ отрезать:
        /// не отдавать 401, а показать форму входа. Формально всё в порядке.
        case webPage
        case unreadable
    }

    public struct Item: Equatable, Sendable {
        /// Номера у строки нет: у вики страница обозначается путём, а не
        /// номером. Прочерк — то, что видит человек, а не признак строки:
        /// сливать по нему две разные страницы нельзя.
        public static let noKey = "—"

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

    /// Сколько байт ответа разбирается. Восемь мегабайт — с запасом: выдача
    /// поиска у самых многословных сервисов измеряется сотнями килобайт.
    ///
    /// Проверяется и здесь, и в `ConnectorSession`: сессия закрывает
    /// коннекторы, написанные руками, а эта проверка — движок, и её видно
    /// набором, потому что подставной HTTP сессию обходит.
    public static let maximumResponseBytes = 8 * 1024 * 1024

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

    /// Кэш приходит снаружи, и по умолчанию он СВОЙ, а не общий.
    ///
    /// Общий по умолчанию — это глобальное изменяемое состояние: первый же
    /// прогон показал, как соседние проверки начали получать чужие ответы
    /// вместо запросов, которые они проверяли. Тот же капкан, что с
    /// настройками процесса, только тише.
    ///
    /// Кэш принадлежит СЕАНСУ, а не запросу: повторяется вопрос на звонке, и
    /// знает об этом приложение. Поэтому `ConnectorCache.shared` передаёт
    /// именно оно, а командная строка и наборы работают без общего кэша —
    /// одиночный вопрос кэшировать не от чего.
    let cache: ConnectorCache

    /// Знание про регистр живёт столько же, сколько кэш: сеанс. Общее по
    /// умолчанию, потому что один лишний запрос на сервис имеет смысл задать
    /// один раз, а не каждым коннектором заново. Набор передаёт своё.
    let caseMemory: ConnectorCaseMemory

    public init(manifest: ConnectorManifest,
                token: String,
                host: String,
                values: [String: String] = [:],
                cache: ConnectorCache = ConnectorCache(),
                caseMemory: ConnectorCaseMemory = ConnectorCaseMemory(),
                http: @escaping HTTP) {
        self.manifest = manifest
        self.token = token
        self.host = host
        self.values = values
        self.cache = cache
        self.caseMemory = caseMemory
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
    public func makeRequest(query: String, limit: Int, page: Int = 0,
                            suffix: String = "") throws -> URLRequest {
        guard isConfigured else { throw ConnectorError.notConfigured }
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // Путь тоже с подстановками: у Plane номер проекта стоит внутри адреса,
        // а не в параметрах.
        var components = URLComponents(
            string: trimmedHost + fill(manifest.request.path, query: query, limit: limit, page: page, suffix: suffix))
        // Пустой список — это `nil`, а не `[]`: с пустым массивом URLComponents
        // дописывает голый «?» в конец адреса. У сервисов вроде Outline
        // параметров нет вовсе, и такой хвост уходил бы в каждый запрос.
        let items = (manifest.request.query + (manifest.scan?.page ?? [])).map {
            URLQueryItem(name: $0.name,
                         value: fill($0.value, query: query, limit: limit, page: page, suffix: suffix))
        }
        components?.queryItems = items.isEmpty ? nil : items
        guard let url = components?.url else { throw ConnectorError.notConfigured }

        var request = URLRequest(url: url)
        request.httpMethod = manifest.request.method
        for header in manifest.request.headers {
            request.setValue(fill(header.value, query: query, limit: limit, page: page, suffix: suffix),
                             forHTTPHeaderField: header.name)
        }
        if let template = manifest.request.body {
            let filled = fill(template, query: escapedForJSON(query), limit: limit, suffix: suffix)
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
        // Вопрос из одних служебных знаков — не вопрос, и молчать об этом
        // дороже, чем кажется. Там, где слово уходит внутрь кавычек,
        // `text ~ ""` для чужого сервера означает «отдай всё»: он честно
        // вернул бы первые N задач, и они встали бы под вопрос, которого
        // никто не задавал.
        if quotesTheQuery, Self.words(of: trimmed).isEmpty {
            return Outcome(items: [], coverage: manifest.scan == nil ? .searched : .wholeList(scanned: 0))
        }

        // Тот же вопрос за последние полторы минуты — это тот же вопрос. На
        // звонке «что решили по срокам» спрашивают трижды за час, и три
        // одинаковых запроса к чужому серверу мы создавали сами: троттлинг,
        // на который потом жалуются, отчасти наш собственный.
        if let cached = await cache.fresh(service: manifest.id, host: host, query: trimmed) {
            return cached
        }

        do {
            let outcome: Outcome
            if let scan = manifest.scan {
                outcome = try await walk(scan, query: trimmed, limit: limit)
            } else {
                outcome = Outcome(items: try parse(try await fetch(query: trimmed, limit: limit)),
                                  coverage: .searched)
            }
            // Находки трёх вопросов складываются здесь: слово человека, оно же
            // с другой буквы, оно же основой. Ни один из трёх не отменяет
            // остальных.
            var found = outcome.items

            // Пусто по-русски — спросим тем же словом с другой буквы.
            //
            // Измерено на живых установках 2026-08-19: Redmine и Nextcloud с
            // базой по умолчанию (SQLite) сравнивают строки побайтово выше
            // ASCII, и «тарифы» не находит «Тарифы». Расшифровка отдаёт слова
            // строчными — так говорят, — поэтому на маленькой самостоятельной
            // установке половина ответов пропадала молча. Для человека это
            // выглядит не как чужая база, а как продукт, который не находит.
            //
            // Второй запрос стоит ровно там, где первый ничего не дал: на
            // обычном пути лишних обращений нет, а «ничего не нашлось» и так
            // конец разговора. Одна попытка, только при кириллице в слове.
            // Только там, где ищет САМ сервис.
            //
            // У перечисления (`scan`) отбор идёт у нас: `walk` сравнивает
            // приведённые к строчным строки, то есть регистр там уже не при чём.
            // Второй проход по десяти страницам чужого сервера не дал бы ни
            // одной новой находки и удвоил бы объявленную границу — это поймал
            // набор «страниц читается не больше объявленного», и поймал верно.
            if manifest.scan == nil, let variant = Self.caseVariant(of: trimmed) {
                let known = await caseMemory.behaviour(service: manifest.id, host: host)
                // Спрашиваем вторым написанием, когда про сервис ещё ничего не
                // знаем (узнаём) или знаем, что он сравнивает байты (иначе
                // потеряем половину). Сервису, приводящему регистр самому,
                // второй запрос не задаётся больше никогда.
                if known != .foldsCase {
                    // Ошибка второго вопроса не должна стоить первого ответа.
                    //
                    // Поймано набором: сервис ответил на первый запрос и
                    // придушил второй (429), и человек терял выдачу, которая
                    // у него уже была. Второй вопрос — это уточнение; провал
                    // уточнения означает «не узнали», а не «не нашли».
                    let second = (try? parse(try await fetch(query: variant, limit: limit))) ?? []
                    let merged = Self.merge(outcome.items, second, limit: limit)

                    if known == .unknown, !second.isEmpty || !outcome.items.isEmpty {
                        // Из двух пустых не следует ничего — так и оставляем
                        // «неизвестно», чтобы спросить в следующий раз.
                        await caseMemory.learn(merged.count > outcome.items.count
                                               ? .comparesBytes : .foldsCase,
                                               service: manifest.id, host: host)
                    }

                    // Раньше здесь стоял возврат: нашлось новое — отдаём и
                    // уходим. Из-за него сервис, сравнивающий байты, никогда
                    // не получал вопроса основой: второй вопрос у него почти
                    // всегда что-то приносит. Измерено на живых Gitea и
                    // Redmine — запись со словом «тарифами» не доезжала до
                    // человека вовсе. Ответ не должен зависеть от того, какая
                    // из двух независимых нехваток случилась первой.
                    found = merged
                }
            }

            // Слово в той форме, в какой его произнесли, — не то слово, что
            // лежит в чужой базе. Человек спрашивает «тарифы», в заметке
            // написано «тарифами», и чужой сервис по-русски не склоняет.
            //
            // Измерено на поднятом у себя BookStack 2026-08-19: «тарифы»
            // находит одну страницу из двух, «тарифами» — другую одну, а
            // основа «тариф» находит ОБЕ. Подстановочный знак, который
            // напрашивался вместо этого, не работает вовсе: «тариф*» вернул
            // ноль. Отсюда правило — спрашивать основой, а не звёздочкой.
            //
            // Основу считает тот же разбор, которым ищется по своим
            // расшифровкам: две разные морфологии на один язык разошлись бы.
            //
            // Про число обращений. Вопрос основой — третий и последний, и он
            // задаётся только тогда, когда второй ничего не принёс: если
            // другое написание нашло новое, мы уже вернули ответ выше и сюда
            // не дошли. В установившемся состоянии вопросов два: про регистр
            // сервис спрашивают, пока не узнают, а узнав — перестают.
            //
            // И спрашиваем только тогда, когда в ответе есть место: если сервис
            // уже вернул столько строк, сколько человек попросил, лишние
            // находки он всё равно не увидит, а обращение к чужому серверу
            // стоит. Так удвоение приходится на бедные ответы, а не на все.
            if manifest.scan == nil, found.count < limit,
               !(await caseMemory.stemsAreUseless(service: manifest.id, host: host)),
               !(await caseMemory.isSlowedDown(service: manifest.id, host: host)) {
                let stem = RecallIndex.searchToken(for: trimmed)
                // Порога длины здесь нет намеренно, и сначала он здесь стоял.
                // Обрубка вроде «до» от «дома» не появится: отсечение окончаний
                // само отказывается опускаться ниже четырёх букв, а второй путь
                // — словарь — возвращает словарную форму, а не обрубок. Порог
                // же резал 332 настоящих слова: «баги» → «баг», «кешам» →
                // «кеш», «sqlу» → «sql». Проверено мутацией: с порогом набор
                // проходил, потому что стеречь было нечего.
                if stem != trimmed {
                    // Как и с регистром: провал уточнения не должен стоить
                    // ответа, который у человека уже есть.
                    let third = (try? parse(try await fetch(query: stem, limit: limit,
                                                            suffix: manifest.stemSuffix ?? ""))) ?? []
                    // Основа короче слова: сервис, ищущий по вхождению, нашёл
                    // бы по ней не меньше. Пустота там, где слово целиком
                    // что-то нашло, означает поиск словами целиком — и больше
                    // основой этот сервис не беспокоим.
                    if third.isEmpty, !found.isEmpty {
                        await caseMemory.learnStemIsUseless(service: manifest.id, host: host)
                    }
                    found = Self.merge(found, third, limit: limit)
                }
            }

            let answer = found.count > outcome.items.count
                ? Outcome(items: found, coverage: outcome.coverage) : outcome
            await cache.store(answer, service: manifest.id, host: host, query: trimmed)
            return answer
        } catch ConnectorError.rateLimited(let retryAfter) {
            // Раз просят реже — перестаём спрашивать вторым написанием.
            await caseMemory.slowDown(service: manifest.id, host: host)

            // Сервис просит подождать. Выбор здесь не между свежим и старым, а
            // между старым и никаким: молчащий источник на звонке — это
            // «ничего не нашлось» в чужих словах.
            //
            // Возраст едет вместе с ответом. Подставить старую выдачу молча
            // значило бы пообещать свежесть, которой нет, — а продукт держится
            // на том, что цитата названа вместе с источником.
            guard let stale = await cache.stale(service: manifest.id, host: host, query: trimmed) else {
                throw ConnectorError.rateLimited(retryAfter: retryAfter)
            }
            return Outcome(items: stale.outcome.items,
                           coverage: .cached(seconds: stale.age, under: .service))
        }
    }

    /// Один запрос: отправить, разобрать коды, отдать байты.
    private func fetch(query: String, limit: Int, page: Int = 0,
                       suffix: String = "") async throws -> Data {
        let (data, response) = try await http(
            makeRequest(query: query, limit: limit, page: page, suffix: suffix))
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
        // Размер проверяется ДО разбора: JSONSerialization на двухстах
        // мегабайтах — это не ошибка, а зависший ответ посреди звонка.
        guard data.count <= Self.maximumResponseBytes else {
            throw ConnectorError.tooLarge(bytes: data.count)
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

        // Основа вопроса считается один раз на поиск, а не на строку: строк
        // до пятисот, и разбор на каждой был бы платой ни за что.
        let needleStem = needle.contains(where: { $0 == " " })
            ? needle : RecallIndex.searchToken(for: needle)
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
                    // Разметку снимаем ДО сравнения, а не только по дороге к
                    // человеку. Иначе искать пришлось бы по тексту с тегами: у
                    // Plane описание приезжает как `<p>…</p>`, и слово,
                    // разорванное подсветкой (`тари<strong>фы</strong>`), не
                    // нашлось бы, а запрос «p» или «href» нашёл бы всё подряд.
                    let text = manifest.response.stripTags == true
                        ? Self.withoutTags(Self.string(at: path, in: row))
                        : Self.string(at: path, in: row)
                    if text.lowercased().contains(needle) { return true }
                    // Здесь отбор наш, а значит склонение стоит НОЛЬ запросов:
                    // у сервиса, который сам ищет, за ту же находку платят
                    // третьим вопросом. Сравниваем основы — тем же разбором,
                    // которым ищется по своим расшифровкам.
                    //
                    // Только для вопроса из одного слова: у словосочетания
                    // основы нет, а «основа» от него была бы обрубком фразы.
                    guard needleStem != needle else { return false }
                    return RecallIndex.tokens(text).contains(needleStem)
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
        // Строки словарём: порядок берётся из отдельного массива.
        //
        // Значения словаря в Swift неупорядочены, поэтому «разобрать словарь»
        // и «сохранить выдачу» — разные вещи. Сам Mattermost на это и
        // рассчитывает: `order` перечисляет идентификаторы по убыванию
        // совпадения, а `posts` — просто хранилище. Без него человек получил бы
        // случайную строку первой и решил, что она и есть лучшее совпадение.
        if let orderPath = manifest.response.order {
            let root = try? JSONSerialization.jsonObject(with: data)
            let ids = Self.follow(orderPath, from: root) as? [String]
            let byKey = Self.follow(manifest.response.list, from: root) as? [String: Any]
            if let ids, let byKey {
                let resolved = ids.compactMap { byKey[$0] as? [String: Any] }
                // Порядок пуст или ведёт в никуда, а строки в хранилище есть.
                //
                // Отдать здесь пустую выдачу — сказать «ничего не нашлось» про
                // ответ, в котором находки лежат. Сервису для этого не нужно
                // ломаться напоказ: достаточно перестать заполнять `order` или
                // сменить вид идентификаторов, и коннектор станет отвечать
                // уверенной пустотой навсегда. Ровно тот ход, который §10.1
                // разбирает под «строки есть, читается ноль»: это смена
                // формата, а не отсутствие находок, и говорить про неё надо
                // вслух.
                //
                // Часть не разошлась — пропускаем молча, как и раньше: одна
                // негодная строка среди годных не повод отказать во всём.
                if resolved.isEmpty, !byKey.isEmpty { throw ConnectorError.unreadable }
                return resolved
            }
            // Порядок объявлен, но его в ответе НЕТ — это смена формата, а не
            // пустая выдача, и разбирать словарь «как получится» здесь нельзя.
            if byKey != nil { throw ConnectorError.unreadable }
        }
        // Пустой список рядом с жалобой сервиса — это отказ, а не «ничего не
        // нашлось».
        //
        // Условие стояло `rows == nil`, то есть жалоба читалась только тогда,
        // когда контейнера списка нет вовсе. У GraphQL он есть почти всегда:
        // штатный ответ с ошибкой — это `{"data": {...
        //   "results": []}, "errors": [{"message": "rate limit exceeded"}]}`.
        // Список разбирался как пустой, ветка с жалобой пропускалась целиком, и
        // человек получал «искали, ничего нет» — то есть вывод про свою вики
        // вместо вывода про наш коннектор. Так отвечают Wiki.js, Linear и сам
        // Fireflies: код 200 у GraphQL стоит всегда, отказ живёт в `errors`.
        //
        // Пустой список БЕЗ жалобы остаётся пустым списком: `message` пуст —
        // проваливаемся дальше и отвечаем пустой выдачей, как раньше.
        if rows?.isEmpty ?? true, let path = manifest.response.errorMessage,
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
        // Не разобралось как JSON, но разобралось бы браузером.
        //
        // Проверяется только когда JSON не вышел: ответ, который разобрался, но
        // не той формы, — это смена формата, и путать её с формой входа нельзя.
        if root == nil, Self.looksLikeWebPage(data) { throw ConnectorError.webPage }

        guard let rows else { throw ConnectorError.unreadable }
        return rows
    }

    /// Похоже ли тело на веб-страницу.
    ///
    /// Смотрим начало, а не весь ответ: строка `<html` встречается и внутри
    /// честного JSON — например, в тексте задачи, где кто-то процитировал
    /// разметку. Начало документа врать неоткуда.
    static func looksLikeWebPage(_ data: Data) -> Bool {
        let head = String(decoding: data.prefix(512), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .lowercased()
        return head.hasPrefix("<!doctype html") || head.hasPrefix("<html")
            || head.hasPrefix("<?xml") && head.contains("<html")
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
        return Item(key: number.map { "#\($0)" } ?? label ?? Item.noKey,
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

    /// Две выдачи в одну, без повторов и в пределах limit.
    ///
    /// Один и тот же ответ приезжает в обоих написаниях, когда сервис регистр
    /// всё-таки приводит. Сличаем по ключу, а где его нет — по заголовку: у
    /// вики номера страницы нет вовсе, и без второго признака одна страница
    /// показалась бы человеку дважды.
    static func merge(_ first: [Item], _ second: [Item], limit: Int) -> [Item] {
        // Прочерк — не обозначение, а его отсутствие. Считать его обозначением
        // значит объявить одинаковыми ВСЕ строки сервиса, который номеров не
        // даёт: у Wiki.js так и было, и второй вопрос там не мог добавить ни
        // одной страницы — на живой установке 2026-08-19 сервис отдавал две, а
        // до человека доезжала одна.
        let mark = { (item: Item) in
            item.key.isEmpty || item.key == Item.noKey ? item.title : item.key
        }
        var seen = Set(first.map(mark))
        var merged = first
        for item in second where seen.insert(mark(item)).inserted {
            merged.append(item)
        }
        return Array(merged.prefix(limit))
    }

    /// То же слово с другим регистром первой буквы, или nil.
    ///
    /// Только для кириллицы: у латиницы `LIKE` в SQLite регистр и так
    /// приводит, поэтому второй запрос там был бы чистой платой чужому
    /// серверу без единого нового ответа.
    ///
    /// Меняется ПЕРВАЯ буква, а не всё слово: «тарифы» → «Тарифы» — это то, с
    /// чего начинается заголовок задачи или имя файла. Верхний регистр целиком
    /// («ТАРИФЫ») людям не свойственен, и лишний запрос за ним не оправдан.
    static func caseVariant(of query: String) -> String? {
        guard query.contains(where: { $0.isCyrillicLetter }) else { return nil }
        guard let first = query.first, first.isLetter else { return nil }
        let flipped = first.isLowercase ? first.uppercased() : first.lowercased()
        let variant = flipped + query.dropFirst()
        return variant == query ? nil : variant
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

    enum Half { case head, tail }

    /// Часть ключа до первого двоеточия или после него. Без двоеточия голова —
    /// весь ключ, а хвост пуст: это «человек вписал не пару», и заголовок
    /// уедет пустым, а не с чужим значением.
    static func half(of token: String, _ part: Half) -> String {
        guard let separator = token.firstIndex(of: ":") else {
            return part == .head ? token : ""
        }
        return part == .head
            ? String(token[token.startIndex..<separator])
            : String(token[token.index(after: separator)...])
    }

    /// Манифест просит очищенный вопрос — значит, чужой сервис разбирает его
    /// как выражение, а не как строку, и пустая середина там опасна.
    private var quotesTheQuery: Bool {
        var texts = [manifest.request.path, manifest.request.body ?? ""]
        texts += manifest.request.query.map(\.value)
        texts += manifest.request.headers.map(\.value)
        return texts.contains { $0.contains("{queryWords}") }
    }

    /// Вопрос, из которого убраны знаки, ломающие чужой язык поиска.
    ///
    /// JQL и CQL берут слово в кавычки: `text ~ "тарифы"`. Кавычка внутри
    /// слова закрывает строку, и остаток вопроса становится продолжением
    /// ЗАПРОСА к чужому серверу — не текстом, который ищут, а условием, по
    /// которому ищут. Вопрос собирается из речи на звонке, то есть приходит
    /// снаружи: сказанная вслух фраза с кавычкой меняла бы не ответ, а сам
    /// вопрос, и человек получил бы уверенный ответ не на то, что спросил.
    /// Это тот же класс, что и подмешивание указаний в расшифровку, только
    /// дверь другая.
    ///
    /// Терять при этом нечего, и это не наша оценка, а слова вендора:
    /// служебные знаки `+ - & | ! ( ) { } [ ] ^ ~ * ? \ :` в индекс не
    /// попадают, искать их нельзя, и поиск с ними даёт тот же результат, что
    /// и без них.
    ///
    /// Замена на ПРОБЕЛ, а не удаление. «Wi-Fi» без дефиса станет «WiFi» —
    /// одно слово, которого в индексе нет; «Wi Fi» — ровно то, что там лежит.
    /// Удаление здесь выглядело бы аккуратнее и молча теряло бы находки.
    static func words(of query: String) -> String {
        // Кавычки обоих видов: JQL допускает и `"…"`, и `'…'`, а CQL в
        // примерах вендора пользуется одинарными.
        let breaking = CharacterSet(charactersIn: "+-&|!(){}[]^~*?\\:\"'")
        return query.components(separatedBy: breaking)
            .joined(separator: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    private func fill(_ template: String, query: String, limit: Int, page: Int = 0,
                      suffix: String = "") -> String {
        // Знак подстановки приписывается ПОСЛЕ очистки, и порядок тут не
        // вкусовщина: `words(of:)` убирает `*` наравне с прочими служебными
        // знаками, потому что из речи он приходит мусором. Приписанный
        // раньше, он был бы съеден — и вопрос основой снова не нашёл бы
        // ничего, а причина выглядела бы как «сервис не умеет».
        var filled = template
            .replacingOccurrences(of: "{query}", with: query + suffix)
            .replacingOccurrences(of: "{queryWords}", with: Self.words(of: query) + suffix)
            .replacingOccurrences(of: "{limit}", with: String(limit))
            .replacingOccurrences(of: "{token}", with: token)
            // `{basic}` — тот же токен, но в base64, для заголовка
            // «Authorization: Basic …». Нужен там, где сервер принимает только
            // Basic: у Nextcloud это пара «имя:пароль приложения», и человек
            // вписывает её одной строкой. Считать base64 в манифесте нельзя,
            // а требовать от человека закодировать пароль руками — значит
            // получать в поле то, что он закодировал неправильно.
            .replacingOccurrences(of: "{basic}", with: Data(token.utf8).base64EncodedString())
            // Половины ключа, записанного через двоеточие.
            //
            // Rocket.Chat просит ДВА значения — токен и идентификатор
            // пользователя — и кладёт их в два РАЗНЫХ заголовка. Человек
            // вписывает их одной строкой: четвёртое поле в настройках
            // гарантированно осталось бы пустым, а пара всё равно выдаётся
            // вместе. `{basic}` рядом решает соседнюю задачу — ту же пару, но
            // склеенной и в base64, — и подменить одно другим нельзя.
            //
            // Двоеточие первое: у Nextcloud пароль приложения может содержать
            // двоеточие, и разрезать по последнему значило бы отдать сервису
            // обрубок вместо ключа.
            .replacingOccurrences(of: "{tokenHead}", with: Self.half(of: token, .head))
            .replacingOccurrences(of: "{tokenTail}", with: Self.half(of: token, .tail))
            .replacingOccurrences(of: "{page}", with: String(page))
            .replacingOccurrences(of: "{perPage}", with: String(manifest.scan?.perPage ?? limit))
        for (name, value) in values {
            filled = filled.replacingOccurrences(of: "{\(name)}", with: value)
        }
        return filled
    }
}
