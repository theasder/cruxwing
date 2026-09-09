import SwiftUI
import CruxwingCore

/// Настройки → «Подключённые приложения», блок рабочих мессенджеров.
///
/// Отдельно от трекеров, потому что вопрос другой: у трекера спрашивают
/// «заводили ли задачу», у мессенджера — «обсуждали ли это». Ответ на второй
/// чаще лежит в переписке.
///
/// Подключение токеном, как у трекеров: MCP-серверов у этих сервисов нет.
/// Рядом с полем написано, где токен взять, — «нужен токен» без адреса это
/// тупик.
struct WorkMessengersSection: View {
    @State private var expanded: WorkMessengers.Service?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(WorkMessengers.Service.allCases, id: \.self) { service in
                WorkMessengerRow(
                    service: service,
                    isExpanded: expanded == service,
                    toggle: { expanded = expanded == service ? nil : service })
            }
            TelegramSupergroupRow()
        }
    }
}

private struct TelegramSupergroupRow: View {
    @EnvironmentObject private var mcp: MCPConnectionManager
    @State private var token = ""
    @State private var chatIDs = ""
    @State private var isExpanded = false
    @State private var isConfigured = false
    @State private var isSaving = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.s) {
                Label("Telegram — supergroups",
                      systemImage: isConfigured ? "checkmark.seal.fill" : "paperplane")
                    .labelStyle(ConnectedRowLabelStyle())
                    .lineLimit(1)
                Spacer()
                if isConfigured {
                    Button("Disconnect") {
                        Task {
                            isSaving = true
                            defer { isSaving = false }
                            do {
                                try await mcp.disconnectTelegram()
                                token = ""; chatIDs = ""; errorText = nil
                                load()
                            } catch {
                                isExpanded = true
                                errorText = "Could not delete the local Telegram archive. The connection and the token were kept; try again."
                            }
                        }
                    }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(isSaving)
                    .accessibilityIdentifier("settings.messenger.telegram.disconnect")
                }
                Button(isExpanded ? "Collapse" : (isConfigured ? "Edit" : "Connect")) {
                    isExpanded.toggle()
                    errorText = nil
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(isSaving)
                .accessibilityIdentifier("settings.messenger.telegram.connect")
            }

            if isExpanded {
                Text("Create a separate bot through BotFather and add it to the supergroups you choose. Turn off privacy mode, or make the bot an administrator.")
                    .font(Typo.caption)
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                SecureField("", text: $token, prompt: Text("bot token"))
                    .textFieldStyle(.plain)
                    .font(Typo.callout)
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, 6)
                    .background(Theme.surfaceSunken,
                                in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                    .accessibilityLabel("Telegram bot token")
                    .accessibilityIdentifier("settings.messenger.telegram.token")

                TextField("", text: $chatIDs,
                          prompt: Text("Supergroup ids separated by commas, for example -100123…"))
                    .textFieldStyle(.plain)
                    .font(Typo.callout)
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, 6)
                    .background(Theme.surfaceSunken,
                                in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                    .accessibilityLabel("Allowed Telegram supergroup ids")
                    .accessibilityIdentifier("settings.messenger.telegram.chatIDs")

                Text("History starts at the moment you connect: the Bot API does not hand over old messages. Cruxwing only receives and locally searches new messages from the supergroups you named; it sends nothing to Telegram itself.")
                    .font(Typo.caption)
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if let errorText {
                    Text(errorText)
                        .font(Typo.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings.messenger.telegram.error")
                }

                HStack {
                    Button(isSaving ? "Checking…" : "Check and save") { save() }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(!canSave || isSaving)
                        .accessibilityIdentifier("settings.messenger.telegram.save")
                    Spacer()
                }
            }
        }
        .onAppear(perform: load)
    }

    private var parsedChatIDs: Set<Int64>? {
        RussianTrackerStore.parseTelegramChatIDs(chatIDs)
    }

    private var canSave: Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !(parsedChatIDs?.isEmpty ?? true)
    }

    private func load() {
        isConfigured = mcp.trackerStore.isTelegramConfigured
        let saved = mcp.trackerStore.telegramAllowedChatIDs()
        if !saved.isEmpty { chatIDs = saved.sorted().map(String.init).joined(separator: ", ") }
    }

    private func save() {
        guard let parsedChatIDs, !parsedChatIDs.isEmpty else {
            errorText = "Give numeric supergroup ids separated by commas."
            return
        }
        isSaving = true
        errorText = nil
        let submittedToken = token
        Task {
            do {
                _ = try await mcp.connectTelegram(
                    token: submittedToken, allowedChatIDs: parsedChatIDs)
                token = ""
                isSaving = false
                load()
            } catch {
                isSaving = false
                errorText = (error as? LocalizedError)?.errorDescription
                    ?? "Could not verify the Telegram connection."
            }
        }
    }
}

