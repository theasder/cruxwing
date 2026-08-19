import Testing
import Foundation
@testable import MeetGPT

/// Подсказка к запросу — только тому, кто запрос ТОЛКУЕТ.
///
/// Инструмент MCP читает запрос и решает, что вернуть: подсказка смещает его
/// выбор. Прямой коннектор кладёт слово в параметр поиска дословно, и подсказка
/// становится одиннадцатью лишними словами внутри условия отбора.
///
/// Измерено на живом Redmine 2026-08-21: «тарифы» — одна находка; «тарифы —
/// открытые задачи, что уже в работе, недавние баги по обсуждаемому» — НОЛЬ.
/// Подсказка не сместила выдачу, а стёрла её.
///
/// Утекало через совпадение имён: `linear` есть и среди серверов MCP, и среди
/// своих коннекторов, поэтому прямой поиск Linear получал английскую подсказку
/// прямо в `searchIssues(term:)`, а WEEEK и Kaiten — русскую.
@Suite struct HintOnlyForToolsTests {

    @Test("прямому поиску уходит только слово человека")
    func literalSearchGetsTheWordAlone() {
        for id in ["linear", "weeek", "kaiten", "trello", "github", "telegram"] {
            let query = ConnectorProbeStrategy.query(
                goal: "тарифы с декабря", serverID: id, destination: .literalSearch)
            #expect(query == "тарифы с декабря",
                    "\(id) получил не только слово человека: «\(query)»")
        }
    }

    @Test("инструменту, который толкует, подсказка остаётся")
    func interpretingToolKeepsItsHint() {
        // Отменить подсказку везде было бы проще и неверно: там, где запрос
        // читают, она и задумана — и работает.
        let query = ConnectorProbeStrategy.query(
            goal: "тарифы", serverID: "hubspot", destination: .interpretingTool)
        #expect(query.contains("тарифы"))
        #expect(query.count > "тарифы".count, "подсказка пропала у того, кому она нужна")
    }

    @Test("умолчание — толкующий инструмент, и это видно на вызове")
    func defaultIsTheInterpretingTool() {
        // Умолчание выбрано так, что забывчивость не молчит: забыть пометку у
        // прямого поиска — значит вернуть подсказку и увидеть это проверкой
        // выше, а не получить пустую выдачу у человека на звонке.
        #expect(ConnectorProbeStrategy.query(goal: "тарифы", serverID: "hubspot")
                != "тарифы")
    }

    @Test("веер помечает прямой поиск во всех ветках")
    func everyDirectBranchIsMarked() throws {
        // Структурно: поднять восемь сервисов ради одной пометки дороже пользы.
        // Правило простое — в веере столько пометок `.literalSearch`, сколько
        // веток прямого поиска. Пропустить одну значит вернуть подсказку
        // ровно тому сервису, о котором забыли, и обнулить его выдачу молча.
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/MeetGPT/MCP/MCPGrounding.swift"), encoding: .utf8)
        let calls = source.components(separatedBy: "ConnectorProbeStrategy.query(").count - 1
        let marked = source.components(separatedBy: ".literalSearch").count - 1
        #expect(calls >= 9, "вызовов запроса нашлось \(calls) — проверка смотрит не туда")
        // Ровно ОДИН вызов остаётся без пометки — обращение к инструменту MCP,
        // который запрос толкует. Все прочие ветки кладут слово в чужой
        // параметр поиска дословно. Первая редакция требовала пометить все и
        // была неверна: она отобрала бы подсказку и у того, кому она нужна.
        #expect(calls - marked == 1,
                "без пометки \(calls - marked) вызовов, а толкующий инструмент один")
        #expect(source.contains("ConnectorProbeStrategy.query(goal: goal, serverID: server.id)"),
                "непомеченным остался не тот вызов")
    }
}
