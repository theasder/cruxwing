import Testing
import Foundation
@testable import OrakulCore

@Suite("Отказ источника остаётся фактом")
struct ConnectorHealthTests {

    private struct Refused: LocalizedError {
        let errorDescription: String?
    }

    @Test("слова сервиса сохраняются, а не пересказываются")
    func vendorWordsAreKept() async {
        let health = ConnectorHealth(now: { Date(timeIntervalSince1970: 1_000) })
        await health.record(service: "wikijs",
                            error: Refused(errorDescription: "Токен настоящий, но права не выдали."))
        let refusal = await health.refusal(for: "wikijs")
        #expect(refusal?.words == "Токен настоящий, но права не выдали.")
        #expect(refusal?.at == Date(timeIntervalSince1970: 1_000))
    }

    @Test("успех стирает прошлый отказ")
    func successClearsRefusal() async {
        let health = ConnectorHealth()
        await health.record(service: "gitea", error: Refused(errorDescription: "нет права"))
        #expect(await health.refusal(for: "gitea") != nil)
        await health.recordSuccess(service: "gitea")
        #expect(await health.refusal(for: "gitea") == nil,
                "жалоба про вчерашний сбой отправит человека чинить то, что работает")
    }

    @Test("источники не путаются между собой")
    func servicesStaySeparate() async {
        let health = ConnectorHealth()
        await health.record(service: "wikijs", error: Refused(errorDescription: "Forbidden"))
        await health.record(service: "gitlab", error: Refused(errorDescription: "нет области read_api"))
        #expect(await health.refusal(for: "wikijs")?.words == "Forbidden")
        #expect(await health.refusal(for: "gitlab")?.words == "нет области read_api")
        #expect(await health.all().count == 2)
    }

    @Test("ошибка без слов не превращается в пустую строку")
    func errorWithoutWordsStillSaysSomething() async {
        struct Bare: Error {}
        let health = ConnectorHealth()
        await health.record(service: "outline", error: Bare())
        let words = await health.refusal(for: "outline")?.words ?? ""
        #expect(!words.isEmpty, "пустая жалоба ничем не лучше тишины, из-за которой всё это писалось")
    }
}
