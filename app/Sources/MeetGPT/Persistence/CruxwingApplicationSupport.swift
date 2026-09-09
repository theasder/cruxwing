import Foundation
import Darwin

/// The sole root for Cruxwing-owned files in Application Support.
///
/// The inherited `Application Support/MeetGPT` directory is shared with the
/// parent product and does not identify which application wrote a file. It is
/// deliberately never read or migrated automatically here: importing that
/// directory without an explicit user choice could expose another product's
/// transcripts and connected-service messages inside Cruxwing.
enum CruxwingApplicationSupport {
    enum ResolutionError: LocalizedError {
        case applicationSupportUnavailable

        var errorDescription: String? {
            switch self {
            case .applicationSupportUnavailable:
                return "macOS provided no user Application Support directory; "
                    + "Cruxwing does not redirect personal data into a temporary folder."
            }
        }
    }

    static let directoryName = "ai.cruxwing.desktop"

    /// Where every build wrote until the product took one name on 2026-09-09.
    ///
    /// Renaming the bundle identifier moves the Application Support directory
    /// with it, and a person who upgrades would find an empty History: the calls
    /// are still on disk, under a directory the new build never looks in. That
    /// is the worst shape a rename can take — nothing is lost, and everything
    /// appears to be.
    static let legacyDirectoryName = "ai.orakul.desktop"

    static func root(in baseDirectory: URL) -> URL {
        baseDirectory.appendingPathComponent(directoryName, isDirectory: true)
    }

    static func legacyRoot(in baseDirectory: URL) -> URL {
        baseDirectory.appendingPathComponent(legacyDirectoryName, isDirectory: true)
    }

    /// Adopts the previous directory when this build has none of its own.
    ///
    /// A move, not a copy: two roots would drift, and the second one to be
    /// written would silently become the loser. Guarded on the new root being
    /// absent, so it runs exactly once and can never overwrite live data —
    /// if both exist, the current one wins and the old one is left untouched
    /// for the person to inspect rather than deleted on their behalf.
    ///
    /// Failure is not fatal and not silent: the build carries on with an empty
    /// root, which is the same state it would have had without this migration,
    /// and the reason is logged.
    @discardableResult
    static func adoptLegacyRootIfNeeded(
        in baseDirectory: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        let current = root(in: baseDirectory)
        let legacy = legacyRoot(in: baseDirectory)
        guard !fileManager.fileExists(atPath: current.path),
              fileManager.fileExists(atPath: legacy.path) else { return false }
        do {
            try fileManager.moveItem(at: legacy, to: current)
            return true
        } catch {
            Log.general.error(
                "Could not adopt the previous Application Support directory: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static func sessionsDirectory(under root: URL) -> URL {
        root.appendingPathComponent("Sessions", isDirectory: true)
    }

    static func telegramArchiveURL(under root: URL) -> URL {
        root.appendingPathComponent("Telegram", isDirectory: true)
            .appendingPathComponent("messages.json", isDirectory: false)
    }

    static func teamWatchAuditLogURL(under root: URL) -> URL {
        root.appendingPathComponent("team-watch.log", isDirectory: false)
    }

    /// Resolves the live root without ever treating OS temporary storage as a
    /// durable home. The parameters are explicit so the failure and test paths
    /// can be exercised without changing process-global `FileManager` state.
    static func resolvedRoot(applicationSupportDirectory: URL?,
                             isUnderTest: Bool,
                             temporaryDirectory: URL) throws -> URL {
        if isUnderTest {
            let base = temporaryDirectory
            .appendingPathComponent("cruxwing-tests", isDirectory: true)
            return root(in: base)
        }
        guard let applicationSupportDirectory else {
            throw ResolutionError.applicationSupportUnavailable
        }
        // Before handing the root out, take over the previous one if this build
        // has none. Done here rather than at launch because every store resolves
        // through this function, so there is no ordering to get wrong.
        adoptLegacyRootIfNeeded(in: applicationSupportDirectory)
        return root(in: applicationSupportDirectory)
    }

    static var activeRoot: URL {
        do {
            return try resolvedRoot(
                applicationSupportDirectory: FileManager.default.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                ).first,
                isUnderTest: AppState.isUnderTest,
                temporaryDirectory: FileManager.default.temporaryDirectory
            )
        } catch {
            // Shared stores cannot make their root throwing without changing
            // every feature constructor. A loud launch failure is preferable
            // to claiming durability while silently writing private records to
            // a purgeable temporary directory.
            fatalError(error.localizedDescription)
        }
    }

    static var sessionsDirectory: URL {
        sessionsDirectory(under: activeRoot)
    }

    static var telegramArchiveURL: URL {
        telegramArchiveURL(under: activeRoot)
    }

    static var teamWatchAuditLogURL: URL {
        teamWatchAuditLogURL(under: activeRoot)
    }
}

/// Writes private JSON snapshots without exposing a partially-written target.
/// The staging file and retained recovery copy live beside the destination, so
/// replacement stays on one volume and both inherit an explicitly restricted
/// mode rather than whatever umask happens to be active.
enum CruxwingAtomicFile {
    enum RecoveryPolicy: Equatable {
        /// The current primary decoded successfully and becomes the next
        /// recovery copy after replacement.
        case replaceRecoveryWithPrimary
        /// The primary is damaged or absent, while the existing recovery copy
        /// is the last known-good state. Commit the new primary without touching
        /// that recovery copy.
        case preserveExistingRecovery
        /// The state transition intentionally removes old content (disconnect,
        /// bot change, allowlist pruning). Erase older recovery/staging copies
        /// before atomically replacing the still-valid primary.
        case discardPreviousContent
    }

