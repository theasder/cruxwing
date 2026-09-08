import Foundation

/// A finished (or in-progress) meeting session persisted to disk — before this
/// existed, the entire product output (transcript, AI answers, digest) died on
/// quit (launch loop M3). One JSON file per session under Application Support.
struct SavedSession: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var startedAt: Date
    var savedAt: Date
    var goal: String
    /// Optional for recordings saved before tutorials/videos could be labeled.
    /// The explicit selection is persisted; automatic inference can be
    /// recomputed from the saved title when the session is reopened.
    var recordingContext: RecordingContextSelection? = nil
    var entries: [TranscriptEntry]
    /// Uniform engine for sessions recorded entirely on one backend. Optional
    /// for old files and mixed-engine calls; entries carry exact provenance.
    var transcriptionEngine: TranscriptionEngine? = nil
    var aiResponse: String
    /// Optional for backward compatibility with sessions saved before answer
    /// provenance and DOCX export were introduced.
    var aiResponsePrompt: String? = nil
    /// Cached LLM-created export title so reopening and re-exporting a session
    /// does not spend another model call.
    var aiResponseExportTitle: String? = nil
    /// Earlier turns of the assistant dialog, oldest first. OPTIONAL, like the
    /// fields above it: Swift's synthesized decoder ignores a property default
    /// for a non-optional type, so a plain `= []` would make every session
    /// saved before this field existed fail to decode.
    var aiHistory: [AIExchange]? = nil
    /// The context panel — imported documents and the free-text notes — as it
    /// stood for THIS meeting. Previously absent entirely, so opening another
    /// call from History left the previous meeting's documents in place and
    /// silently grounded the new one in them.
    ///
    /// Optional for the same reason as the fields above: a synthesized decoder
    /// ignores property defaults for non-optional types, so `= []` would make
    /// every already-saved session fail to load.
    var contextFiles: [ImportedContextFile]? = nil
    var contextNotes: String? = nil
    /// Blind-spot suggestions surfaced during THIS call. They were generated
    /// live and never written down, so every one was lost the moment the call
    /// ended — reopening a meeting from History showed none of the risks and
    /// questions the co-pilot had raised in it.
    ///
    /// Optional like the fields above: a synthesized decoder ignores property
    /// defaults for non-optional types, so `= []` would break every session
    /// already on disk.
    var suggestions: [Suggestion]? = nil
    var digest: String

    // MARK: - Workflow output that used to die with the call
    //
    // Blind spots were persisted; the rest of the co-pilot's output was not.
    // Fact-check verdicts, the two watch notes and the Efficiency Engine's
    // scored action items existed only as live state or as prose inside an
    // answer, so reopening a call from History showed none of them — and the
    // reflection eval, which can only judge what a session records, could not
    // measure the workflows most worth measuring.
    //
    // OPTIONAL for the same reason as every field above: a synthesized decoder
    // ignores property defaults for non-optional types, so `= []` here would
    // fail to decode every session already on disk and take the meeting with it.

    /// Fact-check verdicts for THIS call.
    var factClaims: [FactClaim]? = nil
    /// The rhetoric watch's last note.
    var rhetoricNote: String? = nil
    /// The facilitation watch's last note.
    var facilitationNote: String? = nil
    /// The Efficiency Engine follow-up produced when a decision was filed.
    var followUp: SavedFollowUp? = nil

    /// Sidebar label: the title when set, else the date.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: startedAt)
    }
}

/// Disk store for sessions: one pretty-printed JSON per session, filename =
/// UUID. The root directory is injectable for tests; the shared instance lives
/// in Application Support (works sandboxed and unsandboxed).
struct SessionStore {
    typealias DirectoryContents = @Sendable (URL) throws -> [URL]
    typealias RemoveItem = @Sendable (URL) throws -> Void
    typealias DirectorySynchronizer = @Sendable (URL) throws -> Void

    let root: URL
    private let directoryContents: DirectoryContents
    private let removeItem: RemoveItem
    private let synchronizeDirectory: DirectorySynchronizer

