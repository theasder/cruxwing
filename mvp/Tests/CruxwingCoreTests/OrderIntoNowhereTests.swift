import Testing
import Foundation
@testable import CruxwingCore

/// Ответ, где строки лежат словарём, а порядок — отдельным списком.
///
/// Так отвечает Mattermost: `posts` — хранилище по идентификатору, `order` —
/// перечень тех же идентификаторов по убыванию совпадения. Значения словаря в
/// Swift неупорядочены, поэтому читать надо по `order`, иначе первым человеку
/// достанется случайное сообщение.
///
/// Отсюда ход недружелюбного сервиса, которого не видно ничем: перестать
/// заполнять `order`, оставив `posts`. Ошибки нет, код 200, строки на месте — а
/// коннектор отвечает уверенной пустотой, и так навсегда. То же самое даёт
/// смена вида идентификаторов: список ведёт в никуда.
@Suite struct OrderIntoNowhereTests {

    private func mattermost() throws -> ConnectorManifest {
        try #require(ConnectorManifest.usable().first { $0.id == "mattermost" })
    }

    private func connector(answering body: String) throws -> ManifestConnector {
        ManifestConnector(manifest: try mattermost(), token: "t",
                          host: "https://mm.example", values: ["team": "t1"]) { _ in
            (Data(body.utf8), HTTPURLResponse())
        }
    }

    @Test("порядок пуст, а строки есть — это смена формата, а не пустая выдача")
    func anEmptyOrderIsRefused() async throws {
        let body = """
        {"order":[],"posts":{"p1":{"message":"Поднять тарифы с декабря","user_id":"u1"}}}
        """
        await #expect(throws: ManifestConnector.ConnectorError.unreadable) {
            _ = try await self.connector(answering: body).run("тарифы", limit: 10)
        }
    }

    @Test("порядок ведёт в никуда — тоже отказ")
    func aDanglingOrderIsRefused() async throws {
        // Сервису достаточно сменить вид идентификаторов.
        let body = """
        {"order":["x1","x2"],"posts":{"p1":{"message":"Поднять тарифы","user_id":"u1"}}}
        """
        await #expect(throws: ManifestConnector.ConnectorError.unreadable) {
            _ = try await self.connector(answering: body).run("тарифы", limit: 10)
        }
    }

    @Test("часть не разошлась — остальное доезжает")
    func aPartialOrderStillAnswers() async throws {
        // Одна негодная строка среди годных — не повод отказать во всём: это
        // то же правило, что и для обычного списка.
        let body = """
        {"order":["p1","ghost"],"posts":{"p1":{"message":"Поднять тарифы","user_id":"u1"}}}
        """
        let items = try await connector(answering: body).search("тарифы")
        #expect(items.count == 1)
        #expect(items.first?.title == "Поднять тарифы")
    }

    @Test("пустой ответ целиком остаётся пустым ответом")
    func anEmptyAnswerIsStillAnEmptyAnswer() async throws {
        // Сервис вправе ничего не найти, и отказывать здесь — врать в другую
        // сторону. Разница ровно в том, лежат ли строки в хранилище.
        let items = try await connector(answering: "{\"order\":[],\"posts\":{}}").search("тарифы")
        #expect(items.isEmpty)
    }

    @Test("порядок соблюдается, а не берётся из словаря")
    func theOrderIsHonoured() async throws {
        let body = """
        {"order":["p2","p1"],
         "posts":{"p1":{"message":"первое","user_id":"u1"},
                  "p2":{"message":"второе","user_id":"u2"}}}
        """
        let items = try await connector(answering: body).search("тарифы")
        #expect(items.map(\.title) == ["второе", "первое"])
    }
}
