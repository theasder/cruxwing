import Testing
import Foundation
import OrakulCore
@testable import MeetGPT

/// Пустая выдача источника, видевшего только часть.
///
/// `SearchCoverage` заведён ровно ради разницы между «искали везде» и
/// «просмотрели последние 500 из 40 000» (§7.2). Он ехал вместе с находками —
/// и пропадал, когда находок не было. То есть в единственном случае, когда
/// «часть» и «всё» звучат для читателя одинаково: «ничего не нашлось».
///
/// Для сервиса, который искал сам, молчание честно. Для перечисления с
/// границей — нет: там правда звучит как «в просмотренной части нет».
@Suite struct EmptyButBoundedTests {

    @Test("сервис, искавший сам, молчит — и это честно")
    func aRealSearchMayStaySilent() {
        #expect(MCPConnectionManager.emptyButBounded(.searched) == nil)
    }

    @Test("перечисление с границей говорит, что видело не всё")
    func aBoundedListSpeaks() throws {
        let text = try #require(MCPConnectionManager.emptyButBounded(.latest(scanned: 500, total: 40_000)))
        #expect(text.contains("искали не везде"))
        #expect(text.contains("500"))
        #expect(text.contains("40000") || text.contains("40 000"))
    }

    @Test("ответ из памяти тоже называет себя")
    func acachedAnswerSaysSo() throws {
        // Возраст ответа меняет смысл пустоты так же: «час назад не было» —
        // это не «нет».
        let text = try #require(MCPConnectionManager.emptyButBounded(.cached(seconds: 120, under: .service)))
        #expect(text.contains("120"))
    }

    @Test("просмотр всего списка — тоже граница")
    func awholeListIsStillABound() throws {
        // «Просмотрены все 300» честнее «ничего не нашлось»: отбирали у себя,
        // и слово могло быть написано иначе.
        #expect(try #require(MCPConnectionManager.emptyButBounded(.wholeList(scanned: 300)))
                .contains("300"))
    }

    @Test("граница хранилища говорит про файлы, а не про сервис")
    func theFolderSubjectSpeaksOfFiles() throws {
        // Подлежащее у охвата своё: «просмотрены последние файлы 2000 из 8000»,
        // а не «последние 2000». Для заметок на диске «сервис» — неправда, там
        // нет никакого сервиса.
        let text = try #require(MCPConnectionManager.emptyButBounded(
            .latest(scanned: 2000, total: 8000), subject: .folder))
        #expect(text.contains("файлы"))
        #expect(text.contains("этом компьютере"))
    }

    @Test("все три источника с границей зовут это правило")
    func everyBoundedSourceUsesIt() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/MeetGPT/MCP/MCPGrounding.swift"), encoding: .utf8)
        // Спрашиваем про ВЫЗОВ, а не про наличие строки. Первая редакция
        // проверяла, что нужный текст есть в файле, — и мутация, дописавшая
        // `return (index, nil)` перед ним, её прошла: код остался на месте и
        // стал недостижим.
        let calls = source.components(separatedBy: "Self.boundedEmptySnippet(").count - 1
        #expect(calls == 3, "правило зовут \(calls) раз(а) из трёх источников с границей")
#expect(source.contains(#"sourceID: "western:"#), "западные трекеры потеряли свой источник")
        #expect(source.contains(#"sourceID: "selfhosted:"#), "свои трекеры потеряли свой источник")
        // Заметки на диске — третий источник с границей, и довод про них
        // записан прямо в коде: «модель, получившая часть хранилища как целое,
        // ответит „в заметках этого нет“».
        #expect(source.contains(#"sourceID: "notes-local""#), "заметки потеряли свой источник")
        // И с ТЕМ подлежащим: проверка выше зовёт правило напрямую и подмены
        // `.folder` на «сервис» не увидит — это показала мутация. Для заметок
        // на диске «сервис» неправда: никакого сервиса там нет.
        #expect(source.contains("note: found.coverage.note(.folder)"),
                "охват заметок называет их сервисом")
    }
}
