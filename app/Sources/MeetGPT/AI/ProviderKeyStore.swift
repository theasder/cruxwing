import Foundation

/// Cloud services that receive meeting audio only after the user supplies the
/// corresponding credential at runtime. They deliberately do not share the
/// LLM-provider enum: adding a transcription key must not make an unrelated
/// chat model look configured.
enum CloudTranscriptionProvider: String, CaseIterable, Identifiable, Sendable {
    case deepgram
    case assemblyAI

    var id: String { rawValue }

    var label: String {
        switch self {
        case .deepgram:  return "Deepgram"
        case .assemblyAI: return "AssemblyAI"
        }
    }

    var keyConsoleHint: String {
        switch self {
        case .deepgram:  return "console.deepgram.com → API Keys"
        case .assemblyAI: return "www.assemblyai.com/dashboard → API Keys"
        }
    }
}

/// Ключи провайдеров, которые пользователь вводит сам.
///
/// **Зачем это вернули.** У Cruxwing ключи перестали быть пользовательскими,
/// когда появился серверный шлюз: они уехали на сервер, а в приложение стал
/// зашиваться пустой `Secrets`. orakul этот код унаследовал, но сервера у него
/// нет и не планируется — значит, в готовом установщике ключа нет ни своего, ни
/// чужого, и ответы модели не работают вовсе. Скачанное приложение, которое не
/// может ответить ни на один вопрос, — это не бесплатный продукт, а
/// неработающий.
///
/// Поэтому ключ снова вводится в настройках и живёт в Связке ключей. Для
/// продукта, который считает всё на компьютере пользователя, так и честнее:
/// расход идёт по его собственному договору с провайдером, без посредника.
struct ProviderKeyStore: Sendable {

    /// Providers with two required fields are persisted as one Keychain value.
    /// Two independent SecItem writes cannot be atomic: a locked Keychain can
    /// accept the API key and reject the folder id, leaving an unusable mixed
    /// credential. One encoded record gives save/replace one commit point while
    /// the legacy two-record fallback below keeps existing installs readable.
    private struct PairedCredential: Codable {
        let key: String
        let secondary: String
    }

    private let store: KeychainStore

    init(store: KeychainStore = SystemKeychain.shared) {
        self.store = store
    }

    static let shared = ProviderKeyStore()

    /// Подмена для тестов. Нужна там, где проверяется маршрутизация: она
    /// отбирает модели по `isConfigured`, а это зависит от наличия ключа.
    /// Раньше вопрос не стоял — при серверном шлюзе настроенными считались все
    /// провайдеры сразу, и тесты маршрутизации проходили, ничего про ключи не
    /// зная. В прямом режиме так уже нельзя.
    ///
    /// Продакшен сюда не заглядывает: значение nil, и `current` отдаёт `shared`.
    ///
    /// **Почему `@TaskLocal`, а не обычная статическая переменная.** Раньше была
    /// обычная — одна на весь процесс. Swift Testing гоняет наборы параллельно,
    /// и подмена, сделанная в одном наборе, была видна всем остальным: набор
    /// «LLM catalog» заполнял хранилище ключами, а в это время «Прямой доступ к
    /// провайдеру» спрашивал `isConfigured` и получал true там, где ждал false.
    /// Полный прогон падал каждый раз, причём каждый раз в другом месте, и
    /// каждый упавший тест по отдельности проходил — то есть зелёный прогон
    /// вообще ничего не значил.
    ///
    /// `.serialized` тут не лечит: он упорядочивает тесты ВНУТРИ набора, а
    /// гонка была между наборами в разных файлах. Task-local снимает её
    /// устройством, а не дисциплиной: значение живёт в задаче, которая его
    /// связала, и соседняя задача его просто не видит.
    ///
    /// Цена: `Task.detached` task-local не наследует. Для подмены в тестах это
    /// правильное поведение — оторванная задача и не должна тянуть за собой
    /// тестовое окружение, — но если когда-нибудь понадобится подменить ключи
    /// коду внутри `Task.detached`, придётся передавать хранилище явно.
    @TaskLocal static var overrideForTesting: ProviderKeyStore?

    static var current: ProviderKeyStore { overrideForTesting ?? shared }

    private func account(_ provider: LLMProvider) -> String {
        "provider.key.\(provider.rawValue)"
    }

    private func secondaryAccount(_ provider: LLMProvider) -> String {
        "provider.key.\(provider.rawValue).secondary"
    }

    private func pairedAccount(_ provider: LLMProvider) -> String {
        "provider.key.\(provider.rawValue).paired"
    }

    private func transcriptionAccount(_ provider: CloudTranscriptionProvider) -> String {
        "transcription.provider.key.\(provider.rawValue)"
    }

    /// Ключ, введённый пользователем. nil — не вводили.
    func key(for provider: LLMProvider) -> String? {
        if let paired = pairedCredential(for: provider) { return paired.key }
        guard let data = store.get(account(provider)),
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else { return nil }
        return key
    }

