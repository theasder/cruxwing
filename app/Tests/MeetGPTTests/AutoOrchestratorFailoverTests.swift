import Foundation
import Testing
@testable import MeetGPT

private final class FailoverScriptGateway: LLMGateway, @unchecked Sendable {
    struct Step {
        let deltas: [String]
        let result: Result<String, Error>
    }

    private let lock = NSLock()
    private var steps: [Step]
    private(set) var models: [LLMModel] = []
    private var outputBudgets: [Int?] = []

    init(_ steps: [Step]) { self.steps = steps }

    var calledModels: [LLMModel] {
        lock.lock(); defer { lock.unlock() }
        return models
    }

    var calledOutputBudgets: [Int?] {
        lock.lock(); defer { lock.unlock() }
        return outputBudgets
    }

    private func takeStep(for model: LLMModel, maxOutputTokens: Int?) -> Step {
        lock.lock(); defer { lock.unlock() }
        models.append(model)
        outputBudgets.append(maxOutputTokens)
        return steps.removeFirst()
    }

    func streamChat(system: String, user: String, images: [Data], model: LLMModel,
                    onDelta: @escaping (String) -> Void) async throws -> String {
        let step = takeStep(for: model, maxOutputTokens: nil)
        step.deltas.forEach(onDelta)
        return try step.result.get()
    }

    func streamChat(system: String, user: String, images: [Data], model: LLMModel,
                    maxOutputTokens: Int?,
                    onDelta: @escaping (String) -> Void) async throws -> String {
        let step = takeStep(for: model, maxOutputTokens: maxOutputTokens)
        step.deltas.forEach(onDelta)
        return try step.result.get()
    }
}

private final class ConcurrentDeltaFailureGateway: LLMGateway, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return calls
    }

    private func nextCall() -> Int {
        lock.lock(); defer { lock.unlock() }
        calls += 1
        return calls
    }

    func streamChat(system: String, user: String, images: [Data], model: LLMModel,
                    onDelta: @escaping (String) -> Void) async throws -> String {
        let call = nextCall()
        if call == 1 {
            DispatchQueue.concurrentPerform(iterations: 32) { _ in onDelta("x") }
            throw LLMError.http("OpenAI", 503, "stream failed")
        }
        onDelta("duplicate")
        return "duplicate"
    }
}

@Suite("Direct-provider orchestration failover", .serialized)
struct AutoOrchestratorFailoverTests {

    private let openAI = LLMModel(id: "test-openai", label: "OpenAI test",
                                  provider: .openAI, minTier: .free, supportsVision: true)
    private let google = LLMModel(id: "test-google", label: "Google test",
                                  provider: .google, minTier: .free, supportsVision: true)
    private let anthropic = LLMModel(id: "test-anthropic", label: "Anthropic test",
                                     provider: .anthropic, minTier: .free, supportsVision: true)

    private func orchestrator(_ gateway: FailoverScriptGateway,
                              selection: String,
                              direct: Bool = true,
                              fallbacks: [LLMModel]? = nil) -> AutoOrchestrator {
        let resolvedFallbacks = fallbacks ?? [google, anthropic]
        return AutoOrchestrator(
            inner: gateway,
            selectionProvider: { selection },
            tierProvider: { .premium },
            directClientMode: { direct },
            fallbackResolver: { _, _, _ in resolvedFallbacks })
    }

    private func globalAutoRoute() -> (primary: LLMModel, alternates: [LLMModel]) {
        let primary = AutoOrchestrator.route(.light, tier: .premium, hasImages: false)
        let alternates = [openAI, google, anthropic]
            .filter { $0.provider != primary.provider }
        return (primary, alternates)
    }

    private func errorSource(for provider: LLMProvider) -> String {
        switch provider {
        case .google: return "Gemini"
        case .zhipu: return "Zhipu GLM"
        default: return provider.label
        }
    }

    @Test("captured provider-pinned Auto selection beats a later live setting")
    func capturedProviderPinWins() async throws {
        // Маршрутизация смотрит на наличие ключа: без него пул пуст
        // и закреплённый провайдер теряется на запасном пути.
        try await withSeededProviderKeys {
            let gateway = FailoverScriptGateway([
                .init(deltas: ["ok"], result: .success("ok")),
            ])
            let captured = LLMModel(
                id: LLMCatalog.auto.id, label: LLMCatalog.auto.label,
                provider: .anthropic, minTier: .free, supportsVision: true,
                requestSelectionID: "auto:anthropic")
            let sut = AutoOrchestrator(
                inner: gateway,
                selectionProvider: { "auto:openAI" },
                tierProvider: { .ultra },
                directClientMode: { false },
                fallbackResolver: { _, _, _ in [] })

            _ = try await sut.streamChat(
                system: "s", user: "short", images: [], model: captured,
                onDelta: { _ in })

            #expect(gateway.calledModels.count == 1)
            #expect(gateway.calledModels.first?.provider == .anthropic)
        }
    }

