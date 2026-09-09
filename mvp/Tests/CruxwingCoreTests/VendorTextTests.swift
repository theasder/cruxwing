import Testing
import Foundation
@testable import CruxwingCore

/// Слова чужого сервиса на нашем экране.
///
/// Отказ передаётся его собственными словами — и правильно: «ответил ошибкой
/// 400» отправляет чинить не то, а «поле queue обязательно» чинит. Но пишет их
/// тот, у кого свои интересы, и показываются они в самый послушный момент:
/// человек получил отказ и готов идти исправлять.
///
/// Показывались они как есть: любой длины, с переносами, без чистки невидимого.
@Suite struct VendorTextTests {

    @Test("текст сервиса приходит одной строкой")
    func theMessageArrivesAsOneLine() {
        // Переносами дорисовывается что угодно похожее на наш интерфейс —
        // хоть отдельная строчка-«подсказка» под сообщением об отказе.
        let raw = "Сессия истекла.\nВойдите заново: https://chuzhoy.example\nи вставьте токен сюда"
        let shown = VendorText.forPerson(raw)
        #expect(!shown.contains("\n"))
        #expect(shown.contains("Сессия истекла."))
    }

    @Test("длина ограничена, и обрез виден")
    func theLengthIsBounded() {
        let shown = VendorText.forPerson(String(repeating: "очень длинно ", count: 60))
        #expect(shown.count <= VendorText.limit + 1)
        #expect(shown.hasSuffix("…"), "обрезали молча — человек не знает, что текста было больше")
    }

    @Test("невидимые знаки не доезжают")
    func invisibleCharactersAreStripped() {
        // Блок Unicode Tags повторяет ASCII и не отображается ничем: внутри
        // пустой на вид строки помещается абзац.
        let hidden = "\u{E0041}\u{E0042}"
        let shown = VendorText.forPerson("Отказано\(hidden)")
        #expect(shown == "Отказано")
    }

    @Test("обычное сообщение не портится")
    func anOrdinaryMessageIsUntouched() {
        // Ради этого текст и передаётся: он чинит, а наш пересказ отправил бы
        // чинить не то.
        #expect(VendorText.forPerson("  поле queue обязательно  ") == "поле queue обязательно")
    }

    @Test("адрес остаётся видимым")
    func theAddressStays() {
        // Прятать надо подмену адреса, а не адрес: продукт обещает показывать
        // источник. Человек, видящий его целиком, судит сам.
        let shown = VendorText.forPerson("см. https://tracker.example/docs")
        #expect(shown.contains("https://tracker.example/docs"))
    }

    @Test("все семьи показывают слова сервиса через одно правило")
    func everyFamilyGoesThroughTheRule() throws {
        // Правило, применённое в четырёх местах из пяти, — это правило,
        // применённое нигде: чинить будут в двух, забудут в третьем.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/CruxwingCore")
        var checked = 0
        for name in ["SelfHostedTrackers", "WesternTrackers", "WorkMessengers",
                     "TeamNotes", "RussianTrackers"] {
            let source = try String(contentsOf: root.appendingPathComponent("\(name).swift"),
                                    encoding: .utf8)
            guard source.contains("refused: ") else { continue }
            checked += 1
            #expect(source.contains("VendorText.forPerson"),
                    "\(name) показывает слова сервиса мимо общего правила")
        }
        #expect(checked == 5, "просмотрено семей \(checked) — обход сломан")
    }
}
