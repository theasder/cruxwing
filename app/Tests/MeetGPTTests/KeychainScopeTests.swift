import Foundation
import Security
import Testing
@testable import MeetGPT

/// Reads and writes must address the SAME keychain.
///
/// macOS keeps two separate stores, and `kSecUseDataProtectionKeychain` chooses
/// between them. Writes followed `usesDataProtectionKeychain` (false on a dev
/// build) while reads and deletes hard-coded `true`, so a dev build saved every
/// token to the file keychain and then looked for it in the data-protection one:
/// the session was never read back, the app relaunched signed out, connected
/// apps disappeared, and the credits rail said "credits unavailable" while
/// Settings — reading UserDefaults — still showed the paid plan.
@Suite("Keychain scope")
struct KeychainScopeTests {
    private let store = SystemKeychain(bundleIdentifier: "ai.orakul.desktop.tests")

    private func scope(of query: [String: Any]) -> Bool? {
        query[kSecUseDataProtectionKeychain as String] as? Bool
    }

    // Два разных утверждения, и путать их дорого.
    //
    // Здесь проверяется, что КАЖДЫЙ путь берёт значение у правила: жёстко
    // вписанный `true` (та самая прошлая ошибка) от правила отличается, и это
    // ловится. Что само правило верно для сборки, которая уезжает людям,
    // проверяется отдельно и на обеих ветках — TokensStayOnThisMacTests.
    //
    // Сверять пути только друг с другом мало: правка в общем сборщике запроса
    // меняет их одинаково, и согласие сохраняется при неверном значении.
    // Проверено мутацией — так эта проверка и была однажды ослаблена.
    //
    // И про саму мутацию: портить надо значением, ОТЛИЧНЫМ от правила.
    // Значение зависит не только от devMode, но и от entitlement текущей
    // подписи, поэтому жёстко подставленные `true` или `false` могут случайно
    // совпасть с машиной. Корректная мутация подставляет `!rule`.
    @Test("every query names the keychain the build actually writes to")
    func queriesShareOneKeychain() {
        let plain = store.query(account: "wheespr.session")
        let insert = store.insertAttributes(data: Data("т".utf8), account: "wheespr.session")
        let rule = SystemKeychain.usesDataProtectionKeychain
        #expect(scope(of: plain) == rule)
        #expect(scope(of: insert) == rule,
                "запись и чтение идут в разные связки — токен «пропадёт» при первом же чтении")
    }

    @Test("extras cannot silently redirect a query to the other keychain")
    func extrasDoNotOverrideTheScope() {
        // Read and delete add their own keys on top of the shared base. Those
        // extras are exactly where the mismatched `true` used to live.
        let read = store.query(account: "wheespr.session", adding: [
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ])
        #expect(scope(of: read) == SystemKeychain.usesDataProtectionKeychain,
                "дополнения увели запрос в другую связку")
        #expect(read[kSecReturnData as String] as? Bool == true)
    }

    @Test("the account is namespaced by version and bundle id")
    func accountIsNamespaced() {
        let account = SystemKeychain.versionedAccount(
            "wheespr.session", bundleIdentifier: "ai.orakul.desktop.tests")
        #expect(account == "v1.ai.orakul.desktop.tests.wheespr.session")
        #expect(store.query(account: account)[kSecAttrAccount as String] as? String == account)
    }

    @Test("data-protection keychain requires both a distribution build and its entitlement")
    func dataProtectionSelectionRule() {
        #expect(SystemKeychain.dataProtectionKeychainSelected(
            isDevBuild: false, hasApplicationIdentifier: true
        ))
        #expect(!SystemKeychain.dataProtectionKeychainSelected(
            isDevBuild: false, hasApplicationIdentifier: false
        ))
        #expect(!SystemKeychain.dataProtectionKeychainSelected(
            isDevBuild: true, hasApplicationIdentifier: true
        ))
        #expect(!SystemKeychain.dataProtectionKeychainSelected(
            isDevBuild: true, hasApplicationIdentifier: false
        ))
    }

    @Test("the runtime service belongs to Orakul, with the old service migration-only")
    func serviceIdentity() {
        #expect(store.serviceIdentifier == "ai.orakul.desktop.tests.credentials")
        #expect(store.query(account: "probe")[kSecAttrService as String] as? String
                == "ai.orakul.desktop.tests.credentials")
        #expect(SystemKeychain.legacyServiceIdentifier == "com.cruxwing.credentials")
        #expect(store.serviceIdentifier != SystemKeychain.legacyServiceIdentifier)
    }
}

@Suite("Storage identity")
struct StorageIdentityTests {
    @Test("all live stores share one Orakul-owned Application Support root")
    func liveStorePathsAreOrakulOwned() {
        let base = URL(fileURLWithPath: "/Users/example/Library/Application Support",
                       isDirectory: true)
        let root = OrakulApplicationSupport.root(in: base)

        #expect(root.lastPathComponent == "ai.orakul.desktop")
        #expect(OrakulApplicationSupport.sessionsDirectory(under: root)
            .deletingLastPathComponent() == root)
        #expect(OrakulApplicationSupport.telegramArchiveURL(under: root)
            .deletingLastPathComponent().deletingLastPathComponent() == root)
        #expect(OrakulApplicationSupport.teamWatchAuditLogURL(under: root)
            .deletingLastPathComponent() == root)
    }

    @Test("production sources cannot restore a shared legacy storage root")
    func productionSourcesUseOnlyTheCentralRoot() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/MeetGPT", isDirectory: true)
        let helperName = "OrakulApplicationSupport.swift"
        let forbiddenPathFragments = [
            "appendingPathComponent(\"MeetGPT",
            "appendingPathComponent(\"Cruxwing",
            "appendingPathComponent(\"cruxwing",
        ]
        var offenders: [String] = []

        let enumerator = try #require(
            FileManager.default.enumerator(
                at: sourceRoot,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
        )
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            let code = source.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            let relative = file.path.replacingOccurrences(
                of: sourceRoot.path + "/", with: "")

            if file.lastPathComponent != helperName,
               code.contains(".applicationSupportDirectory") {
                offenders.append("\(relative): bypasses OrakulApplicationSupport")
            }
            for fragment in forbiddenPathFragments where code.contains(fragment) {
                offenders.append("\(relative): contains \(fragment)")
            }
        }

        #expect(offenders.isEmpty,
                "shared legacy storage can mix Orakul and Cruxwing data: \(offenders)")
    }
}
