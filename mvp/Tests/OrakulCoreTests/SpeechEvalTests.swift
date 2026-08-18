import Foundation
import Testing
@testable import OrakulCore

/// Метрика решает, какую модель распознавания мы возьмём. Если она врёт в нашу
/// пользу, мы возьмём не ту — поэтому она проверяется первой, до того как на
/// неё посмотрит хоть один движок.
@Suite("Оценка распознавания")
struct SpeechEvalTests {

    // MARK: - Нормализация

    @Test("«ё» и «е» — одно слово, а не расхождение движков")
    func yoIsNotADisagreement() {
        // Whisper пишет «всё», Parakeet — «все». Без склейки мы считали бы
        // орфографическую традицию ошибкой слуха и видели бы разницу там, где
        // звук расслышан одинаково.
        #expect(SpeechEval.normalize("Всё ещё") == SpeechEval.normalize("Все еще"))
    }

    @Test("пунктуация и регистр не считаются ошибками")
    func punctuationIgnored() {
        let rate = SpeechEval.wordErrorRate(reference: "Поднимем фильтр в прод.",
                                            hypothesis: "поднимем фильтр в прод")
        #expect(rate.errors == 0)
    }

    // MARK: - WER

    @Test("идеальная расшифровка даёт ноль")
    func perfectIsZero() {
        let text = "мы решили перейти на оплату за использование"
        #expect(SpeechEval.wordErrorRate(reference: text, hypothesis: text).rate == 0)
    }

    @Test("замена, пропуск и вставка считаются по отдельности")
    func operationsAreCountedSeparately() {
        // Суммарное расстояние не отвечает на вопрос, речь сломалась или
        // ПРОПАЛА. Глоссарий в промпте когда-то поднял recall терминов ценой
        // 2757 пропусков — по одному числу это выглядело бы улучшением.
        let substitution = SpeechEval.wordErrorRate(reference: "поднимем фильтр в прод",
                                                    hypothesis: "поднимем фильтр в тест")
        #expect(substitution.substitutions == 1)
        #expect(substitution.deletions == 0 && substitution.insertions == 0)

        let deletion = SpeechEval.wordErrorRate(reference: "поднимем фильтр в прод",
                                                hypothesis: "поднимем фильтр")
        #expect(deletion.deletions == 2)
        #expect(deletion.substitutions == 0)

        let insertion = SpeechEval.wordErrorRate(reference: "поднимем фильтр",
                                                 hypothesis: "поднимем фильтр в прод")
        #expect(insertion.insertions == 2)
        #expect(insertion.substitutions == 0)
    }

    @Test("пустая расшифровка — это сто процентов ошибок, а не ноль")
    func emptyHypothesisIsTotalFailure() {
        // Движок, который промолчал, не «не ошибся». Ровно это и произошло с
        // большой моделью: WER 0.95 при почти полном молчании.
        let rate = SpeechEval.wordErrorRate(reference: "мы решили перейти на оплату",
                                            hypothesis: "")
        #expect(rate.rate == 1.0)
        #expect(rate.deletions == 5)
    }

    @Test("WER может быть больше единицы, и это не баг")
    func rateCanExceedOne() {
        // Галлюцинация длиннее исходной фразы — обычное поведение на границах
        // VAD-нарезки. Метрика, зажатая в 0…1, спрятала бы это.
        let rate = SpeechEval.wordErrorRate(reference: "да",
                                            hypothesis: "да и ещё много лишних слов")
        #expect(rate.rate > 1.0)
    }

    // MARK: - Термины без эталона

    @Test("расхождение на термине — доказательство ошибки без эталона")
    func disagreementProvesError() {
        // Один и тот же звук, три расшифровки. Кто прав — неизвестно, но что
        // кто-то неправ — известно точно.
        let reports = SpeechEval.termDisagreements(
            terms: ["LLM", "прод"],
            across: [
                "поднимем LLM фильтр в прод",
                "поднимем LLM фильтр в прод",
                "поднимем элэлэм фильтр в прод",
            ])
        let llm = reports.first { $0.term == "LLM" }!
        #expect(llm.isDisputed)
        #expect(llm.found == 2 && llm.total == 3)

        let prod = reports.first { $0.term == "прод" }!
        #expect(prod.isUnanimous)
    }

    @Test("единогласие не считается доказательством правоты")
    func unanimityIsNotProof() {
        // Все три могли расслышать одинаково неверно. Метод отвечает «где
        // точно плохо» и не притворяется, что отвечает «где хорошо».
        let reports = SpeechEval.termDisagreements(
            terms: ["Kubernetes"],
            across: ["кубернетес поднят", "кубернетес поднят", "кубернетес поднят"])
        let report = reports[0]
        #expect(report.found == 0)
        #expect(report.isUnanimous, "все промахнулись одинаково — согласие, а не успех")
    }

    @Test("термин ищется как слово, а не как подстрока")
    func termMatchIsWordLevel() {
        // «прод» не должен находиться внутри «продукт», иначе метрика начнёт
        // видеть согласие там, где сказаны разные слова.
        let reports = SpeechEval.termDisagreements(terms: ["прод"],
                                                   across: ["мы обсудили продукт"])
        #expect(reports[0].found == 0)
    }

