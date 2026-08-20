import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OrakulCore

/// Второй запрос тем же словом с другой буквы.
///
/// Измерено на живых установках: Redmine и Nextcloud с базой по умолчанию
/// (SQLite) сравнивают строки побайтово выше ASCII, и «тарифы» не находит
/// «Тарифы». Расшифровка отдаёт слова строчными — так говорят, — поэтому на
/// маленькой самостоятельной установке половина ответов пропадала молча, и
/// выглядело это не как чужая база, а как продукт, который не находит.
@Suite("Повтор с другим регистром")
struct CaseRetryTests {

    /// Сервис, отвечающий как SQLite: совпадение только при точном регистре.
    static func caseSensitive(_ титул: String, seen: SeenQueries) -> ManifestConnector.HTTP {
        { request in
            let url = request.url!.absoluteString
            let asked = URLComponents(string: url)?.queryItems?
                .first { $0.name == "q" || $0.name == "search" || $0.name == "query" }?.value ?? ""
            await seen.add(asked)
            let hit = титул.contains(asked) && !asked.isEmpty
            let json = hit
                ? #"{"data":[{"id":1,"name":"\#(титул)","preview_html":{"name":"\#(титул)","content":"..."}}],"total":1}"#
                : #"{"data":[],"total":0}"#
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
                                                     httpVersion: nil, headerFields: [:])!)
        }
    }

    /// Сервис, у которого разные написания дают РАЗНЫЕ записи.
    static func caseSensitiveTwo(lower: String, upper: String,
                                 seen: SeenQueries) -> ManifestConnector.HTTP {
        { request in
            let asked = URLComponents(string: request.url!.absoluteString)?.queryItems?
                .first { $0.name == "query" || $0.name == "q" || $0.name == "search" }?.value ?? ""
            await seen.add(asked)
            let capital = asked.first?.isUppercase == true
            let title = capital ? upper : lower
            let hit = title.contains(asked) && !asked.isEmpty
            let json = hit
                ? #"{"data":[{"id":\#(capital ? 2 : 1),"name":"\#(title)","preview_html":{"name":"\#(title)","content":"..."}}],"total":1}"#
                : #"{"data":[],"total":0}"#
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
                                                     httpVersion: nil, headerFields: [:])!)
        }
    }

    /// Сервис, приводящий регистр сам: оба написания дают одно и то же.
    static func foldsCase(_ title: String, seen: SeenQueries) -> ManifestConnector.HTTP {
        { request in
            let asked = URLComponents(string: request.url!.absoluteString)?.queryItems?
                .first { $0.name == "query" || $0.name == "q" || $0.name == "search" }?.value ?? ""
            await seen.add(asked)
            let hit = title.lowercased().contains(asked.lowercased()) && !asked.isEmpty
            let json = hit
                ? #"{"data":[{"id":1,"name":"\#(title)","preview_html":{"name":"\#(title)","content":"..."}}],"total":1}"#
                : #"{"data":[],"total":0}"#
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
                                                     httpVersion: nil, headerFields: [:])!)
        }
    }

    actor SeenQueries {
        private(set) var all: [String] = []
        func add(_ q: String) { all.append(q) }
    }

    static func connector(_ http: @escaping ManifestConnector.HTTP) throws -> ManifestConnector {
        let manifest = try #require(try ConnectorManifest.bundled().first { $0.id == "bookstack" })
        return ManifestConnector(manifest: manifest, token: "id:секрет",
                                 host: "https://wiki.company.ru", http: http)
    }

    @Test("строчное слово находит запись с заглавной")
    func lowercaseFindsCapitalised() async throws {
        let seen = SeenQueries()
        let connector = try Self.connector(Self.caseSensitive("Тарифы и лимиты", seen: seen))
        let outcome = try await connector.run("тарифы")
        #expect(outcome.items.first?.title == "Тарифы и лимиты")
        let asked = await seen.all
        // «тариф» третьим: вопрос основой идёт и тогда, когда второе
        // написание что-то нашло, — раньше здесь стоял возврат, и сервис,
        // сравнивающий байты, основой не спрашивался никогда.
        #expect(asked == ["тарифы", "Тарифы", "тариф"], "второй запрос ушёл не тем словом: \(asked)")
    }

    // Смысл проверки изменился вместе с решением, и это записано, а не
    // подогнано: раньше второй запрос уходил только на пустой выдаче, теперь
    // первый кириллический вопрос к незнакомому сервису задаётся дважды —
    // так и узнаётся, сравнивает ли он байты. Дальше лишних запросов нет, и
    // это проверяют два теста ниже.
    @Test("вопрос на обучение задаётся один раз, а не при каждом поиске")
    func learningQuestionIsAskedOnce() async throws {
        let seen = SeenQueries()
        let memory = ConnectorCaseMemory()
        let http = Self.foldsCase("тарифы и лимиты", seen: seen)
        let manifest = try #require(try ConnectorManifest.bundled().first { $0.id == "bookstack" })
        for _ in 0..<3 {
            _ = try await ManifestConnector(manifest: manifest, token: "id:секрет",
                                            host: "https://wiki.company.ru",
                                            caseMemory: memory, http: http).run("тарифы")
        }
        let asked = await seen.all
        // «тариф» в хвосте каждого поиска — вопрос основой слова: он идёт
        // третьим и только когда второй НОВОГО не принёс. Здесь сервис
        // приводит регистр сам, поэтому вторым написанием приезжает та же
        // строка — прибавки нет, и очередь доходит до основы.
        // Плата берётся ДВА раза, а не один, и это осознанно: вывод «сервис
        // приводит регистр сам» выключает второй вопрос, а он у некоторых
        // сервисов — половина ответа (измерено на живом Synapse 2026-08-20).
        // Одного наблюдения для такого выключения мало.
        #expect(asked == ["тарифы", "Тарифы", "тариф", "тарифы", "Тарифы", "тариф", "тарифы", "тариф"],
                "плата за знание берётся не два раза: \(asked)")
    }

    @Test("латиница второго запроса не заслуживает")
    func latinDoesNotRetry() async throws {
        let seen = SeenQueries()
        let connector = try Self.connector(Self.caseSensitive("Roadmap", seen: seen))
        _ = try await connector.run("roadmap")
        let asked = await seen.all
        #expect(asked == ["roadmap"],
                "у латиницы регистр приводит сама база — второй запрос это плата ни за что")
    }

    @Test("пусто и во второй раз — остаётся пусто, а не выдумывается")
    func stillEmptyStaysEmpty() async throws {
        let connector = try Self.connector(Self.caseSensitive("совсем другое", seen: SeenQueries()))
        #expect(try await connector.run("тарифы").items.isEmpty)
    }

    // Частичная выдача — тот случай, ради которого появилась память: сервис
    // отдаёт одну запись из двух, и «нашлось» ничем не отличается от «нашлось
    // всё». Ждать пустоты бесполезно, у такого сервиса её может не быть.
    @Test("частичная выдача дополняется вторым написанием")
    func partialResultIsCompleted() async throws {
        let seen = SeenQueries()
        let connector = try Self.connector(
            Self.caseSensitiveTwo(lower: "поднять тарифы", upper: "Тарифы и лимиты", seen: seen))
        let outcome = try await connector.run("тарифы")
        let titles = outcome.items.map(\.title).sorted()
        #expect(titles == ["Тарифы и лимиты", "поднять тарифы"],
                "вторая половина ответа осталась невидимой: \(titles)")
    }

    @Test("сервис, приводящий регистр сам, перестаёт спрашиваться со второго звонка")
    func foldingServiceIsAskedTwiceUntilTheSecondCall() async throws {
        // Раньше хватало одного звонка, и этот тест закреплял именно то.
        //
        // Два вывода тут разной цены. «Сравнивает байты» значит «спрашиваем
        // дальше» — ошибка стоит одного лишнего запроса. «Приводит регистр
        // сам» значит «больше не спрашиваем» — ошибка стоит половины ответа
        // молча, и это измерено на живом Synapse 2026-08-20: «тарифы» находит
        // одно сообщение, «Тарифы» — ДРУГОЕ. Отсюда несимметричный порог:
        // выключать по двум наблюдениям, включать обратно по одному.
        let seen = SeenQueries()
        let memory = ConnectorCaseMemory()
        let http = Self.foldsCase("Тарифы и лимиты", seen: seen)
        let manifest = try #require(try ConnectorManifest.bundled().first { $0.id == "bookstack" })
        let make = { ManifestConnector(manifest: manifest, token: "id:секрет",
                                       host: "https://wiki.company.ru",
                                       caseMemory: memory, http: http) }
        _ = try await make().run("тарифы")   // наблюдение 1
        _ = try await make().run("сроки")    // обе выдачи пусты — не наблюдение
        _ = try await make().run("лимиты")   // наблюдение 2, вывод сделан
        _ = try await make().run("тарифы")   // и вот здесь второго вопроса уже нет
        let asked = await seen.all
        #expect(asked == ["тарифы", "Тарифы", "тариф",
                          "сроки", "Сроки", "срок",
                          "лимиты", "Лимиты", "лимит",
                          "тарифы", "тариф"],
                "второе написание либо не выключилось, либо выключилось раньше срока: \(asked)")
        // Звонок, где обе выдачи пусты, наблюдением не считается — из двух
        // пустых по-прежнему не следует ничего, и «сроки» это доказывает: без
        // этого правила вывод пришёлся бы на него.
    }

    @Test("сервис, сравнивающий байты, дальше спрашивается обоими написаниями")
    func byteComparingServiceKeepsBeingAskedTwice() async throws {
        let seen = SeenQueries()
        let memory = ConnectorCaseMemory()
        let http = Self.caseSensitiveTwo(lower: "поднять тарифы", upper: "Тарифы и лимиты", seen: seen)
        let manifest = try #require(try ConnectorManifest.bundled().first { $0.id == "bookstack" })
        let make = { ManifestConnector(manifest: manifest, token: "id:секрет",
                                       host: "https://wiki.company.ru",
                                       caseMemory: memory, http: http) }
        _ = try await make().run("тарифы")
        #expect(await memory.behaviour(service: "bookstack", host: "https://wiki.company.ru")
                == .comparesBytes)
        _ = try await make().run("сроки")
        let asked = await seen.all
        // Про «срок» в конце: у этого сервиса «сроки» и «Сроки» не находят
        // ничего, поэтому третьим уходит основа. А после «тарифы» второе
        // написание принесло новую строку — там ответ вернулся сразу, и
        // основой не спрашивали вовсе.
        #expect(asked == ["тарифы", "Тарифы", "тариф", "сроки", "Сроки", "срок"],
                "у сервиса, сравнивающего байты, второе написание перестали спрашивать: \(asked)")
    }

    @Test("две пустые выдачи ничему не учат")
    func twoEmptiesTeachNothing() async throws {
        let memory = ConnectorCaseMemory()
        let manifest = try #require(try ConnectorManifest.bundled().first { $0.id == "bookstack" })
        let connector = ManifestConnector(manifest: manifest, token: "id:секрет",
                                          host: "https://wiki.company.ru", caseMemory: memory,
                                          http: Self.caseSensitive("совсем другое", seen: SeenQueries()))
        _ = try await connector.run("тарифы")
        #expect(await memory.behaviour(service: "bookstack", host: "https://wiki.company.ru")
                == .unknown, "из двух пустых сделан вывод, которого в них нет")
    }

    @Test("один и тот же ответ в обоих написаниях не показывается дважды")
    func sameAnswerIsNotShownTwice() async throws {
        let connector = try Self.connector(Self.foldsCase("Тарифы и лимиты", seen: SeenQueries()))
        #expect(try await connector.run("тарифы").items.count == 1)
    }

    @Test("вариант слова строится по первой букве", arguments: [
        ("тарифы", "Тарифы"), ("Тарифы", "тарифы"),
        ("сроки по проекту", "Сроки по проекту"),
    ])
    func variantIsBuiltFromFirstLetter(word: String, expected: String) {
        #expect(ManifestConnector.caseVariant(of: word) == expected)
    }

    @Test("у слов без кириллицы варианта нет", arguments: ["roadmap", "SSO", "42", ""])
    func noVariantWithoutCyrillic(word: String) {
        #expect(ManifestConnector.caseVariant(of: word) == nil)
    }
}
