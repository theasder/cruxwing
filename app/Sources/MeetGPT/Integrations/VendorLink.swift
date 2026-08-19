import Foundation

/// Ссылка, пришедшая из ответа чужого сервера, — и вопрос, можно ли её
/// открывать.
///
/// Экспорт в Notion заканчивался тем, что orakul сам открывал браузер на
/// адресе, который назвал MCP-сервер. Проверка адреса выглядела как проверка:
/// строка начинается с `https://` и СОДЕРЖИТ «notion.so». Содержит её и
/// `https://notion.so.chuzhoy-host.ru/login`, и `https://chuzhoy.ru/?x=notion.so`
/// — то есть сервер выбирал, куда пойдёт браузер человека, а сторож этого не
/// замечал.
///
/// Момент выбран самый доверчивый: человек только что нажал «выгрузить» и ждёт
/// свою страницу. Страница входа, открывшаяся сама, выглядит как продолжение
/// его же действия.
///
/// Правило простое: сравнивать ХОЗЯИНА адреса, а не искать имя внутри строки.
/// Совпадением считается сам домен или его поддомен — `acme.notion.site` да,
/// `notion.so.chuzhoy.ru` нет, потому что хозяин здесь `chuzhoy.ru`.
enum VendorLink {

    /// Первая ссылка в тексте, которая действительно ведёт к названному сервису.
    ///
    /// Текст приходит от инструмента целиком и в свободной форме: у одних это
    /// JSON, у других предложение по-английски. Поэтому разбор по словам, а не
    /// по структуре, — но решение принимается по разобранному адресу.
    static func first(in text: String, allowing hosts: [String]) -> URL? {
        let separators: Set<Character> = [" ", "\n", "\t", "\"", "'", "(", ")", "<", ">", ","]
        for token in text.split(whereSeparator: { separators.contains($0) }) {
            // Ссылки внутри JSON приезжают экранированными: "https:\/\/…".
            let candidate = String(token).replacingOccurrences(of: "\\/", with: "/")
            guard let url = URL(string: candidate), belongs(url, to: hosts) else { continue }
            return url
        }
        return nil
    }

    /// Адрес принадлежит одному из названных доменов.
    ///
    /// Только `https`: `http` открыло бы человека посреднику, а `file://` и
    /// `javascript:` вообще не адреса сервиса — и без явного условия сюда
    /// проходили бы оба, потому что хозяина у них нет и сравнивать было бы
    /// нечего.
    static func belongs(_ url: URL, to hosts: [String]) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), !host.isEmpty else { return false }
        return hosts.contains { allowed in
            let allowed = allowed.lowercased()
            return host == allowed || host.hasSuffix("." + allowed)
        }
    }
}
