import Foundation
import Testing
import CruxwingCore
@testable import MeetGPT

/// The rename of 2026-09-09 moved the identity: `ai.orakul.desktop` became
/// `ai.cruxwing.desktop`, and `ORAKUL_*` became `CRUXWING_*`.
///
/// Both carry state that belongs to the person, not to us. A bundle identifier
/// names the Application Support directory, so renaming it without moving the
/// directory leaves every saved call on disk and invisible — the worst shape a
/// migration can fail in, because nothing is lost and everything appears to be.
/// An environment variable lives in somebody's shell profile or CI job, and a
/// renamed one fails by simply not being read.
@Suite("Rename migration")
struct RenameMigrationTests {

    private func makeBase() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("rename-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    @Test("the previous Application Support directory is adopted, with its contents")
    func adoptsTheLegacyRoot() throws {
        let base = try makeBase()
        let legacy = CruxwingApplicationSupport.legacyRoot(in: base)
        let sessions = CruxwingApplicationSupport.sessionsDirectory(under: legacy)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let call = sessions.appendingPathComponent("s1.json")
        try Data("{}".utf8).write(to: call)

        #expect(CruxwingApplicationSupport.adoptLegacyRootIfNeeded(in: base))

        let moved = CruxwingApplicationSupport.sessionsDirectory(
            under: CruxwingApplicationSupport.root(in: base)
        ).appendingPathComponent("s1.json")
        #expect(FileManager.default.fileExists(atPath: moved.path),
                "the saved call did not come with the directory")
        #expect(!FileManager.default.fileExists(atPath: legacy.path),
                "a move, not a copy: two roots would drift apart")
    }

    @Test("an existing directory is never overwritten by the old one")
    func neverClobbersLiveData() throws {
        let base = try makeBase()
        let current = CruxwingApplicationSupport.root(in: base)
        let legacy = CruxwingApplicationSupport.legacyRoot(in: base)
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let live = current.appendingPathComponent("marker")
        try Data("live".utf8).write(to: live)

        #expect(!CruxwingApplicationSupport.adoptLegacyRootIfNeeded(in: base),
                "adoption ran against a root that already exists")
        #expect(try String(contentsOf: live, encoding: .utf8) == "live")
        #expect(FileManager.default.fileExists(atPath: legacy.path),
                "the old directory is left for the person to inspect, not deleted for them")
    }

    @Test("adoption is a no-op when there is nothing to adopt")
    func noLegacyIsNotAFailure() throws {
        #expect(!CruxwingApplicationSupport.adoptLegacyRootIfNeeded(in: try makeBase()))
    }

    @Test("the previous environment variables are still read")
    func legacyEnvironmentStillWorks() {
        #expect(ProductEnvironment.value("HOME", environment: ["ORAKUL_HOME": "/old"]) == "/old")
        #expect(ProductEnvironment.value("HOME", environment: ["CRUXWING_HOME": "/new"]) == "/new")
        // Both set: the current name wins, so a person who has migrated their
        // scripts is not overridden by a stale line further up the profile.
        #expect(ProductEnvironment.value(
            "HOME", environment: ["ORAKUL_HOME": "/old", "CRUXWING_HOME": "/new"]) == "/new")
        #expect(ProductEnvironment.value("HOME", environment: [:]) == nil)
    }

    @Test("previous settings are adopted, and never overwrite current ones")
    func adoptsLegacyPreferences() throws {
        let legacyName = "ai.orakul.desktop.test.\(UUID().uuidString)"
        let currentName = "ai.cruxwing.desktop.test.\(UUID().uuidString)"
        let legacy = try #require(UserDefaults(suiteName: legacyName))
        let current = try #require(UserDefaults(suiteName: currentName))
        defer {
            legacy.removePersistentDomain(forName: legacyName)
            current.removePersistentDomain(forName: currentName)
        }
        legacy.set("whisper", forKey: "transcription.engine")
        legacy.set(true, forKey: "recording.consented")
        current.set("deepgram", forKey: "transcription.engine")

        let adopted = LegacyPreferences.adoptIfNeeded(
            into: current, legacySuiteName: legacyName)

        #expect(adopted >= 1, "nothing was carried over")
        #expect(current.bool(forKey: "recording.consented"),
                "the consent already given was not carried over")
        #expect(current.string(forKey: "transcription.engine") == "deepgram",
                "adoption overwrote a choice made under the new identity")

        // A marker, not emptiness: running again must be a no-op even though the
        // legacy domain still has rows in it.
        #expect(LegacyPreferences.adoptIfNeeded(
            into: current, legacySuiteName: legacyName) == 0,
                "adoption ran a second time")
    }
}
