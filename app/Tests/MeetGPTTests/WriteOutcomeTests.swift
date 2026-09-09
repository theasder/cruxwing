import Testing
import Foundation
@testable import MeetGPT

/// Что мы говорим человеку про запись в чужой трекер.
///
/// Обращение к серверу MCP считается успешным, когда сервер не поставил
/// признак ошибки. Сервер, который ничего не сделал, отвечает ПУСТОТОЙ и
/// признака не ставит — а пустой ответ прямо превращался в «Задача создана.».
/// Уверенная фраза о том, чего не было, в самом дорогом месте: человек уходит
/// со звонка, считая обязательство записанным, и узнаёт правду через неделю.
///
/// Соседний путь — российские трекеры — так не делал никогда: он показывает
/// ключ задачи, и `parseCreated` отказывается разбирать ответ без ключа. Здесь
/// то же требование доказательства.
@Suite struct WriteOutcomeTests {

    @Test("пустой ответ не выдаётся за созданную задачу")
    func silenceIsNotSuccess() {
        let text = TaskWriteback.outcome(of: "   \n  ")
        #expect(!text.contains("создана"), "пустой ответ прочитан как успех: \(text)")
        #expect(text.contains("there is no confirmation"))
        #expect(text.contains("Check it in the tracker"), "человеку не сказано, что делать")
    }

    @Test("слова сервиса доходят как есть")
    func theServiceSpeaksForItself() {
        // «Created issue ENG-142» — это доказательство, и оно лучше нашего
        // пересказа. Показываем его, а не своё «готово».
        #expect(TaskWriteback.outcome(of: "Created issue ENG-142") == "Created issue ENG-142")
    }

    @Test("длинный ответ обрезается, но не превращается в успех")
    func longAnswerIsBounded() {
        let long = String(repeating: "подробности ", count: 40)
        let text = TaskWriteback.outcome(of: long)
        #expect(text.count <= 160)
        #expect(text.hasPrefix("подробности"))
    }

    @Test("отказ словами остаётся отказом на экране")
    func aRefusalStaysARefusal() {
        // Сервер вправе ответить прозой «нет права на создание» и не ставить
        // признак ошибки. Пересказать это как «готово» — худшее, что можно.
        let text = TaskWriteback.outcome(of: "Permission denied: cannot create issues")
        #expect(text.contains("Permission denied"))
    }

    @Test("лист согласия спрашивает именно это правило")
    func theSheetUsesTheRule() throws {
        // Правило, написанное и не позванное, в этом коде уже случалось.
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/MeetGPT/Views/TaskWritebackSheet.swift"), encoding: .utf8)
        #expect(source.contains("TaskWriteback.outcome(of: result)"),
                "лист согласия снова толкует ответ сам")
        #expect(!source.contains("\"Задача создана.\""),
                "вернулась фраза, утверждающая создание без доказательства")
    }
}
