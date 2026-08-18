import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Куда позволено уводить запрос с токеном.
///
/// Найдено в упражнении с недружелюбным сервисом 2026-08-18, и это худшее из
/// найденного: `URLSession` по умолчанию идёт по перенаправлению САМА и
/// повторяет запрос по новому адресу — вместе с заголовком `Authorization`.
/// Значит сервис, отвечающий `302 Location: https://чужой.example/collect`,
/// получает наш токен, не спрашивая ни у кого разрешения. Для самостоятельного
/// сервера (GitLab, Gitea, Nextcloud) хватит и опечатки в адресе: человек
/// вписал не тот домен — и токен уехал туда.
///
/// Правило простое и намеренно грубое: переходим только туда, где и были.
/// Смена хоста запрещена, понижение https → http запрещено. Перенаправление
/// не молчит — оно доезжает до человека как ответ 3xx, то есть видимая
/// странность вместо тихой отправки ключа.
public enum RedirectPolicy {

    /// Разрешён ли переход. Чистая функция, чтобы это можно было проверить
    /// набором, не поднимая сети.
    public static func allows(from original: URL, to next: URL) -> Bool {
        guard let fromHost = original.host?.lowercased(),
              let toHost = next.host?.lowercased() else { return false }
        guard fromHost == toHost else { return false }
        let fromScheme = original.scheme?.lowercased() ?? ""
        let toScheme = next.scheme?.lowercased() ?? ""
        // http → https разрешён: это усиление. Обратное — нет: токен ушёл бы
        // открытым текстом, и тому, кто это устроил, именно этого и надо.
        if fromScheme == "https" && toScheme != "https" { return false }
        return toScheme == "https" || toScheme == "http"
    }
}

/// Сеть коннекторов: одна сессия на всех, с запретом уводить токен на чужой хост.
public enum ConnectorSession {

    private final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession,
                        task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            guard let from = task.originalRequest?.url, let to = request.url,
                  RedirectPolicy.allows(from: from, to: to) else {
                // `nil` — не идти дальше. Ответом становится сам 3xx, и человек
                // видит «сервис ответил ошибкой 302» вместо тишины.
                completionHandler(nil)
                return
            }
            completionHandler(request)
        }
    }

    private static let guardDelegate = RedirectGuard()

    /// Одна сессия на процесс: у каждой свой пул соединений, и создавать её на
    /// запрос значит открывать соединение заново на каждый вопрос.
    public static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        // Ответы коннекторов не кладутся на диск: это чужие данные, и жить
        // дольше разговора им негде. Своя недолгая память — в ConnectorCache.
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        // Сервису не обязательно отвечать, чтобы навредить: достаточно не
        // закрывать соединение. `timeoutIntervalForRequest` считает ПАУЗЫ, и
        // байт раз в двадцать секунд обнуляет его вечно. По умолчанию у второго
        // предела стоит СЕМЬ СУТОК — то есть его нет.
        //
        // Здесь ограничен весь обмен целиком: минута на ответ, дальше отказ.
        // Поиск по трекеру, который идёт минуту, — это уже сломанный поиск.
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        // Ожидание доступной сети не должно превращаться в вечное ожидание.
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration,
                          delegate: guardDelegate,
                          delegateQueue: nil)
    }()

    /// То, что подставляется коннекторам как `live`.
    public static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        let data = try await collect(bytes, limit: ManifestConnector.maximumResponseBytes)
        return (data, http)
    }

    /// Складывает ответ, останавливаясь на пределе.
    ///
    /// Предел стоял и раньше, но проверялся ПОСЛЕ `session.data(for:)`, а тот
    /// сначала складывает в память весь ответ целиком. Сервис, отдающий десять
    /// гигабайт, съедал память до последнего байта, и только потом сторож
    /// сообщал, что ответ великоват. Сторож был, срабатывать ему было уже не по
    /// чему.
    ///
    /// Сжатие учтено само собой: `URLSession` отдаёт уже распакованное, поэтому
    /// килобайт, разворачивающийся в гигабайт, считается гигабайтом — и здесь
    /// обрывается на восьмом мегабайте, а не после гигабайта.
    static func collect<Bytes: AsyncSequence>(_ bytes: Bytes, limit: Int) async throws -> Data
    where Bytes.Element == UInt8 {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            // Строго больше: ответ ровно в предел — законный ответ.
            if data.count > limit { throw URLError(.dataLengthExceedsMaximum) }
        }
        return data
    }
}
