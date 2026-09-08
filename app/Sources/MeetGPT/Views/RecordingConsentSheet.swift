import SwiftUI

/// One-time consent gate before the first recording (launch loop M10.1).
/// A meeting recorder captures OTHER people — App Review expects the app to put
/// consent responsibility in front of the operator, and several jurisdictions
/// require all-party consent. Recording cannot start until this is affirmed.
struct RecordingConsentSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(spacing: Space.m) {
                Image(systemName: "waveform.badge.exclamationmark")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Theme.accent)
                Text("Before recording")
                    .font(Typo.title)
                    .foregroundStyle(Theme.ink)
            }

            VStack(alignment: .leading, spacing: Space.m) {
                bullet("person.2.wave.2",
                       "Recording captures everyone: your microphone and the call's system audio.")
                bullet("checkmark.shield",
                       "In many countries a conversation may be recorded only with everyone's consent. Warning them and obtaining that consent where the law requires it is your responsibility.")
                bullet("lock.laptopcomputer",
                       "Transcription runs on this computer by default. Fragments of the transcript leave it only when you run an AI action yourself.")
            }

            HStack {
                // Ссылок на политику и условия здесь нет намеренно. Раньше они
                // вели на cruxwing.com — чужой документ про чужую обработку
                // данных, и к orakul он отношения не имеет: у orakul нет
                // сервера, куда что-то уходит. Своих страниц пока нет, а
                // ссылка в никуда на экране про согласие хуже её отсутствия.
                // Существенное сказано выше, списком.
                Spacer()
                Button("Not now") { dismiss() }
                    .buttonStyle(QuietButtonStyle())
                Button("Understood — start recording") {
                    state.acceptRecordingConsent()
                }
                .buttonStyle(QuietButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xl)
        .frame(width: 480)
        .background(Theme.canvas)
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(Theme.accent)
                .frame(width: 20)
            Text(text)
                .font(Typo.callout)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
