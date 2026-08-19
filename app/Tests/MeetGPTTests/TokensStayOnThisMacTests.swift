import Foundation
import Security
import Testing
@testable import MeetGPT

/// Токены не уезжают с этого компьютера.
///
/// В связке ключей лежат ключи от рабочих трекеров, вики и мессенджеров — и от
/// Fireflies, чей владелец продаёт конкурирующий продукт. Атрибут доступа
/// решает, синхронизируются ли они через iCloud: `…ThisDeviceOnly` не
/// синхронизируется никогда, а `kSecAttrAccessibleAfterFirstUnlock` без этого
/// хвоста — уедет на все устройства учётной записи.
///
/// Разница в одном слове, видна только тому, кто её ищет, и прямо противоречит
/// доводу продукта «остаётся на вашем компьютере». Ничем не была закреплена.
@Suite("Токены остаются на этом Mac")
struct TokensStayOnThisMacTests {

    private func attributes() -> [String: Any] {
        SystemKeychain().insertAttributes(data: Data("токен".utf8), account: "проба")
    }

    @Test("токен кладётся с доступом только на этом устройстве")
    func accessibilityIsThisDeviceOnly() {
        let value = attributes()[kSecAttrAccessible as String]
        #expect(value as! CFString == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                "токены от чужих сервисов уедут в iCloud на все устройства")
    }

    @Test("синхронизация не включается отдельным ключом")
    func synchronizableIsNeverTrue() {
        let value = attributes()[kSecAttrSynchronizable as String]
        #expect(value == nil || (value as? Bool) == false,
                "kSecAttrSynchronizable включён — доступ на этом устройстве уже не спасёт")
    }

    // Обратная сторона: «этот компьютер» не должно означать «только пока
    // разблокирован». Расшифровка идёт в фоне, и запрос к трекеру может уйти,
    // когда экран заперт: WhenUnlocked сделал бы источник молчащим без причины.
    @Test("после первой разблокировки, а не только при открытом экране")
    func availableAfterFirstUnlock() {
        let value = attributes()[kSecAttrAccessible as String] as! CFString
        #expect(value != kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                "источник замолчит при запертом экране, и это будет выглядеть поломкой")
    }

    @Test("данные кладутся в современную связку ключей")
    func usesDataProtectionKeychain() {
        // Классическая связка спрашивает пароль диалогом при доступе из другой
        // сборки — на этом уже обжигались с ai.wheespr.meetgpt.
        let value = attributes()[kSecUseDataProtectionKeychain as String]
        #expect(value as? Bool == SystemKeychain.usesDataProtectionKeychain)
    }
}
