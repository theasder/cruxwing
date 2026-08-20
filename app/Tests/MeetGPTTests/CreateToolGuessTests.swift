import Testing
import Foundation
import MCP
@testable import MeetGPT

/// Куда уйдёт обязательство со звонка, если вендор переименовал инструмент.
///
/// Сначала берутся имена, записанные для сервиса. Сюда доходит только случай
/// переименования — и дальше мы угадываем, на пути ЗАПИСИ в чужой трекер.
///
/// Условию «есть create и есть issue или task» отвечает и
/// `create_issue_comment`. Тогда задача не создаётся, а к какой-то чужой задаче
/// добавляется комментарий: человек подтвердил «создать в Jira», сервер ответил
/// успехом, задачи нет. Порядок инструментов в списке задаёт сам сервер, значит
/// выбор между ними — тоже его.
@Suite struct CreateToolGuessTests {

    private func tool(_ name: String) -> Tool {
        Tool(name: name, description: "", inputSchema: .object([:]),
             annotations: .init(readOnlyHint: false, destructiveHint: false))
    }

    @Test("создание задачи узнаётся", arguments: [
        "create_issue", "createIssue", "create_task", "create_tasks",
        "jira_create_issue", "createJiraIssue", "create_work_task",
    ])
    func realCreatorsAreRecognised(name: String) {
        #expect(tool(name).isCreateTool, "«\(name)» перестал узнаваться — запись сломается на переименовании")
    }

    @Test("создание ПРИ задаче — не создание задачи", arguments: [
        "create_issue_comment", "create_task_comment", "create_issue_link",
        "create_issue_worklog", "create_task_attachment", "create_issue_watcher",
        "create_issue_label", "create_task_reminder", "create_issue_relation",
        "create_issue_transition", "create_task_subscriber",
    ])
    func attachmentsAreNotCreators(name: String) {
        #expect(!tool(name).isCreateTool,
                "«\(name)» сойдёт за создание задачи: обязательство уедет комментарием")
    }

    @Test("посторонние имена не годятся", arguments: [
        "search_issues", "update_task", "delete_issue", "create_page", "list_tasks",
    ])
    func unrelatedNamesAreRefused(name: String) {
        #expect(!tool(name).isCreateTool)
    }

    @Test("записанное имя сильнее догадки")
    func thePreferredNameWins() {
        // Список и догадка должны РАЗОЙТИСЬ, иначе проверка ничего не решает:
        // первая редакция брала пару, где оба пути дают один ответ, и мутация,
        // снявшая список целиком, её прошла.
        //
        // У Asana записано ["create_tasks", "create_task", "createTask"], а
        // догадка взяла бы первый подходящий по порядку сервера — «createTask».
        let picked = TaskWriteback.pickCreateTool(
            from: [tool("create_task_comment"), tool("createTask"), tool("create_tasks")],
            serverID: "asana")
        #expect(picked?.name == "create_tasks",
                "выбран не тот, что записан для сервиса: \(picked?.name ?? "ничего")")
    }

    @Test("догадка не выбирает комментарий, даже если он первый")
    func theGuessSkipsTheComment() {
        // Имена для сервиса не совпали — работает запасное узнавание.
        let picked = TaskWriteback.pickCreateTool(
            from: [tool("create_issue_comment"), tool("create_work_task")], serverID: "linear")
        #expect(picked?.name == "create_work_task")
    }

    @Test("подходящего нет — лучше ничего, чем что-нибудь")
    func nothingIsBetterThanSomething() {
        let picked = TaskWriteback.pickCreateTool(
            from: [tool("create_issue_comment"), tool("search_issues")], serverID: "linear")
        #expect(picked == nil, "запись ушла бы в инструмент, который задач не создаёт")
    }
}
