import Foundation

/// Разметка ответа — и ссылки, которых в ней быть не должно.
///
/// Ответ разбирается как встроенный markdown, а он понимает `[слова](адрес)`.
/// Слова видит человек, адрес не видит никто: `Text` рисует это как обычную
/// ссылку, и нажатие уводит браузер туда, куда сказано в скобках.
///
/// Написать такое может не только модель. Текст ответа строится на находках
/// подключённых сервисов: заголовок задачи, страница вики, строка расшифровки
/// от сервиса, который продаёт конкурирующий продукт. Достаточно, чтобы модель
/// перенесла строку в ответ — а переносить цитаты её и просят.
///
/// Это тот же случай, что и адрес из ответа сервера при выгрузке, только дверь
/// другая и опаснее: там адрес хотя бы принадлежал названному сервису, здесь
/// он не показан вовсе.
///
/// Правило: ссылку снимаем, слова оставляем, адрес ПОКАЗЫВАЕМ. Продукт обещает
/// цитату с источником; спрятанный источник — противоположность этого обещания.
enum AnswerMarkdown {

    /// То же правило для РАЗМЕТКИ, а не для разобранного текста.
    ///
    /// На экран ответ попадает разобранным, и там ссылку снимает
    /// `withoutHiddenLinks`. В выгрузку он уезжает КАК ЕСТЬ — строкой markdown,
    /// — и `[слова](адрес)` снова становится ссылкой уже на стороне Notion.
    /// Дверь другая, а хуже она тем, что страницу открывают коллеги: людей
    /// больше, доверия больше, а написано на ней «orakul».
    ///
    /// Правило то же: слова оставляем, адрес показываем. Адрес, совпадающий с
    /// подписью, не повторяем — иначе выгрузка обрастает «https://… (https://…)».
    static func withVisibleAddresses(_ markdown: String) -> String {
        var out = ""
        var rest = Substring(markdown)
        while let open = rest.firstIndex(of: "[") {
            guard let close = rest[open...].firstIndex(of: "]"),
                  rest.index(after: close) < rest.endIndex,
                  rest[rest.index(after: close)] == "(",
                  let end = rest[close...].firstIndex(of: ")") else {
                out += rest[..<rest.index(after: open)]
                rest = rest[rest.index(after: open)...]
                continue
            }
            let label = String(rest[rest.index(after: open)..<close])
            let address = String(rest[rest.index(close, offsetBy: 2)..<end])
            out += rest[..<open]
            out += label == address || label.isEmpty ? address : "\(label) (\(address))"
            rest = rest[rest.index(after: end)...]
        }
        return out + rest
    }

    /// Тот же текст без скрытых переходов.
    static func withoutHiddenLinks(_ parsed: AttributedString) -> AttributedString {
        var out = parsed
        // Сначала собрать, потом менять: правка сдвигает границы соседних
        // отрезков, и обход по ходу правки пропускал бы каждую вторую ссылку.
        let found = out.runs.compactMap { run -> (Range<AttributedString.Index>, String)? in
            guard let link = run.link else { return nil }
            return (run.range, link.absoluteString)
        }
        // С конца — по той же причине: вставка сдвигает всё, что правее.
        for (range, address) in found.reversed() {
            out[range].link = nil
            guard !String(out.characters).contains(address) else { continue }
            out.insert(AttributedString(" (\(address))"), at: range.upperBound)
        }
        return out
    }
}
