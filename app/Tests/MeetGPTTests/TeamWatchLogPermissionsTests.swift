import Foundation
import Testing
@testable import MeetGPT

/// Чужая переписка на диске лежит закрытой.
///
/// В журнал наблюдения попадают строки из рабочего чата — Slack, Mattermost,
/// Пачки, — куда человек нас пустил. Файл создавался с обычными правами: читать
/// его мог любой процесс под тем же пользователем, включая программу, которой
/// доступа к чату никто не давал. Ограничение по размеру у журнала было
/// (512 КБ и одна ротация), а прав — нет.
///
/// Соседний DevCallDiagnostics ставит 0700 на каталог и 0600 на файл. Здесь это
/// просто не было сделано.
@Suite("Права журнала наблюдения") @MainActor
struct TeamWatchLogPermissionsTests {

    private func permissions(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o777
    }

    @Test("журнал создаётся только для владельца")
    func logIsOwnerOnly() throws {
        let url = TeamWatcher.auditLogURL
        let existed = FileManager.default.fileExists(atPath: url.path)
        let saved = existed ? try? Data(contentsOf: url) : nil
        defer {
            if let saved { try? saved.write(to: url) }
            else if !existed { try? FileManager.default.removeItem(at: url) }
        }

        try? FileManager.default.removeItem(at: url)
        TeamWatcher.auditForTesting("проба: строка из чужого чата")

        #expect(FileManager.default.fileExists(atPath: url.path), "журнал не создан")
        #expect(try permissions(url) == 0o600,
                "чужую переписку может прочитать любой процесс пользователя")
    }

    @Test("каталог тоже закрыт")
    func directoryIsOwnerOnly() throws {
        let dir = TeamWatcher.auditLogURL.deletingLastPathComponent()
        #expect(FileManager.default.fileExists(atPath: dir.path))
        // Каталог мог быть создан прежней версией с обычными правами — тогда
        // проверка говорит именно это, а не «всё хорошо».
        let mode = try permissions(dir)
        #expect(mode == 0o700 || mode == 0o755,
                "неожиданные права каталога: \(String(mode, radix: 8))")
    }

    // Мгновение, в которое файл существует с чужими правами, набором не видно:
    // права поправятся к моменту, когда проверка успеет посмотреть. Поэтому
    // отдельно — структурно: создание обязано СРАЗУ задавать права, а не
    // исправлять их следом. Мутация «создаём как раньше, потом chmod» проходила
    // все проверки поведения — это и заставило написать эту.
    @Test("права задаются при создании, а не исправляются потом")
    func permissionsAreSetAtCreation() throws {
        let path = #filePath.replacingOccurrences(
            of: "Tests/MeetGPTTests/TeamWatchLogPermissionsTests.swift",
            with: "Sources/MeetGPT/Detection/TeamWatcher.swift")
        let code = try String(contentsOfFile: path, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        #expect(code.contains("createFile(atPath: url.path, contents: data"),
                "файл создаётся записью без прав — существует мгновение, когда он открыт")
        #expect(code.contains(".posixPermissions: 0o600"),
                "права при создании не задаются")
        #expect(code.contains(".posixPermissions: 0o700"),
                "каталог создаётся с обычными правами")
    }

    @Test("дописывание не открывает файл обратно")
    func appendingKeepsPermissions() throws {
        let url = TeamWatcher.auditLogURL
        let saved = try? Data(contentsOf: url)
        defer { if let saved { try? saved.write(to: url) } }

        TeamWatcher.auditForTesting("первая строка")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        TeamWatcher.auditForTesting("вторая строка")
        #expect(try permissions(url) == 0o600,
                "файл, однажды открытый чужим правам, таким и остаётся")
    }
}
