import Foundation

/// Ответ на вопрос «что мы решили» — то, что человек в итоге читает.
///
/// Здесь живёт главное обещание продукта, и сформулировано оно как запрет:
/// **нет слов в расшифровке — нет ответа**. Модель, которой показали пустой
/// результат, охотно сочинит правдоподобное решение, поэтому фраза «ничего не
/// нашлось» собирается здесь, кодом, а не запрашивается у модели.
///
/// Ответ состоит из трёх частей, и каждая нужна для проверки: название встречи
/// (где сказано), дата (когда) и точная цитата (что именно). Без цитаты ответ
/// невозможно проверить, а непроверяемый ответ про чужие обещания — ровно то,
/// на что жалуются пользователи других инструментов.
public enum RecallAnswer {

    /// Сколько встреч показывать. Больше трёх — это уже не ответ, а выдача.
    public static let maximumMeetings = 3

    /// Текст, который видит пользователь.
    /// Ответ на вопрос.
    ///
    /// `archiveIsEmpty` отделяет «звонки есть, но про это не говорили» от
    /// «звонков ещё нет вовсе». Разные вещи и разные следующие шаги: искать
    /// иначе или сперва что-нибудь добавить. Параметр, а не догадка по
    /// `hits.isEmpty`: пустая выдача бывает и на полном архиве, и по ней
    /// пустоту архива не отличить.
    ///
    /// Значение по умолчанию — false, чтобы не переписывать десяток мест,
    /// где архив заведомо не пуст. Оба настоящих вызова передают его явно.
    /// `unreadable` — файлы архива, которые не открылись.
    ///
    /// Страница зовёт открывать архив руками: «обычные JSON-файлы, их можно
    /// читать и без нас». Раз зовёт, файл рано или поздно окажется испорченным
    /// — недописанным при сбое, перекодированным редактором. `cruxwing список`
    /// про такой файл говорил, а ответ на вопрос — нет: выходило уверенное «в
    /// сохранённых звонках об этом не говорили» поверх архива, часть которого
    /// не открывали. Для продукта, у которого честность ответа и есть продукт,
    /// это хуже пустого результата: человек уходит уверенным, что не обсуждали.
    ///
    /// Предупреждение приписывается к ЛЮБОМУ ответу, включая найденный: то,
    /// что нашлось, могло быть не всем, что есть.
    public static func compose(query: String, hits: [RecallIndex.Hit],
                               archiveIsEmpty: Bool = false,
                               unreadable: [String] = [],
                               suggestions: [String] = []) -> String {
        guard !archiveIsEmpty else {
            // Пусто и при этом что-то не прочиталось — это не пустой архив, а
            // архив, до которого мы не добрались. Разница решающая: в первом
            // случае человеку нечего терять, во втором его записи, возможно,
            // на месте, и «пуст» отправит его заводить всё заново.
            guard unreadable.isEmpty else {
                return withWarning(
                    "Could not read the archive, so I cannot say what is in it.", unreadable)
            }
            return withWarning(
                "The archive is empty, so there is nowhere to search yet. Add a transcript: cruxwing add <file>",
                unreadable)
        }
        let grounded = hits.filter { !$0.excerpt.isEmpty }

        // Вопрос, в котором не осталось слов для поиска.
        //
        // Поиск словарный, служебные слова из него выброшены — и «а что там по
        // этому?» после отбора не оставляет ни одного слова. Искать было
        // нечем, архив никто не открывал, а ответ гласил «в сохранённых
        // звонках об этом не говорили»: утверждение о результате поиска,
        // которого не было. Человек уходит уверенным, что тему не обсуждали.
        //
        // Родной брат ошибки с пустым архивом. Проверяется только когда ничего
        // не нашлось: если находка есть, вопрос был достаточно конкретным по
        // определению, и придираться к нему поздно.
        if grounded.isEmpty, RecallIndex.tokens(query).isEmpty {
            return withWarning("""
            The question contains no words to search by, only stop words.
            Ask something more specific: cruxwing search what did we decide about pricing
            """, unreadable)
        }

        guard !grounded.isEmpty else {
            return withWarning(notFound(hits: hits, suggestions: suggestions), unreadable)
        }

        var lines: [String] = []
        for hit in grounded.prefix(maximumMeetings) {
            lines.append("«\(hit.session.title)», \(humanDate(hit.session.date))")
            // Отступ каждой строке, а не только первой: цитата стала бывать
            // из двух реплик — вопрос и то, что на него ответили, — и вторая
            // без отступа выпадала из колонки.
            for row in hit.excerpt.split(separator: "\n", omittingEmptySubsequences: false) {
                lines.append("    \(row)")
            }
        }

        if grounded.count > maximumMeetings {
            let rest = grounded.count - maximumMeetings
            lines.append("\(rest) more \(callsWord(rest)) in the archive mention it.")
        }
        return withWarning(lines.joined(separator: "\n"), unreadable)
    }

