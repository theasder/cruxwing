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
