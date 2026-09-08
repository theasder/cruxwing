import Foundation
import Testing
@testable import MeetGPT

private final class DeleteRefusingKeychain: KeychainStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    @discardableResult
    func set(_ data: Data, for account: String) -> Bool {
        lock.withLock { storage[account] = data }
        return true
    }

    func get(_ account: String) -> Data? {
        lock.withLock { storage[account] }
    }

    func delete(_ account: String) -> Bool { false }
}

@Suite("Cloud transcription runtime BYOK")
struct CloudTranscriptionBYOKTests {
    @Test("Deepgram and AssemblyAI keys are isolated, trimmed, removable Keychain records")
    func transcriptionKeysRoundTripIndependently() {
        let keychain = InMemoryKeychain()
        let store = ProviderKeyStore(store: keychain)

        #expect(store.configuredTranscriptionProviders.isEmpty)
        #expect(store.setTranscriptionKey("  deepgram-user-key\n", for: .deepgram))
        #expect(store.setTranscriptionKey("assembly-user-key", for: .assemblyAI))
        #expect(store.transcriptionKey(for: .deepgram) == "deepgram-user-key")
        #expect(store.transcriptionKey(for: .assemblyAI) == "assembly-user-key")
        #expect(Set(store.configuredTranscriptionProviders) == [.deepgram, .assemblyAI])

        store.removeTranscriptionKey(for: .deepgram)
        #expect(store.transcriptionKey(for: .deepgram) == nil)
        #expect(store.transcriptionKey(for: .assemblyAI) == "assembly-user-key")

        #expect(store.setTranscriptionKey("   ", for: .assemblyAI))
        #expect(store.configuredTranscriptionProviders.isEmpty)
        #expect(keychain.count == 0)
    }

    @Test("a refused transcription-key deletion is reported and never faked as success")
    func refusedDeletionIsReported() {
        let keychain = DeleteRefusingKeychain()
        let store = ProviderKeyStore(store: keychain)
        #expect(store.setTranscriptionKey("unit-key", for: .deepgram))

        #expect(!store.removeTranscriptionKey(for: .deepgram))
        #expect(store.transcriptionKey(for: .deepgram) == "unit-key")
        #expect(!store.setTranscriptionKey("   ", for: .deepgram),
                "empty input discarded the failed delete result")
    }

    @Test("Config reads transcription credentials only from the runtime store")
    func configUsesRuntimeStore() {
        let store = ProviderKeyStore(store: InMemoryKeychain())
        ProviderKeyStore.$overrideForTesting.withValue(store) {
            #expect(Config.deepgramAPIKey.isEmpty)
            #expect(Config.assemblyAIAPIKey.isEmpty)
            #expect(!Config.engineAvailable(.deepgram))

            store.setTranscriptionKey("dg-runtime", for: .deepgram)
            store.setTranscriptionKey("aai-runtime", for: .assemblyAI)

            #expect(Config.deepgramAPIKey == "dg-runtime")
            #expect(Config.assemblyAIAPIKey == "aai-runtime")
            #expect(Config.engineAvailable(.deepgram))
        }
    }

    @MainActor
    @Test("AppState uses its injected store and never enables server diarization")
    func appStateUsesInjectedStore() {
        let keychain = InMemoryKeychain()
        let keys = ProviderKeyStore(store: keychain)
        let state = AppState(
            credentialStore: keychain,
            transcriptionEngineAvailability: { _ in true })

        #expect(!state.hasDeepgram)
        #expect(!state.hasAssemblyAI)
        #expect(!state.canDiarizeOnServer)

        keys.setTranscriptionKey("dg-runtime", for: .deepgram)
        keys.setTranscriptionKey("aai-runtime", for: .assemblyAI)
        #expect(state.hasDeepgram)
        #expect(state.hasAssemblyAI)
        #expect(!state.canDiarizeOnServer)

        keys.removeTranscriptionKey(for: .deepgram)
        keys.removeTranscriptionKey(for: .assemblyAI)
        #expect(!state.hasDeepgram)
        #expect(!state.hasAssemblyAI)
    }

    @MainActor
    @Test("AppState resolves its initial route from the injected Keychain, never the global one")
    func injectedStoreOwnsInitialization() {
        let defaults = UserDefaults.standard
        let account = "transcription.engine"
        let saved = defaults.object(forKey: account)
        defer {
            if let saved { defaults.set(saved, forKey: account) }
            else { defaults.removeObject(forKey: account) }
        }

        let globalKeychain = InMemoryKeychain()
        let global = ProviderKeyStore(store: globalKeychain)
        global.setTranscriptionKey("wrong-global-key", for: .deepgram)
        let emptyInjected = InMemoryKeychain()
        defaults.set(TranscriptionEngine.deepgram.rawValue, forKey: account)
        var emptyStoreFactoryEngines: [TranscriptionEngine] = []
        let emptyState = ProviderKeyStore.$overrideForTesting.withValue(global) {
            AppState(
                llm: MockLLMGateway(response: ""),
                credentialStore: emptyInjected,
                transcriptionServiceFactory: { engine, _, _, _, _ in
                    emptyStoreFactoryEngines.append(engine)
                    return MockTranscriptionService()
                })
        }
        #expect(emptyState.selectedTranscriptionEngine == .local)
        #expect(emptyStoreFactoryEngines.first == .local)
        #expect(defaults.string(forKey: account) == TranscriptionEngine.local.rawValue)

        let keyedInjected = InMemoryKeychain()
        ProviderKeyStore(store: keyedInjected).setTranscriptionKey(
            "right-injected-key", for: .deepgram)
        let emptyGlobal = ProviderKeyStore(store: InMemoryKeychain())
        defaults.set(TranscriptionEngine.deepgram.rawValue, forKey: account)
        var keyedStoreFactoryEngines: [TranscriptionEngine] = []
        let keyedState = ProviderKeyStore.$overrideForTesting.withValue(emptyGlobal) {
            AppState(
                llm: MockLLMGateway(response: ""),
                credentialStore: keyedInjected,
                transcriptionServiceFactory: { engine, _, _, _, _ in
                    keyedStoreFactoryEngines.append(engine)
                    return MockTranscriptionService()
                })
        }
        #expect(keyedState.selectedTranscriptionEngine == .deepgram)
        #expect(keyedStoreFactoryEngines.first == .deepgram)
    }

    @Test("a misrouted Deepgram chunk service fails closed on-device, never to OpenAI")
    func deepgramFactoryFailsClosedToLocal() {
        let service = TranscriptionFactory.make(
            engine: .deepgram,
            language: "en",
            glossary: "",
            localModel: "base")
        #expect(service is LocalWhisperTranscription)
        #expect(!(service is WhisperAPITranscription))
    }
}
