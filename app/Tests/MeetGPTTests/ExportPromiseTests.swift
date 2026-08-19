import Foundation
import Testing
@testable import MeetGPT

/// Обещание кнопки выгрузки совпадает с тем, что уезжает.
///
/// Подсказка говорила «ответ вместе с запросом и слепыми зонами». Уезжал весь
/// разговор: каждый прежний запрос и каждый прежний ответ этой сессии
/// (`earlierExchanges`). Notion и Google Docs — чужие сервисы, и объём того,
/// что туда уходит, человек должен знать до нажатия, а не по открывшейся
/// странице.
///
/// Решение при этом не менялось: страница и должна быть разговором, а не одним
/// последним ответом, — так написано в NotionExport. Неправдой был текст.
@Suite("Выгрузка обещает то, что отправляет")
struct ExportPromiseTests {

    private func source(_ relative: String) -> String {
        let path = #filePath.replacingOccurrences(
            of: "Tests/MeetGPTTests/ExportPromiseTests.swift",
            with: "Sources/MeetGPT/\(relative)")
        return (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    /// Без комментариев: рядом с правкой они цитируют старое обещание, и
    /// проверка, прочитавшая цитату, проверяет комментарий.
    private func code(_ relative: String) -> String {
        source(relative)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("///") }
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    @Test("выгрузка действительно отправляет весь разговор")
    func exportCarriesTheWholeDialog() {
        let markdown = NotionExport.markdown(
            title: "Планёрка", date: Date(timeIntervalSince1970: 0),
            prompt: "что решили по тарифам",
            answer: "Поднять на 15% с декабря.",
            blindSpots: ["не назван владелец"],
            earlierExchanges: [AIExchange(prompt: "кто отвечает за биллинг",
                                          answer: "Аня")])
        #expect(markdown.contains("кто отвечает за биллинг"),
                "прежний запрос не уехал — тогда и обещание надо менять обратно")
        #expect(markdown.contains("Аня"))
        #expect(markdown.contains("Поднять на 15% с декабря."))
        #expect(markdown.contains("не назван владелец"))
    }

    @Test("подсказка кнопки называет разговор, а не один ответ")
    func tooltipNamesTheDialog() {
        let studio = code("Views/AIStudioView.swift")
        guard let line = studio.split(separator: "\n").first(where: { $0.contains(".help(\"Скопировать") }) else {
            Issue.record("подсказка выгрузки исчезла — проверять нечего")
            return
        }
        #expect(line.contains("весь разговор"),
                "подсказка обещает меньше, чем уезжает: «\(line.trimmingCharacters(in: .whitespaces))»")
        #expect(line.contains("слепым") || line.contains("слепыми"))
    }

    // Обратная сторона: если однажды решат отправлять только последний ответ,
    // текст обязан похудеть вместе с кодом. Проверка держит связь в обе стороны.
    @Test("обещание и вызов держатся друг за друга")
    func promiseAndCallStayTogether() {
        let state = code("AppState.swift")
        let sendsDialog = state.contains("earlierExchanges: doc.earlierExchanges")
        let studio = code("Views/AIStudioView.swift")
        let promisesDialog = studio.contains("весь разговор")
        #expect(sendsDialog == promisesDialog,
                sendsDialog
                ? "разговор уезжает, а подсказка обещает меньше"
                : "подсказка обещает разговор, а уезжает один ответ")
    }
}
