import Foundation
import MCP
import CruxwingCore

/// One piece of background pulled from a connected work app during research.
struct GroundingSnippet: Identifiable, Sendable {
    let id = UUID()
    /// Stable workflow source id (`mcp:notion`, `team:slack`, …). This lets the
    /// activity ledger update the correct preplanned row even when display names
    /// collide. It is never sent to the model.
    let sourceID: String?
    let serverName: String
    let toolName: String
    let text: String
    /// What this source is evidence OF, from `ConnectorProbeStrategy`. Without it
    /// a HubSpot result reads as "some notes about a customer"; with it, as "the
    /// objections this buyer raised last time, which nobody has mentioned today".
    /// The difference decides whether the model uses the snippet or skims past it.
    let readFor: String?
    /// How old this material is, when it was served from cache after the live
    /// call failed. nil for a fresh read.
    ///
    /// It reaches the prompt. A connected app being unreachable is a fact about
    /// the answer, and a half-hour-old CRM note offered as current is worse than
    /// no note at all — the model would reconcile the transcript against stale
    /// state and report the difference as a contradiction in the call.
    let staleAge: TimeInterval?

    init(serverName: String, toolName: String, text: String,
         sourceID: String? = nil, readFor: String? = nil, staleAge: TimeInterval? = nil) {
        self.sourceID = sourceID
        self.serverName = serverName
        self.toolName = toolName
        self.text = text
        self.readFor = readFor
        self.staleAge = staleAge
    }
}

/// Goal-driven research across connected apps: the only input is the call's
/// target. Each connected server is asked through its own search-ish tool
/// (Notion search, Fireflies keyword search, Linear/Jira issue search, …),
/// in parallel; per-server failures are skipped, never fatal.
extension MCPConnectionManager {
    /// Кто из источников не ответил за этот заход — словами, для запроса.
    ///
    /// Берутся отказы, записанные ПОСЛЕ начала веера: `ConnectorHealth` живёт
    /// весь сеанс, и без отсечки по времени в ответ уехал бы вчерашний отказ
    /// сервиса, который сегодня работает.
    /// Память об отказах передаётся, а не берётся глобальная: она общая на
    /// процесс, и проверка, читающая её у соседей, зависит от порядка запуска —
    /// этот капкан репозиторий уже разбирал на общем кэше.
    static func silentSourcesSnippet(since: Date,
                                     health: ConnectorHealth = .shared) async -> GroundingSnippet? {
        let fresh = await health.all().filter { $0.at >= since }
        guard !fresh.isEmpty else { return nil }
        let list = fresh.map { "\($0.service) — \(VendorText.forPerson($0.words))" }
            .joined(separator: "; ")
        return GroundingSnippet(
            serverName: "Sources", toolName: "health",
            text: "Did not answer this question: \(list). "
                + "Their silence does not mean there is nothing there.",
            sourceID: "health:silent",
            readFor: ConnectorProbeStrategy.trackerProbe.readFor)
    }

    /// Что сказать, когда источник не нашёл ничего, но видел лишь часть.
    ///
    /// `.searched` — сервис искал сам, по всему, что у него есть; его пустая
    /// выдача честна, и молчание тут уместно. Всё остальное — перечисление с
    /// границей, ответ из памяти, «просмотрены последние N из 40 000» — значит,
    /// что мы видели ЧАСТЬ. Пустая выдача такого источника не «нет такого», а
    /// «в просмотренной части нет», и это разные утверждения.
    ///
    /// Ровно ради этой разницы и заведён `SearchCoverage` (§7.2). Он ехал
    /// вместе с находками — и пропадал, когда находок не было, то есть в
    /// единственном случае, когда «часть» и «всё» звучат одинаково.
    ///
    /// Проверять нечего изобретать: у `.searched` примечание пустое, у
    /// остальных — нет. Правило и есть это различие.
    nonisolated static func emptyButBounded(_ coverage: SearchCoverage,
                                            subject: SearchCoverage.Subject = .service) -> String? {
        emptyButBounded(note: coverage.note(subject))
    }

    /// То же самое, когда охват приезжает уже строкой: семья своих трекеров
    /// отдаёт `note`, а не сам `SearchCoverage`.
    nonisolated static func emptyButBounded(note: String) -> String? {
        guard !note.isEmpty else { return nil }
        return "Nothing matched, but the search was not exhaustive — \(note)."
    }

    /// Готовый кусок для пустой, но ограниченной выдачи — или ничего.
    ///
    /// Отдельной функцией, а не двумя одинаковыми `guard` на местах: проверка
    /// «оба семейства зовут правило» умеет спросить про ВЫЗОВ и не умеет про
    /// достижимость строки. Мутация, дописавшая `return (index, nil)` перед
    /// прежним кодом, набор проходила — код остался в файле и стал недостижим.
    nonisolated static func boundedEmptySnippet(serverName: String, sourceID: String,
                                                note: String) -> GroundingSnippet? {
        guard let text = emptyButBounded(note: note) else { return nil }
        return GroundingSnippet(serverName: serverName, toolName: "search",
                                text: text, sourceID: sourceID,
                                readFor: ConnectorProbeStrategy.trackerProbe.readFor)
    }


    /// Граница архива словами — та же для найденного и для ненайденного.
    ///
    /// Одна строка на оба случая нарочно: если писать её только при пустой
    /// выдаче, то ответ, построенный на паре сообщений, всё равно умалчивает,
    /// что до этой даты источник слеп.
    nonisolated static func telegramBound(from floor: Date?) -> String {
        guard let floor else {
            return "Telegram coverage: the archive is empty — the bot is connected, but no messages have arrived since. "
                + "Earlier conversation is not available through the Bot API."
        }
        let formatter = DateFormatter()
        formatter.locale = DisplayFormatting.locale
        formatter.dateFormat = "d MMMM yyyy"
        return "Telegram coverage: archived since \(formatter.string(from: floor)). "
            + "Earlier conversation is not available through the Bot API, so its absence here means nothing."
    }


