import Foundation
import MCP

/// Write-back: turn a Tasks-button action item into a real tracker issue/task
/// (Linear / Jira / Asana) via an MCP tool-call — the one place MeetGPT writes
/// to a connected app, always behind the human-confirm the UI enforces. Tool
/// names and argument shapes are resolved from the server's LIVE schema (not
/// hardcoded), so a schema change degrades gracefully instead of mis-calling.
enum TaskWriteback {
    /// Per-server preferred create-tool names; anything not listed falls back to
    /// the `isCreateTool` name heuristic. These are the hosted-MCP trackers whose
    /// task creation we support.
    static let createToolPreferences: [String: [String]] = [
        "linear":    ["create_issue", "createIssue"],
        "atlassian": ["createJiraIssue", "jira_create_issue", "create_issue"],
        // V2 currently advertises the batch-shaped `create_tasks` tool. Keep
        // the singular spellings behind it because Asana explicitly says the
        // live tools/list schema is authoritative and tool names may evolve.
        "asana":     ["create_tasks", "create_task", "createTask"],
    ]

    /// True for servers we offer write-back on.
    static func supportsWriteback(_ serverID: String) -> Bool {
        createToolPreferences[serverID] != nil
    }

    /// Pick the create tool from a server's live tool list: a preferred name
    /// first, else the first tool that looks like an issue/task creator.
    static func pickCreateTool(from tools: [Tool], serverID: String) -> Tool? {
        for name in createToolPreferences[serverID] ?? [] {
            if let tool = tools.first(where: { $0.name == name }) { return tool }
        }
        return tools.first(where: { $0.isCreateTool })
    }

    /// Что сказать человеку про ответ сервера на создание задачи.
    ///
    /// «Задача создана» — утверждение о том, чего мы не видели. Обращение
    /// считается успешным, когда сервер не поставил признак ошибки; сервер,
    /// который ничего не сделал, отвечает ПУСТОТОЙ и признака не ставит.
    /// Пустой ответ прямо превращался в «Задача создана.» — уверенная фраза о
    /// том, чего не было, в самом дорогом месте: человек уходит со звонка,
    /// считая обязательство записанным.
    ///
    /// Правило простое и проверяемое: слова сервиса важнее наших. Есть ответ —
    /// показываем его. Нет ответа — так и говорим, потому что подтверждения у
    /// нас нет.
    static func outcome(of response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Отправлено, но сервис ничего не ответил — подтверждения нет. "
                 + "Проверьте в трекере."
        }
        return String(trimmed.prefix(160))
    }

    /// Fold a task's metadata into a description block. Placeholder markers
    /// ("[OWNER?]", "[DUE?]") are dropped — never write an unstated value.
    static func describe(_ item: TasksArtifact.Item) -> String {
        var lines: [String] = []
        if let owner = item.owner, !owner.contains("[OWNER?]"), !owner.isEmpty {
            lines.append("Владелец: \(owner)")
        }
        if let due = item.due, !due.contains("[DUE?]"), !due.isEmpty {
            lines.append("Срок: \(due)")
        }
        if let check = item.doneCheck, !check.isEmpty { lines.append("Готово, когда: \(check)") }
        if let ref = item.sourceRef, !ref.isEmpty { lines.append("Источник: \(ref)") }
        lines.append("Заведено со звонка в orakul.")
        return lines.joined(separator: "\n")
    }

    /// Build the MCP tool arguments from a task + the tool's schema, merging any
    /// caller-supplied context (teamId / projectId chosen in the confirm UI —
    /// some trackers require it). nil when the schema exposes no string field to
    /// carry the title.
    static func buildArguments(for item: TasksArtifact.Item, tool: Tool,
                               extra: [String: Value] = [:]) -> [String: Value]? {
        // Asana V2's create_tasks input is { tasks: [{ name, ... }], ... }.
        // Resolve that shape from the live schema rather than special-casing
        // the server id, so a compatible schema continues to work if the tool
        // is renamed. Context such as project_id belongs to the task object;
        // default_project and other batch controls remain at the top level.
        if let taskProperties = tool.objectArrayItemProperties(for: "tasks"),
           let titleKey = taskProperties.stringPropertyKey(
               preferring: ["name", "title", "summary"]) {
            var task: [String: Value] = [titleKey: .string(item.task)]
            for key in ["description", "html_notes", "notes", "details"]
                where taskProperties[key] != nil {
                task[key] = .string(describe(item))
                break
            }

            var args: [String: Value] = [:]
            for (key, value) in extra {
                if taskProperties[key] != nil {
                    task[key] = value
                } else {
                    args[key] = value
                }
            }
            args["tasks"] = .array([.object(task)])
            return args
        }

        guard let titleKey = tool.stringArgumentKey(preferring: ["title", "summary", "name"]) else {
            return nil
        }
        var args: [String: Value] = [titleKey: .string(item.task)]
        // Fold the metadata into a description-like field when the schema has one.
        for key in ["description", "body", "content", "details"] where tool.hasArgument(key) {
            args[key] = .string(describe(item))
            break
        }
        // Caller-supplied context wins — it carries required identifiers.
        for (key, value) in extra { args[key] = value }
        return args
    }
}