private struct WorkMessengerRow: View {
    @EnvironmentObject private var mcp: MCPConnectionManager
    let service: WorkMessengers.Service
    let isExpanded: Bool
    let toggle: () -> Void

    @State private var token = ""
    @State private var secondary = ""
    @State private var scope = ""
    @State private var isConfigured = false
    @State private var refusal: ConnectorHealth.Refusal?

    private var store: RussianTrackerStore { mcp.trackerStore }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.s) {
                Label(service.title,
                      systemImage: isConfigured
                        ? "checkmark.seal.fill" : "bubble.left.and.bubble.right")
                    .labelStyle(ConnectedRowLabelStyle())
                    .lineLimit(1)
                Spacer()
                if isConfigured {
                    Button("Disconnect") { disconnect() }
                        .buttonStyle(QuietButtonStyle())
                        .accessibilityIdentifier("settings.messenger.\(service.rawValue).disconnect")
                }
                Button(isExpanded ? "Collapse" : (isConfigured ? "Edit" : "Connect")) {
                    toggle()
                }
                .buttonStyle(QuietButtonStyle())
                .accessibilityIdentifier("settings.messenger.\(service.rawValue).connect")
            }

            // Отказ сервиса виден там же, где его настраивают.
            //
            // Записывался он для всех семейств, а показывался у двух. Для мессенджеров
            // отозванный токен выглядел как «ничего не нашлось» — то есть как
            // продукт, который стал хуже отвечать. Это ещё и рычаг чужой
            // стороны: доступ отзывают молча, и молчит тогда наш экран.
            if let refusal {
                Text("Last refusal: \(refusal.words)")
                    .font(Typo.caption)
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.messenger.\(service.rawValue).refusal")
            }
            if isExpanded {
                Text(service.credentialHint)
                    .font(Typo.caption)
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                SecureField("", text: $token, prompt: Text("token"))
                    .textFieldStyle(.plain)
                    .font(Typo.callout)
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, 6)
                    .background(Theme.surfaceSunken,
                                in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                    .accessibilityLabel("\(service.title) token")
                    .accessibilityIdentifier("settings.messenger.\(service.rawValue).token")

                if service.needsSecondary {
                    // Адрес сервера: Mattermost и Rocket.Chat команды поднимают
                    // сами, общего хоста у них нет.
                    TextField("", text: $secondary, prompt: Text(service.secondaryPrompt ?? ""))
                        .textFieldStyle(.plain)
                        .font(Typo.callout)
                        .padding(.horizontal, Space.s)
                        .padding(.vertical, 6)
                        .background(Theme.surfaceSunken,
                                    in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                        .accessibilityLabel("\(service.secondaryPrompt ?? "") — \(service.title)")
                        .accessibilityIdentifier("settings.messenger.\(service.rawValue).host")
                }

                if service.needsScope {
                    // Где искать. У Mattermost это команда, у Rocket.Chat —
                    // комната; оба параметра обязательны по документации. Без
                    // них сервис отвечает пустым списком, неотличимым от
                    // «ничего не нашлось».
                    TextField("", text: $scope, prompt: Text(service.scopePrompt ?? ""))
                        .textFieldStyle(.plain)
                        .font(Typo.callout)
                        .padding(.horizontal, Space.s)
                        .padding(.vertical, 6)
                        .background(Theme.surfaceSunken,
                                    in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                        .accessibilityLabel("Where to search — \(service.title)")
                        .accessibilityIdentifier("settings.messenger.\(service.rawValue).scope")
                }

                Text(service.needsScope
                     ? "The search runs only where you said."
                     : "The search runs across all your chats.")
                    .font(Typo.caption)
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button("Save") { save() }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(!canSave)
                        .accessibilityIdentifier("settings.messenger.\(service.rawValue).save")
                    Spacer()
                }
            }
        }
        .onAppear(perform: load)
        .task { await loadRefusal() }
    }

    /// Неполный набор сохранять нельзя: настройка выглядела бы законченной, а
    /// сервис отвечал бы пустотой — то есть «не обсуждали», хотя обсуждали.
    private var canSave: Bool {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if service.needsSecondary,
           secondary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if service.needsScope,
           scope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        return true
    }

    private func loadRefusal() async {
        refusal = await ConnectorHealth.shared.refusal(for: service.rawValue)
    }

    private func load() {
        // Токен обратно в поле не поднимаем: показывать секрет незачем, и
        // Связка ключей за него спросит пароль. Хватает отметки «подключено».
        isConfigured = store.messengerToken(for: service) != nil
        secondary = store.messengerSecondary(for: service) ?? ""
        scope = store.messengerScope(for: service) ?? ""
    }

    private func save() {
        store.setMessengerToken(token, for: service)
        store.setMessengerSecondary(secondary, for: service)
        store.setMessengerScope(scope, for: service)
        token = ""
        load()
    }

    private func disconnect() {
        store.removeMessenger(service)
        token = ""; secondary = ""; scope = ""
        load()
    }
}
