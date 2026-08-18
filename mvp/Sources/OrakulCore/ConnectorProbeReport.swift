import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Отчёт о живой проверке коннектора — то, что можно приложить к пулл-реквесту.
///
/// Зачем отдельно от `orakul спросить`. Спросить умеет любой; проверить
/// коннектор может только тот, у кого есть аккаунт в сервисе, а принять правку —
/// тот, у кого аккаунта нет. Между ними нужен документ: что именно ушло на
/// сервер, что он ответил, узналась ли форма. Пересказ словами не годится —
/// половина ошибок коннектора это лишний или потерянный параметр.
///
/// **Токен в отчёт не попадает.** Это главное свойство, а не удобство: человек
/// вставляет вывод в публичный пулл-реквест, и утечка здесь означала бы, что
/// инструмент проверки сам открыл ту дыру, ради закрытия которой существует
/// правило «секреты только в Связке ключей». Поэтому чистится всё сразу —
/// заголовки по именам, ключ внутри адреса (у Битрикс24 он в пути), и на выходе
/// строка ещё раз проходит замену по самому значению токена.
public enum ConnectorProbeReport {

    /// Имена заголовков, в которых по определению лежит секрет.
    static let secretHeaders = ["authorization", "private-token", "x-redmine-api-key",
                                "x-auth-token", "x-org-id", "x-user-id"]

    /// Что вышло из одной живой проверки.
    public struct Outcome: Sendable {
        public let service: String
        public let request: URLRequest?
        public let status: Int?
        public let rows: Int?
        public let firstTitle: String?
        public let failure: String?

        public init(service: String, request: URLRequest?, status: Int?,
                    rows: Int?, firstTitle: String?, failure: String?) {
            self.service = service
            self.request = request
            self.status = status
            self.rows = rows
            self.firstTitle = firstTitle
            self.failure = failure
        }
    }

    /// Собирает отчёт и вычищает из него секрет.
    ///
    /// `token` передаётся отдельно от запроса намеренно: вычистить надо и то,
    /// что мы положили в заголовок сами, и то, что могло попасть в адрес или в
    /// текст ошибки сервиса.
    public static func render(_ outcome: Outcome, token: String) -> String {
        var lines: [String] = []
        lines.append("Сервис: \(outcome.service)")

        if let request = outcome.request {
            let method = request.httpMethod ?? "GET"
            let address = request.url?.absoluteString ?? "—"
            lines.append("Запрос: \(method) \(address)")
            let headers = (request.allHTTPHeaderFields ?? [:]).sorted { $0.key < $1.key }
            for (name, value) in headers {
                let shown = secretHeaders.contains(name.lowercased()) ? "***" : value
                lines.append("  \(name): \(shown)")
            }
            if let body = request.httpBody, let text = String(data: body, encoding: .utf8) {
                lines.append("Тело: \(text)")
            }
        } else {
            lines.append("Запрос: не отправлялся")
        }

        if let status = outcome.status {
            lines.append("Ответ: \(status)")
        }
        if let rows = outcome.rows {
            // Ноль строк — тоже результат, и он отличается от «форму не узнали».
            // Разница ровно та, ради которой заведено правило «пустая выдача
            // только знакомой формы».
            lines.append("Форма узнана, строк: \(rows)")
            if let title = outcome.firstTitle, !title.isEmpty {
                lines.append("Первая строка: \(title)")
            }
        }
        if let failure = outcome.failure {
            lines.append("Не получилось: \(failure)")
        }

        lines.append("")
        lines.append("Токен в этот вывод не попадает — можно прикладывать к пулл-реквесту.")

        return scrub(lines.joined(separator: "\n"), token: token)
    }

    /// Последняя защита: замена по самому значению токена.
    ///
    /// Заголовки чистятся по именам выше, но секрет умеет попадать и туда, где
    /// его не ждут: в путь (вебхук Битрикс24), в параметр запроса, в текст
    /// ошибки, которую вернул сервис. Перечислять места — значит однажды забыть
    /// место; проверять само значение — нет.
    static func scrub(_ text: String, token: String) -> String {
        let secret = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard secret.count >= 4 else { return text }

        // Список того, что надо вычистить, собирается явно — и это не
        // украшение. Прежний вариант чистил сначала целое, потом половинки, и
        // мутация показала, что первая строка ничего не решает: у токена без
        // разделителя «половинка» и есть он сам. Проверка, которую нельзя
        // сломать, — это проверка, которая ничего не сторожит.
        var candidates: Set<String> = [secret]
        // Токен из двух половин: `почта:ключ` у Zulip, `id/код` у вебхука. В
        // запрос уезжает то одна, то другая.
        for half in secret.split(whereSeparator: { $0 == ":" || $0 == "/" }) where half.count >= 4 {
            candidates.insert(String(half))
        }
        // Процентная форма: в адресе нелатинский ключ выглядит как
        // «%D0%A1%D0%95…». Глазами не читается, раскодировать умеет кто угодно.
        for value in candidates {
            if let encoded = value.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
               encoded != value {
                candidates.insert(encoded)
            }
        }

        // Длинные раньше коротких: иначе половинка успевает съесть кусок целого
        // и остаток остаётся в тексте как хвост без начала.
        var cleaned = text
        for value in candidates.sorted(by: { $0.count > $1.count }) {
            cleaned = cleaned.replacingOccurrences(of: value, with: "***")
        }
        return cleaned
    }
}
