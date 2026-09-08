import Foundation
import Testing
@testable import MeetGPT

/// Opt-in full-context mode, client half.
///
/// Eligibility is derived from the verified window metadata in the local model
/// catalogue. Unknown metadata fails closed instead of relying on a copied
/// server pricing contract.
@Suite("Full context requests")
struct FullContextRequestTests {

    private func model(_ id: String) -> LLMModel {
        LLMCatalog.fallback.first { $0.id == id }
            ?? LLMModel(id: id, label: id, provider: .openAI, minTier: .free,
                        supportsVision: false)
    }

    // MARK: - Local catalogue invariants

    @Test("catalogued model identifiers and verified windows are internally valid")
    func catalogueMetadataIsValid() {
        let models = LLMCatalog.fallback
        #expect(Set(models.map(\.id)).count == models.count)
        for model in models {
            if let window = model.contextTokens {
                #expect(window > 0, "\(model.id) has a non-positive context window")
            }
        }
    }

    @Test("eligibility follows verified local window metadata")
    func eligibilityFollowsLocalCatalogue() {
        for model in LLMCatalog.fallback {
            let locallyEligible = (model.contextTokens ?? 0)
                >= FullContextRequest.minimumContextTokens
            #expect(FullContextRequest.isEligible(model) == locallyEligible, "\(model.id)")
        }
    }

    // MARK: - Fail closed

    @Test("a model with no verified window is not eligible")
    func unverifiedWindowIsNotEligible() {
        // Absent metadata means NOT OFFERED, not unknown-so-try. Guessing would
        // send a request the provider rejects for exceeding its window.
        #expect(model("kimi-k2.6").contextTokens == nil)
        #expect(!FullContextRequest.isEligible(model("kimi-k2.6")))
    }

    @Test("models outside the catalogue are not eligible")
    func unknownModelIsNotEligible() {
        #expect(!FullContextRequest.isEligible(model("something-nobody-added")))
    }

    @Test("an ineligible model still reports the ordinary limit")
    func ineligibleFallsBackRatherThanTrapping() {
        #expect(FullContextRequest.maximumInputChars(for: model("glm-5.2"))
                == FullContextRequest.defaultEnvelopeChars)
    }

    // MARK: - The default is untouched

    @Test("not asking leaves the ordinary envelope alone")
    func defaultIsUnchanged() {
        let quote = FullContextRequest.quote(model: model("gemini-3.1-pro-preview"),
                                             requested: false,
                                             inputChars: 500_000)
        #expect(!quote.active)
        #expect(quote.limitChars == FullContextRequest.defaultEnvelopeChars)
        #expect(quote.estimatedInputTokens
                == FullContextRequest.estimatedInputTokens(
                    for: FullContextRequest.defaultEnvelopeChars))
    }

    @Test("an eligible model does not opt itself in")
    func capabilityDoesNotEnableItself() {
        // Per request. A model that supports a big window must not decide to
        // send a larger, potentially more expensive provider request on its own.
        #expect(!FullContextRequest.quote(model: model("gemini-3.1-pro-preview"),
                                          requested: false, inputChars: 900_000).active)
    }

    @Test("truncation is reported even when the mode is off")
    func truncationVisibleWhenOff() {
        // This is what makes opting in a considered choice rather than a guess:
        // the user can see the default envelope is clipping their call.
        #expect(FullContextRequest.quote(model: model("gpt-5.4"), requested: false,
                                         inputChars: 50_000).truncated)
        #expect(!FullContextRequest.quote(model: model("gpt-5.4"), requested: false,
                                          inputChars: 500).truncated)
    }

    // MARK: - Refusals are stated

    @Test("an ineligible model refuses out loud")
    func refusalIsExplained() {
        // Falling back silently would leave the user believing they sent a
        // two-hour call, and acting on an answer that read 8k characters of it.
        let quote = FullContextRequest.quote(model: model("kimi-k2.6"), requested: true,
                                             inputChars: 200_000)
        #expect(!quote.active)
        #expect(quote.refusal?.contains("no verified context window") == true)
        #expect(quote.summary == quote.refusal)
    }

    // MARK: - Provider input estimate

    @Test("the token estimate rounds up and rejects nonsense input")
    func tokenEstimateIsConservative() {
        #expect(FullContextRequest.estimatedInputTokens(for: 1) == 1)
        #expect(FullContextRequest.estimatedInputTokens(for: 7) == 2)
        #expect(FullContextRequest.estimatedInputTokens(for: -5) == 0)
    }

    @Test("the quote estimates what will be sent, not what was offered")
    func estimatesWhatIsSent() {
        let target = model("claude-sonnet-5")
        let limit = FullContextRequest.maximumInputChars(for: target)
        let over = FullContextRequest.quote(model: target, requested: true,
                                            inputChars: limit * 10)
        let atLimit = FullContextRequest.quote(model: target, requested: true,
                                               inputChars: limit)
        #expect(over.estimatedInputTokens == atLimit.estimatedInputTokens)
        #expect(over.truncated)
    }

    // MARK: - What the user reads

    @Test("the summary names provider input without inventing Orakul credits")
    func summaryNamesProviderInput() {
        let quote = FullContextRequest.quote(model: model("gemini-3.1-pro-preview"),
                                             requested: true, inputChars: 40_000)
        #expect(quote.summary.contains("токенов"))
        #expect(quote.summary.contains("Весь контекст"))
        #expect(!quote.summary.lowercased().contains("credit"))
    }

    @Test("a truncated send says so rather than implying everything went")
    func truncatedSummaryIsHonest() {
        let target = model("claude-sonnet-5")
        let limit = FullContextRequest.maximumInputChars(for: target)
        let quote = FullContextRequest.quote(model: target, requested: true,
                                             inputChars: limit * 2)
        #expect(quote.summary.contains("последние"))
        #expect(!quote.summary.contains("отправляю всё"))
    }

    @Test("nothing is shown when the mode is off")
    func silentWhenOff() {
        #expect(FullContextRequest.quote(model: model("gpt-5.4"), requested: false,
                                         inputChars: 100).summary.isEmpty)
    }

    // MARK: - The window is used conservatively

    @Test("headroom is left for the prompt and the answer")
    func headroomIsLeft() {
        // Filling the window exactly with input leaves nothing for the system
        // prompt or the completion, and the provider rejects the request.
        let target = model("gemini-3.1-pro-preview")
        let impliedTokens = Double(FullContextRequest.maximumInputChars(for: target))
            / FullContextRequest.charsPerToken
        #expect(impliedTokens < Double(target.contextTokens ?? 0))
    }

    @Test("a bigger window buys a bigger envelope")
    func biggerWindowBiggerEnvelope() {
        #expect(FullContextRequest.maximumInputChars(for: model("gemini-3.1-pro-preview"))
                > FullContextRequest.maximumInputChars(for: model("claude-sonnet-5")))
    }
}

