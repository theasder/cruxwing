import Foundation
import Testing
@testable import CruxwingCore

/// Поток, который считает, сколько байт с него на самом деле сняли.
///
/// Считает именно потреблённое: утверждение «остановились рано» проверяется
/// только так. Проверка «выкинуло ошибку» одинаково зелёная и когда предел
/// сработал на девятом мегабайте, и когда он сработал после гигабайта в памяти.
private struct CountingBytes: AsyncSequence {
    typealias Element = UInt8
    let total: Int
    let consumed: Counter

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
        func tick() { lock.lock(); value += 1; lock.unlock() }
    }

    struct Iterator: AsyncIteratorProtocol {
        let total: Int
        let consumed: Counter
        var index = 0
        mutating func next() async throws -> UInt8? {
            guard index < total else { return nil }
            index += 1
            consumed.tick()
            return 0x41
        }
    }

    func makeAsyncIterator() -> Iterator { Iterator(total: total, consumed: consumed) }
}

@Suite("Предел размера ответа")
struct ConnectorSessionLimitTests {

    @Test("ответ обрывается на пределе, а не после того, как он весь в памяти")
    func stopsEarly() async throws {
        let counter = CountingBytes.Counter()
        let hostile = CountingBytes(total: 100_000, consumed: counter)

        await #expect(throws: URLError.self) {
            _ = try await ConnectorSession.collect(hostile, limit: 1_000)
        }

        // Ровно предел плюс байт, на котором стало ясно, что предел перейдён.
        #expect(counter.count == 1_001,
                "сняли \(counter.count) байт при пределе 1000 — значит читали дальше")
    }

    @Test("ответ ровно в предел — законный ответ")
    func exactLimitPasses() async throws {
        let data = try await ConnectorSession.collect(
            CountingBytes(total: 1_000, consumed: .init()), limit: 1_000)
        #expect(data.count == 1_000)
    }

    @Test("обычный ответ доходит целиком")
    func normalResponsePasses() async throws {
        let data = try await ConnectorSession.collect(
            CountingBytes(total: 512, consumed: .init()), limit: 1_000)
        #expect(data.count == 512)
    }

    @Test("предел коннекторов — восемь мегабайт")
    func limitIsTheEngineLimit() {
        #expect(ManifestConnector.maximumResponseBytes == 8 * 1024 * 1024)
    }

    // Сервису не нужно ничего присылать, чтобы занять нас навсегда: у второго
    // предела по умолчанию семь суток. Проверяется живая сессия, а не копия
    // настроек: настройку можно задать и не применить.
    @Test("весь обмен ограничен по времени")
    func transferIsBounded() {
        let configuration = ConnectorSession.session.configuration
        // На Linux окно короче: там обрыв ответа не работает, и время —
        // единственная граница. Проверяется то, что задано на этой системе.
        #if canImport(Darwin)
        #expect(configuration.timeoutIntervalForResource == 60)
        #else
        #expect(configuration.timeoutIntervalForResource == 20)
        #endif
        #expect(configuration.timeoutIntervalForRequest == 30)
        // Только на Apple: у corelibs это свойство на чтение, и требовать от
        // него значения значит требовать несуществующего.
        #if canImport(Darwin)
        #expect(configuration.waitsForConnectivity == false)
        #endif
        // Семь суток — значение по умолчанию, то есть «предела нет».
        #expect(configuration.timeoutIntervalForResource < 7 * 24 * 60 * 60)
    }
}