    /// Servers worth querying: live session or silently reconnectable, MINUS the
    /// ones the user has muted.
    ///
    /// The filter belongs here rather than at each call site because this is the
    /// single choke point every consumer of connected-app data already goes
    /// through — grounding, workflow routing, the answer-action planner, task
    /// writeback. Filtering once means a new consumer inherits the mute instead
    /// of having to remember it, and "muted" cannot come to mean different
    /// things in different places.
    var researchableServers: [MCPServerDescriptor] {
        let muted = Config.mutedConnectedApps
        return researchableServersIncludingMuted
            .filter { !muted.contains(Config.mutedAppID(mcpServer: $0.id)) }
    }

    /// Every server that COULD be queried, mute included. Distinct from
    /// `connectedServers`, which is only the ones with a live session THIS
    /// launch — a silently reconnectable server is still usable.
    ///
    /// Display uses this: an app that vanished from the strip when muted would
    /// leave no way to unmute it.
    var researchableServersIncludingMuted: [MCPServerDescriptor] {
        servers.filter { prefersMCP($0.id) }
    }

    /// The read-only search capability discovered during the verified MCP
    /// connection. Workflow design uses its name/description to route custom
    /// servers and user-created prompts without ever selecting write tools.
    func researchTool(for serverID: String) -> Tool? {
        let available = tools(for: serverID)
        for name in Self.searchToolPreferences[serverID] ?? [] {
            if let tool = available.first(where: {
                $0.name == name && MCPImportToolPolicy.isSafeForImport($0)
            }) { return tool }
        }
        return available.first { tool in
            guard MCPImportToolPolicy.isSafeForImport(tool) else { return false }
            return tool.stringArgumentKey(
                preferring: ["query", "keyword", "q", "search", "term", "text"]) != nil
        }
    }

    func researchCapabilityText(for serverID: String) -> [String] {
        guard let tool = researchTool(for: serverID) else { return [] }
        return [tool.name, tool.description ?? ""]
    }

