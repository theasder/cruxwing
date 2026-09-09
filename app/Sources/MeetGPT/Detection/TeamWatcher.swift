import Foundation
import UserNotifications

/// Channel watcher — the "bot" over the token connectors: scans the designated
/// Slack channels (SLACK_CHANNEL_IDS) for
/// the user's keyword rules, and on a NEW match:
///   1. posts a local notification,
///   2. appends an auditable line to team-watch.log (Application Support),
///   3. optionally auto-acknowledges into the channel (TEAM_WATCH_AUTO_ACK=on).
/// Poll cadence ~60 s; matches are deduplicated by channel+timestamp.
@MainActor
final class TeamWatcher: ObservableObject {
    static let shared = TeamWatcher()

    @Published private(set) var isRunning = false
    @Published private(set) var matchCount = 0

    private var task: Task<Void, Never>?
    /// Newest handled timestamp per service:channel — only NEWER items match.
    private var lastSeen: [String: Date] = [:]
    private static let interval: TimeInterval = 60

    func apply() {
        if Config.teamWatchEnabled, !Config.teamWatchKeywords.isEmpty { start() } else { stop() }
    }

    private func start() {
        guard task == nil else { return }
        isRunning = true
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.scan()
                try? await Task.sleep(nanoseconds: UInt64(Self.interval * 1_000_000_000))
            }
        }
    }

    private func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    private func scan() async {
        let keywords = Config.teamWatchKeywords
        guard !keywords.isEmpty else { return }

        for service in [TeamService.slack] where service.isConfigured {
            let items = await TeamConnectors.recentMessages(service)
            for (channel, channelItems) in Dictionary(grouping: items, by: \.channel) {
                let key = "\(service.rawValue):\(channel)"
                let selection = Self.selectNewItems(
                    channelItems, after: lastSeen[key])
                if let highWatermark = selection.highWatermark {
                    lastSeen[key] = highWatermark
                }
                for item in selection.items {
                    let text = item.text.lowercased()
                    guard let hit = keywords.first(where: { text.contains($0) }) else { continue }
                    await handleMatch(item, keyword: hit, service: service)
                }
            }
        }
    }

    /// Slack returns channel history newest-first. Advancing the high-water
    /// mark while iterating that wire order used to accept only the newest new
    /// message and silently discard every other message in the same poll. This
    /// pure selector establishes the first-scan baseline, then returns every
    /// unseen item oldest-first so notifications remain chronological.
    nonisolated static func selectNewItems(
        _ items: [TeamItem], after lastSeen: Date?
    ) -> (items: [TeamItem], highWatermark: Date?) {
        let newest = items.map(\.timestamp).max()
        guard let lastSeen else { return ([], newest) }
        let unseen = items
            .filter { $0.timestamp > lastSeen }
            .sorted { $0.timestamp < $1.timestamp }
        return (unseen, max(lastSeen, newest ?? lastSeen))
    }

    private func handleMatch(_ item: TeamItem, keyword: String, service: TeamService) async {
        matchCount += 1

        // 1. Notification
        let content = UNMutableNotificationContent()
        content.title = "\(service.label): “\(keyword)” in \(item.channel)"
        content.body = String(item.text.prefix(140))
        content.sound = .default
        try? await UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))

        // 2. Audit log (kept short — this is a plaintext file on disk)
        Self.audit("\(iso(item.timestamp)) [\(service.rawValue)#\(item.channel)] keyword=\(keyword) author=\(item.author) text=\(item.text.prefix(140))")

        // 3. Optional automated response
        if Config.teamWatchAutoAck {
            await TeamConnectors.post(service, channel: item.channel,
                                      // Это сообщение УХОДИТ В ЧАТ КОМАНДЫ и
                                      // видно всем, включая владельца сервиса.
                                      // Стояло чужое имя продукта, и
                                      // по-английски — в русской переписке.
                                      text: "⚑ orakul: the word «\(keyword)» was spotted — the team was notified.")
        }
    }

    // MARK: - Audit trail

    static var auditLogURL: URL {
        let url = OrakulApplicationSupport.teamWatchAuditLogURL
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return url
    }

    /// Cap the plaintext audit log so an archive of third-party message text
    /// can't grow without bound.
    private static let auditMaxBytes: UInt64 = 512 * 1024

    /// Права 0600 на файле и 0700 на каталоге.
    ///
    /// В этом файле лежит чужая переписка: строки из рабочего чата, куда
    /// человек нас пустил. По умолчанию он создавался с обычными правами —
    /// читать его мог любой процесс, запущенный под тем же пользователем, в том
    /// числе программа, которой доступ к чату никто не давал.
    ///
    /// Соседний DevCallDiagnostics так и делает (0700 на каталог, 0600 на
    /// файл), и здесь это просто не было сделано.
    /// Вход для набора: сама запись приватная, а проверять права надо.
    static func auditForTesting(_ line: String) { audit(line) }

    private static func audit(_ line: String) {
        rotateIfNeeded()
        let url = auditLogURL
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            // Создание и права — одним действием: файл не должен существовать
            // ни мгновения с чужими правами.
            FileManager.default.createFile(atPath: url.path, contents: data,
                                           attributes: [.posixPermissions: 0o600])
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: url.path)
    }

    /// Once the log passes `auditMaxBytes`, move it aside to a single `.1`
    /// backup (overwriting any previous one) and start fresh, so at most
    /// ~2× the cap of message text is ever retained on disk.
    private static func rotateIfNeeded() {
        let url = auditLogURL
        let fm = FileManager.default
        guard let size = (try? fm.attributesOfItem(atPath: url.path)[.size]) as? UInt64,
              size > auditMaxBytes else { return }
        let rotated = url.appendingPathExtension("1")
        try? fm.removeItem(at: rotated)
        try? fm.moveItem(at: url, to: rotated)
    }

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