    /// Пустая строка убирает ключ, а не сохраняет пустоту: иначе очищенное
    /// поле оставляет мёртвую запись, и провайдер выглядит настроенным.
    /// Возвращает, удалось ли сохранить.
    ///
    /// Раньше результат `store.set` здесь выбрасывался. Связка ключей умеет не
    /// записать — заблокирована, строка осталась от прежней подписи бинарника
    /// (для этих двух случаев в `Keychain.swift` есть отдельная ветка), — и
    /// тогда происходило худшее: настройки говорили «ключ есть», поле
    /// очищалось, а каждый запрос к модели падал с «нет ключа». Человеку
    /// оставалось вставлять ключ снова и снова.
    @discardableResult
    func setKey(_ key: String, for provider: LLMProvider) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return remove(provider)
        }
        if provider.needsSecondary, let secondary = secondary(for: provider) {
            return setCredentials(key: trimmed, secondary: secondary, for: provider)
        }
        return store.set(Data(trimmed.utf8), for: account(provider))
    }

    @discardableResult
    func remove(_ provider: LLMProvider) -> Bool {
        let keyRemoved = store.delete(account(provider))
        let secondaryRemoved = store.delete(secondaryAccount(provider))
        let pairedRemoved = store.delete(pairedAccount(provider))
        return keyRemoved && secondaryRemoved && pairedRemoved
    }

    func hasKey(_ provider: LLMProvider) -> Bool { key(for: provider) != nil }

    // MARK: - Второе поле

    /// Идентификатор каталога у Яндекса. Без него запрос уходит с моделью,
    /// которую сервис не знает, — то же самое, что без ключа, только ошибка
    /// приходит позже и звучит непонятнее.
    func secondary(for provider: LLMProvider) -> String? {
        if let paired = pairedCredential(for: provider) { return paired.secondary }
        guard provider.needsSecondary,
              let data = store.get(secondaryAccount(provider)),
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else { return nil }
        return value
    }

    @discardableResult
    func setSecondary(_ value: String, for provider: LLMProvider) -> Bool {
        guard provider.needsSecondary else { return true }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return store.delete(secondaryAccount(provider))
        }
        if let key = key(for: provider) {
            return setCredentials(key: key, secondary: trimmed, for: provider)
        }
        return store.set(Data(trimmed.utf8), for: secondaryAccount(provider))
    }

    /// Atomically save every field required by a provider. Single-field
    /// providers delegate to `setKey`; YandexGPT writes one encoded Keychain row
    /// so a successful result can never expose a half-new credential.
    @discardableResult
    func setCredentials(key: String, secondary: String, for provider: LLMProvider) -> Bool {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecondary = secondary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return false }
        guard provider.needsSecondary else { return setKey(trimmedKey, for: provider) }
        guard !trimmedSecondary.isEmpty else { return false }
        let credential = PairedCredential(key: trimmedKey, secondary: trimmedSecondary)
        guard let data = try? JSONEncoder().encode(credential),
              store.set(data, for: pairedAccount(provider)) else { return false }
        // Best-effort cleanup of the pre-atomic representation. Reads prefer the
        // paired row, and `remove` verifies deletion of all three accounts.
        _ = store.delete(account(provider))
        _ = store.delete(secondaryAccount(provider))
        return true
    }

    private func pairedCredential(for provider: LLMProvider) -> PairedCredential? {
        guard provider.needsSecondary,
              let data = store.get(pairedAccount(provider)),
              let credential = try? JSONDecoder().decode(PairedCredential.self, from: data),
              !credential.key.isEmpty,
              !credential.secondary.isEmpty else { return nil }
        return credential
    }

    /// Готов ли провайдер к запросу: ключа мало, если нужен ещё и каталог.
    func isReady(_ provider: LLMProvider) -> Bool {
        guard hasKey(provider) else { return false }
        return provider.needsSecondary ? secondary(for: provider) != nil : true
    }

    /// Провайдеры, у которых есть пользовательский ключ.
    var configured: [LLMProvider] {
        LLMProvider.allCases.filter(hasKey)
    }

    // MARK: - Облачная расшифровка

    /// A transcription credential entered by the user. There is intentionally
    /// no build-time or backend fallback: nil means that sending meeting audio
    /// to this vendor is unavailable.
    func transcriptionKey(for provider: CloudTranscriptionProvider) -> String? {
        guard let data = store.get(transcriptionAccount(provider)),
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else { return nil }
        return key
    }

    @discardableResult
    func setTranscriptionKey(_ key: String, for provider: CloudTranscriptionProvider) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return removeTranscriptionKey(for: provider)
        }
        return store.set(Data(trimmed.utf8), for: transcriptionAccount(provider))
    }

    @discardableResult
    func removeTranscriptionKey(for provider: CloudTranscriptionProvider) -> Bool {
        store.delete(transcriptionAccount(provider))
    }

    func hasTranscriptionKey(for provider: CloudTranscriptionProvider) -> Bool {
        transcriptionKey(for: provider) != nil
    }

    var configuredTranscriptionProviders: [CloudTranscriptionProvider] {
        CloudTranscriptionProvider.allCases.filter(hasTranscriptionKey)
    }
}
