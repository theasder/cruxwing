import Foundation
import Testing
@testable import MeetGPT

private final class ControllableWriteKeychain: KeychainStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]
    private var attempts = 0
    private var rejecting = false

    var writeAttempts: Int { lock.withLock { attempts } }

    func rejectWrites(_ value: Bool) {
        lock.withLock { rejecting = value }
    }

    @discardableResult
    func set(_ data: Data, for account: String) -> Bool {
        lock.withLock {
            attempts += 1
            guard !rejecting else { return false }
            storage[account] = data
            return true
        }
    }

    func get(_ account: String) -> Data? {
        lock.withLock { storage[account] }
    }

    @discardableResult
    func delete(_ account: String) -> Bool {
        lock.withLock { storage[account] = nil }
        return true
    }
}

/// Ключи провайдеров, введённые пользователем.
///
/// Смысл всей этой части: в готовом установщике ключей нет ни одного, и без
/// ввода в настройках приложение не может ответить ни на один вопрос. Поэтому
/// проверяется не «строка сохранилась», а то, что делает продукт рабочим —
/// отсутствие резервного источника и мёртвых записей.
@Suite("Ключи провайдеров")
struct ProviderKeyStoreTests {

    @Test("ключ переживает перезапуск и лежит в Связке ключей")
    func keyRoundTrips() {
        let keychain = InMemoryKeychain()
        ProviderKeyStore(store: keychain).setKey("sk-user", for: .openAI)

        // Новый экземпляр — как после перезапуска приложения.
        #expect(ProviderKeyStore(store: keychain).key(for: .openAI) == "sk-user")
        #expect(keychain.count == 1)
    }

    @Test("без пользовательского ключа провайдер не настроен")
    func noBuildTimeFallback() {
        let store = ProviderKeyStore(store: InMemoryKeychain())
        #expect(store.key(for: .openAI) == nil)
        #expect(!store.hasKey(.openAI))

        store.setKey("sk-user", for: .openAI)
        #expect(store.key(for: .openAI) == "sk-user")
    }

    @Test("у каждого провайдера свой ключ")
    func providersDoNotShareOneSlot() {
        // Общая запись означала бы, что второй ключ молча отключает первый.
        let keychain = InMemoryKeychain()
        let store = ProviderKeyStore(store: keychain)
        store.setKey("sk-user", for: .openAI)
        store.setKey("sk-deep", for: .deepSeek)

        #expect(store.key(for: .openAI) == "sk-user")
        #expect(store.key(for: .deepSeek) == "sk-deep")
        #expect(keychain.count == 2)
    }

    @Test("пустая строка убирает ключ, а не сохраняет пустоту")
    func emptyKeyClears() {
        let keychain = InMemoryKeychain()
        let store = ProviderKeyStore(store: keychain)
        store.setKey("sk-user", for: .openAI)
        store.setKey("   ", for: .openAI)

        #expect(store.key(for: .openAI) == nil)
        #expect(keychain.count == 0, "мёртвая запись осталась в Связке ключей")
    }

    @Test("ключ обрезается по краям")
    func keyIsTrimmed() {
        // Скопированный ключ почти всегда приезжает с переводом строки, а
        // провайдер отвечает на такой заголовок 401.
        let store = ProviderKeyStore(store: InMemoryKeychain())
        store.setKey("  sk-user\n", for: .openAI)
        #expect(store.key(for: .openAI) == "sk-user")
    }

    @Test("список настроенных провайдеров — это те, у кого есть ключ")
    func configuredListsOnlyKeyed() {
        let store = ProviderKeyStore(store: InMemoryKeychain())
        #expect(store.configured.isEmpty)

        store.setKey("sk-deep", for: .deepSeek)
        #expect(store.configured == [.deepSeek])

        store.remove(.deepSeek)
        #expect(store.configured.isEmpty)
    }

    @Test("у каждого провайдера своя запись в Связке, а не общая")
    func everyProviderHasItsOwnAccount() {
        // Перебор по всем: новый провайдер в каталоге не должен случайно
        // разделить запись с уже существующим.
        let keychain = InMemoryKeychain()
        let store = ProviderKeyStore(store: keychain)
        for provider in LLMProvider.allCases {
            store.setKey("sk-\(provider.rawValue)", for: provider)
        }
        #expect(keychain.count == LLMProvider.allCases.count)
        for provider in LLMProvider.allCases {
            #expect(store.key(for: provider) == "sk-\(provider.rawValue)")
        }
    }

    @Test("ключ и каталог Яндекса сохраняются одним откатываемым изменением")
    func yandexCredentialIsAtomicAndRollbackSafe() {
        let keychain = ControllableWriteKeychain()
        let store = ProviderKeyStore(store: keychain)

        #expect(store.setCredentials(
            key: "AQVN-old", secondary: "folder-old", for: .yandexGPT))
        #expect(keychain.writeAttempts == 1,
                "сохранение пары снова разложили на две независимые записи")
        #expect(store.key(for: .yandexGPT) == "AQVN-old")
        #expect(store.secondary(for: .yandexGPT) == "folder-old")

        keychain.rejectWrites(true)
        #expect(!store.setCredentials(
            key: "AQVN-new", secondary: "folder-new", for: .yandexGPT))
        #expect(store.key(for: .yandexGPT) == "AQVN-old")
        #expect(store.secondary(for: .yandexGPT) == "folder-old",
                "отказ замены оставил смесь старого и нового credential")
    }
}
