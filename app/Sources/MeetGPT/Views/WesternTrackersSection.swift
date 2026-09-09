import SwiftUI
import CruxwingCore

/// Настройки → «Подключённые приложения»: западные трекеры в облаке.
///
/// Отдельная секция от самостоятельных серверов не ради порядка на экране:
/// здесь нет поля адреса. Сервис облачный, адрес известен заранее, и лишнее
/// поле — это лишняя опечатка, из-за которой человек будет искать проблему в
/// своём токене.
struct WesternTrackersSection: View {
    @State private var expanded: WesternTrackers.Service?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(WesternTrackers.Service.allCases, id: \.self) { service in
                WesternTrackerRow(
                    service: service,
                    isExpanded: expanded == service,
                    toggle: { expanded = expanded == service ? nil : service })
            }
        }
    }
}

private struct WesternTrackerRow: View {
    @EnvironmentObject private var mcp: MCPConnectionManager
    let service: WesternTrackers.Service
    let isExpanded: Bool
    let toggle: () -> Void

    @State private var token = ""
    @State private var fields: [String: String] = [:]
    @State private var isConfigured = false
    @State private var refusal: ConnectorHealth.Refusal?

    private var store: RussianTrackerStore { mcp.trackerStore }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.s) {
                Label(service.title,
                      systemImage: isConfigured ? "checkmark.seal.fill" : "cloud")
                    .labelStyle(ConnectedRowLabelStyle())
                    .lineLimit(1)
                Spacer()
                if isConfigured {
                    Button("Disconnect") { disconnect() }
                        .buttonStyle(QuietButtonStyle())
                        .accessibilityIdentifier("settings.western.\(service.rawValue).disconnect")
                }
                Button(isExpanded ? "Collapse" : (isConfigured ? "Edit" : "Connect")) {
                    toggle()
                }
                .buttonStyle(QuietButtonStyle())
                .accessibilityIdentifier("settings.western.\(service.rawValue).connect")
            }

            // Отказ сервиса виден там же, где его настраивают.
            //
            // Записывался он для всех семейств, а показывался у двух. Для Linear, Trello и Plane
            // отозванный токен выглядел как «ничего не нашлось» — то есть как
            // продукт, который стал хуже отвечать. Это ещё и рычаг чужой
            // стороны: доступ отзывают молча, и молчит тогда наш экран.
            if let refusal {
                Text("Last refusal: \(refusal.words)")
                    .font(Typo.caption)
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.western.\(service.rawValue).refusal")
            }
            if isExpanded {
                Text(service.credentialHint)
                    .font(Typo.caption)
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                SecureField("", text: $token, prompt: Text("key"))
                    .textFieldStyle(.plain)
                    .font(Typo.callout)
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, 6)
                    .background(Theme.surfaceSunken,
                                in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                    .accessibilityLabel("\(service.title) key")
                    .accessibilityIdentifier("settings.western.\(service.rawValue).token")

                // У Trello кроме токена нужен ключ приложения. Он не секрет, и
                // поле обычное — но без него запрос не собрать.
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
                            "settings.western.\(service.rawValue).field.\(field.name)")
                }

                HStack {
                    Button("Save") { save() }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(!canSave)
                        .accessibilityIdentifier("settings.western.\(service.rawValue).save")
                    Spacer()
                }
            }
        }
        .onAppear(perform: load)
        .task { await loadRefusal() }
    }

    /// Правило спрашивается у ядра — иначе кнопка разрешает сохранить то, что
    /// коннектор потом сочтёт неподключённым.
    private var canSave: Bool {
        WesternTrackers(service: service, token: token, values: fields,
                        http: { _ in (Data(), HTTPURLResponse()) }).isConfigured
    }

    private func loadRefusal() async {
        refusal = await ConnectorHealth.shared.refusal(for: service.rawValue)
    }

    private func load() {
        fields = store.westernFields(for: service).compactMapValues { $0 }
        isConfigured = store.westernClient(for: service,
                                           http: { _ in (Data(), HTTPURLResponse()) }) != nil
    }

    private func save() {
        store.setWesternToken(token, for: service)
        for field in service.fields {
            store.setWesternField(fields[field.name] ?? "", name: field.name, for: service)
        }
        token = ""
        load()
    }

    private func disconnect() {
        store.removeWestern(service)
        token = ""; fields = [:]
        load()
    }
}
