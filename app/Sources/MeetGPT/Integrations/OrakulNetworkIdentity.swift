import Foundation
import OrakulCore

/// The identity every app-owned HTTP client presents to another service.
///
/// `URLSession.shared` derives its default User-Agent from the executable name.
/// The executable is still named `MeetGPT` for build compatibility, so using the
/// system default leaks the parent product name and the host's CFNetwork/Darwin
/// versions. All production sessions are created here instead.
enum OrakulNetworkIdentity {
    static var userAgent: String { ConnectorSession.userAgent }

    static let shared: URLSession = makeSession()

    static func makeSession(
        configuration: URLSessionConfiguration = .default,
        delegate: URLSessionDelegate? = nil,
        delegateQueue: OperationQueue? = nil
    ) -> URLSession {
        var headers = configuration.httpAdditionalHeaders ?? [:]
        headers["User-Agent"] = userAgent
        configuration.httpAdditionalHeaders = headers
        return URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: delegateQueue)
    }
}
