import Testing
import Foundation
@testable import OrakulCore

/// Формат корпуса русской речи (роадмап, §6.3).
///
/// Проверяется то, из-за чего замер получился бы красивым и неправдивым:
/// запись без согласия, файл, которого нет, и жанр, смешанный в одном среднем.
@Suite struct SpeechCorpusTests {

    final class Folder {
        let root: URL
        init() {
            root = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("orakul-corpus-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        deinit { try? FileManager.default.removeItem(at: root) }

        func write(_ name: String, _ text: String) {
            try? Data(text.utf8).write(to: root.appendingPathComponent(name))
        }
        var path: String { root.path }
    }

    static let good = """
    {"items": [
      {"id": "doklad-1", "genre": "talk", "consent": "public",
       "source": "https://example.com/talk", "seconds": 900,
       "reference": "doklad-1.reference.txt",
       "engines": {"whisper-large": "doklad-1.whisper.txt", "parakeet": "doklad-1.parakeet.txt"}},
      {"id": "zvonok-1", "genre": "call", "consent": "participants",
       "source": "внутренняя встреча, согласие участников от 2026-08-18",
       "engines": {"whisper-large": "zvonok-1.whisper.txt"}}
    ]}
    """

    static func filled() -> Folder {
        let folder = Folder()
        folder.write("corpus.json", good)
        folder.write("doklad-1.reference.txt", "решили поднять лимиты выгрузки")
        folder.write("doklad-1.whisper.txt", "решили поднять лимиты выгрузки")
        folder.write("doklad-1.parakeet.txt", "решили поднять лимит выгрузки")
        folder.write("zvonok-1.whisper.txt", "годовой тариф не трогаем")
        return folder
    }

    @Test("корпус читается и делится по жанрам")
    func loadsAndCountsGenres() throws {
        let folder = Self.filled()
        let corpus = try SpeechCorpus.load(directory: folder.path)
        #expect(corpus.items.count == 2)
        #expect(corpus.countsByGenre == [.talk: 1, .call: 1])
        #expect(corpus.withReference.map(\.id) == ["doklad-1"],
                "WER считается только там, где есть человеческая расшифровка")
    }

    @Test("файл, которого нет, роняет чтение, а не тихо выпадает из замера")
    func missingFileIsAnError() {
        // Иначе среднее посчитается по тем записям, которые нашлись, и цифра
        // будет про другой корпус.
        let folder = Folder()
        folder.write("corpus.json", Self.good)
        folder.write("doklad-1.reference.txt", "текст")
        folder.write("doklad-1.whisper.txt", "текст")
        // parakeet и zvonok-1 не записаны.
        #expect(throws: SpeechCorpus.CorpusError.self) {
            _ = try SpeechCorpus.load(directory: folder.path)
        }
    }

    @Test("запись без согласия в корпус не принимается")
    func consentIsRequired() {
        // Запись звонка содержит чужие голоса. Поле обязательное на уровне
        // разбора: «забыли указать» и «согласия не было» снаружи неразличимы.
        let folder = Folder()
        folder.write("corpus.json", """
        {"items": [{"id": "x", "genre": "call", "source": "встреча",
                    "engines": {"whisper-large": "x.txt"}}]}
        """)
        folder.write("x.txt", "текст")
        #expect(throws: SpeechCorpus.CorpusError.self) {
            _ = try SpeechCorpus.load(directory: folder.path)
        }
    }

    @Test("жанр обязателен: доклад и звонок нельзя сложить в одно число")
    func genreIsRequired() {
        let folder = Folder()
        folder.write("corpus.json", """
        {"items": [{"id": "x", "consent": "public", "source": "https://example.com",
                    "engines": {"whisper-large": "x.txt"}}]}
        """)
        folder.write("x.txt", "текст")
        #expect(throws: SpeechCorpus.CorpusError.self) {
            _ = try SpeechCorpus.load(directory: folder.path)
        }
    }

    @Test("пустой источник — отказ: замер обязан быть воспроизводимым")
    func sourceMustNotBeEmpty() {
        let folder = Folder()
        folder.write("corpus.json", """
        {"items": [{"id": "x", "genre": "talk", "consent": "public", "source": "  ",
                    "engines": {"whisper-large": "x.txt"}}]}
        """)
        folder.write("x.txt", "текст")
        #expect(throws: SpeechCorpus.CorpusError.emptySource("x")) {
            _ = try SpeechCorpus.load(directory: folder.path)
        }
    }

    @Test("одна и та же запись дважды сдвинула бы среднее")
    func duplicatesAreRefused() {
        let folder = Folder()
        folder.write("corpus.json", """
        {"items": [
          {"id": "x", "genre": "talk", "consent": "public", "source": "https://example.com",
           "engines": {"whisper-large": "x.txt"}},
          {"id": "x", "genre": "talk", "consent": "public", "source": "https://example.com",
           "engines": {"whisper-large": "x.txt"}}]}
        """)
        folder.write("x.txt", "текст")
        #expect(throws: SpeechCorpus.CorpusError.duplicateID("x")) {
            _ = try SpeechCorpus.load(directory: folder.path)
        }
    }

    @Test("запись без единой расшифровки измерять нечем")
    func enginesAreRequired() {
        let folder = Folder()
        folder.write("corpus.json", """
        {"items": [{"id": "x", "genre": "talk", "consent": "public",
                    "source": "https://example.com", "engines": {}}]}
        """)
        #expect(throws: SpeechCorpus.CorpusError.noEngines("x")) {
            _ = try SpeechCorpus.load(directory: folder.path)
        }
    }

    @Test("отсутствующее описание — понятный отказ")
    func missingManifest() {
        let folder = Folder()
        #expect(throws: SpeechCorpus.CorpusError.self) {
            _ = try SpeechCorpus.load(directory: folder.path)
        }
    }

    @Test("WER считается по эталону, а согласие — по движкам между собой")
    func measuresDifferForReferenced() throws {
        // Ровно та разница, ради которой формат и заведён: у записи с эталоном
        // есть настоящая ошибка, у остальных — только расхождение.
        let folder = Self.filled()
        let corpus = try SpeechCorpus.load(directory: folder.path)
        let referenced = try #require(corpus.withReference.first)
        let reference = try String(contentsOfFile: "\(folder.path)/\(referenced.reference!)",
                                   encoding: .utf8)
        let parakeet = try String(contentsOfFile: "\(folder.path)/doklad-1.parakeet.txt",
                                  encoding: .utf8)
        let rate = SpeechEval.wordErrorRate(reference: reference, hypothesis: parakeet)
        #expect(rate.rate > 0, "«лимит» вместо «лимиты» — это ошибка, а не совпадение")
        #expect(rate.substitutions == 1)
    }
}
