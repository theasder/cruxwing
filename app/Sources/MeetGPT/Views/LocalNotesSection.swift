import SwiftUI
import CruxwingCore

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
                Label(folder ?? "No folder selected",
                      systemImage: folder == nil ? "folder" : "checkmark.seal.fill")
                    .labelStyle(ConnectedRowLabelStyle())
                    .lineLimit(1)
                    .accessibilityIdentifier("settings.notes-local.folder")
                Spacer()
                if folder != nil {
                    Button("Remove") { forget() }
                        .buttonStyle(QuietButtonStyle())
                        .accessibilityIdentifier("settings.notes-local.forget")
                }
                Button(folder == nil ? "Choose a folder…" : "Edit…") { choose() }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("settings.notes-local.choose")
            }

            Text("It reads .md and .markdown files, including nested folders. "
                 + "Housekeeping directories such as .obsidian and .trash are skipped. "
                 + "Nothing is sent anywhere: the search runs over your own disk.")
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
