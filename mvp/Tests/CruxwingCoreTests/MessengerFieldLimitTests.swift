import Testing
import Foundation
@testable import CruxwingCore

/// У мессенджера ровно одно поле, и это ограничение, а не наблюдение.
///
/// Человек заполняет для мессенджера одну строку — команду у Mattermost,
/// комнату у Rocket.Chat. `WorkMessengers` берёт ПЕРВОЕ поле манифеста и
/// подставляет туда её.
///
/// Значит манифест с двумя полями описывает сервис, которого нельзя настроить:
/// вторая подстановка останется неразрешённой, и поиск ответит «не настроено»
/// при настроенном сервисе. Тот же отказ уже случался — когда поля не было
/// вовсе, — и в коде рядом об этом написано.
///
/// Поэтому здесь не «сегодня их по одному», а «больше одного не бывает»: пусть
/// набор упадёт у того, кто такой манифест напишет, и объяснит причину, вместо
/// того чтобы он час разбирался с «не настроено».
@Suite struct MessengerFieldLimitTests {

    @Test("манифест мессенджера объявляет не больше одного поля")
    func messengerManifestsDeclareAtMostOneField() throws {
        let manifests = try ConnectorManifest.bundled()
        var checked = 0
        for service in WorkMessengers.Service.allCases {
            guard let manifest = manifests.first(where: { $0.id == service.rawValue }) else { continue }
            checked += 1
            let fields = manifest.parameters?.count ?? 0
            let why = "«\(service.rawValue)» объявляет \(fields) полей, а мессенджер умеет одно: "
                + "второе уедет в никуда, и человек увидит «не настроено» при настроенном сервисе"
            #expect(fields <= 1, "\(why)")
        }
        #expect(checked >= 3, "проверено манифестов \(checked) — разбор сломан")
    }

    @Test("объявленное поле действительно доезжает до запроса")
    func theDeclaredFieldReachesTheRequest() async throws {
        // Проверка выше запрещает лишнее. Эта — что нужное не потерялось: без
        // неё «не больше одного» было бы совместимо с «ни одного».
        let manifest = try #require(ConnectorManifest.usable().first { $0.id == "rocketChat" })
        let field = try #require(manifest.parameters?.first?.name)
        var seen: URLRequest?
        let messengers = WorkMessengers(service: .rocketChat, token: "т:и",
                                        secondary: "https://rc.example",
                                        scope: "комната-1") { request in
            seen = request
            return (Data("{\"messages\":[]}".utf8), HTTPURLResponse())
        }
        _ = try? await messengers.search("тарифы")
        let url = try #require(seen?.url?.absoluteString.removingPercentEncoding)
        #expect(field == "room")
        #expect(url.contains("комната-1"), "поле не доехало: \(url)")
    }
}
