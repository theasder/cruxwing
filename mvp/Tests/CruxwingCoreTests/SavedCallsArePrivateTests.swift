import Testing
import Foundation
@testable import CruxwingCore

/// Сохранённый звонок лежит закрытым.
///
/// «Запись остаётся на вашем компьютере» — главный довод продукта. Про сеть это
/// было правдой с первого дня; на самом компьютере расшифровки создавались с
/// обычными правами, то есть их читал любой процесс под тем же пользователем.
/// Довод означает и это тоже.
@Suite("Права сохранённых звонков")
struct SavedCallsArePrivateTests {

    private func mode(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o777
    }

    private func session(_ id: String) -> RecallIndex.Session {
        RecallIndex.Session(id: id, title: "Планёрка", date: "2026-08-21",
                            digest: "Решили поднять тарифы с декабря.")
    }

    @Test("файл звонка — только для владельца")
    func savedCallIsOwnerOnly() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cruxwing-prava-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionStore(root: root)
        try store.save(session("planerka"))

        let file = root.appendingPathComponent("planerka.json")
        #expect(FileManager.default.fileExists(atPath: file.path), "звонок не сохранился")
        #expect(try mode(file) == 0o600,
                "расшифровку прочитает любой процесс пользователя")
        #expect(try mode(root) == 0o700, "каталог с звонками открыт")
    }

    @Test("перезапись не открывает файл обратно")
    func rewriteKeepsItClosed() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cruxwing-prava-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionStore(root: root)
        try store.save(session("planerka"))
        try store.save(session("planerka"))
        #expect(try mode(root.appendingPathComponent("planerka.json")) == 0o600)
    }

    // Обратная сторона: закрытые права не должны подменять причину отказа.
    // Первая версия бросала здесь свою ошибку вместо системной, и человек вместо
    // «Нет прав на запись» видел «не смог сохранить».
    @Test("настоящая причина отказа доходит до человека")
    func realFailureSurvives() throws {
        let root = URL(fileURLWithPath: "/dev/null/cruxwing")
        let store = SessionStore(root: root)
        #expect(throws: (any Error).self) { try store.save(session("planerka")) }
    }
}
