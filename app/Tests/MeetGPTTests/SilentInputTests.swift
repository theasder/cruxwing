import Testing
import Foundation
@testable import MeetGPT

/// Молчащий вход виден человеку, а не только в системном журнале.
///
/// Счётчики в `AudioChunkBuffer` заведены после случая «слушаю, а транскрипта
/// нет»: путь звука отказывал в полной тишине. Починкой стала запись в журнал —
/// то есть диагностика для сопровождающего. Человек по-прежнему видел «Слушаю.
/// Строки появятся по ходу разговора» и ждал.
///
/// Это тот случай, когда рядом работает чужой диктофон: во время выбора
/// продукта его запускают почти всегда, и устройство может быть занято.
@Suite struct SilentInputTests {

    @Test("ноль буферов после отсрочки — это поломка, и о ней говорят")
    func noBuffersIsTrouble() {
        let message = AudioChunkBuffer.trouble(buffersIn: 0, secondsListening: 25)
        #expect(message?.contains("No audio is arriving") == true)
        #expect(message?.contains("another application is holding the device") == true,
                "не назван самый частый случай — устройство занято соседом")
    }

    @Test("тихая комната поломкой не объявляется")
    func quietRoomIsNotTrouble() {
        // Буферы идут, просто в них тихо. Сказать «звук не поступает» человеку,
        // который молчит, — соврать и научить его не верить предупреждениям.
        #expect(AudioChunkBuffer.trouble(buffersIn: 900, secondsListening: 120) == nil)
    }

    @Test("в первые секунды молчат")
    func earlySilenceIsNotReported() {
        // Устройство просыпается не мгновенно; предупреждение на второй секунде
        // будет мигать при каждом запуске и обесценится.
        #expect(AudioChunkBuffer.trouble(buffersIn: 0, secondsListening: 3) == nil)
    }

    @Test("счётчик буферов виден снаружи")
    func bufferCountIsReadable() {
        // Без этого правило выше проверять нечем: оно чистое, а данные для
        // него живут внутри замка.
        let buffer = AudioChunkBuffer(chunkSeconds: 5, label: "mic", onChunk: { _, _ in })
        #expect(buffer.receivedBufferCount == 0)
    }

    @MainActor
    @Test("предупреждение доезжает до вида, а не только до журнала")
    func troubleReachesTheView() throws {
        // Сторож, который написан и не позван, в этом коде уже случался — и
        // именно здесь починкой когда-то стала запись в журнал, то есть
        // сообщение сопровождающему вместо человека на звонке.
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/MeetGPT/Views/TranscriptView.swift"), encoding: .utf8)
        // Проверяем САМО УСЛОВИЕ, а не присутствие слова: первая редакция
        // требовала лишь, чтобы «audioTrouble» встречалось в файле, и мутация
        // `if false, let trouble = audioTrouble` её проходила. Ветка,
        // выключенная снаружи, выглядит как ветка.
        #expect(source.contains("if let trouble = audioTrouble {"),
                "вид не читает признак — человек снова увидит только «Слушаю»")
        #expect(source.contains("detail: trouble"),
                "заголовок есть, а слова предупреждения до экрана не доходят")
        #expect(source.contains("No audio"), "у предупреждения нет заголовка на экране")

        let state = AppState(llm: MockLLMGateway(response: ""))
        #expect(state.audioTrouble == nil, "предупреждение горит до начала записи")
    }

    @MainActor
    @Test("опрос заводится вместе с записью")
    func watcherStartsWithRecording() throws {
        // Правило чистое, но само себя не позовёт: без вызова из старта записи
        // оно останется верным и бесполезным.
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/MeetGPT/AppState.swift"), encoding: .utf8)
        // Ищем СОСЕДСТВО, а не расстояние: первое вхождение
        // `resetForNewRecording()` в файле — это её объявление, и расстояние
        // от него до вызова ничего не значит. Первая редакция проверки мерила
        // именно его и падала на двухстах сорока тысячах знаков.
        let started = source.components(separatedBy: "resetForNewRecording()\n")
        #expect(started.count >= 2, "место старта записи не найдено — проверка смотрит не туда")
        #expect(started.dropFirst().contains { $0.prefix(400).contains("watchForSilentInput()") },
                "опрос молчащего входа не заводится при старте записи")
    }
}
