import Foundation
import Testing
@testable import MeetGPT

/// A provider with a broken key (Anthropic 401 "invalid x-api-key") must
/// degrade to another configured provider's model, not surface a raw error.
@Suite("LLM auth-failure fallback")
struct AuthFallbackTests {
    @Test("classifies provider auth failures, not backend/session or other errors")
    func classification() {
        // Спрашиваем `failoverCategory` — разбор, по которому идёт работа.
        let category = { (error: Error) in
            AutoOrchestrator.failoverCategory(for: error, provider: .anthropic)
        }
        #expect(category(LLMError.http("Anthropic", 401, "invalid x-api-key")) == .authentication)
        #expect(category(LLMError.missingKey("Anthropic")) == .configuration)
        // Backend 401 = expired session — a different model can't fix it.
        #expect(category(LLMError.http("Backend", 401, "unauthorized")) == nil)
        // Non-auth provider errors get their own category, not authentication.
        #expect(category(LLMError.http("Anthropic", 429, "rate limited")) == .rateLimited)
        #expect(category(LLMError.badResponse("Gemini")) == nil)
    }

    // Проверка отбора запасных живёт в ProviderFallbackTests и спрашивает
    // `providerFallbackModels` — то, что зовёт работа. Здесь стояла её копия
    // через обёртку `authFallbackModel`, которую не звал никто, кроме набора; а
    // перебор внутри шёл с `guard … else { continue }`, поэтому на машине без
    // настроенных провайдеров не выполнялось ни одного утверждения.
}
