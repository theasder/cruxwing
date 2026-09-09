import Foundation
import Testing
@testable import MeetGPT
import OrakulCore

/// Подключённый трекер должен попадать в подсказку.
///
/// Без этого настройки сохраняют токен, кнопка показывает «подключено», и
/// ничего не происходит — то же самое, что кнопка «Подключить», ведущая в
/// никуда, только заметить труднее.
@MainActor
@Suite("Трекеры в подсказке", .serialized)
struct RussianTrackerGroundingTests {

    /// Один ответ на любой запрос: тест про маршрут, а не про разбор JSON —
    /// его проверяет RussianTrackersTests.
    private func manager(seeding services: [RussianTrackers.Service],
                         answer: String = #"[{"id": 314, "title": "Лимиты на выгрузку"}]"#,
                         memory: ConnectorCaseMemory = ConnectorCaseMemory())
        -> (MCPConnectionManager, () -> Int) {
        let keychain = InMemoryKeychain()
        let store = RussianTrackerStore(store: keychain)
        for service in services {
            store.setToken("k-token", for: service)
            if service.needsSecondary {
                store.setSecondary(service == .kaiten ? "team.kaiten.ru" : "1234567", for: service)
            }
        }
        let calls = Counter()
        let http: RussianTrackers.HTTP = { request in
            calls.bump()
            return (Data(answer.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!)
        }
        // Своя память и свой кэш на каждый вызов помощника.
        //
        // Раньше набор звал `ConnectorCaseMemory.shared.forget()`, чтобы начать
        // с чистого листа. Начинал — и стирал знание наборов, идущих рядом:
        // именно это описано в AutoOrchestratorFailoverTests как «глобальное
        // состояние, которое соседние наборы меняют параллельно». Своя память
        // даёт ту же чистоту, ничего не ломая у соседей.
        return (MCPConnectionManager(tokenStore: keychain,
                                     notificationCenter: NotificationCenter(),
                                     trackerHTTP: http,
                                     connectorCache: ConnectorCache(),
                                     connectorCaseMemory: memory),
                { calls.value })
    }

    @Test("настроенный трекер отвечает в подсказку")
    func configuredTrackerGrounds() async {
        let (manager, calls) = self.manager(seeding: [.kaiten])
        let snippets = await manager.groundingSnippets(goal: "лимиты на выгрузку")

        let tracker = snippets.first { $0.sourceID == "tracker:kaiten" }
        #expect(tracker != nil, "подключённый Kaiten молчит")
        #expect(tracker?.text.contains("Лимиты на выгрузку") == true)
        #expect(tracker?.serverName == "Kaiten")
        // Три обращения, как у WEEEK: Kaiten описан манифестом с 2026-08-21, а
        // движок спрашивает вторым написанием (узнаёт про регистр) и основой
        // слова. Соседняя проверка объясняла единицу словами «манифеста у него
        // нет» — причина, прожившая ровно до дня, когда манифест появился.
        #expect(calls() == 3)
    }

    @Test("WEEEK участвует в подсказке как обычный трекер")
    func weeekGrounds() async {
        let answer = #"{"success":true,"tasks":[{"id":19,"title":"Лимиты WEEEK"}],"hasMore":false}"#
        let (manager, calls) = self.manager(seeding: [.weeek], answer: answer)
        let snippets = await manager.groundingSnippets(goal: "лимиты")

        let tracker = snippets.first { $0.sourceID == "tracker:weeek" }
        #expect(tracker?.serverName == "WEEEK")
        #expect(tracker?.text.contains("Лимиты WEEEK") == true)
        // Три обращения, а не одно: WEEEK описан манифестом. Второе — тем же
        // словом с заглавной: так узнаётся, сравнивает ли сервис байты. Третье
        // — основой слова («лимит»), и оно уходит потому, что второе новых
        // строк не принесло, а в ответе есть место. Kaiten выше отвечает так
        // же и по той же причине: манифест у него с 2026-08-21.
        #expect(calls() == 3)
    }

    @Test("ненастроенный трекер не занимает место среди источников")
    func unconfiguredTrackerStaysOut() async {
        // Пустой список источников — не то же, что источник, который молчит:
        // второй тратит бюджет ожидания и вытесняет тот, который ответил бы.
        let (manager, calls) = self.manager(seeding: [])
        let snippets = await manager.groundingSnippets(goal: "лимиты на выгрузку")

        #expect(!snippets.contains { $0.sourceID?.hasPrefix("tracker:") == true })
        #expect(calls() == 0, "запрос ушёл без токена")
    }

    @Test("токен без организации не делает Яндекс Трекер источником")
    func yandexNeedsOrganisationToGround() async {
        let keychain = InMemoryKeychain()
        RussianTrackerStore(store: keychain).setToken("y0_synthetic", for: .yandexTracker)
        let calls = Counter()
        let manager = MCPConnectionManager(
            tokenStore: keychain, notificationCenter: NotificationCenter(),
            trackerHTTP: { request in
                calls.bump()
                return (Data("[]".utf8),
                        HTTPURLResponse(url: request.url!, statusCode: 200,
                                        httpVersion: nil, headerFields: nil)!)
            })

        let snippets = await manager.groundingSnippets(goal: "сроки по задаче")
        #expect(!snippets.contains { $0.sourceID == "tracker:yandexTracker" })
        #expect(calls.value == 0, "ушёл запрос, который вернул бы 403")
    }

    @Test("пустая выдача трекера не превращается в пустой источник")
    func emptyResultIsNoSource() async {
        // Источник со строкой из нуля задач стоит места в подсказке и ничего
        // не сообщает.
        let (manager, _) = self.manager(seeding: [.yougile], answer: "[]")
        let snippets = await manager.groundingSnippets(goal: "лимиты")
        #expect(!snippets.contains { $0.sourceID == "tracker:yougile" })
    }

    @Test("сломанный трекер не роняет остальную подсказку")
    func failureIsSurvivable() async {
        // 401 у одного коннектора не должен стоить пользователю ответа: он
        // узнает о просроченном токене в настройках, а не посреди звонка.
        let keychain = InMemoryKeychain()
        RussianTrackerStore(store: keychain).setToken("k-token", for: .kaiten)
        let manager = MCPConnectionManager(
            tokenStore: keychain, notificationCenter: NotificationCenter(),
            trackerHTTP: { request in
                (Data("{}".utf8),
                 HTTPURLResponse(url: request.url!, statusCode: 401,
                                 httpVersion: nil, headerFields: nil)!)
            })

        let snippets = await manager.groundingSnippets(goal: "лимиты")
        #expect(!snippets.contains { $0.sourceID == "tracker:kaiten" })
    }

    @Test("трекеру уходит подсказка про задачи, а не голая цель")
    func queryCarriesTheTrackerHint() {
        // Голая цель («что мы решили по срокам») ищется в трекере плохо: его
        // ранжирование опирается на слова из задач.
        let query = ConnectorProbeStrategy.query(goal: "сроки", serverID: "kaiten")
        #expect(query.contains("сроки"))
        #expect(query.contains("open issues"))
        #expect(ConnectorProbeStrategy.probe(forTracker: "kaiten") != nil)
        #expect(ConnectorProbeStrategy.probe(forTracker: "notion") == nil,
                "не трекер, а MCP-сервер со своей подсказкой")
    }

