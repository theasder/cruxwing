import Foundation

/// Словарь, описанный данными: термины лежат в JSON, а не в коде на Swift.
///
/// Причина ровно та же, по которой данными описаны коннекторы: правит словарь
/// не тот, кто собирает macOS-проект, а тот, у кого на звонках слышится «промт»
/// вместо «промпт». CONTRIBUTING называет пополнение словаря вторым по скорости
/// способом попасть в проект — и до сих пор он требовал редактировать Swift.
///
/// **Кураторство остаётся и становится исполняемым.** Слово входит в словарь
/// только если его нормализованная форма не совпадает с обычным русским словом:
/// «агент» — это страховой агент, и починка сломала бы нормальную фразу. Раньше
/// это было правило в комментарии плюс шесть слов в тесте; теперь список едет в
/// самом пакете и проверяется при загрузке.
public struct LexiconPack: Decodable, Equatable, Sendable {

    public let id: String
    public let title: String
    public let note: String?
    /// Пишутся латиницей заглавными: чинится только регистр.
    public let acronyms: [String]
    /// Пишутся кириллицей: канон русской расшифровки.
    public let loanwords: [String]
    /// Слова языка, которым в словаре не место. Пополняется вместе с попытками
    /// их добавить — список отказов ценнее списка правил.
    public let ordinary: [String]

    public enum PackError: Error, Equatable, CustomStringConvertible {
        case collidesWithOrdinaryWord(pack: String, word: String)
        case duplicate(pack: String, word: String)
        case wrongAlphabet(pack: String, word: String)

        public var description: String {
            switch self {
            case .collidesWithOrdinaryWord(let pack, let word):
                return "«\(word)» из пакета «\(pack)» — обычное русское слово. Починка превратила бы нормальную фразу в жаргон: страховой агент стал бы термином. Такое слово в словарь не берут."
            case .duplicate(let pack, let word):
                return "«\(word)» в пакете «\(pack)» указано дважды. Два канона у одного слова означают, что починка зависит от порядка обхода."
            case .wrongAlphabet(let pack, let word):
                return "«\(word)» из пакета «\(pack)» записано не тем алфавитом: аббревиатуры пишутся латиницей, заимствования — кириллицей. Иначе словарь чинит слово в сторону, обратную канону."
            }
        }
    }

    /// Проверяет то, без чего словарь портит речь.
    ///
    /// Все три правила — про испорченный текст, а не про формат файла: слово
    /// языка ломает обычную фразу, дубль делает починку зависящей от порядка
    /// обхода, не тот алфавит чинит слово в обратную сторону.
    public func validate() throws {
        let ordinarySet = Set(ordinary.map { Self.key($0) })
        var seen = Set<String>()
        for word in acronyms + loanwords {
            let key = Self.key(word)
            if ordinarySet.contains(key) {
                throw PackError.collidesWithOrdinaryWord(pack: id, word: word)
            }
            if !seen.insert(key).inserted {
                throw PackError.duplicate(pack: id, word: word)
            }
        }
        for word in acronyms where word.contains(where: { $0.isCyrillicLetter }) {
            throw PackError.wrongAlphabet(pack: id, word: word)
        }
        for word in loanwords where word.contains(where: { $0.isASCII && $0.isLetter }) {
            throw PackError.wrongAlphabet(pack: id, word: word)
        }
    }

    /// «ё» и «е» — одно слово, регистр не важен: так же, как в самом словаре.
    static func key(_ word: String) -> String {
        word.lowercased().replacingOccurrences(of: "ё", with: "е")
    }

    /// Все пакеты из ресурсов, разобранные и проверенные.
    ///
    /// Каталог перечисляется руками по той же причине, что у коннекторов:
    /// `Bundle.urls(forResourcesWithExtension:)` отдаёт `[URL]` на Apple и
    /// `[NSURL]` в swift-corelibs-foundation.
    public static func bundled(in bundle: Bundle? = nil) throws -> [LexiconPack] {
        let bundle = bundle ?? .module
        guard let root = bundle.resourceURL?.appendingPathComponent("lexicon") else { return [] }
        let urls = ((try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.absoluteString.hasSuffix(".json") }
        let decoder = JSONDecoder()
        var packs: [LexiconPack] = []
        for url in urls.sorted(by: { $0.absoluteString < $1.absoluteString }) {
            let pack = try decoder.decode(LexiconPack.self, from: try Data(contentsOf: url))
            try pack.validate()
            packs.append(pack)
        }
        return packs
    }
}

private extension Character {
    var isCyrillicLetter: Bool {
        unicodeScalars.contains { $0.value >= 0x0400 && $0.value <= 0x04FF }
    }
}
