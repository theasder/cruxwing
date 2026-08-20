import Testing
import Foundation
import OrakulCore
@testable import MeetGPT

/// Пустая выдача телеграмного архива — не «не обсуждали».
///
/// Bot API старую переписку не отдаёт: архив начинается ровно в тот момент,
/// когда подключили бота. Источник при пустой выдаче не отвечал НИЧЕГО — ни
/// строки в запрос, — и молчание читалось как «в переписке этого нет».
///
/// Честное утверждение другое: «до такого-то числа мы не видели ничего». Оно и
/// бывает ответом — обсуждали раньше, чем появился бот.
@MainActor
@Suite struct TelegramArchiveBoundTests {

    @Test("граница названа днём, с которого архив что-то знает")
    func theFloorIsADate() {
        let floor = Date(timeIntervalSince1970: 1_770_000_000)   // 2026-02-02
        let text = MCPConnectionManager.telegramBound(from: floor)
        #expect(text.contains("Охват Telegram"))
        #expect(text.contains("2026"))
        #expect(text.contains("Более ранняя переписка Bot API недоступна"))
    }

    @Test("пустой архив говорит, что он пуст, а не молчит")
    func anEmptyArchiveSaysSo() {
        let text = MCPConnectionManager.telegramBound(from: nil)
        #expect(text.contains("архив пуст"))
        #expect(text.contains("Более ранняя переписка Bot API недоступна"))
    }

    @Test("граница едет и вместе с находками")
    func theBoundTravelsWithHitsToo() throws {
        // Если писать её только при пустой выдаче, ответ, построенный на паре
        // сообщений, всё равно умалчивает, что до этой даты источник слеп.
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/MeetGPT/MCP/MCPGrounding.swift"), encoding: .utf8)
        #expect(source.contains("text: text + \"\\n\" + bound"),
                "находки уезжают без границы архива")
        #expect(source.contains("text: bound, sourceID: \"messenger:telegram\""),
                "пустая выдача снова молчит")
    }

    @Test("архив знает свой первый день")
    func theArchiveKnowsItsFirstDay() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("granica-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = TelegramMessageArchive(fileURL: root.appendingPathComponent("a.json"))
        try await archive.activate(botID: 44)
        let early = Date(timeIntervalSince1970: 1_770_000_000)
        let late = Date(timeIntervalSince1970: 1_780_000_000)
        try await archive.ingest(.init(messages: [
            TelegramSupergroups.Message(updateID: 2, chatID: -1001, messageID: 2,
                                        chatTitle: "Договоры", text: "позже", timestamp: late),
            TelegramSupergroups.Message(updateID: 1, chatID: -1001, messageID: 1,
                                        chatTitle: "Договоры", text: "раньше", timestamp: early),
        ], nextOffset: 3), allowedChatIDs: [-1001])

        #expect(await archive.earliestMessageDate(allowedChatIDs: [-1001]) == early)
        // Чужой чат в счёт не идёт: граница должна быть про то, что человек
        // разрешил читать.
        #expect(await archive.earliestMessageDate(allowedChatIDs: [-2002]) == nil)
    }
}
