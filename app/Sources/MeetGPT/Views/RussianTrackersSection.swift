import SwiftUI
import CruxwingCore

/// Настройки → «Подключённые приложения», первый блок: российские трекеры.
///
/// Наверху, потому что это первое, что человек здесь ищет. Список,
/// начинающийся с Notion и Linear, читается как «нашего трекера тут нет», и
/// дальше третьей строки его не листают.
///
/// Подключение не через OAuth: MCP-серверов у этих сервисов нет, поэтому здесь
/// токен, который человек создаёт у себя в трекере. Рядом с полем написано,
/// где именно, — «нужен токен» без адреса это тупик.
struct RussianTrackersSection: View {
    @State private var expanded: RussianTrackers.Service?
    @State private var githubExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(RussianTrackers.Service.allCases, id: \.self) { service in
                RussianTrackerRow(
                    service: service,
                    isExpanded: expanded == service,
                    toggle: { expanded = expanded == service ? nil : service })
            }
            // GitHub стоит здесь же: для разработчика это тот же вопрос —
            // «где лежат задачи». Подключается так же, токеном.
            GitHubRow(isExpanded: githubExpanded,
                      toggle: { githubExpanded.toggle() })
        }
    }
}

/// GitHub подключается личным токеном: динамической регистрации клиента у него
/// нет, а секреты в установщик не кладут — см. `GitHubConnector`.
private struct GitHubRow: View {
    @EnvironmentObject private var mcp: MCPConnectionManager
    let isExpanded: Bool
    let toggle: () -> Void

    @State private var token = ""
    @State private var repositories = ""
    @State private var isReady = false
    @State private var refusal: ConnectorHealth.Refusal?

    private var store: RussianTrackerStore { mcp.trackerStore }

    private var canSave: Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !repositories.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.s) {
                Label("GitHub", systemImage: isReady ? "checkmark.seal.fill" : "chevron.left.forwardslash.chevron.right")
                    .labelStyle(ConnectedRowLabelStyle())
                    .lineLimit(1)
                Spacer()
                if isReady {
                    Button("Disconnect") {
                        store.removeGitHub()
                        token = ""; repositories = ""
                        load()
                    }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("settings.github.disconnect")
                }
                Button(isExpanded ? "Collapse" : (isReady ? "Edit" : "Connect")) { toggle() }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("settings.github.connect")
            }

            // Отказ сервиса виден там же, где его настраивают. Для GitHub
            // отозванный токен выглядел как «ничего не нашлось» — то есть как
            // продукт, который стал хуже отвечать.
            if let refusal {
                Text("Last refusal: \(refusal.words)")
                    .font(Typo.caption)
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.github.refusal")
            }
            if isExpanded {
                Text(GitHubConnector.credentialHint)
                    .font(Typo.caption).foregroundStyle(Theme.inkTertiary)

                SecureField("", text: $token, prompt: Text("token"))
                    .textFieldStyle(.plain).font(Typo.callout)
                    .padding(.horizontal, Space.s).padding(.vertical, 6)
                    .background(Theme.surfaceSunken,
                                in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                    .accessibilityLabel("GitHub token")
                    .accessibilityIdentifier("settings.github.token")

                // Без репозиториев поиск ушёл бы по всему GitHub и принёс чужие
                // задачи — шум, неотличимый от контекста команды.
                TextField("", text: $repositories,
                          prompt: Text(GitHubConnector.repositoriesPrompt))
                    .textFieldStyle(.plain).font(Typo.callout)
                    .padding(.horizontal, Space.s).padding(.vertical, 6)
                    .background(Theme.surfaceSunken,
                                in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                    .accessibilityLabel("GitHub repositories")
                    .accessibilityIdentifier("settings.github.repos")

                HStack {
                    Button("Save") {
                        store.setGitHubToken(token)
                        store.setGitHubRepositories(repositories)
                        token = ""
                        load()
                        toggle()
                    }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(!canSave)
                    .accessibilityIdentifier("settings.github.save")
                    Spacer()
                }
            }
        }
        .onAppear(perform: load)
        .task { await loadRefusal() }
    }

    private func loadRefusal() async {
        refusal = await ConnectorHealth.shared.refusal(for: "github")
    }

    private func load() {
        isReady = store.isGitHubReady
        repositories = store.githubRepositories().joined(separator: ", ")
    }
}

private struct RussianTrackerRow: View {
    /// Хранилище берётся у менеджера подключений, а не создаётся здесь: у него
    /// оно построено на том же `KeychainStore`, что и остальные токены, и в
    /// тестах это фальшивая Связка ключей — иначе проверка настроек лезла бы
    /// в настоящие токены пользователя.
    @EnvironmentObject private var mcp: MCPConnectionManager
    let service: RussianTrackers.Service
    let isExpanded: Bool
    let toggle: () -> Void

