import Foundation

/// Адрес сервиса, который вписал человек.
///
/// Одно правило, и оно про токен, а не про адрес: по `http://` он уезжает
/// открытым текстом. Любой, кто видит сеть между человеком и сервером —
/// гостиничный Wi-Fi, прокси провайдера, сосед по офису, — читает ключ от
/// рабочего трекера целиком. Ни один конкурент для этого ничего делать не
/// должен: достаточно, чтобы человек скопировал адрес с `http` из старой
/// закладки.
///
/// Раньше `http://…` принимался как есть: схему дописывали только тогда, когда
/// её не было вовсе.
///
/// Исключение ровно одно и оно осмысленное: адрес, до которого нельзя дойти
/// снаружи. `localhost`, `127.0.0.1`, `::1`, имена в `.local` и частные
/// диапазоны (`10.x`, `192.168.x`, `172.16–31.x`) — это машина в своей же сети,
/// и требовать от неё сертификат значит запретить половину самостоятельных
/// установок GitLab и Gitea, которые именно так и живут.
public enum ConnectorAddress {

    /// Нормализованный адрес: со схемой и без хвостовой косой черты.
    public static func normalise(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }

        let withScheme = value.contains("://") ? value : "https://\(value)"

        // nil значит «человек ничего не вписал» и только это. Если он вписал
        // мусор, мусор и возвращаем: у `TeamNotes` пустое значение означает
        // «облако вендора», и превратить непарсящийся адрес своей установки в
        // облако — это ровно тот увоз токена, от которого файл и написан.
        // Мусор не подключится, и это разговор про адрес, а не про утечку.
        guard let url = URL(string: withScheme), let host = url.host else {
            return upgraded(withScheme)
        }

        if url.scheme?.lowercased() == "http" && !isLocal(host) {
            // Молча поднимаем до https. Отказать было бы честнее на словах, но
            // на деле человек прочитал бы «не подключён» и пошёл проверять
            // токен. Если у сервера действительно нет TLS, он ответит ошибкой
            // соединения — и это разговор про сервер, а не утёкший ключ.
            return upgraded(withScheme)
        }
        return withScheme
    }

    private static func upgraded(_ address: String) -> String {
        address.replacingOccurrences(of: "http://", with: "https://",
                                     options: [.caseInsensitive, .anchored])
    }

    /// Адрес, до которого не дойти из чужой сети.
    public static func isLocal(_ host: String) -> Bool {
        let name = host.lowercased()
        if name == "localhost" || name == "127.0.0.1" || name == "::1" { return true }
        if name.hasSuffix(".local") || name.hasSuffix(".localhost") { return true }
        if name.hasPrefix("10.") || name.hasPrefix("192.168.") { return true }
        // 172.16.0.0 – 172.31.255.255: частный диапазон, но 172.32.x уже нет.
        if name.hasPrefix("172.") {
            let parts = name.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) {
                return true
            }
        }
        return false
    }
}
