import Foundation
import Testing
import OrakulCore
@testable import MeetGPT

@Suite("Локальный архив Telegram", .serialized)
struct TelegramMessageArchiveTests {
    private func location() -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("orakul-telegram-\(UUID().uuidString)", isDirectory: true)
        return (root, root.appendingPathComponent("messages.json"))
    }

    private func message(update: Int64, chat: Int64 = -1001, id: Int64 = 7,
                         topic: Int64? = 11, text: String,
                         edited: Bool = false) -> TelegramSupergroups.Message {
        TelegramSupergroups.Message(
            updateID: update, chatID: chat, messageID: id, topicID: topic,
            chatTitle: "Запуск", author: "Ира", text: text,
            timestamp: Date(timeIntervalSince1970: TimeInterval(1_770_000_000 + update)),
            isEdited: edited)
    }

    @Test("offset, allowlist, edit, topic, dedupe и поиск переживают перезапуск")
    func ingestAndSearchAreDurable() async throws {
        let (root, file) = location()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = TelegramMessageArchive(fileURL: file)
        try await archive.activate(botID: 44)
        try await archive.ingest(.init(messages: [
            message(update: 10, text: "Старый тариф"),
            message(update: 11, text: "Исправленный тариф", edited: true),
            message(update: 12, chat: -9999, id: 8, text: "Чужой секрет"),
        ], nextOffset: 13), allowedChatIDs: [-1001])

        #expect(await archive.offset() == 13)
        #expect(await archive.count(allowedChatIDs: [-1001]) == 1)
        let hits = await archive.search("тариф", allowedChatIDs: [-1001])
        #expect(hits.count == 1)
        #expect(hits.first?.message.text == "Исправленный тариф")
        #expect(hits.first?.message.topicID == 11)
        #expect(hits.first?.message.isEdited == true)
        #expect((await archive.search("секрет", allowedChatIDs: [-1001])).isEmpty)

        let reopened = TelegramMessageArchive(fileURL: file)
        #expect(await reopened.offset() == 13)
        #expect((await reopened.search("тариф", allowedChatIDs: [-1001])).count == 1)
    }

    @Test("другой bot id не наследует offset и сообщения")
    func botIdentityScopesTheOffset() async throws {
        let (root, file) = location()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = TelegramMessageArchive(fileURL: file)
        try await archive.activate(botID: 44)
        try await archive.ingest(.init(messages: [message(update: 20, text: "Тариф")],
                                       nextOffset: 21), allowedChatIDs: [-1001])

        try await archive.activate(botID: 55)
        #expect(await archive.offset() == nil)
        #expect(await archive.count(allowedChatIDs: [-1001]) == 0)
    }

    @Test("offset истекает после недели без обновлений, но сообщения остаются")
    func staleOffsetExpiresDurably() async throws {
        let (root, file) = location()
        defer { try? FileManager.default.removeItem(at: root) }
        let receivedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let archive = TelegramMessageArchive(fileURL: file)
        try await archive.activate(botID: 44)
        try await archive.ingest(
            .init(messages: [message(update: 20, text: "Тариф")], nextOffset: 21),
            allowedChatIDs: [-1001], receivedAt: receivedAt)

        #expect(await archive.offset(
            now: receivedAt.addingTimeInterval(7 * 24 * 60 * 60 - 1)) == 21)
        #expect(await archive.offset(
            now: receivedAt.addingTimeInterval(7 * 24 * 60 * 60)) == nil)

        // First post-expiry update may have a lower random id. It becomes the
        // new sequential watermark instead of reviving the old offset 21.
        let resumedAt = receivedAt.addingTimeInterval(8 * 24 * 60 * 60)
        try await archive.ingest(
            .init(messages: [message(update: 3, id: 8, text: "Новый тариф")],
                  nextOffset: 4),
            allowedChatIDs: [-1001], receivedAt: resumedAt)
        #expect(await archive.offset(now: resumedAt) == 4)

        let reopened = TelegramMessageArchive(fileURL: file)
        #expect(await reopened.offset(now: resumedAt) == 4)
        #expect((await reopened.search("тариф", allowedChatIDs: [-1001])).count == 2)
    }

    @Test("disconnect ждёт poller и удаляет архив")
    func disconnectErasesArchive() async throws {
        let (root, file) = location()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = TelegramMessageArchive(fileURL: file)
        try await archive.activate(botID: 44)
        try await archive.ingest(.init(messages: [message(update: 30, text: "Тариф")],
                                       nextOffset: 31), allowedChatIDs: [-1001])
        let source = TelegramSupergroupSource(archive: archive, http: { request in
            try await Task.sleep(nanoseconds: 20_000_000)
            return (Data(#"{"ok":true,"result":[]}"#.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!)
        })
        try await source.start(token: "123:synthetic", allowedChatIDs: [-1001], botID: 44)
        try await source.disconnectAndEraseArchive()

        #expect(await archive.offset() == nil)
        #expect(await archive.count(allowedChatIDs: [-1001]) == 0)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(!FileManager.default.fileExists(
            atPath: OrakulAtomicFile.recoveryURL(for: file).path))
        let reopened = TelegramMessageArchive(fileURL: file)
        #expect(await reopened.count(allowedChatIDs: [-1001]) == 0)
    }

    @Test("повреждённый основной файл восстанавливается из ограниченной копии")
    func recoveryCopySurvivesInterruptedWrite() async throws {
        let (root, file) = location()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = TelegramMessageArchive(fileURL: file)
        try await archive.activate(botID: 44)
        try await archive.ingest(
            .init(messages: [message(update: 40, text: "Первый тариф")], nextOffset: 41),
            allowedChatIDs: [-1001]
        )
        try await archive.ingest(
            .init(messages: [message(update: 41, id: 8, text: "Второй тариф")], nextOffset: 42),
            allowedChatIDs: [-1001]
        )

        let recovery = OrakulAtomicFile.recoveryURL(for: file)
        #expect(FileManager.default.fileExists(atPath: recovery.path))
        try Data("partial".utf8).write(to: file)

        let reopened = TelegramMessageArchive(fileURL: file)
        #expect(await reopened.count(allowedChatIDs: [-1001]) == 1)
        #expect(await reopened.offset() == 41)
        #expect((await reopened.search("Первый", allowedChatIDs: [-1001])).count == 1)
        let attributes = try FileManager.default.attributesOfItem(atPath: recovery.path)
        #expect(attributes[.posixPermissions] as? Int == 0o600)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: root.path)
        #expect(directoryAttributes[.posixPermissions] as? Int == 0o700)

        // Mutating a snapshot loaded from recovery must not replace that last
        // known-good copy with the corrupt primary.
        try await reopened.ingest(
            .init(messages: [message(update: 42, id: 9, text: "Третий тариф")], nextOffset: 43),
            allowedChatIDs: [-1001]
        )
        try Data("partial again".utf8).write(to: file)
        let recoveredAgain = TelegramMessageArchive(fileURL: file)
        #expect(await recoveredAgain.offset() == 41)
        #expect((await recoveredAgain.search("Первый", allowedChatIDs: [-1001])).count == 1)
    }

    @Test("повреждение primary при живом actor не уничтожает исправный recovery")
    func livePrimaryCorruptionPreservesKnownGoodRecovery() async throws {
        let (root, file) = location()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = TelegramMessageArchive(fileURL: file)
        try await archive.activate(botID: 44)
        try await archive.ingest(
            .init(messages: [message(update: 90, text: "Исправный первый")], nextOffset: 91),
            allowedChatIDs: [-1001]
        )
        try await archive.ingest(
            .init(messages: [message(update: 91, id: 8, text: "Исправный второй")],
                  nextOffset: 92),
            allowedChatIDs: [-1001]
        )

        let recovery = OrakulAtomicFile.recoveryURL(for: file)
        #expect(FileManager.default.fileExists(atPath: recovery.path))
        // Damage happens after actor initialization, so a one-time load flag is
        // insufficient: the ordinary write must revalidate disk immediately.
        try Data("external damage".utf8).write(to: file)
        try await archive.ingest(
            .init(messages: [message(update: 92, id: 9, text: "Исправный третий")],
                  nextOffset: 93),
            allowedChatIDs: [-1001]
        )

        try Data("external damage again".utf8).write(to: file)
        let recovered = TelegramMessageArchive(fileURL: file)
        #expect(await recovered.offset() == 91)
        #expect((await recovered.search("первый", allowedChatIDs: [-1001])).count == 1)
    }

    @Test("смена бота удаляет старые сообщения и recovery-копию")
    func botChangeDoesNotRetainPreviousArchive() async throws {
        let (root, file) = location()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = TelegramMessageArchive(fileURL: file)
        try await archive.activate(botID: 44)
        try await archive.ingest(
            .init(messages: [message(update: 50, text: "Секрет старого бота")], nextOffset: 51),
            allowedChatIDs: [-1001]
        )
        let recovery = OrakulAtomicFile.recoveryURL(for: file)
        #expect(FileManager.default.fileExists(atPath: recovery.path))

        try await archive.activate(botID: 55)

        #expect(await archive.count(allowedChatIDs: [-1001]) == 0)
        #expect(!FileManager.default.fileExists(atPath: recovery.path))
        let reopened = TelegramMessageArchive(fileURL: file)
        #expect(await reopened.count(allowedChatIDs: [-1001]) == 0)
    }

    @Test("прерванная смена бота чистит вторичные копии до commit primary")
    func interruptedBotChangeCleansSensitiveCopiesBeforeCommit() async throws {
        enum Interruption: Error, Equatable { case afterCleanup }
        let (root, file) = location()
        defer { try? FileManager.default.removeItem(at: root) }
        let healthy = TelegramMessageArchive(fileURL: file)
        try await healthy.activate(botID: 44)
        try await healthy.ingest(
            .init(messages: [message(update: 100, text: "Секрет старого бота")],
                  nextOffset: 101),
            allowedChatIDs: [-1001]
        )
        try await healthy.ingest(
            .init(messages: [message(update: 101, id: 8, text: "Ещё старый секрет")],
                  nextOffset: 102),
            allowedChatIDs: [-1001]
        )

        let recovery = OrakulAtomicFile.recoveryURL(for: file)
        let stale = OrakulAtomicFile.stagingURL(for: file)
        try Data("sensitive interrupted write".utf8).write(to: stale)
        let primaryBefore = try Data(contentsOf: file)
        #expect(FileManager.default.fileExists(atPath: recovery.path))

        let interrupted = TelegramMessageArchive(
            fileURL: file,
            synchronizeDirectory: { _ in throw Interruption.afterCleanup }
        )
        await #expect(throws: Interruption.afterCleanup) {
            try await interrupted.activate(botID: 55)
        }

        // The synchronization failure occurs after old secondary copies were
        // removed but before the atomic primary replacement. Thus the caller
        // sees failure, the coherent old primary remains, and no hidden copy of
        // its content survives outside that primary.
        #expect(try Data(contentsOf: file) == primaryBefore)
        #expect(!FileManager.default.fileExists(atPath: recovery.path))
        #expect(!FileManager.default.fileExists(atPath: stale.path))
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(!names.contains { $0.hasSuffix(".tmp") })
    }

    @Test("сужение allowlist не оставляет удалённый чат в recovery")
    func allowlistPruningDoesNotRetainRemovedChat() async throws {
        let (root, file) = location()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = TelegramMessageArchive(fileURL: file)
        try await archive.activate(botID: 44)
        try await archive.ingest(.init(messages: [
            message(update: 60, chat: -1001, text: "Разрешённый чат"),
            message(update: 61, chat: -2002, id: 8, text: "Удалённый секрет"),
        ], nextOffset: 62), allowedChatIDs: [-1001, -2002])

        try await archive.activate(botID: 44, allowedChatIDs: [-1001])

        #expect(await archive.count(allowedChatIDs: [-1001, -2002]) == 1)
        #expect(!FileManager.default.fileExists(
            atPath: OrakulAtomicFile.recoveryURL(for: file).path))
        let reopened = TelegramMessageArchive(fileURL: file)
        #expect((await reopened.search("секрет", allowedChatIDs: [-1001, -2002])).isEmpty)
    }

    @Test("reset удаляет primary, recovery и след оборванной записи")
    func resetErasesEveryOwnedArtifact() async throws {
        let (root, file) = location()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = TelegramMessageArchive(fileURL: file)
        try await archive.activate(botID: 44)
        try await archive.ingest(
            .init(messages: [message(update: 70, text: "Секрет")], nextOffset: 71),
            allowedChatIDs: [-1001]
        )
        let recovery = OrakulAtomicFile.recoveryURL(for: file)
        let staging = OrakulAtomicFile.stagingURL(for: file)
        try Data("private crash remnant".utf8).write(to: staging)

        try await archive.reset()

        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(!FileManager.default.fileExists(atPath: recovery.path))
        #expect(!FileManager.default.fileExists(atPath: staging.path))
        let reopened = TelegramMessageArchive(fileURL: file)
        #expect(await reopened.count(allowedChatIDs: [-1001]) == 0)
    }

    @Test("ошибка удаления recovery видна и не удаляет primary")
    func resetFailurePreservesPrimary() async throws {
        enum RemovalFailure: Error, Equatable { case denied }
        let (root, file) = location()
        defer { try? FileManager.default.removeItem(at: root) }
        let healthy = TelegramMessageArchive(fileURL: file)
        try await healthy.activate(botID: 44)
        try await healthy.ingest(
            .init(messages: [message(update: 80, text: "Остаётся")], nextOffset: 81),
            allowedChatIDs: [-1001]
        )
        let recovery = OrakulAtomicFile.recoveryURL(for: file)
        let failing = TelegramMessageArchive(fileURL: file, removeItem: { candidate in
            if candidate.standardizedFileURL == recovery.standardizedFileURL {
                throw RemovalFailure.denied
            }
            try FileManager.default.removeItem(at: candidate)
        })

        await #expect(throws: RemovalFailure.denied) { try await failing.reset() }
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: recovery.path))
        let reopened = TelegramMessageArchive(fileURL: file)
        #expect((await reopened.search("Остаётся", allowedChatIDs: [-1001])).count == 1)
    }

    @Test("нечитаемый архив нельзя молча перезаписать пустым снимком")
    func corruptArchiveFailsBeforeOverwrite() async throws {
        let (root, file) = location()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file)

        let archive = TelegramMessageArchive(fileURL: file)
        await #expect(throws: (any Error).self) {
            try await archive.activate(botID: 44)
        }
        #expect(try Data(contentsOf: file) == Data("not json".utf8))
    }
}
