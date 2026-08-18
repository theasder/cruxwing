import Testing
@testable import OrakulCore

// Токен уезжает по тому адресу, который вписал человек. Если он вписал `http`,
// токен от рабочего трекера едет открытым текстом — и увидит его не конкурент,
// а любой, кто сидит между: гостиничный Wi-Fi, прокси, сосед по офису.
@Suite("Адрес сервиса")
struct ConnectorAddressTests {

    @Test("http до чужого сервера поднимается до https")
    func publicHTTPIsUpgraded() {
        #expect(ConnectorAddress.normalise("http://git.company.ru") == "https://git.company.ru")
        #expect(ConnectorAddress.normalise("HTTP://git.company.ru") == "https://git.company.ru")
        #expect(ConnectorAddress.normalise("http://tracker.io/api/v4") == "https://tracker.io/api/v4")
    }

    @Test("адрес без схемы получает https, а не http")
    func bareHostGetsTLS() {
        #expect(ConnectorAddress.normalise("git.company.ru") == "https://git.company.ru")
        #expect(ConnectorAddress.normalise("  git.company.ru  ") == "https://git.company.ru")
    }

    @Test("https не трогаем")
    func httpsUntouched() {
        #expect(ConnectorAddress.normalise("https://git.company.ru") == "https://git.company.ru")
    }

    // Своя машина в своей сети — законный http. Требовать от неё сертификат
    // значит запретить половину самостоятельных установок GitLab и Gitea.
    @Test("http до своей сети остаётся http", arguments: [
        "http://localhost:3000",
        "http://127.0.0.1:8080",
        "http://gitea.local",
        "http://10.0.0.5",
        "http://192.168.1.10:8929",
        "http://172.16.4.4",
        "http://172.31.255.1",
    ])
    func localHTTPKept(address: String) {
        #expect(ConnectorAddress.normalise(address) == address)
    }

    // 172.32 уже не частный диапазон: он маршрутизируется, и токен по нему
    // уедет наружу. Граница проверяется с обеих сторон.
    @Test("соседние с частным диапазоном адреса частными не считаются")
    func rangeBordersHold() {
        #expect(ConnectorAddress.normalise("http://172.32.0.1") == "https://172.32.0.1")
        #expect(ConnectorAddress.normalise("http://172.15.0.1") == "https://172.15.0.1")
        #expect(ConnectorAddress.isLocal("172.32.0.1") == false)
        #expect(ConnectorAddress.isLocal("172.16.0.1"))
        // «10.» в середине имени — не частная сеть, а чужой домен.
        #expect(ConnectorAddress.isLocal("not10.example.com") == false)
        #expect(ConnectorAddress.isLocal("localhost.attacker.com") == false)
    }

    // nil значит «ничего не вписано» и только это.
    @Test("пусто — это пусто, мусор — это мусор")
    func emptyAndGarbageDiffer() {
        #expect(ConnectorAddress.normalise(nil) == nil)
        #expect(ConnectorAddress.normalise("   ") == nil)
        #expect(ConnectorAddress.normalise("не адрес") != nil)
    }

    // Самая дорогая ошибка этого файла: у заметок пустой адрес означает
    // «облако вендора». Если непарсящийся адрес своей установки вернёт nil, то
    // токен от внутреннего Outline уедет в чужое облако — тише и хуже, чем http.
    @Test("непарсящийся адрес не превращается в облако вендора")
    func garbageNeverFallsBackToCloud() {
        let notes = TeamNotes.Service.outline
        let host = notes.host("http://ой ой")
        #expect(host != notes.cloudHost)
        #expect(host?.hasPrefix("https://") == true)
    }

    // Правило должно стоять на всех трёх дверях, а не на той, где его писали.
    @Test("все три семейства коннекторов ходят через одно правило")
    func everyFamilyUsesTheRule() {
        #expect(SelfHostedTrackers.Service.gitlab.host("http://git.co") == "https://git.co")
        #expect(TeamNotes.Service.outline.host("http://wiki.co") == "https://wiki.co")
        #expect(WorkMessengers.Service.mattermost.host(secondary: "http://chat.co") == "https://chat.co")
        // И своя сеть проходит через все три так же.
        #expect(SelfHostedTrackers.Service.gitlab.host("http://localhost:3000") == "http://localhost:3000")
    }
}
