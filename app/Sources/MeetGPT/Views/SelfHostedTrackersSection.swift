import SwiftUI
import CruxwingCore

/// Настройки → «Подключённые приложения»: открытые трекеры на своём сервере.
///
/// Отдельно от GitHub: у того адрес зашит (`api.github.com`), а GitLab и Gitea
/// команда поднимает у себя — без поля адреса подключать некуда.
struct SelfHostedTrackersSection: View {
    @State private var expanded: SelfHostedTrackers.Service?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(SelfHostedTrackers.Service.allCases, id: \.self) { service in
                SelfHostedTrackerRow(
                    service: service,
                    isExpanded: expanded == service,
                    toggle: { expanded = expanded == service ? nil : service })
            }
        }
    }
}

private struct SelfHostedTrackerRow: View {
    @EnvironmentObject private var mcp: MCPConnectionManager
    let service: SelfHostedTrackers.Service
    let isExpanded: Bool
    let toggle: () -> Void

    @State private var token = ""
    @State private var host = ""
    /// Поля, которые у сервиса свои. У GitLab и Gitea пусто, у Plane два.
    @State private var fields: [String: String] = [:]
    @State private var isConfigured = false
    @State private var refusal: ConnectorHealth.Refusal?

    private var store: RussianTrackerStore { mcp.trackerStore }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.s) {
                Label(service.title,
                      systemImage: isConfigured ? "checkmark.seal.fill" : "server.rack")
                    .labelStyle(ConnectedRowLabelStyle())
                    .lineLimit(1)
                Spacer()
                if isConfigured {
                    Button("Disconnect") { disconnect() }
                        .buttonStyle(QuietButtonStyle())
                        .accessibilityIdentifier("settings.selfhosted.\(service.rawValue).disconnect")
                }
                Button(isExpanded ? "Collapse" : (isConfigured ? "Edit" : "Connect")) {
                    toggle()
                }
                .buttonStyle(QuietButtonStyle())
                .accessibilityIdentifier("settings.selfhosted.\(service.rawValue).connect")
            }


            // Последний отказ источника — там, где человек и так решает, что
            // делать с этим коннектором. Во время звонка отказ ничего не ломает
            // и ничего не показывает: подсказка собирается по другим источникам,
            // и правильно, что вопрос человека важнее полноты. Но узнать о нём
            // было негде, и отозванный токен выглядел как продукт, который стал
            // хуже отвечать.
            if let refusal {
                Text("Last refusal: \(refusal.words)")
                    .font(Typo.caption)
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.selfhosted.\(service.rawValue).refusal")
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
                    .accessibilityIdentifier("settings.selfhosted.\(service.rawValue).token")

                TextField("", text: $host, prompt: Text(service.hostPrompt))
                    .textFieldStyle(.plain)
                    .font(Typo.callout)
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, 6)
                    .background(Theme.surfaceSunken,
                                in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                    .accessibilityLabel("Server address — \(service.title)")
                    .accessibilityIdentifier("settings.selfhosted.\(service.rawValue).host")

                // Поля из манифеста: у Plane пространство и проект стоят
                // внутри адреса, и без них запрос собрать не из чего.
                ForEach(service.fields, id: \.name) { field in
                    TextField("", text: Binding(
                        get: { fields[field.name] ?? "" },
                        set: { fields[field.name] = $0 }),
                        prompt: Text(field.example))
                        .textFieldStyle(.plain)
                        .font(Typo.callout)
                        .padding(.horizontal, Space.s)
                        .padding(.vertical, 6)
                        .background(Theme.surfaceSunken,
                                    in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                        .accessibilityLabel("\(field.title) — \(service.title)")
                        .accessibilityIdentifier(
                            "settings.selfhosted.\(service.rawValue).field.\(field.name)")
                }

                HStack {
                    Button("Save") { save() }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(!canSave)
                        .accessibilityIdentifier("settings.selfhosted.\(service.rawValue).save")
                    Spacer()
                }
            }
        }
        .onAppear(perform: load)
        .task { await loadRefusal() }
    }

    /// Кнопка включается ровно тогда, когда ядро сочтёт подключение
    /// настроенным.
    ///
    /// Правило спрашивается у ядра, а не повторяется здесь. Второй список
    /// условий разъезжается с первым молча: кнопка «Сохранить» доступна,
    /// сохранение проходит, а вопросы возвращают «трекер не подключён» — и
    /// человеку не за что зацепиться.
    private var canSave: Bool {
        SelfHostedTrackers(service: service, token: token, host: host, values: fields,
                           http: { _ in (Data(), HTTPURLResponse()) }).isConfigured
    }

    private func loadRefusal() async {
        refusal = await ConnectorHealth.shared.refusal(for: service.rawValue)
    }

    private func load() {
        host = store.selfHostedHost(for: service) ?? ""
        fields = store.selfHostedFields(for: service).compactMapValues { $0 }
        // «Подключён» — это то же самое, что считает ядро: токен, адрес и все
        // поля. Иначе строка показывает галочку, а вопросы возвращают ошибку.
        isConfigured = store.selfHostedClient(for: service,
                                              http: { _ in (Data(), HTTPURLResponse()) }) != nil
    }

    private func save() {
        store.setSelfHostedToken(token, for: service)
        store.setSelfHostedHost(host, for: service)
        for field in service.fields {
            store.setSelfHostedField(fields[field.name] ?? "", name: field.name, for: service)
        }
        token = ""
        load()
    }

    private func disconnect() {
        store.removeSelfHosted(service)
        token = ""; host = ""; fields = [:]
        load()
    }
}
