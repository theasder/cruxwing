import Foundation
import Testing
@testable import CruxwingCore

/// Словарь из данных обязан совпадать со словарём из кода — слово в слово.
///
/// Пакет собран из таблиц `RussianLexicon`, и пока продукт читает таблицы, эта
/// сверка и есть единственное доказательство, что пакет не разошёлся с тем, что
/// работает. Та же дисциплина, что у коннекторов: описание данными стоит ровно
/// столько, сколько ему можно доверить из уже работающего.
@Suite("Пакет словаря")
struct LexiconPackTests {

    static func base() throws -> LexiconPack {
        let packs = try LexiconPack.bundled()
        return try #require(packs.first { $0.id == "base" }, "базового пакета нет среди ресурсов")
    }

    @Test("пакет слово в слово совпадает с таблицами в коде")
    func packMatchesCode() throws {
        let pack = try Self.base()
        #expect(pack.acronyms == RussianLexicon.acronyms,
                "аббревиатуры разошлись: пакет \(pack.acronyms.count), код \(RussianLexicon.acronyms.count)")
        #expect(pack.loanwords == RussianLexicon.loanwords,
                "заимствования разошлись: пакет \(pack.loanwords.count), код \(RussianLexicon.loanwords.count)")
        // Две таблицы замен — тем же способом. Пакет не заменяет код, пока
        // продукт читает Swift: он держит ту же правду в виде, который правит
        // тот, у кого на звонках слышится «промт», а не тот, кто собирает
        // macOS-проект. Расхождение здесь означает, что правку внесли в одно
        // место из двух — и словарь тихо стал другим.
        #expect(pack.variants == RussianLexicon.variants,
                "таблица замен разошлась: пакет \(pack.variants?.count ?? 0), код \(RussianLexicon.variants.count)")
        #expect(pack.infrastructure == RussianLexicon.infrastructure,
                "имена инструментов разошлись: пакет \(pack.infrastructure?.count ?? 0), код \(RussianLexicon.infrastructure.count)")
    }

    @Test("таблица замен не берёт обычных слов, а таблица инструментов — берёт")
    func curationDiffersBetweenTheTwoMaps() throws {
        let pack = try Self.base()
        let ordinary = Set(pack.ordinary.map { LexiconPack.key($0) })
        // По `variants` текст ПЕРЕПИСЫВАЕТСЯ: обычное слово там испортит фразу.
        for spoken in (pack.variants ?? [:]).keys {
            #expect(!ordinary.contains(LexiconPack.key(spoken)),
                    "«\(spoken)» — обычное слово, а по нему переписывают расшифровку")
        }
        // А `infrastructure` действует только на поиск, и обычные слова там
        // намеренно есть: «редис» останется овощем в тексте и найдётся по
        // запросу redis. Если этого больше нет — таблицу выхолостили.
        let names = Set((pack.infrastructure ?? [:]).keys.map { LexiconPack.key($0) })
        #expect(!names.isDisjoint(with: ["редис", "кафка", "прометей", "кролик", "откат"]),
                "из таблицы инструментов пропали имена, совпадающие с обычными словами — ради них она и заведена")
    }

    @Test("каждый пакет из ресурсов проходит кураторские правила")
    func bundledPacksAreValid() throws {
        let packs = try LexiconPack.bundled()
        #expect(!packs.isEmpty, "пакетов не нашлось — проверка была бы пустой")
        for pack in packs {
            #expect(throws: Never.self) { try pack.validate() }
        }
    }

    static func pack(acronyms: [String] = [], loanwords: [String] = [],
                     ordinary: [String] = ["агент", "модель"],
                     variants: [String: String] = [:],
                     infrastructure: [String: String] = [:]) throws -> LexiconPack {
        let json = try JSONSerialization.data(withJSONObject: [
            "id": "проба", "title": "Проба",
            "acronyms": acronyms, "loanwords": loanwords, "ordinary": ordinary,
            "variants": variants, "infrastructure": infrastructure,
        ])
        return try JSONDecoder().decode(LexiconPack.self, from: json)
    }

    @Test("обычное слово слева в таблице замен не принимается")
    func ordinaryWordInVariantsIsRejected() throws {
        // По этой таблице расшифровку ПЕРЕПИСЫВАЮТ, поэтому правило то же, что
        // и для списков, — только смотреть надо на левую часть: на то, что
        // человек сказал. Без этой проверки «агент» → «agent» переписал бы
        // страхового агента в термин.
        let pack = try Self.pack(variants: ["агент": "agent"])
        #expect(throws: LexiconPack.PackError.collidesWithOrdinaryWord(pack: "проба", word: "агент")) {
            try pack.validate()
        }
    }

    @Test("обычное слово в таблице инструментов принимается")
    func ordinaryWordInInfrastructureIsAllowed() throws {
        // Разница между двумя таблицами. Эта действует только на поиск: цена
        // ошибки — лишняя находка про овощ, а не испорченный архив. Запретить
        // здесь обычные слова значило бы выбросить «редис», «кафку» и
        // «прометея» — то есть ровно то, ради чего таблица заведена.
        let pack = try Self.pack(ordinary: ["редис"], infrastructure: ["редис": "redis"])
        #expect(throws: Never.self) { try pack.validate() }
    }

    @Test("обычное русское слово в словарь не принимается")
    func ordinaryWordIsRejected() throws {
        // Это и есть кураторство: «агент» — страховой агент, и починка
        // превратила бы обычную фразу в жаргон. Раньше правило жило в
        // комментарии и в шести словах внутри теста; теперь его исполняет код.
        let pack = try Self.pack(loanwords: ["агент"])
        #expect(throws: LexiconPack.PackError.collidesWithOrdinaryWord(pack: "проба", word: "агент")) {
            try pack.validate()
        }
    }

    @Test("«ё» не спасает слово от проверки")
    func yoDoesNotBypassTheRule() throws {
        // Иначе одно и то же слово — разное для проверки и одно для починки, и
        // запрещённое входит через написание с «ё».
        let pack = try Self.pack(loanwords: ["чёрный"], ordinary: ["черный"])
        #expect(throws: LexiconPack.PackError.self) { try pack.validate() }
    }

    @Test("дубль внутри пакета — ошибка, а не мелочь")
    func duplicateIsRejected() throws {
        // Два канона у одного слова означают, что результат починки зависит от
        // порядка обхода: сегодня так, завтра иначе.
        let pack = try Self.pack(loanwords: ["прод", "Прод"])
        #expect(throws: LexiconPack.PackError.duplicate(pack: "проба", word: "Прод")) {
            try pack.validate()
        }
    }

    @Test("аббревиатура кириллицей и заимствование латиницей не проходят")
    func alphabetIsChecked() throws {
        // Канон у каждой половины свой: аббревиатуры латиницей, заимствования
        // кириллицей. Перепутанный алфавит чинит слово в обратную сторону —
        // ровно то расхождение движков, ради которого словарь и написан.
        #expect(throws: LexiconPack.PackError.wrongAlphabet(pack: "проба", word: "АПИ")) {
            try Self.pack(acronyms: ["АПИ"]).validate()
        }
        #expect(throws: LexiconPack.PackError.wrongAlphabet(pack: "проба", word: "prod")) {
            try Self.pack(loanwords: ["prod"]).validate()
        }
    }

    // MARK: - Правила между пакетами (доменные пакеты, §9)

    @Test("два пакета не могут чинить одно слово по-разному")
    func conflictingCanonsAreRefused() throws {
        // Иначе побеждает тот, чьё имя файла раньше по алфавиту. Это тот же
        // дубль, что внутри пакета, только увидеть его труднее: каждый пакет
        // сам по себе безупречен.
        let first = try Self.pack(variants: ["прод": "прод"])
        let second = try LexiconPack(pack: "мобильный", variants: ["прод": "production"])
        #expect(throws: LexiconPack.PackError.self) {
            try LexiconPack.validate([first, second])
        }
    }

    @Test("одинаковая починка в двух пакетах — не поломка")
    func sameCanonInTwoPacksIsFine() throws {
        // Повтор безвреден: результат один и тот же при любом порядке чтения.
        // Запретить его значило бы требовать от доменного пакета знать
        // содержимое базового наизусть.
        let first = try Self.pack(variants: ["апи": "API"])
        let second = try LexiconPack(pack: "мобильный", variants: ["апи": "API"])
        #expect(throws: Never.self) { try LexiconPack.validate([first, second]) }
    }

    @Test("пакет не чинит слово, которое другой считает обычным")
    func termCannotBeOrdinaryElsewhere() throws {
        // Списки отказов — накопленный опыт: «агент» это страховой агент.
        // Доменный пакет не должен отменять его молча.
        let base = try Self.pack(ordinary: ["агент"])
        let domain = try LexiconPack(pack: "продуктовый", loanwords: ["агент"])
        #expect(throws: LexiconPack.PackError.self) {
            try LexiconPack.validate([base, domain])
        }
    }

    @Test("имена инструментов из чужого списка обычных слов не запрещены")
    func infrastructureIsNotBoundByOrdinaryLists() throws {
        // Разница между таблицами держится и между пакетами: имена работают
        // только на поиск, и «редис» обязан оставаться овощем в тексте.
        let base = try Self.pack(ordinary: ["редис"])
        let domain = try LexiconPack(pack: "инфраструктурный", infrastructure: ["редис": "redis"])
        #expect(throws: Never.self) { try LexiconPack.validate([base, domain]) }
    }

    @Test("загрузка сама проверяет пакеты между собой, а не надеется на вызов")
    func loaderAppliesCrossPackRules() throws {
        // Без этого правило есть, но его никто не применяет: продукт зовёт
        // `bundled()`, а не `validate(_:)`. Мутация «убрать вызов из загрузки»
        // проходила именно поэтому — единственная проверка звала обе функции
        // руками.
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cruxwing-lexicon-\(UUID().uuidString)")
        let lexicon = folder.appendingPathComponent("lexicon")
        try FileManager.default.createDirectory(at: lexicon, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        func write(_ name: String, _ object: [String: Any]) throws {
            let data = try JSONSerialization.data(withJSONObject: object)
            try data.write(to: lexicon.appendingPathComponent(name))
        }
        // Два пакета, каждый безупречен сам по себе, и разный канон одного слова.
        try write("a-base.json", ["id": "база", "title": "База", "acronyms": [], "loanwords": [],
                                  "ordinary": [], "variants": ["прод": "прод"]])
        try write("b-mobile.json", ["id": "мобильный", "title": "Мобильный", "acronyms": [],
                                    "loanwords": [], "ordinary": [],
                                    "variants": ["прод": "production"]])

        let bundle = try #require(Bundle(url: folder), "не удалось собрать поддельный набор ресурсов")
        #expect(throws: LexiconPack.PackError.self) {
            _ = try LexiconPack.bundled(in: bundle)
        }
    }

    @Test("пакеты в ресурсах проходят и правила между собой")
    func bundledPacksAgreeWithEachOther() throws {
        // Сегодня пакет один, и проверка почти пустая — но она стоит здесь до
        // первого доменного пакета намеренно: правило, написанное после того,
        // как его нарушили, обсуждают, а не соблюдают.
        #expect(throws: Never.self) { try LexiconPack.validate(try LexiconPack.bundled()) }
    }
}

private extension LexiconPack {
    /// Пакет с произвольным именем — для проверок между пакетами.
    init(pack id: String, acronyms: [String] = [], loanwords: [String] = [],
         ordinary: [String] = [], variants: [String: String] = [:],
         infrastructure: [String: String] = [:]) throws {
        let json = try JSONSerialization.data(withJSONObject: [
            "id": id, "title": id,
            "acronyms": acronyms, "loanwords": loanwords, "ordinary": ordinary,
            "variants": variants, "infrastructure": infrastructure,
        ])
        self = try JSONDecoder().decode(LexiconPack.self, from: json)
    }
}