    private var store: RussianTrackerStore { mcp.trackerStore }
    @State private var token = ""
    @State private var secondary = ""
    @State private var destination = ""
    @State private var isConfigured = false
    @State private var refusal: ConnectorHealth.Refusal?
    @State private var canFileTasks = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.s) {
                Label(service.title,
                      systemImage: canFileTasks ? "checkmark.seal.fill"
                                 : (isConfigured ? "arrow.down.circle" : "tray.full"))
                    .labelStyle(ConnectedRowLabelStyle())
                    .lineLimit(1)
                Spacer()
                if isConfigured {
                    Button("Disconnect") { disconnect() }
                        .buttonStyle(QuietButtonStyle())
                        .accessibilityIdentifier("settings.tracker.\(service.rawValue).disconnect")
                }
                Button(isExpanded ? "Collapse" : (isConfigured ? "Edit" : "Connect")) {
                    toggle()
                }
                .buttonStyle(QuietButtonStyle())
                .accessibilityIdentifier("settings.tracker.\(service.rawValue).connect")
            }

            // Отказ сервиса виден там же, где его настраивают.
            //
            // Записывался он для всех семейств, а показывался у двух. Для российских трекеров
            // отозванный токен выглядел как «ничего не нашлось» — то есть как
            // продукт, который стал хуже отвечать. Это ещё и рычаг чужой
            // стороны: доступ отзывают молча, и молчит тогда наш экран.
            if let refusal {
                Text("Last refusal: \(refusal.words)")
                    .font(Typo.caption)
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.tracker.\(service.rawValue).refusal")
            }
            if isExpanded {
                Text(service.credentialHint)
                    .font(Typo.caption)
                    .foregroundStyle(Theme.inkTertiary)

                SecureField("", text: $token, prompt: Text("token"))
                    .textFieldStyle(.plain)
                    .font(Typo.callout)
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, 6)
                    .background(Theme.surfaceSunken,
                                in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                    .accessibilityLabel("\(service.title) token")
                    .accessibilityIdentifier("settings.tracker.\(service.rawValue).token")

                if service.needsSecondary {
                    // У Яндекса без X-Org-ID это 403, у Kaiten без адреса команды
                    // нет самого хоста. Не украшение, а вторая половина ключа.
                    TextField("", text: $secondary, prompt: Text(service.secondaryPrompt ?? ""))
                        .textFieldStyle(.plain)
                        .font(Typo.callout)
                        .padding(.horizontal, Space.s)
                        .padding(.vertical, 6)
                        .background(Theme.surfaceSunken,
                                    in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                        .accessibilityLabel("\(service.secondaryPrompt ?? "") — \(service.title)")
                        .accessibilityIdentifier("settings.tracker.\(service.rawValue).org")
                }

                // Третье поле — куда класть заведённую задачу. Пустое поле
                // это не ошибка: трекер можно подключить только на чтение, и
                // тогда кнопка «Завести задачу» для него просто не появится.
                TextField("", text: $destination,
                          prompt: Text(service.destinationPrompt ?? ""))
                    .textFieldStyle(.plain)
                    .font(Typo.callout)
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, 6)
                    .background(Theme.surfaceSunken,
                                in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                    .accessibilityLabel("Where to create tasks — \(service.title)")
                    .accessibilityIdentifier("settings.tracker.\(service.rawValue).destination")

                Text(destination.trimmingCharacters(in: .whitespaces).isEmpty
                     ? "Without this field the tracker connects read-only."
                     : "Tasks from a call will be created here.")
                    .font(Typo.caption)
                    .foregroundStyle(Theme.inkTertiary)

                HStack {
                    Button("Save") { save() }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(!canSave)
                        .accessibilityIdentifier("settings.tracker.\(service.rawValue).save")
                    Spacer()
                }
            }
        }
        .onAppear(perform: load)
        .task { await loadRefusal() }
    }

    /// Сохранять половину ключа нельзя: настройка будет выглядеть законченной и
    /// падать с 403 при первом же запросе.
    private var canSave: Bool {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard service.needsSecondary else { return true }
        return !secondary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadRefusal() async {
        refusal = await ConnectorHealth.shared.refusal(for: service.rawValue)
    }

    private func load() {
        // Сам токен обратно в поле не поднимаем: показывать секрет незачем,
        // и Связка ключей за него спросит пароль. Хватает отметки «подключено».
        isConfigured = store.isConfigured(service)
        canFileTasks = store.canFileTasks(service)
        secondary = store.secondary(for: service) ?? ""
        destination = store.destination(for: service) ?? ""
    }

    private func save() {
        store.setToken(token, for: service)
        store.setSecondary(secondary, for: service)
        store.setDestination(destination, for: service)
        token = ""
        load()
    }

    private func disconnect() {
        store.remove(service)
        token = ""
        secondary = ""
        destination = ""
        load()
    }
}