    @Test("доля согласия считается по терминам, а не по расшифровкам")
    func agreementRate() {
        let rate = SpeechEval.termAgreementRate(
            terms: ["LLM", "прод", "релиз"],
            across: ["LLM прод релиз", "LLM прод релиз", "элэлэм прод релиз"])
        // Два термина из трёх единогласны.
        #expect(abs(rate - 2.0 / 3.0) < 0.001)
    }

    @Test("без расшифровок метрика молчит, а не выдумывает")
    func emptyInput() {
        #expect(SpeechEval.termDisagreements(terms: ["LLM"], across: []).isEmpty)
        #expect(SpeechEval.termAgreementRate(terms: [], across: ["текст"]) == 1)
    }

    /// Замер на настоящей русской речи — не проверка, а измерение.
    ///
    ///     CRUXWING_RU_CORPUS=/путь/к/корпусу \
    ///     swift test --filter probeRussianCorpus
    ///
    /// Что читается: `corpus.json` в этой папке (формат — `SpeechCorpus`).
    /// Раньше здесь стояли три имени файлов, вписанные руками: корпус нельзя
    /// было пополнить, не правя набор, и жанр записи нигде не учитывался.
    ///
    /// Считается два разных числа, и они не взаимозаменяемы:
    ///
    ///   * WER — только там, где есть расшифровка, размеченная человеком.
    ///     Это настоящая ошибка распознавания;
    ///   * согласие движков — там, где эталона нет. Разногласие доказывает
    ///     ошибку, единогласие не доказывает ничего, и вывод не должен
    ///     притворяться, что доказывает.
    ///
    /// Доклады и звонки печатаются раздельно. Смешать их в одном среднем —
    /// значит пообещать точность, которой на звонке не будет: переключение
    /// языков в докладе слабее (план, §6.2).
    @Test("замер: русский корпус — WER по эталону, согласие движков без него",
          .enabled(if: ProcessInfo.processInfo.environment["CRUXWING_RU_CORPUS"] != nil))
    func probeRussianCorpus() throws {
        let dir = ProcessInfo.processInfo.environment["CRUXWING_RU_CORPUS"]!
        let corpus = try SpeechCorpus.load(directory: dir)
        let terms = ["LLM", "API", "промпт", "агент", "фильтр", "токен", "инъекция",
                     "прод", "MCP", "RAG", "модель", "модели", "пайплайн", "деплой",
                     "релиз", "бэкенд", "джейлбрейк"]

        for (genre, count) in corpus.countsByGenre.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            print("\(genre.rawValue): записей \(count)")
        }
        print("с человеческой расшифровкой: \(corpus.withReference.count) из \(corpus.items.count)")

        func read(_ file: String) -> String? {
            try? String(contentsOfFile: "\(dir)/\(file)", encoding: .utf8)
        }

        var werByGenre: [SpeechCorpus.Genre: [Double]] = [:]
        var agreementByGenre: [SpeechCorpus.Genre: [Double]] = [:]

        for item in corpus.items.sorted(by: { $0.id < $1.id }) {
            let engines = item.engines.sorted { $0.key < $1.key }
            let texts = engines.compactMap { read($0.value) }
            guard texts.count == engines.count else {
                print("\(item.id): не прочиталась часть расшифровок — пропущено")
                continue
            }

            if let referenceFile = item.reference, let reference = read(referenceFile) {
                // Эталон есть — считается настоящая ошибка, по каждому движку.
                for (engine, text) in zip(engines.map(\.key), texts) {
                    let raw = SpeechEval.wordErrorRate(reference: reference, hypothesis: text)
                    let fixed = SpeechEval.wordErrorRate(reference: reference,
                                                         hypothesis: RussianLexicon.restore(text))
                    werByGenre[item.genre, default: []].append(fixed.rate)
                    print(String(format: "%@ [%@] %@: WER %.1f%% → после словаря %.1f%%",
                                 item.id, item.genre.rawValue, engine,
                                 raw.rate * 100, fixed.rate * 100))
                }
                continue
            }

            // Эталона нет — остаётся согласие движков между собой.
            let reports = SpeechEval.termDisagreements(terms: terms, across: texts)
            let spoken = reports.filter { $0.found > 0 }
            guard !spoken.isEmpty else { continue }
            let disputed = spoken.filter(\.isDisputed)
            let agreement = Double(spoken.count - disputed.count) / Double(spoken.count)
            agreementByGenre[item.genre, default: []].append(agreement)
            print(String(format: "%@ [%@]: терминов прозвучало %d, спорных %d, согласие %.0f%%",
                         item.id, item.genre.rawValue, spoken.count, disputed.count,
                         agreement * 100))
            for report in disputed.sorted(by: { $0.term < $1.term }) {
                print("    спорный «\(report.term)»: нашли \(report.found) из \(report.total)")
            }
        }

        func mean(_ values: [Double]) -> Double {
            values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        }
        for (genre, values) in werByGenre.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            print(String(format: "средний WER (%@, после словаря): %.1f%% по %d замерам",
                         genre.rawValue, mean(values) * 100, values.count))
        }
        for (genre, values) in agreementByGenre.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            print(String(format: "среднее согласие движков (%@): %.0f%% по %d записям",
                         genre.rawValue, mean(values) * 100, values.count))
        }
        if werByGenre[.call] == nil {
            // Главное предупреждение отчёта: доклад и звонок — разные жанры.
            print("!! звонков с эталоном в корпусе нет — число про доклады, а обещание продукта про звонки")
        }
        // Порога здесь нет намеренно: это замер, а не ворота.
    }
}