    typealias DirectoryContents = (URL) throws -> [URL]
    typealias RemoveItem = (URL) throws -> Void
    typealias DirectorySynchronizer = (URL) throws -> Void

    static let privateDirectoryPermissions = 0o700
    static let privateFilePermissions = 0o600
    private static let recoverySuffix = ".recovery"

    static func recoveryURL(for destination: URL) -> URL {
        destination.deletingLastPathComponent().appendingPathComponent(
            destination.lastPathComponent + recoverySuffix,
            isDirectory: false
        )
    }

    static func primaryURL(forRecoveryURL recoveryURL: URL) -> URL? {
        let name = recoveryURL.lastPathComponent
        guard name.hasSuffix(recoverySuffix) else { return nil }
        return recoveryURL.deletingLastPathComponent().appendingPathComponent(
            String(name.dropLast(recoverySuffix.count)),
            isDirectory: false
        )
    }

    static func stagingURL(for destination: URL, identifier: UUID = UUID()) -> URL {
        destination.deletingLastPathComponent().appendingPathComponent(
            ".\(destination.lastPathComponent).\(identifier.uuidString).tmp",
            isDirectory: false
        )
    }

    static func primaryURL(forStagingURL stagingURL: URL) -> URL? {
        let name = stagingURL.lastPathComponent
        guard name.hasPrefix("."), name.hasSuffix(".tmp") else { return nil }
        let withoutMarkers = String(name.dropFirst().dropLast(".tmp".count))
        guard let separator = withoutMarkers.lastIndex(of: ".") else { return nil }
        let identifier = String(withoutMarkers[withoutMarkers.index(after: separator)...])
        guard UUID(uuidString: identifier) != nil else { return nil }
        let primaryName = String(withoutMarkers[..<separator])
        guard !primaryName.isEmpty else { return nil }
        return stagingURL.deletingLastPathComponent().appendingPathComponent(
            primaryName, isDirectory: false)
    }

    static func readableCandidates(for destination: URL,
                                   fileManager: FileManager = .default) -> [URL] {
        [destination, recoveryURL(for: destination)].filter {
            fileManager.fileExists(atPath: $0.path)
        }
    }

    /// Removes every private artifact owned by one logical snapshot. Staging
    /// and recovery files go first, so a partial failure leaves the current
    /// primary visible instead of resurrecting an older copy on relaunch.
    @discardableResult
    static func erase(
        _ destination: URL,
        directoryContents: DirectoryContents = {
            try FileManager.default.contentsOfDirectory(
                at: $0, includingPropertiesForKeys: nil)
        },
        removeItem: RemoveItem = { try FileManager.default.removeItem(at: $0) },
        synchronizeDirectory: DirectorySynchronizer = {
            try CruxwingAtomicFile.synchronizeDirectory($0)
        }
    ) throws -> Bool {
        let directory = destination.deletingLastPathComponent()
        let files: [URL]
        do {
            files = try directoryContents(directory)
        } catch {
            if isMissingFileError(error) { return false }
            throw error
        }

        let recovery = recoveryURL(for: destination).standardizedFileURL
        let primary = destination.standardizedFileURL
        let owned = files.filter { candidate in
            let standardized = candidate.standardizedFileURL
            return standardized == primary
                || standardized == recovery
                || primaryURL(forStagingURL: candidate)?.standardizedFileURL == primary
        }.sorted { artifactRank($0, primary: primary) < artifactRank($1, primary: primary) }

        guard !owned.isEmpty else { return false }
        for candidate in owned { try removeItem(candidate) }
        try synchronizeDirectory(directory)
        return true
    }