    @Test("provider-pinned Auto stays within its chosen provider on failure")
    func providerPinnedAutoFailsClosed() async {
        await withSeededProviderKeys {
            let gateway = FailoverScriptGateway([
                .init(deltas: [], result: .failure(
                    LLMError.http("OpenAI", 503, "private upstream body"))),
                .init(deltas: ["must not run"], result: .success("must not run")),
            ])
            let sut = orchestrator(
                gateway, selection: "auto:openAI", fallbacks: [google])

            do {
                _ = try await sut.streamChat(
                    system: "s", user: "short", images: [], model: LLMCatalog.auto,
                    onDelta: { _ in })
                Issue.record("expected bounded provider failure")
            } catch let error as AutoOrchestrator.ProviderFailoverError {
                #expect(error.attempts == [
                    .init(provider: .openAI, category: .unavailable),
                ])
                #expect(!error.localizedDescription.contains("private upstream body"))
            } catch {
                Issue.record("unexpected error: \(type(of: error))")
            }
            #expect(gateway.calledModels.map(\.provider) == [.openAI])
        }
    }

    @Test("a concrete model failure never sends the request to another provider")
    func concreteSelectionFailsClosed() async {
        await withoutProviderKeys {
            let gateway = FailoverScriptGateway([
                .init(deltas: [], result: .failure(
                    LLMError.http("OpenAI", 402, #"{"error":"not enough funds"}"#))),
                .init(deltas: ["must not run"], result: .success("must not run")),
            ])
            let sut = orchestrator(gateway, selection: openAI.id)

            do {
                _ = try await sut.streamChat(
                    system: "s", user: "u", images: [], model: openAI,
                    maxOutputTokens: 321, onDelta: { _ in })
                Issue.record("expected bounded provider failure")
            } catch let error as AutoOrchestrator.ProviderFailoverError {
                #expect(error.attempts == [
                    .init(provider: .openAI, category: .funding),
                ])
                #expect(!error.localizedDescription.contains("not enough funds"))
            } catch {
                Issue.record("unexpected error: \(type(of: error))")
            }
            #expect(gateway.calledModels.map(\.provider) == [.openAI])
            #expect(gateway.calledOutputBudgets == [321])
        }
    }

    @Test("Auto recovers from a funding 429 on a different configured vendor")
    func autoFundingFallback() async throws {
        try await withSeededProviderKeys {
            let route = globalAutoRoute()
            let fallback = try #require(route.alternates.first)
            let gateway = FailoverScriptGateway([
                .init(deltas: [], result: .failure(
                    LLMError.http(errorSource(for: route.primary.provider), 429,
                                  #"{"code":"insufficient_quota"}"#))),
                .init(deltas: ["ok"], result: .success("ok")),
            ])
            let sut = orchestrator(
                gateway, selection: LLMCatalog.autoID, fallbacks: [fallback])
            var deltas: [String] = []

            let answer = try await sut.streamChat(
                system: "s", user: "short", images: [], model: LLMCatalog.auto,
                onDelta: { deltas.append($0) })

            #expect(answer == "ok")
            #expect(deltas == ["ok"])
            #expect(gateway.calledModels.map(\.provider) == [
                route.primary.provider, fallback.provider,
            ])
        }
    }

    @Test("pre-output timeout and 5xx failures can use another vendor")
    func transientFallback() async throws {
        try await withSeededProviderKeys {
            let route = globalAutoRoute()
            let fallback = try #require(route.alternates.first)
            func assertFallback(_ error: Error) async throws {
                let gateway = FailoverScriptGateway([
                    .init(deltas: [], result: .failure(error)),
                    .init(deltas: ["recovered"], result: .success("recovered")),
                ])
                let sut = orchestrator(
                    gateway, selection: LLMCatalog.autoID, fallbacks: [fallback])

                let answer = try await sut.streamChat(
                    system: "s", user: "u", images: [], model: LLMCatalog.auto,
                    onDelta: { _ in })

                #expect(answer == "recovered")
                #expect(gateway.calledModels.map(\.provider) == [
                    route.primary.provider, fallback.provider,
                ])
            }

            try await assertFallback(LLMError.http(
                errorSource(for: route.primary.provider), 503, "upstream unavailable"))
            try await assertFallback(URLError(.timedOut))
        }
    }

    @Test("no vendor is retried after the first non-empty output delta")
    func noFallbackAfterOutput() async throws {
        // Ключи закреплены: без подмены `ProviderKeyStore.current` читает
        // связку ключей САМОЙ МАШИНЫ, и отбор провайдеров зависит от того,
        // вставил ли сопровождающий ключ в приложение. Здесь пул пуст
        // намеренно — так этот набор и вёл себя, — но теперь это сказано,
        // а не унаследовано от машины.
        await withoutProviderKeys {
            let original = LLMError.http(
                "OpenAI", 503, "stream broke account=customer-secret sk-proj-tail")
            let gateway = FailoverScriptGateway([
                .init(deltas: ["partial"], result: .failure(original)),
                .init(deltas: ["duplicate"], result: .success("duplicate")),
            ])
            let sut = orchestrator(gateway, selection: openAI.id)
            var deltas: [String] = []

            do {
                _ = try await sut.streamChat(
                    system: "s", user: "u", images: [], model: openAI,
                    onDelta: { deltas.append($0) })
                Issue.record("expected the interrupted provider error")
            } catch let error as AutoOrchestrator.ProviderFailoverError {
                guard error.outputStarted,
                      error.attempts == [.init(provider: .openAI, category: .unavailable)] else {
                    Issue.record("unexpected error: \(type(of: error))")
                    return
                }
                #expect(!error.localizedDescription.contains("customer-secret"))
                #expect(!error.localizedDescription.contains("sk-proj-tail"))
            } catch {
                Issue.record("unexpected error: \(type(of: error))")
            }

            #expect(deltas == ["partial"])
            #expect(gateway.calledModels.map(\.provider) == [.openAI])
        }
    }

    @Test("the output-started retry barrier is safe across concurrent callbacks")
    func concurrentOutputBarrier() async {
        let gateway = ConcurrentDeltaFailureGateway()
        let sut = AutoOrchestrator(
            inner: gateway,
            selectionProvider: { self.openAI.id },
            tierProvider: { .premium },
            directClientMode: { true },
            fallbackResolver: { _, _, _ in [self.google] })

        do {
            _ = try await sut.streamChat(
                system: "s", user: "u", images: [], model: openAI, onDelta: { _ in })
            Issue.record("expected stream failure")
        } catch let error as AutoOrchestrator.ProviderFailoverError {
            guard error.outputStarted,
                  error.attempts == [.init(provider: .openAI, category: .unavailable)] else {
                Issue.record("unexpected error: \(type(of: error))")
                return
            }
        } catch {
            Issue.record("unexpected error: \(type(of: error))")
        }
        #expect(gateway.callCount == 1)
    }

    @Test("one configured provider never exposes a raw funding body")
    func safeSingleProviderFailure() async throws {
        // Ключи закреплены: без подмены `ProviderKeyStore.current` читает
        // связку ключей САМОЙ МАШИНЫ, и отбор провайдеров зависит от того,
        // вставил ли сопровождающий ключ в приложение. Здесь пул пуст
        // намеренно — так этот набор и вёл себя, — но теперь это сказано,
        // а не унаследовано от машины.
        await withoutProviderKeys {
            let gateway = FailoverScriptGateway([
                .init(deltas: [], result: .failure(
                    LLMError.http("OpenAI", 402,
                                  "billing account customer-secret sk-proj-tail"))),
            ])
            let sut = orchestrator(gateway, selection: openAI.id, fallbacks: [])

            do {
                _ = try await sut.streamChat(
                    system: "s", user: "u", images: [], model: openAI, onDelta: { _ in })
                Issue.record("expected bounded provider failure")
            } catch let error as AutoOrchestrator.ProviderFailoverError {
                #expect(!error.outputStarted)
                #expect(error.attempts == [.init(provider: .openAI, category: .funding)])
                #expect(!error.localizedDescription.contains("customer-secret"))
                #expect(!error.localizedDescription.contains("sk-proj-tail"))
            } catch {
                Issue.record("unexpected error: \(type(of: error))")
            }
            #expect(gateway.calledModels.count == 1)
        }
    }

    @Test("non-retryable direct-provider rejections are sanitized without fallback")
    func safeRequestRejection() async throws {
        // Ключи закреплены: без подмены `ProviderKeyStore.current` читает
        // связку ключей САМОЙ МАШИНЫ, и отбор провайдеров зависит от того,
        // вставил ли сопровождающий ключ в приложение. Здесь пул пуст
        // намеренно — так этот набор и вёл себя, — но теперь это сказано,
        // а не унаследовано от машины.
        await withoutProviderKeys {
            let gateway = FailoverScriptGateway([
                .init(deltas: [], result: .failure(
                    LLMError.http("OpenAI", 400, "private request echo customer-secret"))),
                .init(deltas: ["must not run"], result: .success("must not run")),
            ])
            let sut = orchestrator(gateway, selection: openAI.id)

            do {
                _ = try await sut.streamChat(
                    system: "s", user: "u", images: [], model: openAI, onDelta: { _ in })
                Issue.record("expected bounded rejection")
            } catch let error as AutoOrchestrator.ProviderFailoverError {
                #expect(!error.outputStarted)
                #expect(error.attempts == [.init(provider: .openAI, category: .rejected)])
                #expect(!error.localizedDescription.contains("customer-secret"))
            } catch {
                Issue.record("unexpected error: \(type(of: error))")
            }
            #expect(gateway.calledModels.count == 1)
        }
    }

    @Test("only global Auto, council, and orchestration selections permit cross-provider retry")
    func crossProviderSelectionPolicy() {
        #expect(!AutoOrchestrator.selectionPermitsCrossVendorFailover(openAI.id))
        #expect(!AutoOrchestrator.selectionPermitsCrossVendorFailover("auto:openAI"))
        #expect(!AutoOrchestrator.selectionPermitsCrossVendorFailover("auto:not-a-provider"))
        #expect(!AutoOrchestrator.selectionPermitsCrossVendorFailover("orchestrate:not-a-level"))
        #expect(AutoOrchestrator.selectionPermitsCrossVendorFailover(LLMCatalog.autoID))
        #expect(AutoOrchestrator.selectionPermitsCrossVendorFailover(LLMCatalog.councilUS))
        #expect(AutoOrchestrator.selectionPermitsCrossVendorFailover(LLMCatalog.councilCN))
        #expect(AutoOrchestrator.selectionPermitsCrossVendorFailover(
            OrchestrationLevel.max.selectionID))
    }

    @Test("explicit Auto preserves the requested output budget across provider retry")
    func autoFallbackPreservesOutputBudget() async throws {
        try await withSeededProviderKeys {
            let route = globalAutoRoute()
            let fallback = try #require(route.alternates.first)
            let gateway = FailoverScriptGateway([
                .init(deltas: [], result: .failure(
                    LLMError.http(
                        errorSource(for: route.primary.provider), 503, "unavailable"))),
                .init(deltas: ["recovered"], result: .success("recovered")),
            ])
            let sut = orchestrator(
                gateway, selection: LLMCatalog.autoID, fallbacks: [fallback])

            let answer = try await sut.streamChat(
                system: "s", user: "u", images: [], model: LLMCatalog.auto,
                maxOutputTokens: OutputTokenBudget.explicitUserFacing) { _ in }

            #expect(answer == "recovered")
            #expect(gateway.calledModels.map(\.provider) == [
                route.primary.provider, fallback.provider,
            ])
            #expect(gateway.calledOutputBudgets == [
                OutputTokenBudget.explicitUserFacing,
                OutputTokenBudget.explicitUserFacing,
            ])
        }
    }

    @Test("aggregate failure is bounded and never exposes upstream bodies")
    func safeAggregateFailure() async {
        await withSeededProviderKeys {
            let route = globalAutoRoute()
            let alternates = Array(route.alternates.prefix(2))
            #expect(alternates.count == 2)
            guard alternates.count == 2 else { return }
            let gateway = FailoverScriptGateway([
                .init(deltas: [], result: .failure(
                    LLMError.http(errorSource(for: route.primary.provider), 402,
                                  "secret-account-id primary-body"))),
                .init(deltas: [], result: .failure(
                    LLMError.http(errorSource(for: alternates[0].provider), 503,
                                  "private-second-body"))),
                .init(deltas: [], result: .failure(
                    LLMError.http(errorSource(for: alternates[1].provider), 401,
                                  "private-third-body"))),
            ])
            let sut = orchestrator(
                gateway, selection: LLMCatalog.autoID, fallbacks: alternates)

            do {
                _ = try await sut.streamChat(
                    system: "s", user: "u", images: [], model: LLMCatalog.auto,
                    onDelta: { _ in })
                Issue.record("expected aggregate failure")
            } catch let error as AutoOrchestrator.ProviderFailoverError {
                let message = error.localizedDescription
                #expect(error.attempts.count == 3)
                #expect(!error.outputStarted)
                #expect(error.attempts.map(\.provider) == [
                    route.primary.provider, alternates[0].provider, alternates[1].provider,
                ])
                #expect(error.attempts.map(\.category) == [
                    .funding, .unavailable, .authentication,
                ])
                #expect(!message.contains("secret-account-id"))
                #expect(!message.contains("private-second-body"))
                #expect(!message.contains("private-third-body"))
            } catch {
                Issue.record("unexpected error: \(type(of: error))")
            }
        }
    }

    @Test("Backend session 401 and Cruxwing credit-cap 429 are preserved",
          arguments: [401, 429])
    func backendErrorsDoNotFailOver(status: Int) async {
        // Ключи закреплены — см. соседние проверки: без подмены отбор
        // провайдеров зависит от связки ключей самой машины.
        await withoutProviderKeys {
            let body = status == 429
                ? "You need 2 compute credits, but only 0 remain this period."
                : "session expired"
            let gateway = FailoverScriptGateway([
                .init(deltas: [], result: .failure(LLMError.http("Backend", status, body))),
                .init(deltas: ["must not run"], result: .success("must not run")),
            ])
            let sut = orchestrator(gateway, selection: openAI.id)

            do {
                _ = try await sut.streamChat(
                    system: "s", user: "u", images: [], model: openAI, onDelta: { _ in })
                Issue.record("expected backend error")
            } catch {
                guard case LLMError.http("Backend", let actualStatus, let actualBody) = error else {
                    Issue.record("backend error was replaced")
                    return
                }
                #expect(actualStatus == status)
                #expect(actualBody == body)
                if status == 429 {
                    #expect(CreditExhaustion.quotaMessage(
                        from: error, managed: true) == body)
                }
            }
            #expect(gateway.calledModels.count == 1)
        }
    }

    @Test("managed mode never converts a provider-shaped failure into client failover")
    func managedModeDoesNotFailOver() async throws {
        // Ключи закреплены: без подмены `ProviderKeyStore.current` читает
        // связку ключей САМОЙ МАШИНЫ, и отбор провайдеров зависит от того,
        // вставил ли сопровождающий ключ в приложение. Здесь пул пуст
        // намеренно — так этот набор и вёл себя, — но теперь это сказано,
        // а не унаследовано от машины.
        await withoutProviderKeys {
            let gateway = FailoverScriptGateway([
                .init(deltas: [], result: .failure(LLMError.http("OpenAI", 402, "funds"))),
                .init(deltas: ["must not run"], result: .success("must not run")),
            ])
            let sut = orchestrator(gateway, selection: openAI.id, direct: false)

            do {
                _ = try await sut.streamChat(
                    system: "s", user: "u", images: [], model: openAI, onDelta: { _ in })
                Issue.record("expected original error")
            } catch {
                guard case LLMError.http("OpenAI", 402, _) = error else {
                    Issue.record("original error was replaced")
                    return
                }
            }
            #expect(gateway.calledModels.count == 1)
        }
    }

    @Test("classification distinguishes provider funds from Cruxwing credits")
    func classification() {
        #expect(AutoOrchestrator.failoverCategory(
            for: LLMError.http("OpenAI", 402, ""), provider: .openAI) == .funding)
        #expect(AutoOrchestrator.failoverCategory(
            for: LLMError.http("OpenAI", 429, "insufficient_quota"),
            provider: .openAI) == .funding)
        #expect(AutoOrchestrator.failoverCategory(
            for: LLMError.http("OpenAI", 429, "requests per minute"),
            provider: .openAI) == .rateLimited)
        #expect(AutoOrchestrator.failoverCategory(
            for: LLMError.http("Backend", 429, "compute credits"),
            provider: .openAI) == nil)
        #expect(AutoOrchestrator.failoverCategory(
            for: LLMError.http("Orchestrate", 401, "sign in"),
            provider: .openAI) == nil)
        #expect(AutoOrchestrator.failoverCategory(
            for: URLError(.cancelled), provider: .openAI) == nil)
    }
}