    init(root: URL,
         directoryContents: @escaping DirectoryContents = {
             try FileManager.default.contentsOfDirectory(
                 at: $0, includingPropertiesForKeys: nil)
         },
         removeItem: @escaping RemoveItem = {
             try FileManager.default.removeItem(at: $0)
         },
         synchronizeDirectory: @escaping DirectorySynchronizer = {
             try OrakulAtomicFile.synchronizeDirectory($0)
         }) {
        self.root = root
        self.directoryContents = directoryContents
        self.removeItem = removeItem
        self.synchronizeDirectory = synchronizeDirectory
    }

    static let shared: SessionStore = {
        // The central path helper also redirects tests to a scratch root. Never
        // fall back to the inherited MeetGPT directory: it is shared with the
        // parent product, so its transcripts have no trustworthy owner marker.
        SessionStore(root: OrakulApplicationSupport.sessionsDirectory)
    }()

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func url(for id: UUID) -> URL {
        root.appendingPathComponent("\(id.uuidString).json")
    }

    private struct DecodedSession {
        let session: SavedSession
        let recovered: Bool
    }

    private func decodedSession(at destination: URL) -> DecodedSession? {
        let recovery = OrakulAtomicFile.recoveryURL(for: destination).standardizedFileURL
        for candidate in OrakulAtomicFile.readableCandidates(for: destination) {
            guard let data = try? Data(contentsOf: candidate),
                  let session = try? decoder.decode(SavedSession.self, from: data) else {
                continue
            }
            return DecodedSession(
                session: session,
                recovered: candidate.standardizedFileURL == recovery
            )
        }
        return nil
    }

    /// Write (or overwrite) a session. Errors are surfaced to the caller —
    /// losing a meeting silently is exactly what this store exists to prevent.
    func save(_ session: SavedSession) throws {
        let data = try encoder.encode(session)
        let destination = url(for: session.id)
        let decoded = decodedSession(at: destination)
        let policy: OrakulAtomicFile.RecoveryPolicy
        if decoded?.recovered == true {
            policy = .preserveExistingRecovery
        } else if decoded != nil {
            policy = .replaceRecoveryWithPrimary
        } else {
            // Neither copy is known-good. Commit the complete in-memory session
            // first, then remove corrupt leftovers rather than blessing one as a
            // recovery snapshot.
            policy = .discardPreviousContent
        }
        try OrakulAtomicFile.write(data, to: destination, recoveryPolicy: policy)
    }

    /// All sessions, newest first. Unreadable files are skipped, never fatal.
    func list() -> [SavedSession] { listWithUnreadable().sessions }

    /// Sessions plus every condition that made the archive incomplete: an
    /// unreadable file, a recovery fallback, or a directory-listing failure.
    ///
    /// Пропустить нечитаемый файл — правильно: один испорченный звонок не
    /// должен ронять весь архив. Но пропустить МОЛЧА — нет. Раньше здесь стоял
    /// `compactMap { try? decode }`, и имя такого файла не сохранялось никуда:
    /// приложение отвечало «в сохранённых звонках об этом не говорили» поверх
    /// архива, часть которого не открылась, и человек уходил уверенным, что не
    /// обсуждали.
    ///
    /// Случай не выдуманный: страница зовёт открывать архив руками — «обычные
    /// JSON-файлы, их можно читать и без нас», — а значит, испорченный файл
    /// появится. Командная строка про такой файл уже говорит.
    func listWithUnreadable() -> (sessions: [SavedSession], unreadable: [String]) {
        let files: [URL]
        do {
            files = try directoryContents(root)
        } catch {
            let cocoa = error as NSError
            if cocoa.domain == NSCocoaErrorDomain,
               cocoa.code == NSFileReadNoSuchFileError {
                return ([], [])
            }
            // `DecisionRecallContext` already reports every entry in
            // `unreadable` as an incomplete record. Preserve that path instead
            // of turning an enumeration failure into a confident empty archive.
            return ([], ["archive directory could not be listed: \(error.localizedDescription)"])
        }

        var destinations = Set(files.filter { $0.pathExtension == "json" })
        for file in files {
            if let primary = OrakulAtomicFile.primaryURL(forRecoveryURL: file),
               primary.pathExtension == "json" {
                destinations.insert(primary)
            }
            if let primary = OrakulAtomicFile.primaryURL(forStagingURL: file),
               primary.pathExtension == "json" {
                destinations.insert(primary)
            }
        }

        var sessions: [SavedSession] = []
        var unreadable: [String] = []
        for destination in destinations {
            guard let decoded = decodedSession(at: destination) else {
                unreadable.append(destination.lastPathComponent)
                continue
            }
            sessions.append(decoded.session)
            if decoded.recovered {
                unreadable.append(destination.lastPathComponent + " (opened recovery copy)")
            }
        }
        return (sessions.sorted { $0.startedAt > $1.startedAt }, unreadable.sorted())
    }

