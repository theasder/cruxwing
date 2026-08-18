import SwiftUI
import OrakulCore

/// Настройки → «Подключённые приложения»: заметки в папке на этом компьютере.
///
/// Единственный источник без токена и без адреса. Поэтому и строка другая: не
/// поля для ключа, а выбор папки — и он же выдаёт приложению разрешение её
/// читать. В песочнице иначе нельзя: путь, введённый руками, открыть не
/// получится.
struct LocalNotesSection: View {
    @State private var folder: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.s) {
                Label(folder ?? "Папка не выбрана",
                      systemImage: folder == nil ? "folder" : "checkmark.seal.fill")
                    .labelStyle(ConnectedRowLabelStyle())
                    .lineLimit(1)
                    .accessibilityIdentifier("settings.notes-local.folder")
                Spacer()
                if folder != nil {
                    Button("Убрать") { forget() }
                        .buttonStyle(QuietButtonStyle())
                        .accessibilityIdentifier("settings.notes-local.forget")
                }
                Button(folder == nil ? "Выбрать папку…" : "Изменить…") { choose() }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("settings.notes-local.choose")
            }

            Text("Читаются файлы .md и .markdown, включая вложенные папки. "
                 + "Служебные каталоги вроде .obsidian и .trash пропускаются. "
                 + "Ничего никуда не отправляется: поиск идёт по вашему диску.")
                .font(Typo.caption)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { folder = LocalNotesFolder.live.displayName }
    }

    private func choose() {
        guard LocalNotesFolder.live.choose() else { return }
        folder = LocalNotesFolder.live.displayName
    }

    private func forget() {
        LocalNotesFolder.live.forget()
        folder = nil
    }
}
