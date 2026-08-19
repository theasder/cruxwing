import Foundation
// URLRequest и HTTPURLResponse на Linux живут в FoundationNetworking — том же
// модуле, что и в ядре. Без этого набор не собирается там, где он и должен
// доказывать переносимость.
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Что коннектор отправил в сеть. Лежал тремя одинаковыми копиями в наборах
/// про российские трекеры, свои серверы и мессенджеры; четвёртая копия
/// понадобилась для заведения задач — и стало ясно, что копий уже слишком
/// много, чтобы правка задевала одну.
///
/// `@unchecked Sendable` с замком, а не актор: коннекторы зовут запись из
/// своей задачи, и `await` внутри стаба переставил бы порядок, который тесты
/// как раз и проверяют.
final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        requests.append(request)
    }
    var last: URLRequest? { lock.lock(); defer { lock.unlock() }; return requests.last }
    /// Первый запрос — тот, что унёс слово человека. Коннектор может
    /// спросить второй раз с заглавной буквы, и тогда `last` уже не про то.
    var first: URLRequest? { lock.lock(); defer { lock.unlock() }; return requests.first }
    var count: Int { lock.lock(); defer { lock.unlock() }; return requests.count }
    var all: [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
}

/// Ответ-заглушка для проверок, которые до сети не доходят вовсе: коннектор
/// отказывается раньше, чем дошёл бы до запроса, и что вернул бы сервер —
/// неважно.
///
/// Существует из-за одной разницы между системами: пустого `HTTPURLResponse()`
/// в swift-corelibs-foundation нет, там этот инициализатор требует `coder:`.
/// Найдено сборкой набора на Linux, а не рассуждением.
func stubHTTPResponse(status: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(url: URL(string: "https://example.invalid")!, statusCode: status,
                    httpVersion: nil, headerFields: [:])!
}

/// Флаг и счётчик для подставного HTTP — по той же причине, что и `Recorder`.
///
/// Замыкание запроса вызывается из другого места, чем набор его читает, и
/// захваченная `var` в Swift 6 — уже не предупреждение, а ошибка сборки.
/// Наборы перестанут собираться в тот день, когда пакет перейдёт на язык 6.
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func raise() { lock.lock(); value = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

/// Счётчик для СИНХРОННОГО чтения.
///
/// В ConnectorQueryTests уже есть `Counter` — актор, и он правильный там, где
/// значение читают из async-кода. Здесь читатель синхронный (`() -> Int`), и
/// актор потребовал бы await у каждого читателя. Разные имена, потому что это
/// разные вещи; одно имя на две — это столкновение, а не переиспользование.
final class SyncCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func tick() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}
