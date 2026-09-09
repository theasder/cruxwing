import Foundation
import Testing
@testable import MeetGPT

/// Приложение называется cruxwing — везде, где название видит пользователь.
///
/// Отдельный идентификатор и своё имя тома уже проверяются снаружи
/// (`cruxwing/test/identity.test.mjs`), но там речь про то, как приложение
/// выглядит для macOS. Здесь — про то, как оно разговаривает: подпись в
/// экспортированном документе и подписи в настройках это и есть продукт для
/// того, кто их читает.
///
/// Форк переносит изменения сверху, из Cruxwing, и каждая такая правка тащит
/// чужое имя обратно. Поэтому это тест, а не разовая замена.
@Suite("Название продукта")
struct ProductNameTests {

    private var sources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // MeetGPTTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // app
            .appendingPathComponent("Sources/MeetGPT")
    }

    /// Строковые литералы файла — грубо, но достаточно: комментарии про
    /// происхождение форка законны и не должны валить тест, а вот текст в
    /// кавычках почти всегда попадает на экран.
    private func literals(of file: URL) -> [String] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }

        // Разбор по кавычкам не видит многострочные блоки: у `\"\"\"`-текста
        // кавычек внутри нет. Всплывающие подсказки живут именно там, и чужое
        // имя в них проходило мимо этой проверки целиком — при том что имя
        // и есть смысл форка. Проверено мутацией: «Cruxwing» внутри `.help`
        // не ловился.
        var result: [String] = []
        var insideBlock = false
        for rawLine in text.split(separator: "\n") {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("\"\"\"") {
                insideBlock.toggle()
                continue
            }
            guard !trimmed.hasPrefix("//") else { continue }
            if insideBlock {
                if !trimmed.isEmpty { result.append(trimmed) }
                continue
            }
            for (offset, chunk) in line.split(separator: "\"", omittingEmptySubsequences: false)
                .enumerated() where offset % 2 == 1 {   // нечётные куски — внутри кавычек
                result.append(String(chunk))
            }
        }
        return result
    }

    private func swiftFiles(under directory: String) -> [URL] {
        let root = sources.appendingPathComponent(directory)
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    @Test("ни один текст на экране не называет приложение чужим именем")
    func viewsNeverSayCruxwing() {
        // Не только `Views/`. Заголовок окна живёт в `MeetGPTApp.swift`, лист
        // отзыва — в `Feedback/`, страница «подключено», которую браузер
        // показывает после входа, — в `MCP/`, подписи выгруженных документов —
        // в `Export/` и `Integrations/`. Всё это человек видит, и во всём этом
        // стояло чужое имя: проверка смотрела в одну папку из шести.
        var files = swiftFiles(under: "Views")
            + swiftFiles(under: "Feedback") + swiftFiles(under: "Export")
            + swiftFiles(under: "Transcription")
        files.append(sources.appendingPathComponent("MeetGPTApp.swift"))
        for path in ["MCP/LoopbackRedirectServer.swift",
                     "Integrations/GoogleFileExport.swift",
                     "Integrations/GoogleDriveWriter.swift"] {
            files.append(sources.appendingPathComponent(path))
        }
        #expect(files.count > 14, "не нашлись файлы интерфейса — проверка была бы фиктивной")

        var offenders: [String] = []
        for file in files {
            // The foreign names are the commercial identities this edition was
            // forked from, not our own. Until 2026-09-09 the product was called
            // orakul and "Cruxwing" was the name to keep off screen; the rename
            // made Cruxwing ours, so what must not appear is MeetGPT and Wheespr.
            //
            // Interpolations are stripped first. `\(state.wheesprEmail)` is a
            // property name, not a word anybody reads, and matching it would
            // report the one thing this check is not about.
            for literal in literals(of: file) {
                // Two strips, because the naive literal split cuts a fragment
                // in half when an interpolation contains a quote of its own:
                // `Account: \(state.wheesprEmail ?? "` has no closing paren to
                // match, so an unterminated interpolation is dropped as well.
                let visible = literal
                    .replacingOccurrences(
                        of: #"\\\([^)]*\)"#, with: "", options: .regularExpression)
                    .replacingOccurrences(
                        of: #"\\\(.*$"#, with: "", options: .regularExpression)
                guard ["meetgpt", "wheespr"]
                    .contains(where: visible.localizedCaseInsensitiveContains) else { continue }
                offenders.append("\(file.lastPathComponent): \(literal.prefix(70))")
            }
        }
        let report = offenders.joined(separator: "; ")
        #expect(offenders.isEmpty, "чужое имя на экране: \(report)")
    }

    @Test("экспортированный документ подписан cruxwing")
    func exportsAreStampedWithOurName() {
        // Документ уезжает в чужой Notion или Google Docs и живёт там дольше
        // приложения. Чужая подпись в нём — это не опечатка в настройках,
        // это чужой продукт в переписке пользователя.
        // Подпись ищется по дате, а не по слову «export»: слово из неё как раз
        // и убрали, и проверка на него молча перестала что-либо проверять —
        // тест продолжал «проходить», найдя ноль подписей.
        for path in ["MCP/NotionExport.swift", "Integrations/GoogleDocsWriter.swift"] {
            let file = sources.appendingPathComponent(path)
            let stamps = literals(of: file).filter { $0.contains("df.string(from: date)") }
            #expect(stamps.count == 1, "\(path): подпись экспорта не найдена (\(stamps.count))")
            for stamp in stamps {
                #expect(stamp.contains("cruxwing"),
                        "\(path): документ не подписан именем продукта — \(stamp)")
                for foreign in ["meetgpt", "wheespr"] {
                    #expect(!stamp.localizedCaseInsensitiveContains(foreign),
                            "\(path): документ подписан чужим именем — \(stamp)")
                }
            }
        }
    }

    @Test("имя приложения в бандле совпадает с тем, что говорит интерфейс")
    func bundleAgreesWithTheCopy() {
        // Заодно ловит обратный случай: интерфейс переименовали, а Info.plist
        // остался прежним, и в Dock висит другое имя.
        let plist = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Support/Info.plist")
        let text = (try? String(contentsOf: plist, encoding: .utf8)) ?? ""
        #expect(text.contains("<string>cruxwing</string>"), "Info.plist называет приложение иначе")
        // Only Wheespr is foreign here. `CFBundleExecutable` is `MeetGPT`,
        // which is this repository's own Swift target, not another product.
        #expect(!text.localizedCaseInsensitiveContains("wheespr"),
                "Info.plist carries the commercial Wheespr identity")
    }
}