    /// The file's bytes are synchronized before replacement. The directory is
    /// synchronized after every namespace mutation so a successful return also
    /// covers the rename/backup entries, not only the staging file's contents.
    static func synchronizeDirectory(_ directory: URL) throws {
        let descriptor = open(directory.path, O_RDONLY)
        guard descriptor >= 0 else { throw posixError() }
        defer { _ = close(descriptor) }
        guard fsync(descriptor) == 0 else { throw posixError() }
    }

    static func write(_ data: Data, to destination: URL,
                      recoveryPolicy: RecoveryPolicy,
                      fileManager: FileManager = .default,
                      synchronizeDirectory: DirectorySynchronizer = {
                          try CruxwingAtomicFile.synchronizeDirectory($0)
                      }) throws {
        let directory = destination.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: privateDirectoryPermissions]
        )
        try fileManager.setAttributes(
            [.posixPermissions: privateDirectoryPermissions],
            ofItemAtPath: directory.path
        )

        // A process may have died after synchronizing an earlier staging file.
        // Remember those exact same-target remnants and remove them only after
        // the new primary commits; until then they remain possible forensic
        // material rather than being destroyed ahead of a failed save.
        let staleStaging = try fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ).filter {
            primaryURL(forStagingURL: $0)?.standardizedFileURL
                == destination.standardizedFileURL
        }

        let stagingURL = stagingURL(for: destination)
        guard fileManager.createFile(
            atPath: stagingURL.path,
            contents: nil,
            attributes: [.posixPermissions: privateFilePermissions]
        ) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: stagingURL.path])
        }
        var stagingStillExists = true
        defer {
            if stagingStillExists { try? fileManager.removeItem(at: stagingURL) }
        }

        let handle = try FileHandle(forWritingTo: stagingURL)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }

        let recoveryURL = recoveryURL(for: destination)
        if recoveryPolicy == .discardPreviousContent {
            // Do not create a crash window in which the reduced primary is
            // durable but an excluded chat or previous bot still survives in a
            // recovery/staging copy. The current primary stays untouched until
            // cleanup has completed and its directory entry is synchronized, so
            // a cleanup failure still leaves one coherent pre-transition state.
            var removedSensitiveArtifact = false
            if fileManager.fileExists(atPath: recoveryURL.path) {
                try fileManager.removeItem(at: recoveryURL)
                removedSensitiveArtifact = true
            }
            for stale in staleStaging where fileManager.fileExists(atPath: stale.path) {
                try fileManager.removeItem(at: stale)
                removedSensitiveArtifact = true
            }
            if removedSensitiveArtifact { try synchronizeDirectory(directory) }
        }

        if fileManager.fileExists(atPath: destination.path) {
            // Restrict a legacy destination before replacement. Depending on
            // policy it may become the retained recovery copy.
            try fileManager.setAttributes(
                [.posixPermissions: privateFilePermissions],
                ofItemAtPath: destination.path
            )
            switch recoveryPolicy {
            case .replaceRecoveryWithPrimary:
                if fileManager.fileExists(atPath: recoveryURL.path) {
                    try fileManager.removeItem(at: recoveryURL)
                    try synchronizeDirectory(directory)
                }
                _ = try fileManager.replaceItemAt(
                    destination,
                    withItemAt: stagingURL,
                    backupItemName: recoveryURL.lastPathComponent,
                    options: [.withoutDeletingBackupItem]
                )
            case .preserveExistingRecovery, .discardPreviousContent:
                _ = try fileManager.replaceItemAt(
                    destination,
                    withItemAt: stagingURL,
                    backupItemName: nil,
                    options: []
                )
            }
        } else {
            try fileManager.moveItem(at: stagingURL, to: destination)
        }
        stagingStillExists = false
        try synchronizeDirectory(directory)

        if recoveryPolicy != .discardPreviousContent {
            var removedStaging = false
            for stale in staleStaging where fileManager.fileExists(atPath: stale.path) {
                try fileManager.removeItem(at: stale)
                removedStaging = true
            }
            if removedStaging { try synchronizeDirectory(directory) }
        }
    }

    private static func artifactRank(_ candidate: URL, primary: URL) -> Int {
        let standardized = candidate.standardizedFileURL
        if primaryURL(forStagingURL: candidate) != nil { return 0 }
        if standardized == recoveryURL(for: primary).standardizedFileURL { return 1 }
        return 2
    }

    private static func isMissingFileError(_ error: Error) -> Bool {
        let cocoa = error as NSError
        return cocoa.domain == NSCocoaErrorDomain
            && cocoa.code == NSFileReadNoSuchFileError
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
