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

    public struct Response: Decodable, Equatable, Sendable {
        /// Путь до массива строк. Пустой — массив лежит на верхнем уровне
        /// (GitLab, Gitea); `["results"]` — завёрнут (Redmine).
        public let list: [String]
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
        /// Ключ состояния. В ответе может отсутствовать — тогда пусто, и это не
        /// ошибка: Redmine состояния в поиске не отдаёт вовсе.
        public let state: String
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
    }

    public let id: String
    public let title: String
    /// Ссылка на документацию вендора. Обязательна.
    public let docs: String
    /// Когда её читали. «Проверено» стареет, и читатель вправе знать, насколько.
    public let verifiedOn: String
    public let note: String?
    public let request: Request
    public let response: Response

    public enum ManifestError: Error, Equatable, CustomStringConvertible {
        case missingDocumentation(String)
        case noSearchParameter(String)
        case unreadable(String)

        public var description: String {
            switch self {
            case .missingDocumentation(let id):
                return "Манифест «\(id)» без ссылки на документацию вендора. Метод, адрес, параметр поиска и форму ответа проверяют по ней; без неё коннектор — догадка."
            case .noSearchParameter(let id):
                return "В манифесте «\(id)» ни один параметр не подставляет {query}. Перечисление задач поиском не считается: фильтрация первой страницы у себя отвечает «ничего не нашлось» на полном архиве."
            case .unreadable(let name):
                return "Манифест «\(name)» не разобрался."
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
        let inQuery = request.query.contains { $0.value.contains("{query}") }
        let inBody = request.body?.contains("{query}") ?? false
        guard inQuery || inBody else { throw ManifestError.noSearchParameter(id) }
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
        let urls = ((try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.absoluteString.hasSuffix(".json") }
        let decoder = JSONDecoder()
        var manifests: [ConnectorManifest] = []
        for url in urls.sorted(by: { $0.absoluteString < $1.absoluteString }) {
            let data = try Data(contentsOf: url)
            guard let manifest = try? decoder.decode(ConnectorManifest.self, from: data) else {
                let name = url.absoluteString.split(separator: "/").last.map(String.init)
                    ?? url.absoluteString
                throw ManifestError.unreadable(name)
            }
            try manifest.validate()
            manifests.append(manifest)
        }
        return manifests
    }
}
