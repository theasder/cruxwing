import Testing
import Foundation
@testable import MeetGPT

/// Что уезжает в чужие сервисы, пока человек просто говорит.
///
/// Фоновая проверка идёт сама, по своему расписанию, и её запрос уходит в
/// КАЖДЫЙ подключённый источник — в трекер, в вики, в мессенджер, а при
/// подключённом конкуренте и туда. Человек в этот момент ничего не спрашивал.
///
/// Соседний путь — запрос, собранный моделью, — этого не разрешает:
/// `looksLikeAQuote` отбрасывает строку, несущую шесть слов подряд из встречи.
/// Фоновый путь строил ровно такую строку по устройству: цель плюс дословный
/// хвост расшифровки. Одно и то же правило расходилось на двух путях, и
/// запрещённую форму собирал тот, за которым не следят.
@Suite struct BackgroundQueryLeakTests {

    /// Живая русская фраза со звонка: длинная, дословная, с числами.
    private let speech = "мы решили поднять тарифы с декабря на пятнадцать "
        + "процентов для клиентов из Германии и Австрии"

    @Test("сказанное вслух не уезжает предложением")
    func theSentenceDoesNotTravel() {
        let query = GroundingContextPolicy.backgroundQuery(
            goal: "Пересмотр тарифов", recentTranscript: speech, maxChars: 180)
        #expect(!PromptWorkflows.looksLikeAQuote(query, of: speech),
                "запрос уносит фразу встречи целиком: \(query)")
        #expect(!query.contains("решили поднять тарифы с декабря"))
    }

    @Test("имена и номера всё равно доезжают")
    func identifiersStillTravel() {
        // Ради них хвост и брали: без номера задачи фоновый поиск ищет вслепую.
        let query = GroundingContextPolicy.backgroundQuery(
            goal: "Resolve the Project Falcon migration blocker",
            recentTranscript: String(repeating: "context ", count: 100)
                + "CRX-42 is still blocked by legal approval",
            maxChars: 180)
        #expect(query.contains("CRX-42"))
        #expect(query.contains("Falcon"))
        #expect(query.count <= 180)
    }

    @Test("служебные слова отсеиваются, содержательные остаются")
    func shortWordsAreDropped() {
        let terms = GroundingContextPolicy.recentTerms(
            in: "мы уже это на них смотрели про тарифы", cap: 100)
        #expect(terms.contains("тарифы"))
        #expect(terms.contains("смотрели"))
        #expect(!terms.contains("мы "))
        #expect(!terms.contains(" на "))
    }

    @Test("короткий номер с цифрой не отсеивается длиной")
    func aShortIdentifierSurvives() {
        // Найдено мутацией: «CRX-42» проходит и без условия про цифру, потому
        // что в нём шесть знаков. А «Q3», «v2» и «42» — по два, и отбор по
        // одной длине выбросил бы ровно то, что человек назвал вслух.
        let terms = GroundingContextPolicy.recentTerms(
            in: "переносим на Q3 и правим 42", cap: 100)
        #expect(terms.contains("Q3"))
        #expect(terms.contains("42"))
    }

    @Test("фраза из одних длинных слов тоже не уезжает")
    func aSentenceOfLongWordsIsStillRefused() {
        // Разбор на слова сам по себе не спасает: живая речь бывает без
        // коротких связок, и тогда значимые слова идут подряд и остаются
        // подряд. Здесь и работает общая проверка на цитату — последняя, уже
        // после разбора.
        let dense = "проверяем интеграцию платежей клиентам подписки корпоративным сегментом"
        let query = GroundingContextPolicy.backgroundQuery(
            goal: "Интеграция", recentTranscript: dense, maxChars: 180)
        #expect(!PromptWorkflows.looksLikeAQuote(query, of: dense),
                "плотная фраза уехала целиком: \(query)")
        #expect(query == "Интеграция")
    }

    @Test("хвост, из которого ничего не уцелело, оставляет одну цель")
    func aTailOfNoiseLeavesTheGoal() {
        // Речь может целиком состоять из коротких слов. Тогда хвоста нет, и
        // запрос — это цель звонка, а не обрубок.
        let query = GroundingContextPolicy.backgroundQuery(
            goal: "Пересмотр тарифов", recentTranscript: "да и мы уже там", maxChars: 180)
        #expect(query == "Пересмотр тарифов")
    }

    @Test("оба пути судят одним правилом")
    func bothPathsShareTheRule() throws {
        // Правило, живущее в двух видах, расходится ровно тогда, когда его
        // меняют. Здесь проверяется, что фоновый путь спрашивает то же самое,
        // а не свою копию.
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/MeetGPT/AI/GroundingContextPolicy.swift"),
                                encoding: .utf8)
        #expect(source.contains("PromptWorkflows.looksLikeAQuote(query, of: recentTranscript)"),
                "фоновый запрос снова судит сам себя")
    }
}