    /// Ask connected apps — MCP servers AND token connectors (Slack,
    /// Confluence) — for material related to the goal.
    /// - Parameters:
    ///   - limitTo: restrict to these catalog server ids (nil = all connected).
    ///     Per-button workflows pass their relevant subset so, e.g., a Tasks run
    ///     queries trackers but not Sentry.
    ///   - includeTeam: whether the token connectors are queried too.
    func groundingSnippets(goal: String,
                           limitTo: Set<String>? = nil,
                           includeTeam: Bool = true,
                           maxCharsPerSource: Int = 4000,
                           maxSources: Int? = nil) async -> [GroundingSnippet] {
        let allTargets = researchableServers.filter { limitTo?.contains($0.id) ?? true }
        let allTeamServices = includeTeam ? TeamConnectors.configured : []
        let mcpCandidates = allTargets.map { server -> GroundingContextPolicy.SourceCandidate in
            let probe = ConnectorProbeStrategy.probe(forServerID: server.id)
            return GroundingContextPolicy.SourceCandidate(
                id: "mcp:\(server.id)",
                searchableText: ([server.id, server.name] + server.keywords
                    + [probe?.queryHint ?? "", probe?.readFor ?? ""])
                    .joined(separator: " "),
                strongFor: probe?.strongFor ?? [])
        }
        // Российские трекеры — такие же токенные коннекторы, как Slack: не MCP,
        // но отвечают на тот же вопрос, что Linear и Jira. Проходят через тот
        // же подбор источников, иначе подключённый Яндекс Трекер молчал бы,
        // а Linear отвечал.
        let allTrackers = includeTeam ? trackerStore.configured : []
        let trackerCandidates = allTrackers.map { service -> GroundingContextPolicy.SourceCandidate in
            GroundingContextPolicy.SourceCandidate(
                id: "tracker:\(service.rawValue)",
                searchableText: [service.rawValue, service.title,
                                 ConnectorProbeStrategy.trackerProbe.queryHint]
                    .joined(separator: " "),
                strongFor: ConnectorProbeStrategy.trackerProbe.strongFor)
        }
        // GitHub — источник того же рода: задачи команды, только не через MCP
        // (у GitHub нет динамической регистрации клиента, см. GitHubConnector).
        let githubReady = includeTeam && trackerStore.isGitHubReady
        let githubCandidates: [GroundingContextPolicy.SourceCandidate] = githubReady
            ? [GroundingContextPolicy.SourceCandidate(
                id: "github",
                searchableText: "github issues pull requests задачи пулл-реквесты "
                    + ConnectorProbeStrategy.trackerProbe.queryHint,
                strongFor: ConnectorProbeStrategy.trackerProbe.strongFor)]
            : []

        // Рабочие мессенджеры — тот же род источника, но отвечают на другой
        // вопрос: не «заводили ли задачу», а «обсуждали ли это». Ответ на
        // второй чаще лежит в переписке, чем в трекере.
        let allMessengers = includeTeam ? trackerStore.configuredMessengers : []
        let messengerCandidates = allMessengers.map { service -> GroundingContextPolicy.SourceCandidate in
            GroundingContextPolicy.SourceCandidate(
                id: "messenger:\(service.rawValue)",
                searchableText: [service.rawValue, service.title,
                                 "переписка чат сообщения обсуждали писали"]
                    .joined(separator: " "),
                strongFor: ConnectorProbeStrategy.trackerProbe.strongFor)
        }
        let telegramReady = includeTeam && trackerStore.isTelegramConfigured
        let telegramCandidates: [GroundingContextPolicy.SourceCandidate] = telegramReady
            ? [GroundingContextPolicy.SourceCandidate(
                id: "messenger:telegram",
                searchableText: "telegram телеграм супергруппа чат сообщения переписка обсуждали писали",
                strongFor: ConnectorProbeStrategy.trackerProbe.strongFor)]
            : []

        // Открытые трекеры на своём сервере — тот же вопрос, что у GitHub,
        // только адрес свой.
        let allSelfHosted = includeTeam ? trackerStore.configuredSelfHosted : []
        let selfHostedCandidates = allSelfHosted.map { service -> GroundingContextPolicy.SourceCandidate in
            GroundingContextPolicy.SourceCandidate(
                id: "selfhosted:\(service.rawValue)",
                searchableText: [service.rawValue, service.title,
                                 ConnectorProbeStrategy.trackerProbe.queryHint]
                    .joined(separator: " "),
                strongFor: ConnectorProbeStrategy.trackerProbe.strongFor)
        }

        // База знаний — третий вопрос: не «заводили» и не «обсуждали», а
        // «описывали». Решение, записанное в вики полгода назад, не найдётся
        // ни в задачах, ни в переписке.
        let allNotes = includeTeam ? trackerStore.configuredNotes : []
        let notesCandidates = allNotes.map { service -> GroundingContextPolicy.SourceCandidate in
            GroundingContextPolicy.SourceCandidate(
                id: "notes:\(service.rawValue)",
                searchableText: [service.rawValue, service.title,
                                 "вики база знаний документация описывали заметки"]
                    .joined(separator: " "),
                strongFor: ConnectorProbeStrategy.trackerProbe.strongFor)
        }

        // Западные трекеры — тот же вопрос, что у GitHub, только сервис
        // облачный. Без этого они отвечали бы только из командной строки, а на
        // звонке молчали: настройки есть, а источника в веере нет.
        let allWestern = includeTeam ? trackerStore.configuredWestern : []
        let westernCandidates = allWestern.map { service -> GroundingContextPolicy.SourceCandidate in
            GroundingContextPolicy.SourceCandidate(
                id: "western:\(service.rawValue)",
                searchableText: [service.rawValue, service.title,
                                 ConnectorProbeStrategy.trackerProbe.queryHint]
                    .joined(separator: " "),
                strongFor: ConnectorProbeStrategy.trackerProbe.strongFor)
        }

        // Заметки на этом компьютере. Единственный источник, который отвечает
        // без сети, — и единственный, у которого нет ни токена, ни сервиса:
        // есть выбранная папка или её нет.
        let localNotesReady = includeTeam && LocalNotesFolder.live.isConfigured
        let localNotesCandidates: [GroundingContextPolicy.SourceCandidate] = localNotesReady
            ? [GroundingContextPolicy.SourceCandidate(
                id: "notes-local",
                searchableText: "заметки obsidian markdown записи мои файлы на компьютере "
                    + "вики база знаний описывали",
                strongFor: ConnectorProbeStrategy.trackerProbe.strongFor)]
            : []

        let teamCandidates = allTeamServices.map { service -> GroundingContextPolicy.SourceCandidate in
            let probe = ConnectorProbeStrategy.probe(forTeamService: service.rawValue)
            return GroundingContextPolicy.SourceCandidate(
                id: "team:\(service.rawValue)",
                searchableText: [service.rawValue, service.label,
                                 probe?.queryHint ?? "", probe?.readFor ?? ""]
                    .joined(separator: " "),
                strongFor: probe?.strongFor ?? [])
        }
        let selected = GroundingContextPolicy.selectSources(
            trackerCandidates + githubCandidates + messengerCandidates + telegramCandidates
                + selfHostedCandidates + notesCandidates + westernCandidates
                + localNotesCandidates + mcpCandidates + teamCandidates,
            query: goal,
            tier: Config.currentTier,
            requestedLimit: maxSources)
        // Selection happens before task creation: a one-source Blind Spot run
        // creates one connector request, rather than fetching everything and
        // discarding all but the first response afterward.
        let targets: [MCPServerDescriptor] = selected.compactMap {
            candidate -> MCPServerDescriptor? in
            guard candidate.id.hasPrefix("mcp:") else { return nil }
            // Тип проставлен явно: у `+` десятки перегрузок, и цепочка из шести
            // слагаемых с тернарником перебиралась почти секунду на каждое место
            // вызова — пока сборка не начала падать с «unable to type-check».
            let id = String(candidate.id.dropFirst("mcp:".count))
            return allTargets.first { $0.id == id }
        }
        let teamServices: [TeamService] = selected.compactMap {
            candidate -> TeamService? in
            guard candidate.id.hasPrefix("team:") else { return nil }
            let id = String(candidate.id.dropFirst("team:".count))
            return allTeamServices.first { $0.rawValue == id }
        }
        let trackerServices: [RussianTrackers.Service] = selected.compactMap {
            candidate -> RussianTrackers.Service? in
            guard candidate.id.hasPrefix("tracker:") else { return nil }
            let id = String(candidate.id.dropFirst("tracker:".count))
            return allTrackers.first { $0.rawValue == id }
        }
        let messengerServices: [WorkMessengers.Service] = selected.compactMap {
            candidate -> WorkMessengers.Service? in
            guard candidate.id.hasPrefix("messenger:") else { return nil }
            let id = String(candidate.id.dropFirst("messenger:".count))
            return allMessengers.first { $0.rawValue == id }
        }
        let selfHostedServices: [SelfHostedTrackers.Service] = selected.compactMap {
            candidate -> SelfHostedTrackers.Service? in
            guard candidate.id.hasPrefix("selfhosted:") else { return nil }
            let id = String(candidate.id.dropFirst("selfhosted:".count))
            return allSelfHosted.first { $0.rawValue == id }
        }
        let notesServices: [TeamNotes.Service] = selected.compactMap {
            candidate -> TeamNotes.Service? in
            guard candidate.id.hasPrefix("notes:") else { return nil }
            let id = String(candidate.id.dropFirst("notes:".count))
            return allNotes.first { $0.rawValue == id }
        }
        let westernServices: [WesternTrackers.Service] = selected.compactMap {
            candidate -> WesternTrackers.Service? in
            guard candidate.id.hasPrefix("western:") else { return nil }
            let id = String(candidate.id.dropFirst("western:".count))
            return allWestern.first { $0.rawValue == id }
        }
        let localNotesSelected = selected.contains { $0.id == "notes-local" }
        let githubSelected = selected.contains { $0.id == "github" }
        let telegramSelected = selected.contains { $0.id == "messenger:telegram" }
        guard !targets.isEmpty || !teamServices.isEmpty || !trackerServices.isEmpty
                || githubSelected || !messengerServices.isEmpty
                || telegramSelected
                || !selfHostedServices.isEmpty || !notesServices.isEmpty
                || !westernServices.isEmpty || localNotesSelected
        else { return [] }
        // Тип результата закрытия проставлен явно. Без него компилятор
        // выводит его из семи веток `group.addTask` разом и перестаёт
        // укладываться в отведённое время — сборка падает не ошибкой в
        // коде, а «unable to type-check in reasonable time».
        // Отсечка по времени для отказов: ConnectorHealth живёт весь сеанс,
        // и без неё в ответ уехал бы вчерашний отказ сервиса, который
        // сегодня работает.
        let startedAt = Date()
        return await withTaskGroup(of: (Int, GroundingSnippet?).self) { group -> [GroundingSnippet] in
            for (index, server) in targets.enumerated() {
                group.addTask { @MainActor in
                    (index, await self.researchOne(
                        server: server, goal: goal, cap: maxCharsPerSource))
                }
            }
            for (offset, service) in teamServices.enumerated() {
                let index: Int = targets.count + offset
                group.addTask {
                    let query = ConnectorProbeStrategy.query(goal: goal, serverID: service.rawValue,
                                                                 destination: .literalSearch)
                    guard let text = await TeamConnectors.search(service, query: query, cap: maxCharsPerSource),
                          !text.isEmpty else { return (index, nil) }
                    return (index, GroundingSnippet(
                        serverName: service.label, toolName: "search", text: text,
                        sourceID: "team:\(service.rawValue)",
                        readFor: ConnectorProbeStrategy.probe(
                            forTeamService: service.rawValue)?.readFor))
                }
            }
            let store = trackerStore
            let http = trackerHTTP
            for (offset, service) in trackerServices.enumerated() {
                let index: Int = targets.count + teamServices.count + offset
                group.addTask {
                    let query = ConnectorProbeStrategy.query(
                        goal: goal, serverID: service.rawValue,
                        destination: .literalSearch)
                    guard let text = await store.searchText(
                        service, query: query, cap: maxCharsPerSource, http: http),
                          !text.isEmpty else { return (index, nil) }
                    return (index, GroundingSnippet(
                        serverName: service.title, toolName: "search",
                        text: text, sourceID: "tracker:\(service.rawValue)",
                        readFor: ConnectorProbeStrategy.trackerProbe.readFor))
                }
            }
            let githubCount: Int = githubSelected ? 1 : 0
            // База знаний идёт после открытых трекеров.
            // Сложение разбито по шагам не ради читаемости: одной цепочкой из
            // шести слагаемых с тернарником оно проверялось 8,8 с, и после
            // подключения второго модуля сборка стала падать не ошибкой в коде,
            // а «unable to type-check this expression in reasonable time».
            // Замер: -Xfrontend -warn-long-expression-type-checking.
            var notesBase: Int = targets.count
            notesBase += teamServices.count
            notesBase += trackerServices.count
            notesBase += githubCount
            notesBase += messengerServices.count
            notesBase += selfHostedServices.count
            for (offset, service) in notesServices.enumerated() {
                let index = notesBase + offset
                let store = trackerStore
                let http = notesHTTP
                group.addTask {
                    let query = ConnectorProbeStrategy.query(
                        goal: goal, serverID: service.rawValue,
                        destination: .literalSearch)
                    guard let client = store.notesClient(for: service, http: http) else { return (index, nil) }
                    // Срок тот же, что у MCP-инструмента: зависший сервис должен
                    // стоить одного источника, а не всего ответа на звонке.
                    // `timeoutInterval` у запроса этого не даёт — он сбрасывается
                    // на каждом принятом байте, и сервер, отдающий по байту,
                    // держит соединение сколько угодно.
                    // Отказ записывается, а не растворяется.
                    //
                    // Ответ на звонке от этого не меняется: упавший источник
                    // по-прежнему стоит одного источника, а не всего ответа.
                    // Меняется другое — «сервис отказал» перестаёт выглядеть
                    // так же, как «в вики про это ничего нет». Отозванный
                    // токен иначе неотличим от продукта, который стал хуже
                    // отвечать, и чинить человек пойдёт не то.
                    let hits = await withMCPDeadline(seconds: Self.groundingDeadline) {
                        do {
                            let found = try await client.search(query)
                            await ConnectorHealth.shared.recordSuccess(service: service.rawValue)
                            return found
                        } catch {
                            await ConnectorHealth.shared.record(service: service.rawValue, error: error)
                            throw error
                        }
                    }
                    guard let hits else {
                        await ConnectorHealth.shared.recordTimeout(
                            service: service.rawValue, seconds: Self.groundingDeadline)
                        return (index, nil)
                    }
                    guard !hits.isEmpty else { return (index, nil) }
                    let text = hits.prefix(10)
                        .map { "[\($0.title)] \($0.context)" }
                        .joined(separator: "\n")
                        .prefix(maxCharsPerSource).description
                    return (index, GroundingSnippet(
                        serverName: service.title, toolName: "search",
                        text: text, sourceID: "notes:\(service.rawValue)",
                        readFor: ConnectorProbeStrategy.trackerProbe.readFor))
                }
            }
            // Открытые трекеры идут последними, после мессенджеров.
            var selfHostedBase: Int = targets.count
            selfHostedBase += teamServices.count
            selfHostedBase += trackerServices.count
            selfHostedBase += githubCount
            selfHostedBase += messengerServices.count
            for (offset, service) in selfHostedServices.enumerated() {
                let index = selfHostedBase + offset
                let store = trackerStore
                let http = selfHostedHTTP
                group.addTask {
                    let query = ConnectorProbeStrategy.query(
                        goal: goal, serverID: service.rawValue,
                        destination: .literalSearch)
                    guard let client = store.selfHostedClient(for: service, http: http) else { return (index, nil) }
                    // Срок тот же, что у MCP-инструмента: зависший сервис должен
                    // стоить одного источника, а не всего ответа на звонке.
                    // `timeoutInterval` у запроса этого не даёт — он сбрасывается
                    // на каждом принятом байте, и сервер, отдающий по байту,
                    // держит соединение сколько угодно.
                    // Отказ записывается, а не растворяется.
                    //
                    // Ответ на звонке от этого не меняется: упавший источник
                    // по-прежнему стоит одного источника, а не всего ответа.
                    // Меняется другое — «сервис отказал» перестаёт выглядеть
                    // так же, как «в вики про это ничего нет». Отозванный
                    // токен иначе неотличим от продукта, который стал хуже
                    // отвечать, и чинить человек пойдёт не то.
                    let outcome = await withMCPDeadline(seconds: Self.groundingDeadline) {
                        do {
                            let found = try await client.run(query)
                            await ConnectorHealth.shared.recordSuccess(service: service.rawValue)
                            return found
                        } catch {
                            await ConnectorHealth.shared.record(service: service.rawValue, error: error)
                            throw error
                        }
                    }
                    // Молчание тоже записывается: `withMCPDeadline` отдаёт nil
                    // и на отказе, и на истёкшем сроке, а для человека это
                    // разные починки. Отказ уже записан выше, в `catch`;
                    // здесь остаётся тот случай, когда сервис просто тянул.
                    guard let outcome else {
                        await ConnectorHealth.shared.recordTimeout(
                            service: service.rawValue, seconds: Self.groundingDeadline)
                        return (index, nil)
                    }
                    guard !outcome.items.isEmpty else {
                        return (index, Self.boundedEmptySnippet(
                            serverName: service.title,
                            sourceID: "selfhosted:\(service.rawValue)",
                            note: outcome.note))
                    }
                    // Состояние задачи в тексте: «уже закрыто» меняет смысл
                    // находки на противоположный. Охват — по той же причине:
                    // часть списка, выданная за весь, меняет смысл ответа так
                    // же сильно.
                    let text = Self.withCoverage(
                        outcome.items.prefix(10)
                            .map { "\(IssueLabel.render(key: $0.key, state: $0.state)) \($0.title)" }
                            .joined(separator: "\n"),
                        note: outcome.note, limit: maxCharsPerSource)
                    return (index, GroundingSnippet(
                        serverName: service.title, toolName: "search",
                        text: text, sourceID: "selfhosted:\(service.rawValue)",
                        readFor: ConnectorProbeStrategy.trackerProbe.readFor))
                }
            }
            // Мессенджеры идут после GitHub, поэтому и смещение считается от
            // него. Индексы здесь ручные: результаты собираются по позиции, и
            // сдвиг на единицу подменил бы источник у сниппета.
            var messengerBase: Int = targets.count
            messengerBase += teamServices.count
            messengerBase += trackerServices.count
            messengerBase += githubCount
            for (offset, service) in messengerServices.enumerated() {
                let index = messengerBase + offset
                let store = trackerStore
                let http = messengerHTTP
                group.addTask {
                    let query = ConnectorProbeStrategy.query(
                        goal: goal, serverID: service.rawValue,
                        destination: .literalSearch)
                    guard let client = store.messengerClient(for: service, http: http) else { return (index, nil) }
                    // Срок тот же, что у MCP-инструмента: зависший сервис должен
                    // стоить одного источника, а не всего ответа на звонке.
                    // `timeoutInterval` у запроса этого не даёт — он сбрасывается
                    // на каждом принятом байте, и сервер, отдающий по байту,
                    // держит соединение сколько угодно.
                    // Отказ записывается, а не растворяется.
                    //
                    // Ответ на звонке от этого не меняется: упавший источник
                    // по-прежнему стоит одного источника, а не всего ответа.
                    // Меняется другое — «сервис отказал» перестаёт выглядеть
                    // так же, как «в вики про это ничего нет». Отозванный
                    // токен иначе неотличим от продукта, который стал хуже
                    // отвечать, и чинить человек пойдёт не то.
                    let hits = await withMCPDeadline(seconds: Self.groundingDeadline) {
                        do {
                            let found = try await client.search(query)
                            await ConnectorHealth.shared.recordSuccess(service: service.rawValue)
                            return found
                        } catch {
                            await ConnectorHealth.shared.record(service: service.rawValue, error: error)
                            throw error
                        }
                    }
                    guard let hits else {
                        await ConnectorHealth.shared.recordTimeout(
                            service: service.rawValue, seconds: Self.groundingDeadline)
                        return (index, nil)
                    }
                    guard !hits.isEmpty else { return (index, nil) }
                    // Автор попадает в текст: «это писала Полина» меняет вес
                    // находки, а по одному тексту сообщения этого не видно.
                    let text = hits.prefix(10)
                        .map { hit in
                            hit.author.map { "[\($0)] \(hit.text)" } ?? hit.text
                        }
                        .joined(separator: "\n")
                        .prefix(maxCharsPerSource).description
                    return (index, GroundingSnippet(
                        serverName: service.title, toolName: "search",
                        text: text, sourceID: "messenger:\(service.rawValue)",
                        readFor: ConnectorProbeStrategy.trackerProbe.readFor))
                }
            }
            if telegramSelected,
               let token = trackerStore.telegramToken() {
                let chatIDs = trackerStore.telegramAllowedChatIDs()
                let botID = trackerStore.telegramBotID()
                let source = telegramSource
                var index: Int = targets.count
                index += teamServices.count
                index += trackerServices.count
                index += githubCount
                index += messengerServices.count
                index += selfHostedServices.count
                index += notesServices.count
                group.addTask {
                    try? await source.ensureStarted(
                        token: token, allowedChatIDs: chatIDs,
                        botID: botID)
                    let query = ConnectorProbeStrategy.query(goal: goal, serverID: "telegram",
                                                                 destination: .literalSearch)
                    let hits = await source.search(query, limit: 10)
                    // Пустая выдача этого источника — не «не обсуждали».
                    //
                    // Bot API старую переписку не отдаёт: архив начинается в тот
                    // момент, когда подключили бота. Молчание источника читалось
                    // как «в переписке ничего нет», хотя честное утверждение —
                    // «до такого-то числа мы не видели ничего». Это разные вещи,
                    // и вторая иногда и есть ответ: обсуждали раньше.
                    //
                    // Поэтому источник отвечает всегда, а не только когда нашёл.
                    let floor = await source.archiveStart()
                    let bound = Self.telegramBound(from: floor)
                    guard !hits.isEmpty else {
                        return (index, GroundingSnippet(
                            serverName: "Telegram", toolName: "local_archive_search",
                            text: bound, sourceID: "messenger:telegram",
                            readFor: ConnectorProbeStrategy.trackerProbe.readFor))
                    }
                    let text = hits.map { hit in
                        let topic = hit.message.topicID.map { " · topic \($0)" } ?? ""
                        let author = hit.message.author.map { "[\($0)] " } ?? ""
                        return "[\(hit.message.chatTitle)\(topic)] \(author)\(hit.message.text)"
                    }
                    .joined(separator: "\n")
                    .prefix(maxCharsPerSource).description
                    return (index, GroundingSnippet(
                        serverName: "Telegram", toolName: "local_archive_search",
                        text: text + "\n" + bound, sourceID: "messenger:telegram",
                        readFor: ConnectorProbeStrategy.trackerProbe.readFor))
                }
            }
            if githubSelected {
                let index: Int = targets.count + teamServices.count + trackerServices.count
                let store = trackerStore
                let http = trackerHTTP
                group.addTask {
                    let query = ConnectorProbeStrategy.query(goal: goal, serverID: "github",
                                                                 destination: .literalSearch)
                    guard let client = store.githubClient(http: http) else { return (index, nil) }
                    // Срок тот же, что у MCP-инструмента: зависший сервис должен
                    // стоить одного источника, а не всего ответа на звонке.
                    // `timeoutInterval` у запроса этого не даёт — он сбрасывается
                    // на каждом принятом байте, и сервер, отдающий по байту,
                    // держит соединение сколько угодно.
                    // Отказ записывается, а не растворяется.
                    //
                    // Ответ на звонке от этого не меняется: упавший источник
                    // по-прежнему стоит одного источника, а не всего ответа.
                    // Меняется другое — «сервис отказал» перестаёт выглядеть
                    // так же, как «в вики про это ничего нет». Отозванный
                    // токен иначе неотличим от продукта, который стал хуже
                    // отвечать, и чинить человек пойдёт не то.
                    let items = await withMCPDeadline(seconds: Self.groundingDeadline) {
                        do {
                            let found = try await client.search(query)
                            await ConnectorHealth.shared.recordSuccess(service: "github")
                            return found
                        } catch {
                            await ConnectorHealth.shared.record(service: "github", error: error)
                            throw error
                        }
                    }
                    guard let items else {
                        await ConnectorHealth.shared.recordTimeout(
                            service: "github", seconds: Self.groundingDeadline)
                        return (index, nil)
                    }
                    guard !items.isEmpty else { return (index, nil) }
                    // Состояние задачи попадает в текст: «уже закрыто» меняет
                    // смысл находки на противоположный, а по одному заголовку
                    // этого не видно.
                    let text = items.prefix(10)
                        .map { "\(IssueLabel.render(key: $0.key, state: $0.state)) \($0.title)" }
                        .joined(separator: "\n")
                        .prefix(maxCharsPerSource).description
                    return (index, GroundingSnippet(
                        serverName: "GitHub", toolName: "search",
                        text: text, sourceID: "github",
                        readFor: ConnectorProbeStrategy.trackerProbe.readFor))
                }
            }

            // Западные трекеры и заметки на диске идут последними: их смещение
            // считается от суммы всех предыдущих. Сложение по шагам — по той же
            // причине, что выше: одной цепочкой оно перестаёт проверяться по
            // типам за отведённое время, и сборка падает не ошибкой в коде.
            var westernBase: Int = targets.count
            westernBase += teamServices.count
            westernBase += trackerServices.count
            westernBase += githubCount
            westernBase += messengerServices.count
            westernBase += selfHostedServices.count
            westernBase += notesServices.count
            for (offset, service) in westernServices.enumerated() {
                let index = westernBase + offset
                let store = trackerStore
                let http = westernHTTP
                group.addTask {
                    let query = ConnectorProbeStrategy.query(
                        goal: goal, serverID: service.rawValue,
                        destination: .literalSearch)
                    guard let client = store.westernClient(for: service, http: http) else {
                        return (index, nil)
                    }
                    // Отказ записывается, а не растворяется.
                    //
                    // Ответ на звонке от этого не меняется: упавший источник
                    // по-прежнему стоит одного источника, а не всего ответа.
                    // Меняется другое — «сервис отказал» перестаёт выглядеть
                    // так же, как «в вики про это ничего нет». Отозванный
                    // токен иначе неотличим от продукта, который стал хуже
                    // отвечать, и чинить человек пойдёт не то.
                    let outcome = await withMCPDeadline(seconds: Self.groundingDeadline) {
                        do {
                            // `run`, а не `search`: второе отдаёт находки без
                            // охвата, и человеку на звонке доезжало «вот что
                            // есть в Plane» там, где прочитаны пятьсот строк
                            // из полутора тысяч. То же и с ответом из памяти:
                            // сервис попросил обращаться реже, ответу минута,
                            // и об этом надо сказать.
                            let found = try await client.run(query)
                            await ConnectorHealth.shared.recordSuccess(service: service.rawValue)
                            return found
                        } catch {
                            await ConnectorHealth.shared.record(service: service.rawValue, error: error)
                            throw error
                        }
                    }
                    // Молчание тоже записывается: `withMCPDeadline` отдаёт nil
                    // и на отказе, и на истёкшем сроке, а для человека это
                    // разные починки. Отказ уже записан выше, в `catch`;
                    // здесь остаётся тот случай, когда сервис просто тянул.
                    guard let outcome else {
                        await ConnectorHealth.shared.recordTimeout(
                            service: service.rawValue, seconds: Self.groundingDeadline)
                        return (index, nil)
                    }
                    guard !outcome.items.isEmpty else {
                        return (index, Self.boundedEmptySnippet(
                            serverName: service.title,
                            sourceID: "western:\(service.rawValue)",
                            note: outcome.coverage.note()))
                    }
                    let text = Self.withCoverage(
                        outcome.items.prefix(10)
                            .map { "\(IssueLabel.render(key: $0.key, state: $0.state)) \($0.title)" }
                            .joined(separator: "\n"),
                        note: outcome.coverage.note(), limit: maxCharsPerSource)
                    return (index, GroundingSnippet(
                        serverName: service.title, toolName: "search",
                        text: text, sourceID: "western:\(service.rawValue)",
                        readFor: ConnectorProbeStrategy.trackerProbe.readFor))
                }
            }

            if localNotesSelected {
                var index: Int = westernBase
                index += westernServices.count
                group.addTask {
                    let query = ConnectorProbeStrategy.query(goal: goal, serverID: "notes-local",
                                                            destination: .literalSearch)
                    // Срок тот же, что у сетевых источников. Диск обычно
                    // быстрее сети, но хранилище на сетевом диске — нет, и
                    // ждать его весь звонок не стоит.
                    let found = await withMCPDeadline(seconds: Self.groundingDeadline) {
                        LocalNotesFolder.live.search(query)
                    }
                    guard let found = found ?? nil else { return (index, nil) }
                    // Пустая выдача хранилища — тот самый случай, про который
                    // написано ниже: модель, не услышавшая ничего, отвечает «в
                    // заметках этого нет», а мы смотрели последние две тысячи
                    // файлов из восьми. Довод стоял рядом и применялся только
                    // к непустой выдаче.
                    guard !found.hits.isEmpty else {
                        return (index, Self.boundedEmptySnippet(
                            serverName: "Notes", sourceID: "notes-local",
                            note: found.coverage.note(.folder)))
                    }
                    var text = found.hits.prefix(10)
                        .map { "[\($0.path)] \($0.context)" }
                        .joined(separator: "\n")
                    // Охват дописывается к тексту: модель, получившая часть
                    // хранилища как целое, ответит «в заметках этого нет» —
                    // а мы смотрели последние две тысячи файлов из восьми.
                    let note = found.coverage.note(.folder)
                    if case .latest = found.coverage, !note.isEmpty {
                        text += "\n(\(note))"
                    }
                    return (index, GroundingSnippet(
                        serverName: "Notes", toolName: "search",
                        text: text.prefix(maxCharsPerSource).description,
                        sourceID: "notes-local",
                        readFor: ConnectorProbeStrategy.trackerProbe.readFor))
                }
            }

            var snippets: [(Int, GroundingSnippet)] = []
            for await (index, snippet) in group {
                if let snippet { snippets.append((index, snippet)) }
            }
            var ordered = snippets.sorted { $0.0 < $1.0 }.map(\.1)
            // Источник, который НЕ ОТВЕТИЛ, — не то же самое, что источник,
            // который ответил пусто.
            //
            // Отказы записываются (`ConnectorHealth`) и показываются человеку —
            // в настройках, на строке сервиса. До запроса они не доезжали
            // никогда. Значит звонок, на котором трекер тянул, вики отказала, а
            // мессенджер придушили, давал ответ, построенный на одной
            // расшифровке, и выглядел он в точности как проверенный по
            // источникам. Это тот же «уверенное утверждение о непроверенном»,
            // только собранное из молчания трёх сервисов сразу.
            //
            // Недружелюбному сервису этого достаточно: не отвечать. Ни отказа,
            // ни ошибки — просто тишина, которую мы выдавали за отсутствие.
            if let silence = await Self.silentSourcesSnippet(since: startedAt) {
                ordered.append(silence)
            }
            return ordered
        }
    }

