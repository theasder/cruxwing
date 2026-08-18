import Foundation
import Testing
@testable import OrakulCore

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
                     ordinary: [String] = ["агент", "модель"]) throws -> LexiconPack {
        let json = try JSONSerialization.data(withJSONObject: [
            "id": "проба", "title": "Проба",
            "acronyms": acronyms, "loanwords": loanwords, "ordinary": ordinary,
        ])
        return try JSONDecoder().decode(LexiconPack.self, from: json)
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
}
