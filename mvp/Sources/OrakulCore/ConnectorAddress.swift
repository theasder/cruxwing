import Foundation

/// Адрес сервиса, который вписал человек.
///
/// Одно правило, и оно про токен, а не про адрес: наружу он уезжает только по
/// `https://`. По `http://` ключ идёт открытым текстом, а произвольная схема
/// (`ftp://`, `ws://` или зарегистрированная библиотекой позже) обходит саму
/// гарантию, что коннектор использует HTTP поверх TLS. Любой, кто видит сеть
/// между человеком и сервером —
/// гостиничный Wi-Fi, прокси провайдера, сосед по офису, — читает ключ от
/// рабочего трекера целиком. Ни один конкурент для этого ничего делать не
/// должен: достаточно, чтобы человек скопировал адрес с `http` из старой
/// закладки.
///
/// Раньше `http://…` принимался как есть: схему дописывали только тогда, когда
/// её не было вовсе.
///
/// Исключение ровно одно: loopback той же машины. `localhost`, `127.0.0.0/8`
/// и `::1` не проходят через офисную или домашнюю сеть. `.local` и частные IP
/// — уже другие устройства в LAN; там HTTP раскрывает bearer-токен любому,
/// кто контролирует точку доступа, DNS/mDNS или ARP-маршрут.
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
        // Мусор не подключится, и это разговор про адрес, а не про утечку. При
        // этом сохранять неизвестную схему нельзя: Foundation на разных
        // платформах поддерживает разные протоколы, и новый обработчик не должен
        // однажды превратить сегодняшний безопасный отказ в отправку токена.
        guard let url = URL(string: withScheme), let host = url.host else {
            return forcedHTTPS(withScheme)
        }

        let scheme = url.scheme?.lowercased()
        if scheme == "https" || (scheme == "http" && isLoopback(host)) {
            return withScheme
        }

        if scheme == "http" {
            // Молча поднимаем до https. Отказать было бы честнее на словах, но
            // на деле человек прочитал бы «не подключён» и пошёл проверять
            // токен. Если у сервера действительно нет TLS, он ответит ошибкой
            // соединения — и это разговор про сервер, а не утёкший ключ.
            return forcedHTTPS(withScheme)
        }

        // Разрешительный список намеренно короткий. URLSession на Darwin и
        // swift-corelibs Foundation на Linux поддерживают не одинаковый набор
        // схем; безопасность адреса не должна зависеть от реализации рантайма.
        return forcedHTTPS(withScheme)
    }

    private static func forcedHTTPS(_ address: String) -> String {
        guard let separator = address.range(of: "://") else {
            return "https://\(address)"
        }
        return "https://\(address[separator.upperBound...])"
    }

    /// Адрес, который гарантированно остаётся внутри этого компьютера.
    public static func isLoopback(_ host: String) -> Bool {
        let name = host.lowercased()
        return name == "localhost"
            || name.hasSuffix(".localhost")
            || isIPv4LoopbackLiteral(name)
            || name == "::1"
            || name == "[::1]"
    }

    /// Only a numeric four-octet address can claim the 127/8 exception.
    /// A prefix check would also trust a DNS name such as
    /// `127.attacker.example`, which can resolve to any machine on the
    /// internet while looking superficially local.
    private static func isIPv4LoopbackLiteral(_ host: String) -> Bool {
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return false }

        var numbers: [UInt8] = []
        numbers.reserveCapacity(4)
        for octet in octets {
            guard !octet.isEmpty,
                  octet.allSatisfy(\.isNumber),
                  let number = UInt8(octet) else { return false }
            numbers.append(number)
        }
        return numbers[0] == 127
    }
}