    @Test("хранилище слушает переданную ему память, а не общую")
    func storeObeysTheInjectedMemory() async {
        // Положительный контроль, а не отрицательный. Первая редакция портила
        // ОБЩУЮ память и требовала, чтобы здесь ничего не изменилось, — и
        // проходила при любом коде: подделка ложилась не под тот ключ, и
        // проверка молча ничего не проверяла. Здесь наоборот: память передаётся
        // внутрь, и если хранилище её слушает, число обращений ОБЯЗАНО
        // измениться. Слушает общую — подделка не подействует, и проверка
        // упадёт.
        let memory = ConnectorCaseMemory()
        let answer = #"{"success":true,"tasks":[{"id":19,"title":"Лимиты WEEEK"}],"hasMore":false}"#
        let (plain, plainCalls) = self.manager(seeding: [.weeek], answer: answer, memory: memory)
        _ = await plain.groundingSnippets(goal: "лимиты")
        let withoutKnowledge = plainCalls()

        // Учим ДВАЖДЫ на каждый ключ: вывод «сервис приводит регистр сам»
        // выключает второй вопрос, а он у некоторых сервисов половина ответа
        // (измерено на живом Synapse 2026-08-20), поэтому одного наблюдения
        // для него мало. Здесь нужна память, которая уже знает, — значит её
        // надо научить по-настоящему, а не поставить флаг.
        let taught = ConnectorCaseMemory()
        for _ in 0..<2 {
            await taught.learn(.foldsCase, service: "weeek", host: nil)
            for host in ["https://api.weeek.net/public/v1", "api.weeek.net"] {
                await taught.learn(.foldsCase, service: "weeek", host: host)
            }
        }
        let (second, secondCalls) = self.manager(seeding: [.weeek], answer: answer, memory: taught)
        _ = await second.groundingSnippets(goal: "лимиты")

        #expect(secondCalls() < withoutKnowledge,
                "переданная память не спрашивается: было \(withoutKnowledge), стало \(secondCalls())")
    }
}

/// Считает вызовы: замыкание `Sendable`, поэтому счётчик под замком.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func bump() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }

}
