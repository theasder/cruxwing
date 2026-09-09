import Testing
import Foundation
@testable import MeetGPT

/// Подсказка о начавшемся звонке и напоминание о будущем должны читаться как
/// два разных события — «идёт сейчас» против «вот-вот начнётся», — чтобы это
/// было видно с одного взгляда. Проверки держат именно те слова, которые их
/// различают.
///
/// Тексты были английскими, и в двух из них стояло «Cruxwing» — имя другого
/// продукта. Уведомление — самая заметная поверхность приложения: оно
/// появляется поверх всего посреди звонка.
struct CallNotificationCopyTests {

    @Test("Active-call prompt names the source and asks to record")
    func callPromptDelineatesActiveCall() {
        let text = CallNotifier.callPromptText(source: "Zoom")
        #expect(text.title == "A call in Zoom")
        #expect(text.body == "cruxwing can record this call. Record it?")
        #expect(!text.body.contains("Cruxwing"), "в уведомлении имя другого продукта")
    }

    @Test("Scheduled reminder names the topic and its lead time")
    func reminderDelineatesScheduledCall() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let text = MeetingReminderScheduler.reminderText(
            title: "Weekly Sync", start: start, minutesBefore: 5)
        #expect(text.title == "Call soon: Weekly Sync")
        // Время в скобках не проверяется: его формат зависит от языка системы,
        // на которой идёт прогон.
        #expect(text.body.contains("Starts in 5 min"))
        #expect(text.body.contains("open cruxwing"))
        #expect(!text.body.contains("Cruxwing"), "в напоминании имя другого продукта")
    }

    @Test("The two notifications are unmistakably different")
    func theTwoContextsAreDistinct() {
        // Даже когда за обоими стоит один и тот же сервис, заголовки не должны
        // совпадать: один про идущий звонок, другой про будущий.
        let call = CallNotifier.callPromptText(source: "Google Meet")
        let reminder = MeetingReminderScheduler.reminderText(
            title: "Google Meet", start: Date(), minutesBefore: 2)
        #expect(call.title != reminder.title)
        #expect(call.title.localizedCaseInsensitiveContains("a call in"))
        #expect(reminder.title.localizedCaseInsensitiveContains("call soon"))
    }

    @Test("Reminder lead time is clamped to at least one minute")
    func reminderClampsLead() {
        // Повторяет ограничение `max(1, minutesBefore)` в самом планировщике:
        // текст не должен обещать «Начало через 0 мин».
        let text = MeetingReminderScheduler.reminderText(
            title: "Standup", start: Date(), minutesBefore: 0)
        #expect(text.body.contains("Starts in 1 min"))
    }
}
