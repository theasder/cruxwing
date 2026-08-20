import Testing
import Foundation
@testable import OrakulCore

/// Память о том, что вопрос основой у сервиса бесполезен.
///
/// Вопрос основой — то, чем находятся русские склонения: человек сказал
/// «тарифы», в базе лежит «тарифами». Есть сервисы, которым он не помогает, и
/// у них его перестают задавать — иначе это трата чужого сервера.
///
/// Вывод делался с ПЕРВОГО наблюдения, и цена ошибки тут несимметрична.
/// Осторожность стоит одного лишнего запроса за звонок. Поспешность стоит
/// поиска по склонениям у этого сервиса до конца работы программы, и человеку
/// об этом не скажет никто.
///
/// Поводов ошибиться хватает без всякого умысла: перестраивается индекс,
/// сервис отвечает пустотой на переключении. А недружелюбному сервису это
/// рычаг, дешёвый и незаметный: ответить на слово находками, а на основу
/// пустотой — и мы сами выключим у себя половину русского поиска.
@Suite struct StemMemoryPoisonTests {

    @Test("одного промаха мало")
    func oneMissIsNotEnough() async {
        let memory = ConnectorCaseMemory()
        await memory.learnStemIsUseless(service: "s", host: "h")
        #expect(await memory.stemsAreUseless(service: "s", host: "h") == false)
    }

    @Test("два промаха подряд — вывод")
    func twoMissesInARowDecide() async {
        let memory = ConnectorCaseMemory()
        await memory.learnStemIsUseless(service: "s", host: "h")
        await memory.learnStemIsUseless(service: "s", host: "h")
        #expect(await memory.stemsAreUseless(service: "s", host: "h"))
    }

    @Test("удача между промахами обнуляет счёт")
    func successResetsTheCount() async {
        // Два промаха за неделю, разделённые сотней удачных вопросов, — не то
        // же самое, что два подряд.
        let memory = ConnectorCaseMemory()
        await memory.learnStemIsUseless(service: "s", host: "h")
        await memory.learnStemWorks(service: "s", host: "h")
        await memory.learnStemIsUseless(service: "s", host: "h")
        #expect(await memory.stemsAreUseless(service: "s", host: "h") == false)
    }

    @Test("память раздельна по сервисам и по хостам")
    func memoryIsPerServiceAndHost() async {
        let memory = ConnectorCaseMemory()
        await memory.learnStemIsUseless(service: "s", host: "h")
        await memory.learnStemIsUseless(service: "s", host: "другой")
        #expect(await memory.stemsAreUseless(service: "s", host: "h") == false,
                "промахи с разных хостов сложились в один вывод")
    }

    @Test("сервис, отвечающий словами, замолкает со второго звонка")
    func aWholeWordServiceIsLearnedOnTheSecondCall() async throws {
        // Так ведёт себя честный Gitea: слово находит, основа — ничего.
        let manifest = try #require(ConnectorManifest.usable().first { $0.id == "gitea" })
        let memory = ConnectorCaseMemory()
        let box = Counter()
        let connector = ManifestConnector(
            manifest: manifest, token: "t", host: "https://g.example",
            cache: ConnectorCache(), caseMemory: memory) { request in
            let url = (request.url?.absoluteString.removingPercentEncoding ?? "")
            box.bump()
            // Слово находит, основа — нет.
            // Gitea отдаёт массив верхним уровнем, а не под ключом.
            let body = url.contains("тарифы") || url.contains("сроки")
                ? "[{\"number\":1,\"title\":\"тарифы\",\"state\":\"open\"}]"
                : "[]"
            return (Data(body.utf8), HTTPURLResponse())
        }
        _ = try await connector.run("тарифы", limit: 10)
        #expect(await memory.stemsAreUseless(service: "gitea", host: "https://g.example") == false,
                "вывод сделан с первого звонка")
        _ = try await connector.run("сроки", limit: 10)
        #expect(await memory.stemsAreUseless(service: "gitea", host: "https://g.example"),
                "два звонка подряд ничего не решили — основой будем спрашивать вечно")
    }

    @Test("удачный вопрос основой обнуляет счёт и в самом движке")
    func theEngineResetsTheCount() async throws {
        // Найдено мутацией: проверка выше зовёт память НАПРЯМУЮ, поэтому
        // снятие обнуления из движка она проходила. Здесь три звонка подряд
        // через коннектор, и средний — удачный.
        let manifest = try #require(ConnectorManifest.usable().first { $0.id == "gitea" })
        let memory = ConnectorCaseMemory()
        let connector = ManifestConnector(
            manifest: manifest, token: "t", host: "https://g.example",
            cache: ConnectorCache(), caseMemory: memory) { request in
            let url = request.url?.absoluteString.removingPercentEncoding ?? ""
            // Слово находит всегда; основа — только у «смет».
            let whole = ["тарифы", "сметы", "лимиты"].contains { url.contains("q=" + $0) }
            let luckyStem = url.contains("q=смет") && !url.contains("q=сметы")
            let body = whole || luckyStem
                ? "[{\"number\":1,\"title\":\"есть\",\"state\":\"open\"}]"
                : "[]"
            return (Data(body.utf8), HTTPURLResponse())
        }
        _ = try await connector.run("тарифы", limit: 10)   // промах 1
        _ = try await connector.run("сметы", limit: 10)    // основа нашла — сброс
        _ = try await connector.run("лимиты", limit: 10)   // снова промах 1, не 2
        #expect(await memory.stemsAreUseless(service: "gitea", host: "https://g.example") == false,
                "движок не обнулил счёт после удачного вопроса основой")
    }

    @Test("вывод «регистр приводит сам» тоже требует двух наблюдений")
    func foldingConclusionNeedsTwo() async {
        // Тот же рычаг, что и у основы, на соседнем вопросе: ответить один раз
        // одинаково на два написания — и мы сами перестали бы спрашивать
        // вторым. На Synapse это стоило бы половины находок.
        let memory = ConnectorCaseMemory()
        await memory.learn(.foldsCase, service: "s", host: "h")
        #expect(await memory.behaviour(service: "s", host: "h") == .unknown,
                "вывод сделан по одному наблюдению")
        await memory.learn(.foldsCase, service: "s", host: "h")
        #expect(await memory.behaviour(service: "s", host: "h") == .foldsCase)
    }

    @Test("обратный вывод делается сразу — он ничего не выключает")
    func theOppositeConclusionIsImmediate() async {
        // «Сравнивает байты» значит «спрашиваем дальше». Ошибка стоит одного
        // лишнего запроса, поэтому доказывать её дважды незачем — пороги здесь
        // несимметричны нарочно.
        let memory = ConnectorCaseMemory()
        await memory.learn(.comparesBytes, service: "s", host: "h")
        #expect(await memory.behaviour(service: "s", host: "h") == .comparesBytes)
    }

    @Test("одно наблюдение обратного стирает накопленное")
    func oneOppositeObservationResetsTheCount() async {
        let memory = ConnectorCaseMemory()
        await memory.learn(.foldsCase, service: "s", host: "h")
        await memory.learn(.comparesBytes, service: "s", host: "h")
        await memory.learn(.foldsCase, service: "s", host: "h")
        #expect(await memory.behaviour(service: "s", host: "h") == .comparesBytes,
                "накопленное не стёрлось: сервис выключил второй вопрос по старому счёту")
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func bump() { lock.lock(); n += 1; lock.unlock() }
    }
}
