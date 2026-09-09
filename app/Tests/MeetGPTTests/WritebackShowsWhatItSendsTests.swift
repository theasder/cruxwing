import Foundation
import Testing
@testable import MeetGPT

/// В трекер уезжает то, что человек видел.
///
/// Кнопка спрашивает согласия на «завести задачу». Уезжало при этом больше, чем
/// показано: строка в листе несла название и владельца, а тело запроса — ещё
/// срок, признак готовности и «Источник: …», то есть кусок разговора. Трекер
/// бывает чужим — у Jira и Notion свои владельцы, и один из них продаёт
/// конкурирующий продукт, — а согласие на задачу не есть согласие на цитату.
///
/// Два пути записи при этом отправляли РАЗНОЕ: путь MCP — полное описание,
/// путь российских трекеров — одну фамилию в поле описания.
@Suite("Запись в трекер показывает то, что отправляет")
struct WritebackShowsWhatItSendsTests {


    /// Код листа без комментариев.
    ///
    /// Комментарий рядом с правкой намеренно цитирует то, чего в коде быть не
    /// должно («здесь стояло `description: item.owner`»), — и проверка,
    /// прочитавшая цитату, проверяет комментарий. Этот набор на том и упал.
    private func sheetCode() -> String {
        let path = #filePath.replacingOccurrences(
            of: "Tests/MeetGPTTests/WritebackShowsWhatItSendsTests.swift",
            with: "Sources/MeetGPT/Views/TaskWritebackSheet.swift")
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func item() -> TasksArtifact.Item {
        TasksArtifact.Item(task: "Пересчитать тарифы",
                           owner: "Аня",
                           due: "до пятницы",
                           doneCheck: "Готово, когда таблица обновлена",
                           dependency: nil,
                           sourceRef: "решили поднять на 15%",
                           tracked: false)
    }

    @Test("описание несёт всё, что человеку показали")
    func descriptionCarriesEveryShownField() {
        let text = TaskWriteback.describe(item())
        #expect(text.contains("Аня"))
        #expect(text.contains("до пятницы"))
        #expect(text.contains("таблица обновлена"))
        #expect(text.contains("решили поднять на 15%"))
        #expect(text.contains("cruxwing"), "задача не говорит, откуда она взялась")
    }

    // Строка листа собирается той же функцией, что и тело запроса. Иначе это
    // два текста, и расходиться они начнут в тот день, когда добавят поле.
    @Test("лист показывает ту же строку, что уходит в запрос")
    func sheetShowsThePayload() {
        let sheet = sheetCode()
        #expect(sheet.contains("Text(TaskWriteback.describe(item))"),
                "лист показывает свой текст, а не тот, что уедет в трекер")
    }

    @Test("оба пути записи отправляют одно тело")
    func bothPathsSendTheSameBody() {
        let sheet = sheetCode()
        #expect(sheet.contains("description: TaskWriteback.describe(item)"),
                "путь российских трекеров отправляет своё описание")
        #expect(!sheet.contains("description: item.owner"),
                "в описание задачи уезжает одна фамилия, а срок и источник теряются")
    }

    // Пустые поля не должны превращаться в строки-заглушки: «Владелец: [OWNER?]»
    // в чужом трекере читается как имя человека.
    @Test("незаполненные поля в трекер не уезжают")
    func placeholdersStayHome() {
        let bare = TasksArtifact.Item(task: "Уточнить сроки", owner: "[OWNER?]", due: "[DUE?]",
                                      doneCheck: nil, dependency: nil, sourceRef: nil, tracked: false)
        let text = TaskWriteback.describe(bare)
        #expect(!text.contains("OWNER?"))
        #expect(!text.contains("DUE?"))
        #expect(text.contains("cruxwing"))
    }
}
