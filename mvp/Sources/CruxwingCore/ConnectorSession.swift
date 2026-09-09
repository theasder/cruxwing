import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Куда позволено уводить запрос с токеном.
///
/// Найдено в упражнении с недружелюбным сервисом 2026-08-18. Первая запись
/// здесь утверждала, что `URLSession` уносит на чужой хост заголовок
/// `Authorization` вместе с запросом. Это оказалось неправдой, и узналось это
/// только тогда, когда против настоящего сокета встал настоящий недружелюбный
/// сервер (`scripts/vrazhdebnyj-server.py`, 2026-08-19).
///
/// Измеренное поведение сессии по умолчанию оказалось РАЗНЫМ на двух системах,
/// и это главное, что дал опыт:
///
///   * macOS: за перенаправлением идёт (конечный адрес — чужой хост, ответ
///     200), но заголовок `Authorization` Foundation при смене хоста снимает.
///     Токен не уезжает;
///   * Linux, swift-corelibs-foundation 6.0.3: идёт и заголовок ПЕРЕНОСИТ.
///     Сборщик получил `Bearer секретный-ключ` целиком.
///
/// То есть на Linux исходное утверждение было верным, а на macOS — нет; общего
/// «Foundation защищает» не существует. Командная строка cruxwing работает именно
/// на Linux (план, §6.1), и там этот делегат — единственное, что стоит между
/// токеном от чужого трекера и адресом, который назвал сам сервис.
///
/// На обеих системах к чужому хосту уходит САМ ЗАПРОС — путь и параметры. У
/// коннектора в параметрах лежит слово, которое человек ищет, то есть
/// содержание его разговора. Поэтому правило запрещает переход, а не чистит
/// заголовки: снятие заголовка — поведение чужой библиотеки, которое здесь не
/// обещано никем и на одной из двух систем не выполняется.
///
/// Для самостоятельного сервера (GitLab, Gitea, Nextcloud) хватит и опечатки в
/// адресе, чтобы запрос ушёл не туда.
///
/// Проверка «ловушка ловит» стоит в наборе рядом: сессия по умолчанию до
/// сборщика доходит, наша — нет.
///
/// Правило простое и намеренно грубое: переходим только в тот же origin —
/// схема, хост и эффективный порт должны совпасть. Другой порт означает другой
/// процесс и другую границу доверия даже на том же имени. Перенаправление не
/// молчит — оно доезжает до человека как ответ 3xx, то есть видимая странность
/// вместо тихой отправки ключа.
public enum RedirectPolicy {

    /// Разрешён ли переход. Чистая функция, чтобы это можно было проверить
    /// набором, не поднимая сети.
    public static func allows(from original: URL, to next: URL) -> Bool {
        guard let fromHost = original.host?.lowercased(),
              let toHost = next.host?.lowercased() else { return false }
        guard fromHost == toHost else { return false }
        let fromScheme = original.scheme?.lowercased() ?? ""
        let toScheme = next.scheme?.lowercased() ?? ""
        guard (fromScheme == "https" || fromScheme == "http"),
              fromScheme == toScheme else { return false }
        return effectivePort(of: original, scheme: fromScheme)
            == effectivePort(of: next, scheme: toScheme)
    }

    private static func effectivePort(of url: URL, scheme: String) -> Int? {
        if let port = url.port { return port }
        switch scheme {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
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
    private static let streamGuard = StreamGuard()

    /// Складывает ответ кусками и обрывает задачу на первом куске за пределом.
    ///
    /// Состояние — по номеру задачи: делегат один на всю сессию, а запросов
    /// одновременно много. Общий буфер здесь означал бы перемешанные ответы,
    /// то есть чужую задачу в чужой выдаче.
    private final class StreamGuard: NSObject, URLSessionDataDelegate, @unchecked Sendable {

        private struct Pending {
            var data = Data()
            var limit = 0
            var response: HTTPURLResponse?
            var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
        }

        private let lock = NSLock()
        private var pending: [Int: Pending] = [:]

        func send(_ request: URLRequest, on session: URLSession,
                  limit: Int) async throws -> (Data, HTTPURLResponse) {
            let task = session.dataTask(with: request)
            return try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                var slot = Pending()
                slot.limit = limit
                slot.continuation = continuation
                pending[task.taskIdentifier] = slot
                lock.unlock()
                task.resume()
            }
        }

        /// Возвращает продолжение ровно один раз: второй вызов — падение.
        private func finish(_ id: Int, with result: Result<(Data, HTTPURLResponse), Error>) {
            lock.lock()
            let continuation = pending[id]?.continuation
            pending[id]?.continuation = nil
            if continuation != nil { pending[id] = nil }
            lock.unlock()
            continuation?.resume(with: result)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                        didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            lock.lock()
            pending[dataTask.taskIdentifier]?.response = response as? HTTPURLResponse
            lock.unlock()
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            lock.lock()
            guard var slot = pending[dataTask.taskIdentifier] else { lock.unlock(); return }
            slot.data.append(data)
            let over = slot.data.count > slot.limit
            pending[dataTask.taskIdentifier] = slot
            lock.unlock()

            if over {
                // Отмена — не «мы больше не читаем», а «соединение закрыто»:
                // иначе сервис продолжает лить, а мы продолжаем платить.
                dataTask.cancel()
                finish(dataTask.taskIdentifier,
                       with: .failure(URLError(.dataLengthExceedsMaximum)))
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            lock.lock()
            let slot = pending[task.taskIdentifier]
            lock.unlock()
            if let error {
                finish(task.taskIdentifier, with: .failure(error))
                return
            }
            guard let http = slot?.response else {
                finish(task.taskIdentifier, with: .failure(URLError(.badServerResponse)))
                return
            }
            finish(task.taskIdentifier, with: .success((slot?.data ?? Data(), http)))
        }

        // Перенаправления остаются на том же правиле: делегат у сессии один, и
        // задачи с данными идут через него же.
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            guard let from = task.originalRequest?.url, let to = request.url,
                  RedirectPolicy.allows(from: from, to: to) else {
                completionHandler(nil)
                return
            }
            completionHandler(request)
        }
    }

    /// Одна сессия на процесс: у каждой свой пул соединений, и создавать её на
    /// запрос значит открывать соединение заново на каждый вопрос.
    /// Как мы представляемся чужому сервису.
    ///
    /// Строка короткая и без подробностей о системе: назвать себя — вежливость
    /// и требование части API, а перечислять версию macOS чужому серверу
    /// незачем. Имя — публичное, то самое, что человек видит в интерфейсе.
    public static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "cruxwing/\(version ?? "0")"
    }