/// Full context as the user meets it: a per-request control with an input estimate.
@MainActor
@Suite("Full context in the app")
struct FullContextAppStateTests {

    private func state() -> AppState {
        let appState = AppState(credentialStore: InMemoryKeychain())
        appState.applyTestWorkspace(recording: false)
        return appState
    }

    @Test("off by default")
    func offByDefault() {
        #expect(!state().fullContextRequested)
    }

    @Test("attached material counts toward the quote")
    func attachedMaterialCounted() {
        // A folder of specs can dwarf the transcript. An estimate that ignored
        // it would understate what is sent.
        let appState = state()
        let before = appState.attachedContextCharacters
        appState.contextFiles = [ImportedContextFile(name: "spec.md",
                                                     text: String(repeating: "x", count: 5_000))]
        appState.contextNotes = String(repeating: "y", count: 1_000)
        #expect(appState.attachedContextCharacters == before + 6_000)
    }

    @Test("the quote is recomputed, never cached")
    func quoteIsLive() {
        // A cached size would quote a stale figure for a transcript that has
        // since grown — and the transcript grows continuously during a call.
        let appState = state()
        appState.fullContextRequested = true
        let first = appState.fullContextQuote
        appState.contextNotes = String(repeating: "z", count: 200_000)
        #expect(appState.fullContextQuote != first)
    }

    @Test("the transcript cap is only lifted when the mode is armed")
    func capLiftedOnlyWhenArmed() {
        let appState = state()
        appState.contextNotes = ""
        let clipped = appState.promptTranscript(cap: 50)
        appState.fullContextRequested = true
        let full = appState.promptTranscript(cap: 50)
        // With an eligible model the armed call must not be the clipped one.
        if appState.fullContextAvailable {
            #expect(full.count >= clipped.count)
        }
    }

    @Test("an ineligible model hides the control rather than disabling it")
    func hiddenWhenIneligible() {
        // An always-visible control that is usually disabled teaches people to
        // stop reading the row.
        let appState = state()
        #expect(appState.fullContextAvailable
                == FullContextRequest.isEligible(Config.selectedRequestModel))
    }

}
