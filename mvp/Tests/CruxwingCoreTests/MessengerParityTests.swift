import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CruxwingCore

/// Манифест мессенджера читает то же, что читала рука.
///
/// Сверка нужна ровно потому, что продакшн уже ходит через манифест: сравнивать
/// «манифест с продакшеном» после перехода значит сравнивать манифест с самим
/// собой, и такая проверка проходит на любой порче. Поэтому зовётся
/// `legacySearch` — вторая, действительно другая реализация.
@Suite struct MessengerParityTests {

    static let host = "chat.company.ru"

    static func both(_ service: WorkMessengers.Service, json: String,
                     scope: String? = "team-1") async throws
        -> (manifest: [WorkMessengers.Hit], legacy: [WorkMessengers.Hit]) {
        let data = Data(json.utf8)
        let http: WorkMessengers.HTTP = { request in
            (data, HTTPURLResponse(url: request.url!, statusCode: 200,
                                   httpVersion: nil, headerFields: [:])!)
        }
        let client = WorkMessengers(service: service, token: "me@company.ru:key",
                                    secondary: host, scope: scope, http: http)
        let resolved = service.host(secondary: host) ?? host
        return (try await client.search("тарифы"),
                try await client.legacySearch("тарифы", host: resolved))
    }

    @Test("Пачка: манифест и рука читают одно и то же")
    func pachkaParity() async throws {
        let json = #"{"data":[{"content":"Тарифы с декабря","user_id":42}]}"#
        let (manifest, legacy) = try await Self.both(.pachca, json: json, scope: nil)
        #expect(manifest.map(\.text) == legacy.map(\.text))
        #expect(manifest.map(\.author) == legacy.map(\.author))
    }

    @Test("Mattermost: манифест и рука читают одно и то же, включая порядок")
    func mattermostParity() async throws {
        let json = #"""
        {"order":["p2","p1"],
         "posts":{"p1":{"message":"Тарифы позже","user_id":"u1"},
                  "p2":{"message":"Тарифы сначала","user_id":"u2"}}}
        """#
        let (manifest, legacy) = try await Self.both(.mattermost, json: json)
        #expect(manifest.map(\.text) == legacy.map(\.text))
        #expect(manifest.map(\.text) == ["Тарифы сначала", "Тарифы позже"],
                "порядок сервиса потерян хотя бы одной из реализаций")
        #expect(manifest.map(\.author) == legacy.map(\.author))
    }

    @Test("Zulip: расхождение по разметке — оно намеренное")
    func zulipDivergesOnMarkup() async throws {
        // Zulip отдаёт `content` уже размеченным HTML. Рукописная ветка клала
        // его в подсказку как есть, то есть человеку на звонке ехало
        // «<p>Тарифы <strong>с декабря</strong></p>». Манифест снимает разметку.
        //
        // Это расхождение, которое стоит оставить, а не скопировать, — и оно
        // записано здесь вслух, чтобы осталось решением, а не находкой
        // следующего.
        let json = #"{"messages":[{"content":"<p>Тарифы <strong>с декабря</strong></p>","sender_full_name":"Полина"}],"result":"success"}"#
        let (manifest, legacy) = try await Self.both(.zulip, json: json, scope: nil)
        #expect(manifest.map(\.author) == legacy.map(\.author))
        #expect(manifest.first?.text == "Тарифы с декабря")
        #expect(legacy.first?.text == "<p>Тарифы <strong>с декабря</strong></p>")
        #expect(manifest.first?.text != legacy.first?.text)
    }

    @Test("Matrix: манифест и рука читают одну и ту же вложенность")
    func matrixParity() async throws {
        // Вложенность здесь родная для сервиса: он умеет искать в нескольких
        // категориях сразу. Манифест ходит по тому же пути путями полей, а не
        // разбором руками.
        let json = #"""
        {"search_categories":{"room_events":{"results":[
          {"result":{"content":{"body":"Тарифы с декабря"},"sender":"@anya:company.ru"}},
          {"result":{"content":{"body":"Лимиты позже"},"sender":"@boris:company.ru"}}
        ]}}}
        """#
        let (manifest, legacy) = try await Self.both(.matrix, json: json, scope: nil)
        #expect(manifest.map(\.text) == legacy.map(\.text))
        #expect(manifest.map(\.author) == legacy.map(\.author))
        #expect(manifest.first?.text == "Тарифы с декабря")
        #expect(manifest.first?.author == "@anya:company.ru")
    }

    @Test("Rocket.Chat: ключ режется на две половины и уезжает в два заголовка")
    func rocketChatSplitsTheCredential() async throws {
        // Единственный, кому нужны ДВА значения. Человек вписывает их одной
        // строкой через двоеточие — четвёртое поле в настройках осталось бы
        // пустым, потому что пару выдают вместе.
        let json = #"{"messages":[{"msg":"Тарифы с декабря","u":{"username":"anya"}}],"success":true}"#
        let recorder = Recorder()
        let http: WorkMessengers.HTTP = { request in
            recorder.record(request)
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
                                                     httpVersion: nil, headerFields: [:])!)
        }
        let client = WorkMessengers(service: .rocketChat, token: "tok-abc:user-42",
                                    secondary: Self.host, scope: "GENERAL", http: http)
        let manifest = try await client.search("тарифы")
        let legacy = try await client.legacySearch(
            "тарифы", host: WorkMessengers.Service.rocketChat.host(secondary: Self.host) ?? Self.host)

        #expect(manifest.map(\.text) == legacy.map(\.text))
        #expect(manifest.map(\.author) == legacy.map(\.author))
        #expect(manifest.first?.author == "anya", "автор лежит на этаж глубже, в u.username")

        let first = try #require(recorder.first)
        #expect(first.value(forHTTPHeaderField: "X-Auth-Token") == "tok-abc")
        #expect(first.value(forHTTPHeaderField: "X-User-Id") == "user-42")
        // Комната обязательна по документации вендора: поиск идёт внутри неё.
        let items = URLComponents(url: first.url!, resolvingAgainstBaseURL: false)?.queryItems
        #expect(items?.contains { $0.name == "roomId" && $0.value == "GENERAL" } == true)
        #expect(items?.contains { $0.name == "searchText" && $0.value == "тарифы" } == true)
    }

    @Test("ключ без двоеточия не даёт чужому заголовку чужое значение")
    func halfOfACredentialWithoutASeparator() {
        // Человек вписал один токен вместо пары: голова — весь ключ, хвост
        // пуст. Отдать хвосту тот же ключ значило бы послать сервису
        // идентификатор пользователя, которым он не является.
        #expect(ManifestConnector.half(of: "tok-abc", .head) == "tok-abc")
        #expect(ManifestConnector.half(of: "tok-abc", .tail) == "")
        // Двоеточие ПЕРВОЕ: у пароля приложения оно может быть внутри.
        #expect(ManifestConnector.half(of: "id:pa:ss", .head) == "id")
        #expect(ManifestConnector.half(of: "id:pa:ss", .tail) == "pa:ss")
    }
}
