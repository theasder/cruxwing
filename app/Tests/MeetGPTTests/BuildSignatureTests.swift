import Testing
import Foundation
@testable import MeetGPT

/// Строка версии внизу настроек — то единственное, по чему человек сообщает,
/// какую сборку он запускал. Форма её — обязательство: по ней сверяют отчёт
/// об ошибке с кодом, из которого собрано.
@Suite struct BuildSignatureTests {

    /// Корень репозитория: файл лежит в app/Tests/MeetGPTTests, значит вверх на три.
    private static var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test("Полный Info.plist даёт имя, версию и штамп исходников")
    func fullPlist() {
        let signature = SettingsView.buildSignature(from: [
            "CFBundleDisplayName": "cruxwing (тест)",
            "CFBundleShortVersionString": "0.1.0",
            "CruxwingSourceHash": "81281531422f"
        ])
        #expect(signature == "cruxwing (тест) 0.1.0 · 81281531422f")
    }

    /// У сборки разработчика штампа нет. Показать пустое место честнее, чем
    /// подставить «dev» или «неизвестно»: тестировщик перепишет то, что видит,
    /// и правдоподобная выдумка попадёт в отчёт как факт.
    @Test("Без штампа строка короче, но не врёт")
    func missingStamp() {
        let signature = SettingsView.buildSignature(from: [
            "CFBundleDisplayName": "cruxwing (тест)",
            "CFBundleShortVersionString": "0.1.0"
        ])
        #expect(signature == "cruxwing (тест) 0.1.0")
        #expect(!signature.contains("·"))
    }

    @Test("Пустой Info.plist не даёт ни разделителей, ни пустых кусков")
    func emptyPlist() {
        #expect(SettingsView.buildSignature(from: [:]) == "cruxwing")
    }

    /// Имя в подписи — это имя из config/app.json, а не литерал в коде. Если
    /// сборку переименуют, а строку версии забудут, тестировщик пришлёт имя,
    /// которого нет ни на одном значке.
    @Test("Имя берётся из настроек сборки")
    func nameComesFromBuildConfig() throws {
        let data = try Data(contentsOf: Self.root.appendingPathComponent("config/app.json"))
        let config = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let app = try #require(config["app"] as? [String: Any])
        let displayName = try #require(app["displayName"] as? String)

        let signature = SettingsView.buildSignature(from: [
            "CFBundleDisplayName": displayName,
            "CFBundleShortVersionString": "0.1.0",
            "CruxwingSourceHash": "81281531422f"
        ])
        #expect(signature.hasPrefix(displayName))
    }
}