    /// Приписать к ответу строку о том, что часть архива не открылась.
    ///
    /// Приписывается, а не заменяет ответ: находки — это находки, их человек
    /// обязан получить. И только когда есть о чём предупреждать: строка,
    /// которая печатается всегда, перестаёт читаться за день.
    private static func withWarning(_ answer: String, _ unreadable: [String]) -> String {
        guard !unreadable.isEmpty else { return answer }
        let files = unreadable.sorted().joined(separator: ", ")
        let word = unreadable.count == 1 ? "file" : "files"
        return answer + "\n\nCould not read \(unreadable.count) \(word) in the archive, "
            + "so this answer may be incomplete: \(files)"
    }

    /// Почему ответа нет — разными словами для разных причин.
    ///
    /// «Не нашёл» и «нашёл звонок, но там про это не сказано» — разные
    /// сообщения, и человек принимает по ним разные решения: искать иначе или
    /// перестать искать.
    ///
    /// Слово на всё одно — «звонок». В этом файле их было три: «созвон» здесь,
    /// «встреча» в счёте ниже и «звонок» на странице и в README. Из-за этого же
    /// README цитировал отказ со словом «звонках» и расходился с тем, что
    /// программа печатает на самом деле.
    ///
    /// `suggestions` — слова из архива, похожие на спрошенное с точностью до
    /// опечатки. Без них «не говорили» звучит как итог проверки, хотя проверено
    /// было слово с лишней буквой; человек уходит уверенным, что темы не было.
    /// Подсказка не подменяет вопрос и не ищет за человека — она показывает,
    /// какие слова в архиве есть, а решает он.
    static func notFound(hits: [RecallIndex.Hit], suggestions: [String] = []) -> String {
        if hits.isEmpty {
            let refusal = "The saved calls did not discuss this. I will not invent an answer."
            guard !suggestions.isEmpty else { return refusal }
            let words = suggestions.map { "«\($0)»" }.joined(separator: ", ")
            return refusal + "\nLooks like a typo — the archive has \(words)."
        }
        let titles = hits.prefix(maximumMeetings)
            .map { "«\($0.session.title)»" }
            .joined(separator: ", ")
        return "There are similar calls — \(titles) — but the transcript has none of "
            + "your question's exact words, so there is nothing to quote."
    }

    /// «2026-07-24» → «24 июля 2026». Дату в ответе читает человек, а не
    /// сортирует машина.
    static func humanDate(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), (1...12).contains(month),
              let day = Int(parts[2]) else { return iso }
        let months = ["January", "February", "March", "April", "May", "June",
                      "July", "August", "September", "October", "November", "December"]
        return "\(day) \(months[month - 1]) \(parts[0])"
    }

    /// 1 call, 2 calls. English has no case forms, so the count alone decides.
    static func callsWord(_ count: Int) -> String {
        count == 1 ? "call" : "calls"
    }
}
