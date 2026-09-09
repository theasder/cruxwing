import Foundation
import Testing
@testable import MeetGPT
import CruxwingCore

/// Что человек читает, когда коннектор отказал.
///
/// Swift без `LocalizedError` печатает «The operation couldn’t be completed.
/// (MeetGPT.WorkMessengers.ConnectorError error 1.)». В приложении, где всё
/// остальное по-русски, это выходит наружу ровно в тот момент, когда человеку
/// нужна помощь: не тот токен, недоступный сервер, не та очередь.
///
/// `RenderedRussianTests` этого не ловит: он смотрит на статичные строки
/// интерфейса, а такие сообщения рождаются во время работы.
@Suite("Сообщения об отказе коннекторов")
struct ConnectorErrorTextTests {

    /// Все ошибки, которые может увидеть человек.
    static let all: [Error] = [
        WorkMessengers.ConnectorError.notConfigured,
        WorkMessengers.ConnectorError.unauthorised,
        WorkMessengers.ConnectorError.unreadable,
        SelfHostedTrackers.ConnectorError.notConfigured,
        SelfHostedTrackers.ConnectorError.unauthorised,
        SelfHostedTrackers.ConnectorError.unreadable,
        TeamNotes.ConnectorError.notConfigured,
        TeamNotes.ConnectorError.unauthorised,
        TeamNotes.ConnectorError.unreadable,
        RussianTrackers.TrackerError.notConfigured(.yandexTracker),
        RussianTrackers.TrackerError.unauthorised(.kaiten),
        RussianTrackers.TrackerError.http(.yougile, 404),
        RussianTrackers.TrackerError.unreadable(.yandexTracker),
        GitHubConnector.ConnectorError.notConfigured,
        GitHubConnector.ConnectorError.unauthorised,
        GitHubConnector.ConnectorError.http(404),
        GitHubConnector.ConnectorError.unreadable,
    ]

    @Test("ни одна ошибка не показывает английскую заглушку и внутренности",
          arguments: all.map { $0.localizedDescription })
    func noBoilerplateLeaks(text: String) {
        for leak in ["operation couldn", "MeetGPT.", "error 0", "error 1",
                     "error 2", "error 3", "ConnectorError", "TrackerError"] {
            #expect(!text.contains(leak), "наружу вышли внутренности: «\(text)»")
        }
    }

    @Test("every message is long enough to explain itself, in one language",
          arguments: all.map { $0.localizedDescription })
    func everyMessageExplainsItself(text: String) {
        #expect(text.count >= 25, "too short: «\(text)»")
        // Vendor names stay in Cyrillic — «Пачка», «Яндекс Трекер» — so what is
        // checked is that Russian is not most of the sentence, which is what a
        // half-migrated message looks like.
        let cyrillic = text.filter { ("а"..."я").contains($0) || ("А"..."Я").contains($0) }
        #expect(cyrillic.count < text.count / 3, "the message is still mostly Russian: «\(text)»")
    }

    @Test("«not connected» points at the screen that fixes it",
          arguments: [WorkMessengers.ConnectorError.notConfigured as Error,
                      SelfHostedTrackers.ConnectorError.notConfigured,
                      TeamNotes.ConnectorError.notConfigured,
                      RussianTrackers.TrackerError.notConfigured(.kaiten),
                      GitHubConnector.ConnectorError.notConfigured])
    func notConfiguredNamesTheScreen(error: Error) {
        #expect(error.localizedDescription.contains("Connected apps"),
                "it does not say where to connect: «\(error.localizedDescription)»")
    }

    @Test("ошибка трекера называет, какой именно трекер отказал")
    func trackerErrorsNameTheService() {
        // При трёх подключённых трекерах «не принял токен» без имени
        // бесполезно: непонятно, где менять.
        let text = RussianTrackers.TrackerError.unauthorised(.kaiten).localizedDescription
        #expect(text.contains(RussianTrackers.Service.kaiten.title),
                "в сообщении нет имени сервиса: «\(text)»")
    }

    @Test("код ответа доходит до человека")
    func httpStatusSurvives() {
        #expect(GitHubConnector.ConnectorError.http(404).localizedDescription.contains("404"))
        #expect(RussianTrackers.TrackerError.http(.yougile, 500).localizedDescription.contains("500"))
    }
}
