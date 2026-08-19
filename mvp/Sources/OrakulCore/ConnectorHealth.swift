import Foundation

/// Отказ источника, который иначе выглядит как «ничего не нашлось».
///
/// Подсказки на звонке собираются по нескольким источникам сразу, и упавший
/// источник не должен ронять ответ: вопрос человека важнее, чем полнота. Но
/// «сервис отказал» и «в вики про это ничего нет» приходили в одно и то же
/// место — в `nil`, и дальше в тишину. Отозванный токен, снятое право,
/// недружелюбный сервис — всё это выглядело как продукт, который стал хуже
/// отвечать. Человек винит orakul, потому что больше некого.
///
/// Здесь отказ остаётся фактом: с чьими словами, когда. Ответ на звонке от
/// этого не меняется — меняется то, что человек может узнать, почему источник
/// молчит.
public actor ConnectorHealth {

    public struct Refusal: Equatable, Sendable {
        public let service: String
        /// Слова сервиса, как их сформулировала обёртка семьи.
        public let words: String
        public let at: Date

        public init(service: String, words: String, at: Date) {
            self.service = service
            self.words = words
            self.at = at
        }
    }

    public static let shared = ConnectorHealth()

    private var refusals: [String: Refusal] = [:]
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    /// Записать отказ. Слова берутся у ошибки — свои мы не сочиняем.
    public func record(service: String, error: Error) {
        let words = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        refusals[service] = Refusal(service: service, words: words, at: now())
    }

    /// Успех стирает отказ: висящая жалоба про вчерашний сбой хуже молчания —
    /// человек пойдёт чинить то, что уже работает.
    public func recordSuccess(service: String) {
        refusals[service] = nil
    }

    public func refusal(for service: String) -> Refusal? { refusals[service] }

    public func all() -> [Refusal] { refusals.values.sorted { $0.service < $1.service } }
}