    public static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        // Ответы коннекторов не кладутся на диск: это чужие данные, и жить
        // дольше разговора им негде. Своя недолгая память — в ConnectorCache.
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        // Кто стучится — сказано нарочно.
        //
        // Без этого заголовок собирает сама система из ИМЕНИ ИСПОЛНЯЕМОГО
        // ФАЙЛА: у собранного приложения это «MeetGPT» — внутреннее имя цели, а
        // продукт называется cruxwing. Измерено 2026-08-21 на своём сервере,
        // записавшем настоящий запрос: «MeetGPT/… CFNetwork/… Darwin/24.6.0».
        // Каждый подключённый сервис — включая сервис конкурента — видел имя,
        // которого нет ни на странице, ни в интерфейсе.
        //
        // Версию берём из того же места, что и упаковка: два числа об одной
        // сборке обязаны совпадать.
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent]
        // Сервису не обязательно отвечать, чтобы навредить: достаточно не
        // закрывать соединение. `timeoutIntervalForRequest` считает ПАУЗЫ, и
        // байт раз в двадцать секунд обнуляет его вечно. По умолчанию у второго
        // предела стоит СЕМЬ СУТОК — то есть его нет.
        //
        // Здесь ограничен весь обмен целиком: минута на ответ, дальше отказ.
        // Поиск по трекеру, который идёт минуту, — это уже сломанный поиск.
        configuration.timeoutIntervalForRequest = 30
        // Предел на весь обмен. На Linux он ЖЁСТЧЕ, и это не вкусовщина.
        //
        // Измерено 2026-08-19 на corelibs 6.0.3: обрыв ответа там не работает.
        // Предел мы замечаем на первом же куске за ним и возвращаем человеку
        // ошибку сразу — но сама передача продолжается. После `cancel()` задачи
        // пришло ещё 62 450 кусков за пять секунд, после
        // `invalidateAndCancel()` сессии — 72 414. Остановить чтение из
        // делегата на этой системе нечем.
        //
        // Значит единственная граница здесь — время, и поэтому оно короче:
        // поиск по трекеру, идущий двадцать секунд, сломан в любом случае, а
        // втрое короче окно — втрое меньше того, что успеет влить недружелюбный
        // сервис.
        #if canImport(Darwin)
        configuration.timeoutIntervalForResource = 60
        #else
        configuration.timeoutIntervalForResource = 20
        #endif
        // Ожидание доступной сети не должно превращаться в вечное ожидание.
        //
        // Только у Apple: в swift-corelibs-foundation это свойство доступно
        // ТОЛЬКО НА ЧТЕНИЕ, и присваивание там не собирается. Потолок на весь
        // обмен выше работает на обеих системах, поэтому Linux не остаётся без
        // границы — он остаётся без одной из двух.
        #if canImport(Darwin)
        configuration.waitsForConnectivity = false
        #endif
        return URLSession(configuration: configuration,
                          delegate: streamGuard,
                          delegateQueue: nil)
    }()

    /// То, что подставляется коннекторам как `live`.
    ///
    /// Через делегата, а не через `session.bytes(for:)`.
    ///
    /// `bytes(for:)` есть только у Apple: в swift-corelibs-foundation 6.0.3
    /// такого метода нет вовсе, и ядро на Linux с ним просто не собиралось.
    /// Узналось это, когда шаг CI впервые запустили в том же образе, в котором
    /// он должен идти, — на моей машине всё собиралось четыре дня подряд.
    ///
    /// Делегат работает на обеих системах одинаково: куски приходят по мере
    /// прихода, счётчик растёт, на первом же куске за пределом задача
    /// отменяется. Именно этого и добивались: ответ не должен оказаться в
    /// памяти целиком, чтобы про него сказали «великоват».
    public static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await streamGuard.send(request, on: session,
                                   limit: ManifestConnector.maximumResponseBytes)
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