extension Tool {
    /// Whether this looks like a tracker "create issue/task" tool.
    /// Слова, после которых «создать задачу» перестаёт быть созданием задачи.
    ///
    /// Всё это — создание чего-то ПРИ задаче, а не задачи: комментария, связи,
    /// вложения, записи о работе. Имена настоящие, такие инструменты есть у
    /// трекеров рядом с нужным.
    static let attachedToSomethingElse = [
        "comment", "link", "worklog", "attachment", "relation",
        "watcher", "subscriber", "label", "transition", "reminder",
    ]

    /// Запасное узнавание по имени — и его цена.
    ///
    /// Сначала берутся имена, записанные для этого сервиса. Сюда доходит
    /// только тот случай, когда вендор ПЕРЕИМЕНОВАЛ инструмент, и дальше мы
    /// угадываем — на пути ЗАПИСИ в чужой трекер.
    ///
    /// Условие «есть create и есть issue или task» выполняет и
    /// `create_issue_comment`. Тогда обязательство со звонка ушло бы
    /// комментарием к какой-то задаче: человек подтвердил «создать в Jira»,
    /// сервер ответил успехом, задачи нет. Порядок инструментов задаёт сам
    /// сервер, то есть выбор между ними — тоже его.
    ///
    /// Полностью отказаться от угадывания нельзя: переименование у вендора
    /// сломало бы запись целиком. Но угадывать СОЗДАНИЕ ЗАДАЧИ, а не создание
    /// чего угодно при ней, — можно.
    var isCreateTool: Bool {
        let n = name.lowercased()
        guard n.contains("create"), n.contains("issue") || n.contains("task") else { return false }
        return !Self.attachedToSomethingElse.contains { n.contains($0) }
    }

    /// Properties of an object stored as the items of an array argument.
    /// JSON Schema producers do not consistently repeat `type: object`, so the
    /// structural `properties` member is the compatibility boundary here.
    func objectArrayItemProperties(for argument: String) -> [String: Value]? {
        guard let spec = schemaProperties?[argument],
              case .object(let arraySchema) = spec,
              case .object(let itemSchema)? = arraySchema["items"],
              case .object(let properties)? = itemSchema["properties"] else { return nil }
        return properties
    }
}

private extension Dictionary where Key == String, Value == MCP.Value {
    func stringPropertyKey(preferring preferred: [String]) -> String? {
        for name in preferred {
            guard let spec = self[name], case .object(let details) = spec,
                  case .string(let type)? = details["type"], type == "string" else { continue }
            return name
        }
        for (name, spec) in sorted(by: { $0.key < $1.key }) {
            if case .object(let details) = spec,
               case .string(let type)? = details["type"], type == "string" {
                return name
            }
        }
        return nil
    }
}

extension MCPConnectionManager {
    /// Connected tracker servers that actually expose a create tool right now —
    /// the valid write-back targets for the confirm UI.
    func writebackTargets() -> [MCPServerDescriptor] {
        researchableServers.filter { server in
            TaskWriteback.supportsWriteback(server.id)
                && TaskWriteback.pickCreateTool(from: tools(for: server.id), serverID: server.id) != nil
        }
    }

    /// Create a tracker issue/task from a meeting task via the server's create
    /// tool. Caller (the confirm UI) supplies any required context ids. Returns
    /// the tool's text result — usually the created item's URL or id.
    @discardableResult
    func createTrackerItem(_ item: TasksArtifact.Item, on server: MCPServerDescriptor,
                           extra: [String: Value] = [:],
                           requiredConnectionScope: UInt64? = nil) async throws -> String {
        if let requiredConnectionScope {
            try requireReviewedConnection(
                server, scope: requiredConnectionScope,
                acceptsOverrideTransport: false)
        } else if !isConnected(server.id) {
            await connect(server)
        }
        guard let tool = TaskWriteback.pickCreateTool(from: tools(for: server.id), serverID: server.id) else {
            throw MCPConnectionError.notConnected(server.name, "No task-creation tool is available.")
        }
        guard let args = TaskWriteback.buildArguments(for: item, tool: tool, extra: extra) else {
            throw MCPConnectionError.toolFailed(tool.name, "The tool schema has no title field.")
        }
        return try await callToolText(
            server: server,
            tool: tool.name,
            arguments: args,
            requiredConnectionScope: requiredConnectionScope)
    }
}
