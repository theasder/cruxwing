import Testing
import Foundation
@testable import CruxwingCore

/// Просьба подождать — это просьба подождать, а не приговор.
///
/// Ответ 429 выключает второй вопрос: спрашивать тем же словом в другом
/// написании значит удваивать нагрузку тому, кто уже сказал «реже».
///
/// Запись была БЕССРОЧНОЙ, и это превращало один ответ 429 в постоянное
/// отключение — а второй вопрос у части сервисов половина ответа: на живом
/// Synapse измерено 2026-08-20, что «тарифы» находит одно сообщение, а
/// «Тарифы» другое. Дешевле рычага у недружелюбного сервиса не было: один
/// ответ, и русский поиск наполовину выключен до конца работы программы, без
/// следа для человека.
@Suite struct SlowDownExpiryTests {

    /// Часы, которыми управляет проверка. Ожидание настоящего времени в наборе
    /// однажды уже стало причиной мерцающих отказов.
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = Date(timeIntervalSince1970: 1_000_000)
        var now: @Sendable () -> Date { { self.read() } }
        private func read() -> Date { lock.lock(); defer { lock.unlock() }; return value }
        func advance(_ seconds: TimeInterval) {
            lock.lock(); value = value.addingTimeInterval(seconds); lock.unlock()
        }
    }

    @Test("срок из слов сервиса соблюдается и кончается")
    func theServicesOwnDelayIsHonoured() async {
        let clock = Clock()
        let memory = ConnectorCaseMemory(now: clock.now)
        await memory.slowDown(service: "s", host: "h", seconds: 30)
        #expect(await memory.isSlowedDown(service: "s", host: "h"))
        clock.advance(29)
        #expect(await memory.isSlowedDown(service: "s", host: "h"),
                "перестали ждать раньше, чем просили")
        clock.advance(2)
        #expect(await memory.isSlowedDown(service: "s", host: "h") == false,
                "ждём дольше, чем просили: находки теряются без причины")
    }

    @Test("сервис промолчал — ждём своё, а не вечно")
    func silenceMeansTheDefault() async {
        let clock = Clock()
        let memory = ConnectorCaseMemory(now: clock.now)
        await memory.slowDown(service: "s", host: "h")
        clock.advance(ConnectorCaseMemory.defaultSlowDown - 1)
        #expect(await memory.isSlowedDown(service: "s", host: "h"))
        clock.advance(2)
        #expect(await memory.isSlowedDown(service: "s", host: "h") == false)
    }

    @Test("нулевой и отрицательный срок не значат «навсегда»")
    func abrokenHeaderDoesNotMeanForever() async {
        // Такой заголовок присылает и сломанный посредник, и ноль в нём — не
        // «нисколько», иначе просьбу можно было бы не заметить вовсе.
        let clock = Clock()
        let memory = ConnectorCaseMemory(now: clock.now)
        await memory.slowDown(service: "s", host: "h", seconds: 0)
        #expect(await memory.isSlowedDown(service: "s", host: "h"))
        clock.advance(ConnectorCaseMemory.defaultSlowDown + 1)
        #expect(await memory.isSlowedDown(service: "s", host: "h") == false)
    }

    @Test("пока срок идёт, второе написание не спрашивают")
    func theSecondSpellingIsSilencedWhileItLasts() async {
        let clock = Clock()
        let memory = ConnectorCaseMemory(now: clock.now)
        await memory.learn(.comparesBytes, service: "s", host: "h")
        await memory.slowDown(service: "s", host: "h", seconds: 60)
        // Просьба сильнее знания: даже зная, что сервис сравнивает байты,
        // пока он душит — не давим.
        #expect(await memory.behaviour(service: "s", host: "h") == .foldsCase)
        clock.advance(61)
        #expect(await memory.behaviour(service: "s", host: "h") == .comparesBytes,
                "знание не вернулось после срока")
    }
}
