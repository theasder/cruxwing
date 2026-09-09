import Foundation
import Testing
@testable import MeetGPT

/// What the app tells the user about where their meeting audio goes.
///
/// Two different vendors sit behind one button. The UI named only AssemblyAI,
/// which is the BYO-key FALLBACK — a signed-in user's audio goes to the backend
/// and on to OpenAI. A wrong vendor name is not a copy nit: it is a false
/// statement about where a recording of other people's voices is sent.
@Suite("Diarize destination")
struct DiarizeDestinationTests {

    @Test("names the backend when the server path will run")
    func namesBackendForServerPath() {
        let destination = AppState.diarizeDestination(onServer: true)

        #expect(destination.contains("server"))
        // Must not claim AssemblyAI on the path that does not use it. This is
        // the bug: the UI named AssemblyAI unconditionally.
        #expect(!destination.contains("AssemblyAI"))
    }

    // The fragment is substituted into a whole sentence, and before 2026-08-20
    // it produced a mix of languages: «запись уйдёт в AssemblyAI with your own
    // key». The §6.4 counter never saw it — that one counts Views and
    // Onboarding, and this text is assembled in AppState. The direction has
    // since reversed, so the check reads the other way and keeps the same job.
    @Test("both branches speak one language")
    func bothPathsSpeakOneLanguage() {
        for onServer in [true, false] {
            let destination = AppState.diarizeDestination(onServer: onServer)
            #expect(destination.range(of: "[а-яА-ЯёЁ]", options: .regularExpression) == nil,
                    "Russian inside an English warning: «\(destination)»")
        }
    }

    // Чужого продукта в предупреждении orakul быть не должно ни в одной ветке.
    // Ветка сервера в собранном orakul недостижима — DIST-сборка отказывается
    // печь адрес сервера, — но достижимость меняется одной строкой сборки, а
    // текст читают глазами.
    @Test("ни одна ветка не называет другой продукт")
    func noForeignProductIsNamed() {
        for onServer in [true, false] {
            let destination = AppState.diarizeDestination(onServer: onServer).lowercased()
            #expect(!destination.contains("cruxwing"),
                    "человеку, поставившему orakul, сообщают про чужой сервис")
        }
    }

    @Test("names AssemblyAI only on the bring-your-own-key path")
    func namesAssemblyAIForLocalKeyPath() {
        #expect(AppState.diarizeDestination(onServer: false).contains("AssemblyAI"))
    }

    @Test("always names some destination")
    func alwaysNamesSomething() {
        // Interpolated into a sentence the user reads before sending audio. An
        // empty one would read as "Sends the audio to ."
        for onServer in [true, false] {
            #expect(!AppState.diarizeDestination(onServer: onServer)
                .trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @Test("the two paths never name the same destination")
    func pathsAreDistinguishable() {
        // If they were equal the string would be decorative rather than
        // informative, and the original bug could return unnoticed.
        #expect(AppState.diarizeDestination(onServer: true)
                != AppState.diarizeDestination(onServer: false))
    }
}
