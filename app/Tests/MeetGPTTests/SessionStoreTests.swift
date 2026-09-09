import Testing
import Foundation
@testable import MeetGPT

/// M3 session persistence: meetings must survive quit. Round-trip the store in
/// a temp directory with an injectable root.
@Suite("Session store")
struct SessionStoreTests {
    private func makeStore() -> SessionStore {
        SessionStore(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("session-store-tests-\(UUID().uuidString)", isDirectory: true))
    }

    /// ISO8601 persists whole seconds — use second-precision dates so Equatable
    /// round-trips exactly.
    private func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    private func sampleSession(title: String, startedAt: Date = Date()) -> SavedSession {
        let now = wholeSeconds(Date())
        return SavedSession(
            id: UUID(), title: title, startedAt: wholeSeconds(startedAt), savedAt: now,
            goal: "close the Q3 renewal",
            entries: [
                TranscriptEntry(source: .mic, text: "we agreed on usage pricing", timestamp: now, speaker: "Sam",
                                transcriptionEngine: .local),
                TranscriptEntry(source: .system, text: "ship before August", timestamp: now, speaker: "Dana",
                                transcriptionEngine: .local),
            ],
            transcriptionEngine: .local,
            aiResponse: "## TL;DR\n- pricing decided",
            aiResponsePrompt: "Summarize the pricing decision.",
            aiResponseExportTitle: "Q3 Pricing Decision",
            digest: "• decided usage pricing")
    }

    @Test("save → list → load round-trips every field")
    func roundTrip() throws {
        let store = makeStore()
        let session = sampleSession(title: "Pricing sync")
        try store.save(session)

        let listed = store.list()
        #expect(listed.count == 1)
        #expect(listed[0] == session)

        let loaded = store.load(id: session.id)
        #expect(loaded?.entries.count == 2)
        #expect(loaded?.entries[0].speaker == "Sam")
        #expect(loaded?.entries[1].source == .system)
        #expect(loaded?.entries[0].transcriptionEngine == .local)
        #expect(loaded?.transcriptionEngine == .local)
        #expect(loaded?.digest == "• decided usage pricing")
        #expect(loaded?.aiResponsePrompt == "Summarize the pricing decision.")
        #expect(loaded?.aiResponseExportTitle == "Q3 Pricing Decision")
    }

