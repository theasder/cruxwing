import SwiftUI
import OrakulCore

/// Настройки → «Подключённые приложения»: база знаний команды.
///
/// Адрес здесь НЕ обязателен, в отличие от трекеров: Outline бывает облачным.
/// Требовать адрес значило бы не пустить тех, у кого он облачный.
struct TeamNotesSection: View {
    @State private var expanded: TeamNotes.Service?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(TeamNotes.Service.allCases, id: \.self) { service in
                TeamNoteRow(
                    service: service,
                    isExpanded: expanded == service,
                    toggle: { expanded = expanded == service ? nil : service })
            }
        }
    }
}

private struct TeamNoteRow: View {
    @EnvironmentObject private var mcp: MCPConnectionManager
    let service: TeamNotes.Service
    let isExpanded: Bool
    let toggle: () -> Void

    @State private var token = ""
    @State private var host = ""
    @State private var fields: [String: String] = [:]
    @State private var isConfigured = false

    private var store: RussianTrackerStore { mcp.trackerStore }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.s) {
                Label(service.title,
                      systemImage: isConfigured ? "checkmark.seal.fill" : "book.closed")
                    .labelStyle(ConnectedRowLabelStyle())
                    .lineLimit(1)
                Spacer()
                if isConfigured {
                    Button("Отключить") { disconnect() }
                        .buttonStyle(QuietButtonStyle())
                        .accessibilityIdentifier("settings.notes.\(service.rawValue).disconnect")
                }
                Button(isExpanded ? "Свернуть" : (isConfigured ? "Изменить" : "Подключить")) {
                    toggle()
                }
                .buttonStyle(QuietButtonStyle())
                .accessibilityIdentifier("settings.notes.\(service.rawValue).connect")
            }

            if isExpanded {
                Text(service.credentialHint)
                    .font(Typo.caption)
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                SecureField("", text: $token, prompt: Text("токен"))
                    .textFieldStyle(.plain)
                    .font(Typo.callout)
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, 6)
                    .background(Theme.surfaceSunken,
                                in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                    .accessibilityLabel("Токен \(service.title)")
                    .accessibilityIdentifier("settings.notes.\(service.rawValue).token")

                TextField("", text: $host, prompt: Text(service.hostPrompt))
                    .textFieldStyle(.plain)
                    .font(Typo.callout)
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, 6)
                    .background(Theme.surfaceSunken,
                                in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                    .accessibilityLabel("Адрес сервера — \(service.title)")
                    .accessibilityIdentifier("settings.notes.\(service.rawValue).host")

                // Поля из манифеста: у Nextcloud это «где искать» — провайдер
                // стоит внутри адреса, и без него запрос собрать не из чего.
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
                            "settings.notes.\(service.rawValue).field.\(field.name)")
                }

                HStack {
                    Button("Сохранить") { save() }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(!canSave)
                        .accessibilityIdentifier("settings.notes.\(service.rawValue).save")
                    Spacer()
                }
            }
        }
        .onAppear(perform: load)
    }

    /// Правило спрашивается у ядра: у Outline пустой адрес значит облако, у
    /// BookStack облака нет и адрес обязателен. Второй список условий здесь
    /// разъехался бы с первым молча — кнопка доступна, сохранение проходит, а
    /// вопросы отвечают «база знаний не подключена».
    private var canSave: Bool {
        TeamNotes(service: service, token: token, host: host, values: fields,
                  http: { _ in (Data(), HTTPURLResponse()) }).isConfigured
    }

    private func load() {
        host = store.notesHost(for: service) ?? ""
        fields = store.notesFields(for: service).compactMapValues { $0 }
        isConfigured = store.notesClient(for: service,
                                         http: { _ in (Data(), HTTPURLResponse()) }) != nil
    }

    private func save() {
        store.setNotesToken(token, for: service)
        store.setNotesHost(host, for: service)
        for field in service.fields {
            store.setNotesField(fields[field.name] ?? "", name: field.name, for: service)
        }
        token = ""
        load()
    }

    private func disconnect() {
        store.removeNotes(service)
        token = ""; host = ""; fields = [:]
        load()
    }
}
