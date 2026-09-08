import Testing
import Foundation
@testable import MeetGPT
import OrakulCore

/// Охват доезжает до звонка, а не только до командной строки.
///
/// Часть списка, выданная за весь список, — это уверенная фраза о том, чего не
/// было. У Plane граница — пятьсот строк, и человек на звонке слышал «вот что
/// есть в Plane» там, где прочитана треть. В командной строке приписка про
/// охват печаталась с самого начала; в приложении её не было ни в одной ветке,
/// кроме локальных заметок, потому что ветки звали `search` — тот самый метод,
/// про который в ядре написано «то же самое без охвата, для тех, кто его всё
/// равно не показывает».
@Suite struct CoverageReachesTheCallTests {

    @Test("охват приписан к находкам")
    func coverageIsAppended() {
        let text = MCPConnectionManager.withCoverage("#1 Тарифы\n#2 Лимиты",
                                             note: SearchCoverage.latest(scanned: 500, total: 1500).note(),
                                             limit: 4000)
        #expect(text.contains("#1 Тарифы"))
        #expect(text.contains("500"), "числа охвата нет: \(text)")
        #expect(text.contains("1500"))
    }

    @Test("обычному поиску приписывать нечего")
    func plainSearchGetsNoNote() {
        // Приписка в каждой подсказке была бы шумом, и модель начала бы её
        // пересказывать человеку.
        let text = MCPConnectionManager.withCoverage("#1 Тарифы", note: SearchCoverage.searched.note(), limit: 4000)
        #expect(text == "#1 Тарифы")
    }

    @Test("ответ из памяти назван ответом из памяти")
    func cachedAnswerSaysSo() {
        // Сервис попросил обращаться реже — значит это ответ минутной
        // давности. На звонке разница между «сейчас» и «минуту назад» бывает
        // решающей: задачу успели закрыть.
        let text = MCPConnectionManager.withCoverage("#1 Тарифы",
                                             note: SearchCoverage.cached(seconds: 60, under: .service).note(),
                                             limit: 4000)
        #expect(text.contains("from memory"), "про память не сказано: \(text)")
    }

    @Test("приписка не теряется, когда находок много")
    func noteSurvivesTruncation() {
        // Резать надо список, а не приписку: иначе охват пропадает ровно там,
        // где находок много, то есть где он нужнее всего. Обрезка ПОСЛЕ
        // приписки вернула бы ещё и строку длиннее предела.
        let long = String(repeating: "#1 Очень длинная задача про тарифы\n", count: 500)
        let note = SearchCoverage.latest(scanned: 500, total: 1500).note()
        let text = MCPConnectionManager.withCoverage(long, note: note, limit: 300)
        #expect(text.count <= 300, "предел нарушен: \(text.count)")
        #expect(text.contains("500"), "приписку срезало: \(text.suffix(80))")
    }

    @Test("ветки звонка спрашивают охват, а не только находки")
    func groundingBranchesAskForCoverage() throws {
        // Структурно: поведение ветки требует поднять весь веер с сетью и
        // хранилищем ключей. Правило же простое — в веере нет вызова `search`
        // у клиентов, которые умеют отдавать охват.
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/MeetGPT/MCP/MCPGrounding.swift"), encoding: .utf8)
        let code = source.split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        // Якорь — именно место в веере, а не первое вхождение слова в файле:
        // «selfhosted:» встречается строкой выше в разборе идентификаторов, и
        // проверка искала ветку не там. Ровно тот случай, ради которого в
        // репозитории записано «сторож смотрит в один угол».
        // И какой ИМЕННО охват уезжает: вызов `withCoverage` с пустой строкой
        // выглядит как исполнение правила и не несёт ничего. Проверено
        // мутацией — первая редакция этой проверки его пропускала.
        for (branch, source_) in [("sourceID: \"western:", "outcome.coverage.note()"),
                                  ("sourceID: \"selfhosted:", "outcome.note")] {
            // ПОСЛЕДНЕЕ вхождение, а не первое: с 2026-08-20 в каждой ветке
            // их два. Первое — кусок для пустой, но ограниченной выдачи
            // («ничего не нашлось, но искали не везде»), второе — находки.
            // Проверка про находки, и якорь на первом вхождении срезал ветку
            // до `withCoverage` и объявлял пропажу того, что лежит на месте.
            let head = try #require(code.range(of: branch, options: .backwards))
            // Ветка целиком — от её объявления вверх до предыдущего `group.addTask`.
            let before = String(code[..<head.lowerBound])
            let start = try #require(before.range(of: "group.addTask", options: .backwards))
            let body = String(before[start.lowerBound...])
            #expect(body.contains("client.run(query)"),
                    "ветка \(branch) снова спрашивает находки без охвата")
            #expect(body.contains("withCoverage("),
                    "ветка \(branch) получила охват и не донесла его")
            #expect(body.contains("note: \(source_)"),
                    "ветка \(branch) зовёт withCoverage не с охватом сервиса")
        }
    }
}