    @Test("sessions saved before DOCX provenance still decode")
    func legacySessionCompatibility() throws {
        let store = makeStore()
        let session = sampleSession(title: "Legacy")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(session)) as? [String: Any])
        object.removeValue(forKey: "aiResponsePrompt")
        object.removeValue(forKey: "aiResponseExportTitle")
        try FileManager.default.createDirectory(at: store.root, withIntermediateDirectories: true)
        let url = store.root.appendingPathComponent("\(session.id.uuidString).json")
        try JSONSerialization.data(withJSONObject: object).write(to: url)

        let loaded = try #require(store.load(id: session.id))
        #expect(loaded.aiResponse == session.aiResponse)
        #expect(loaded.aiResponsePrompt == nil)
        #expect(loaded.aiResponseExportTitle == nil)
    }

    @Test("list orders newest first; delete removes the file")
    func orderingAndDelete() throws {
        let store = makeStore()
        let older = sampleSession(title: "older", startedAt: Date(timeIntervalSinceNow: -3600))
        let newer = sampleSession(title: "newer")
        try store.save(older)
        try store.save(newer)

        #expect(store.list().map(\.title) == ["newer", "older"])

        try store.delete(id: newer.id)
        #expect(store.list().map(\.title) == ["older"])
        #expect(store.load(id: newer.id) == nil)
    }

    @Test("deleteAll removes every saved session (History → Clear all)")
    func clearAll() throws {
        let store = makeStore()
        try store.save(sampleSession(title: "a"))
        try store.save(sampleSession(title: "b"))
        try store.save(sampleSession(title: "c"))
        #expect(store.list().count == 3)

        try store.deleteAll()
        #expect(store.list().isEmpty)
    }

    @Test("re-saving the same id overwrites instead of duplicating")
    func overwrite() throws {
        let store = makeStore()
        var session = sampleSession(title: "v1")
        try store.save(session)
        session.aiResponse = "updated after post-call summarize"
        session.title = "v2"
        try store.save(session)

        let listed = store.list()
        #expect(listed.count == 1)
        #expect(listed[0].title == "v2")
        #expect(listed[0].aiResponse.contains("updated"))
    }

    @Test("overwrite keeps a restricted recovery copy and can read it")
    func atomicOverwriteRecovery() throws {
        let store = makeStore()
        var session = sampleSession(title: "recoverable v1")
        try store.save(session)
        session.title = "current v2"
        try store.save(session)

        let destination = store.root.appendingPathComponent("\(session.id.uuidString).json")
        let recovery = CruxwingAtomicFile.recoveryURL(for: destination)
        #expect(FileManager.default.fileExists(atPath: recovery.path))

        try Data("interrupted write".utf8).write(to: destination)
        #expect(store.load(id: session.id)?.title == "recoverable v1")
        let recoveredArchive = store.listWithUnreadable()
        #expect(recoveredArchive.sessions.map(\.title) == ["recoverable v1"])
        #expect(recoveredArchive.unreadable == [
            "\(session.id.uuidString).json (opened recovery copy)"
        ])

        let attributes = try FileManager.default.attributesOfItem(atPath: recovery.path)
        #expect(attributes[.posixPermissions] as? Int == 0o600)
        let directoryAttributes = try FileManager.default.attributesOfItem(
            atPath: store.root.path)
        #expect(directoryAttributes[.posixPermissions] as? Int == 0o700)
        let names = try FileManager.default.contentsOfDirectory(atPath: store.root.path)
        #expect(!names.contains { $0.hasSuffix(".tmp") })

        try store.delete(id: session.id)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(!FileManager.default.fileExists(atPath: recovery.path))
    }

    @Test("a save after fallback keeps the known-good recovery")
    func mutationAfterRecoveryDoesNotBackUpCorruption() throws {
        let store = makeStore()
        var session = sampleSession(title: "known good v1")
        try store.save(session)
        session.title = "current v2"
        try store.save(session)

        let destination = store.root.appendingPathComponent("\(session.id.uuidString).json")
        let recovery = CruxwingAtomicFile.recoveryURL(for: destination)
        try Data("damaged primary".utf8).write(to: destination)
        #expect(store.load(id: session.id)?.title == "known good v1")

        session.title = "committed v3"
        try store.save(session)
        #expect(store.load(id: session.id)?.title == "committed v3")

        // A second damaged primary must still fall back to the last known-good
        // copy, not to the corrupt primary that the v3 save replaced.
        try Data("damaged again".utf8).write(to: destination)
        #expect(store.load(id: session.id)?.title == "known good v1")
        #expect(try Data(contentsOf: recovery) != Data("damaged primary".utf8))
    }

    @Test("clear all erases primaries, recovery copies, and crash staging files")
    func clearAllErasesEveryOwnedArtifact() throws {
        let store = makeStore()
        var session = sampleSession(title: "private v1")
        try store.save(session)
        session.title = "private v2"
        try store.save(session)

        let destination = store.root.appendingPathComponent("\(session.id.uuidString).json")
        let recovery = CruxwingAtomicFile.recoveryURL(for: destination)
        let staging = CruxwingAtomicFile.stagingURL(for: destination)
        try Data("private crash remnant".utf8).write(to: staging)
        let unrelated = store.root.appendingPathComponent("keep.txt")
        try Data("not a session".utf8).write(to: unrelated)

        try store.deleteAll()

        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(!FileManager.default.fileExists(atPath: recovery.path))
        #expect(!FileManager.default.fileExists(atPath: staging.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
    }

    @Test("failed recovery deletion is surfaced before the primary is removed")
    func deletionFailurePreservesPrimary() throws {
        enum RemovalFailure: Error, Equatable { case denied }
        let healthy = makeStore()
        var session = sampleSession(title: "v1")
        try healthy.save(session)
        session.title = "v2"
        try healthy.save(session)
        let destination = healthy.root.appendingPathComponent("\(session.id.uuidString).json")
        let recovery = CruxwingAtomicFile.recoveryURL(for: destination)
        let failing = SessionStore(root: healthy.root, removeItem: { candidate in
            if candidate.standardizedFileURL == recovery.standardizedFileURL {
                throw RemovalFailure.denied
            }
            try FileManager.default.removeItem(at: candidate)
        })

        #expect(throws: RemovalFailure.denied) {
            try failing.delete(id: session.id)
        }
        #expect(FileManager.default.fileExists(atPath: destination.path))
        #expect(FileManager.default.fileExists(atPath: recovery.path))
    }

    @Test("clear all surfaces directory enumeration failure")
    func clearAllListingFailureIsVisible() throws {
        enum ListingFailure: Error, Equatable { case denied }
        let healthy = makeStore()
        let session = sampleSession(title: "still here")
        try healthy.save(session)
        let failing = SessionStore(root: healthy.root, directoryContents: { _ in
            throw ListingFailure.denied
        })

        #expect(throws: ListingFailure.denied) { try failing.deleteAll() }
        #expect(healthy.load(id: session.id) != nil)
    }

    @Test("a committed replacement synchronizes its containing directory")
    func replacementSynchronizesDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("atomic-sync-\(UUID().uuidString)", isDirectory: true)
        let destination = root.appendingPathComponent("snapshot.json")
        defer { try? FileManager.default.removeItem(at: root) }
        var synchronized: [URL] = []

        try CruxwingAtomicFile.write(
            Data("snapshot".utf8),
            to: destination,
            recoveryPolicy: .discardPreviousContent,
            synchronizeDirectory: { synchronized.append($0) }
        )

        #expect(synchronized.contains(root))
    }

    @Test("History state exposes a directory listing failure")
    @MainActor
    func appStateShowsListingFailure() throws {
        enum ListingFailure: Error { case denied }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-warning-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SessionStore(root: root, directoryContents: { _ in
            throw ListingFailure.denied
        })

        let state = AppState(llm: MockLLMGateway(response: ""), sessionStore: store)
        #expect(state.savedSessions.isEmpty)
        #expect(state.historyStorageWarning?.contains("did not open in full") == true)
    }

    @Test("listing failure is not reported as a legitimately empty archive")
    func listingFailureIsVisible() throws {
        enum ListingFailure: Error { case denied }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-store-listing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SessionStore(root: root, directoryContents: { _ in
            throw ListingFailure.denied
        })

        let result = store.listWithUnreadable()
        #expect(result.sessions.isEmpty)
        #expect(result.unreadable.count == 1)
        #expect(result.unreadable[0].contains("could not be listed"))

        let legitimatelyEmpty = makeStore().listWithUnreadable()
        #expect(legitimatelyEmpty.sessions.isEmpty)
        #expect(legitimatelyEmpty.unreadable.isEmpty)
    }

    @Test("production storage never falls back to a temporary directory")
    func applicationSupportResolution() throws {
        let temporary = URL(fileURLWithPath: "/private/tmp/cruxwing-explicit-test")
        #expect(throws: CruxwingApplicationSupport.ResolutionError.self) {
            _ = try CruxwingApplicationSupport.resolvedRoot(
                applicationSupportDirectory: nil,
                isUnderTest: false,
                temporaryDirectory: temporary
            )
        }

        let testRoot = try CruxwingApplicationSupport.resolvedRoot(
            applicationSupportDirectory: nil,
            isUnderTest: true,
            temporaryDirectory: temporary
        )
        #expect(testRoot.path.hasPrefix(temporary.path))
        #expect(testRoot.lastPathComponent == CruxwingApplicationSupport.directoryName)
    }

    @Test("displayTitle falls back to the date when the title is blank")
    func displayTitle() {
        let untitled = sampleSession(title: "   ")
        #expect(!untitled.displayTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        #expect(sampleSession(title: "Named").displayTitle == "Named")
    }
}
