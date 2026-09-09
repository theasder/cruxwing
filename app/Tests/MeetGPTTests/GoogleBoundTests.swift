import Testing
import Foundation
@testable import MeetGPT

/// Сколько Диска мы на самом деле прочитали.
///
/// Поиск по Google просит СТРАНИЦУ, и страница крошечная: три документа за
/// вопрос, потолок пять, тексты внутри обрезаны. Значит пустая выдача — это «в
/// трёх прочитанных нет», а не «в Диске нет».
///
/// Остальные источники называют свою границу с 2026-08-20. Этот жил вне того
/// веера — в `AppState`, а не в `MCPGrounding`, — и правила не получил: молчал
/// и когда нашёл, и когда нет.
@MainActor
@Suite struct GoogleBoundTests {

    @Test("граница названа числом прочитанного и потолком")
    func theBoundNamesWhatWasRead() {
        let text = AppState.googleBound(read: 3)
        #expect(text.contains("3 documents read"))
        #expect(text.contains("no more than three"))
        #expect(text.contains("from the beginning"), "про обрезку текста не сказано")
        #expect(text.contains("does not mean it is absent from Drive"))
    }

    @Test("ноль прочитанного — тоже число, и оно называется")
    func zeroIsStated() {
        #expect(AppState.googleBound(read: 0).contains("0 documents read"))
    }

    @Test("граница едет обоими путями — и с находками, и без")
    func theBoundTravelsBothWays() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/MeetGPT/AppState.swift"), encoding: .utf8)
        // Пустая ветка отдаёт границу…
        #expect(source.contains("text: bound, sourceID: \"google:\\(service.rawValue)\""),
                "пустая выдача Google снова молчит")
        // …и найденное уезжает вместе с ней.
        #expect(source.contains("text: String(text.prefix(cap)) + \"\\n\" + bound"),
                "находки Google уезжают без границы")
    }

    @Test("потолок в запросе к Google — тот, про который написано")
    func theRequestedPageMatchesTheSentence() throws {
        // Строка обещает «больше трёх не запрашивается». Обещание про число в
        // другом файле — это ровно то, что расходится молча.
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/MeetGPT/Integrations/GoogleWorkspaceSearchService.swift"),
                                encoding: .utf8)
        #expect(source.contains("maxResults: Int = 3"),
                "запрашиваемое число разошлось с тем, что сказано человеку")
    }
}