    /// Уже импортированный звонок с тем же началом и названием, если он есть.
    ///
    /// Импорт из Fireflies строит `SavedSession(id: UUID(), …)` — каждый раз
    /// новый идентификатор, и внешнего идентификатора встречи в записи не
    /// хранится. Нажать «импортировать» второй раз, не поняв, сработало ли в
    /// первый, — обычное дело, и в архиве появлялась вторая копия.
    ///
    /// Копии не просто занимают место: ответ показывает не больше трёх звонков
    /// (`RecallAnswer.maximumMeetings`), поэтому дубли вытесняют из ответа
    /// РАЗНЫЕ звонки. Та же беда, что была у `orakul добавить`.
    ///
    /// Ключ — начало встречи и название. `startedAt` берётся из самой встречи,
    /// а не из момента импорта (см. `FirefliesPastCalls.session(for:)`), то
    /// есть при повторном импорте он тот же. Двух разных звонков с совпадающей
    /// секундой начала И названием не бывает.
    func alreadyImported(_ candidate: SavedSession) -> SavedSession? {
        list().first { $0.startedAt == candidate.startedAt && $0.title == candidate.title }
    }

    /// Сохранить импортированный звонок — или вернуть уже заведённый.
    ///
    /// Решение живёт здесь, а не в вызывающем: пока оно стояло в `AppState`,
    /// мутация, отключавшая проверку, не роняла ни один тест. Путь импорта
    /// требует сети и менеджера, тестом его не пройти, а проверка «в исходнике
    /// есть слово alreadyImported» не отличает «зовёт» от «зовёт и
    /// игнорирует». Здесь же это обычная функция, и повторный вызов проверяется
    /// напрямую — по тому, сколько файлов легло на диск.
    @discardableResult
    func saveImported(_ session: SavedSession) throws -> SavedSession {
        if let existing = alreadyImported(session) { return existing }
        try save(session)
        return session
    }

    func load(id: UUID) -> SavedSession? {
        decodedSession(at: url(for: id))?.session
    }

    @discardableResult
    func delete(id: UUID) throws -> Bool {
        try OrakulAtomicFile.erase(
            url(for: id),
            directoryContents: directoryContents,
            removeItem: removeItem,
            synchronizeDirectory: synchronizeDirectory
        )
    }

    /// Remove every saved session (the History "clear all" action). Deletes the
    /// JSON files directly so even a corrupt/unlisted file is cleared.
    func deleteAll() throws {
        let files: [URL]
        do {
            files = try directoryContents(root)
        } catch {
            let cocoa = error as NSError
            if cocoa.domain == NSCocoaErrorDomain,
               cocoa.code == NSFileReadNoSuchFileError {
                return
            }
            throw error
        }

        let artifacts = files.filter { file in
            if file.pathExtension == "json" { return true }
            if OrakulAtomicFile.primaryURL(forRecoveryURL: file)?.pathExtension == "json" {
                return true
            }
            return OrakulAtomicFile.primaryURL(forStagingURL: file)?.pathExtension == "json"
        }.sorted { left, right in
            func rank(_ file: URL) -> Int {
                if OrakulAtomicFile.primaryURL(forStagingURL: file) != nil { return 0 }
                if OrakulAtomicFile.primaryURL(forRecoveryURL: file) != nil { return 1 }
                return 2
            }
            return rank(left) < rank(right)
        }

        guard !artifacts.isEmpty else { return }
        for artifact in artifacts { try removeItem(artifact) }
        try synchronizeDirectory(root)
    }
}
