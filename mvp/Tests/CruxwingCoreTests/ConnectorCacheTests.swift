import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CruxwingCore

/// Ответ из памяти против придушенного сервиса.
///
/// Продолжение упражнения с конкурентом: заблокировать нас заметно, а отвечать
/// 429 на каждый третий запрос — нет, и выглядит это как «у них само не
/// работает». Здесь проверяется, что источник от этого не замолкает и что
/// старый ответ не выдаётся за свежий.
@Suite struct ConnectorCacheTests {

    final class Counter: @unchecked Sendable {
        private(set) var calls = 0
        private let answer: Data
        private let statusAfterFirst: Int
        init(answer: Data, statusAfterFirst: Int = 200) {
            self.answer = answer
            self.statusAfterFirst = statusAfterFirst
        }
        func http() -> ManifestConnector.HTTP {
            { [self] request in
                calls += 1
                let code = calls == 1 ? 200 : statusAfterFirst
                return (code == 200 ? answer : Data(),
                        HTTPURLResponse(url: request.url!, statusCode: code,
                                        httpVersion: nil,
                                        headerFields: code == 429 ? ["Retry-After": "60"] : [:])!)
            }
        }
    }

    static let answer = Data(#"[{"number":42,"title":"Поднять лимиты","state":"open"}]"#.utf8)

    static func manifest() throws -> ConnectorManifest {
        try #require(try ConnectorManifest.bundled().first { $0.id == "gitea" })
    }

    /// Про регистр сервису здесь уже всё известно, и это не подгонка под
    /// счётчик.
    ///
    /// Первый кириллический вопрос к незнакомому сервису задаётся дважды —
    /// так узнаётся, сравнивает ли он байты. Этот набор про КЭШ: он считает
    /// обращения и должен считать только те, что относятся к кэшу. Иначе
    /// каждая проверка кэша заодно молча проверяла бы обучение регистру, и
    /// сломались бы обе, когда сломается одно.
    static func connector(_ cache: ConnectorCache, _ http: @escaping ManifestConnector.HTTP)
        throws -> ManifestConnector {
        let memory = ConnectorCaseMemory()
        return ManifestConnector(manifest: try manifest(), token: "т",
                                 host: "https://git.example.com",
                                 cache: cache, caseMemory: memory, http: http)
    }

    /// То же, но с уже известным поведением сервиса.
    static func connector(_ cache: ConnectorCache, _ memory: ConnectorCaseMemory,
                          _ http: @escaping ManifestConnector.HTTP) throws -> ManifestConnector {
        ManifestConnector(manifest: try manifest(), token: "т", host: "https://git.example.com",
                          cache: cache, caseMemory: memory, http: http)
    }

    static func taughtMemory() async -> ConnectorCaseMemory {
        let memory = ConnectorCaseMemory()
        await memory.learn(.foldsCase, service: "gitea", host: "https://git.example.com")
        return memory
    }

    @Test("тот же вопрос за полторы минуты не бьёт по сервису второй раз")
    func repeatedQuestionIsNotAskedTwice() async throws {
        // Троттлинг, на который жалуются, отчасти наш собственный: на звонке
        // один вопрос задают трижды.
        let counter = Counter(answer: Self.answer)
        let cache = ConnectorCache()
        let connector = try Self.connector(cache, await Self.taughtMemory(), counter.http())
        _ = try await connector.run("лимиты")
        // Считаем ПРИБАВКУ, а не общее число: один поиск стоит больше одного
        // обращения — к слову человека добавляется вопрос основой. Раньше здесь
        // стояло «== 1», и это утверждение было про число вопросов на поиск, а
        // не про память, ради которой набор написан.
        let afterFirst = counter.calls
        _ = try await connector.run("лимиты")
        _ = try await connector.run("ЛИМИТЫ")   // регистр — тот же вопрос
        #expect(counter.calls == afterFirst,
                "повтор стоил ещё \(counter.calls - afterFirst) обращений")
    }

    @Test("другой вопрос спрашивается заново")
    func differentQuestionGoesOut() async throws {
        let counter = Counter(answer: Self.answer)
        let connector = try Self.connector(ConnectorCache(), await Self.taughtMemory(),
                                           counter.http())
        _ = try await connector.run("лимиты")
        let afterFirst = counter.calls
        _ = try await connector.run("тарифы")
        #expect(counter.calls > afterFirst, "другой вопрос ушёл из памяти, а не к сервису")
    }

    @Test("устаревший ответ не считается свежим")
    func staleAnswerIsNotFresh() async throws {
        // Часы подставные: ждать полторы минуты в наборе — это набор, который
        // никто не гоняет.
        let clock = Clock(start: Date(timeIntervalSince1970: 1_000_000))
        let cache = ConnectorCache(now: { clock.now })
        let counter = Counter(answer: Self.answer)
        let connector = try Self.connector(cache, await Self.taughtMemory(), counter.http())
        _ = try await connector.run("лимиты")
        let afterFirst = counter.calls
        clock.advance(ConnectorCache.freshFor + 1)
        _ = try await connector.run("лимиты")
        #expect(counter.calls > afterFirst, "ответ старше полутора минут выдан как свежий")
    }

    @Test("сервис просит подождать — отвечаем из памяти и говорим, сколько ему секунд")
    func throttledFallsBackToCache() async throws {
        let clock = Clock(start: Date(timeIntervalSince1970: 1_000_000))
        let cache = ConnectorCache(now: { clock.now })
        let counter = Counter(answer: Self.answer, statusAfterFirst: 429)
        let connector = try Self.connector(cache, counter.http())

        let first = try await connector.run("лимиты")
        #expect(first.coverage == .searched)

        clock.advance(ConnectorCache.freshFor + 30)   // свежесть кончилась, годность нет
        let second = try await connector.run("лимиты")
        #expect(second.items.map(\.title) == ["Поднять лимиты"], "источник замолчал под троттлингом")
        #expect(second.coverage == .cached(seconds: 120, under: .service))
        #expect(second.coverage.note().contains("120s-old"),
                "ответ из памяти не назвал свой возраст: «\(second.coverage.note())»")
    }

    @Test("нечего вспомнить — отказ остаётся отказом")
    func throttledWithoutCacheStillFails() async throws {
        // Иначе «мы всегда отвечаем» достигалось бы тем, что мы отвечаем пусто.
        let counter = Counter(answer: Self.answer, statusAfterFirst: 429)
        let connector = try Self.connector(ConnectorCache(), counter.http())
        _ = try await connector.run("лимиты")
        await #expect(throws: ManifestConnector.ConnectorError.rateLimited(retryAfter: 60)) {
            _ = try await connector.run("тарифы")
        }
    }

    @Test("совсем старый ответ не достают даже под троттлингом")
    func veryOldAnswerIsNotUsed() async throws {
        // Пятнадцать минут — граница, за которой «что решили» рискует пережить
        // само решение.
        let clock = Clock(start: Date(timeIntervalSince1970: 1_000_000))
        let cache = ConnectorCache(now: { clock.now })
        let counter = Counter(answer: Self.answer, statusAfterFirst: 429)
        let connector = try Self.connector(cache, counter.http())
        _ = try await connector.run("лимиты")
        clock.advance(ConnectorCache.usableWhenThrottledFor + 1)
        await #expect(throws: ManifestConnector.ConnectorError.self) {
            _ = try await connector.run("лимиты")
        }
    }

    final class Clock: @unchecked Sendable {
        private(set) var now: Date
        init(start: Date) { now = start }
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }
}
