import Foundation

/// Ответы сервисов, недолго живущие в памяти.
///
/// Заведён против самого дешёвого приёма недружелюбного сервиса: не
/// блокировать, а придушить. Заблокировать нас — заметно и объяснимо; отвечать
/// 429 на каждый третий запрос — незаметно, и выглядит как «у них само не
/// работает». Раньше один 429 означал, что источник молчит до конца звонка.
///
/// Что делает кэш. Во-первых, снимает нагрузку, которой троттлинг и вызван:
/// один и тот же вопрос на звонке повторяется — «что решили по срокам»
/// спрашивают трижды за час, и три одинаковых запроса к чужому серверу мы
/// создавали сами. Во-вторых, даёт чем ответить, когда сервис уже просит
/// подождать.
///
/// Чего он НЕ делает: не притворяется, что ответ свежий. Ответ из кэша уезжает
/// с возрастом, и человек видит «сервис просит подождать, это ответ минутной
/// давности», а не выдачу без пометки. Продукт, который обещает цитату с
/// источником, не может врать о времени ответа — устаревшая правда и свежая
/// правда отвечают на разные вопросы.
///
/// В памяти и только в памяти: на диске это был бы второй экземпляр чужих
/// данных, живущий дольше разговора, — ровно то, чего продукт не делает.
public actor ConnectorCache {

    public static let shared = ConnectorCache()

    /// Сколько ответ считается свежим. Меньше минуты — и повтор вопроса на
    /// звонке снова бьёт по сервису; больше пяти — и «решили вчера» рискует
    /// пережить решение, принятое только что.
    public static let freshFor: TimeInterval = 90

    /// Сколько ответ ещё годится, когда сервис просит подождать. Здесь порог
    /// другой: выбор не между свежим и старым, а между старым и никаким.
    public static let usableWhenThrottledFor: TimeInterval = 900

    struct Entry {
        let items: [ManifestConnector.Item]
        let coverage: SearchCoverage
        let storedAt: Date
    }

    private var entries: [String: Entry] = [:]

    /// Часы отдельно, чтобы набор не ждал полторы минуты ради проверки возраста.
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    static func key(service: String, host: String, query: String) -> String {
        // Слово приводится к нижнему регистру: «Тарифы» и «тарифы» — один
        // вопрос, и незачем спрашивать сервис дважды.
        "\(service)|\(host)|\(query.lowercased())"
    }

    func store(_ outcome: ManifestConnector.Outcome, service: String, host: String, query: String) {
        entries[Self.key(service: service, host: host, query: query)] =
            Entry(items: outcome.items, coverage: outcome.coverage, storedAt: now())
    }

    /// Свежий ответ, если он есть. Иначе `nil` — и сервис спрашивают.
    func fresh(service: String, host: String, query: String) -> ManifestConnector.Outcome? {
        guard let entry = entries[Self.key(service: service, host: host, query: query)],
              now().timeIntervalSince(entry.storedAt) <= Self.freshFor else { return nil }
        return ManifestConnector.Outcome(items: entry.items, coverage: entry.coverage)
    }

    /// Ответ на случай, когда сервис просит подождать: с возрастом, чтобы его
    /// можно было назвать человеку.
    func stale(service: String, host: String, query: String)
        -> (outcome: ManifestConnector.Outcome, age: Int)? {
        guard let entry = entries[Self.key(service: service, host: host, query: query)] else {
            return nil
        }
        let age = now().timeIntervalSince(entry.storedAt)
        guard age <= Self.usableWhenThrottledFor else { return nil }
        return (ManifestConnector.Outcome(items: entry.items, coverage: entry.coverage),
                Int(age.rounded()))
    }

    /// Для наборов: забыть всё. Общий кэш между проверками — то же общее
    /// состояние, на котором этот репозиторий уже обжигался.
    public func forget() { entries.removeAll() }
}