    // MARK: - Per-server research

    /// Known-good search tools per catalog server; anything else falls back to
    /// the first tool whose name contains "search".
    static let searchToolPreferences: [String: [String]] = [
        "notion": ["notion-search"],
        "fireflies": ["fireflies_get_transcripts", "fireflies_search"],
        // Asana V2's universal search works for every workspace tier; the more
        // specific search_tasks tool requires a Premium workspace.
        "asana": ["search_objects", "search_tasks"],
        // Not optional for Gmail. `list_drafts` also exposes a `query`
        // argument and is listed BEFORE `search_threads`, so the generic
        // readable-tool fallback picks it and researches the user's own
        // unsent drafts instead of their mail.
        "gmail": ["search_threads"],
        // GA4 exposes get_metadata and check_compatibility, which describe the
        // property rather than report on it — the readable-tool heuristic would
        // happily pick one and return a schema instead of a number.
        "google-analytics": ["run_report", "run_realtime_report"],
    ]

    private func researchOne(server: MCPServerDescriptor, goal: String, cap: Int) async -> GroundingSnippet? {
        guard let tool = await findSearchTool(server: server) else { return nil }

        // Capture provenance after connection. Disconnect, reconnect, or a
        // Cruxwing account transition advances this synchronously. Every await
        // below revalidates it so an old-account hit/network response cannot be
        // returned or stored after the boundary changes underneath the task.
        let cacheScope = groundingCacheScope

        // The goal rides in whichever string property the schema declares — but
        // biased per connector. Sending the raw goal to every server asked a bug
        // tracker and a CRM the same question and got a generic answer from both.
        let query = ConnectorProbeStrategy.query(goal: goal, serverID: server.id)
        guard let arguments = Self.researchArguments(
            tool: tool, serverID: server.id, query: query) else { return nil }

        let sourceID = "mcp:\(server.id)"
        let breakerID = "\(cacheScope)|\(server.id)"
        let cacheKey = MCPResultCache.key(
            sourceID: sourceID, tool: tool.name, query: query, scope: cacheScope)
        let telemetryRequestID = makeConnectorTelemetryRequestID()
        let retryCount = await groundingCache.consecutiveFailures(serverID: breakerID)
        let callArguments = arguments
        let readFor = ConnectorProbeStrategy.probe(forServerID: server.id)?.readFor

        func snippet(_ text: String, staleAge: TimeInterval?) -> GroundingSnippet {
            GroundingSnippet(serverName: server.name, toolName: tool.name,
                             text: String(text.prefix(cap)), sourceID: sourceID,
                             readFor: readFor, staleAge: staleAge)
        }

        // Still fresh: the same goal is re-queried every tick of a five-minute
        // loop, and a tracker does not change between two of them.
        if let hit = await groundingCache.fresh(cacheKey) {
            guard cacheScope == groundingCacheScope else { return nil }
            recordConnectorCacheTelemetry(
                server: server,
                toolName: tool.name,
                requestID: telemetryRequestID,
                result: .freshHit,
                age: hit.age,
                retryCount: retryCount)
            return snippet(hit.text, staleAge: nil)
        }

        // This server has been failing; do not dial it again yet. Its last good
        // answer still counts, labelled.
        if await groundingCache.isOpen(serverID: breakerID) {
            let stale = await groundingCache.stale(cacheKey)
            guard cacheScope == groundingCacheScope else { return nil }
            recordConnectorCacheTelemetry(
                server: server,
                toolName: tool.name,
                requestID: telemetryRequestID,
                result: .circuitOpen,
                age: stale?.age,
                retryCount: retryCount,
                status: .offline)
            return stale.map { snippet($0.text, staleAge: $0.age) }
        }

        // A deadline, so one wedged app costs one source instead of the run.
        let text = await withMCPDeadline(seconds: Self.groundingDeadline) { [weak self] in
            try await self?.callToolText(
                server: server,
                tool: tool.name,
                arguments: callArguments,
                telemetryContext: ConnectorTelemetryContext(
                    requestID: telemetryRequestID,
                    cacheResult: .miss,
                    retryCount: retryCount))
        } ?? nil

        guard cacheScope == groundingCacheScope else { return nil }

        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await groundingCache.recordFailure(serverID: breakerID)
            let stale = await groundingCache.stale(cacheKey)
            guard cacheScope == groundingCacheScope else { return nil }
            if let stale {
                recordConnectorCacheTelemetry(
                    server: server,
                    toolName: tool.name,
                    requestID: telemetryRequestID,
                    result: .staleFallback,
                    age: stale.age,
                    retryCount: retryCount)
            }
            return stale.map { snippet($0.text, staleAge: $0.age) }
        }
        await groundingCache.store(cacheKey, text: text, serverID: breakerID)
        guard cacheScope == groundingCacheScope else { return nil }
        return snippet(text, staleAge: nil)
    }

    /// Schema-driven read arguments, pure so connector contracts can be tested
    /// without opening a browser or starting an MCP transport.
    static func researchArguments(tool: Tool, serverID: String,
                                  query: String) -> [String: Value]? {
        guard let key = tool.stringArgumentKey(
            preferring: ["query", "keyword", "q", "search", "term", "text"]) else { return nil }
        var arguments: [String: Value] = [key: .string(query)]
        // Verified live on Fireflies: cap results, search titles+content, and
        // prefer its compact JSON response shape.
        if tool.hasArgument("limit") { arguments["limit"] = .int(3) }
        if tool.hasArgument("scope") { arguments["scope"] = .string("all") }
        if tool.hasArgument("format") { arguments["format"] = .string("json") }
        // search_objects spans projects, users, portfolios, goals and tasks.
        // Meeting grounding is task evidence, so constrain it when the live
        // schema exposes the documented selector.
        if serverID == "asana", tool.name == "search_objects",
           tool.hasArgument("resource_type") {
            arguments["resource_type"] = .string("task")
        }
        return arguments
    }

    /// How long one connected app may hold up a grounding round. Chosen against
    /// the loop it blocks, not against the app: a blind-spot tick that arrives
    /// after the moment it described is worth less than a tick with one source
    /// missing.
    ///
    /// Stored rather than computed so tests can stop racing it. A test driving
    /// grounding through an instant in-process stub is not exercising this
    /// deadline at all — but on a saturated machine the eight seconds can still
    /// elapse before the stub is even scheduled, at which point the deadline
    /// fires, grounding correctly returns nothing, and the test reports a
    /// product failure that never happened. Production never assigns this.
    /// Подмена срока для тестов — только внутри своей задачи.
    ///
    /// Была обычная изменяемая статическая переменная, и это тот же капкан,
    /// который уже сработал на `ProviderKeyStore`: Swift Testing гоняет наборы
    /// ПАРАЛЛЕЛЬНО. `GroundingContextPolicyTests` выставляет 600, чтобы часы не
    /// вмешивались в его проверку, а `WedgedConnectorTests` в это же время
    /// утверждает, что срок не больше пятнадцати. Пересекутся — второй упадёт с
    /// «срок 600.0 с — это уже не срок», то есть сообщит о поломке продукта,
    /// которой нет.
    ///
    /// Воспроизвести не удалось (шесть прогонов подряд зелёные): окно узкое.
    /// Но чинится это устройством, а не дисциплиной, и стоит одну строку —
    /// а разбирать раз в месяц падающий набор стоит вечера.
    ///
    /// Цена та же, что у `ProviderKeyStore`: `Task.detached` task-local не
    /// наследует. Веер источников собран на `withTaskGroup`, а он наследует.
    @TaskLocal static var deadlineOverrideForTesting: TimeInterval?

    /// Находки плюс охват — и обрезка ПОСЛЕ приписки, а не до неё.
    ///
    /// Порядок здесь и есть вся суть: приписать охват к уже обрезанному тексту
    /// значило бы вернуть строку длиннее предела, а обрезать после — потерять
    /// приписку ровно там, где находок много, то есть где она нужнее всего.
    /// Поэтому под охват место резервируется, и режется список.
    ///
    /// Пустой охват не приписывается: у обычного поиска сказать нечего, и
    /// приписка в каждой подсказке была бы шумом.
    nonisolated static func withCoverage(_ body: String, note: String, limit: Int) -> String {
        guard !note.isEmpty else { return String(body.prefix(limit)) }
        let tail = "\n(\(note))"
        let room = max(0, limit - tail.count)
        return String(body.prefix(room)) + tail
    }

    static var groundingDeadline: TimeInterval { deadlineOverrideForTesting ?? 8 }

    private func findSearchTool(server: MCPServerDescriptor) async -> Tool? {
        if !isConnected(server.id) { await connect(server) }
        return researchTool(for: server.id)
    }
}
