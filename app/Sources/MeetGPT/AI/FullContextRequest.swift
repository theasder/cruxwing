import Foundation

/// Opt-in full-context mode: send the whole transcript and everything attached,
/// to models whose window can hold it.
///
/// **The default is untouched.** This is a deliberate, potentially more
/// expensive provider request, not a better default. A user who never opts in
/// sees no change in behaviour or provider spend.
///
/// **Per request, never a setting.** A persistent switch would keep charging
/// after the one long call that justified it, and the person who turned it on in
/// March would not connect the bill in June to the toggle. It resets after every
/// send.
///
/// **Bounded before the send.** Eligibility and the input ceiling come from the
/// verified metadata in the local model catalogue. Missing metadata fails
/// closed; there is no copied server pricing contract in public Cruxwing.
enum FullContextRequest {

    /// Chars per token. Deliberately LOW so the estimate errs high — quoting
    /// under and charging over is the failure that loses trust.
    static let charsPerToken = 3.5
    /// Below this a bigger window is a rounding difference sold as a feature.
    static let minimumContextTokens = 200_000
    /// Headroom for the system prompt, attached material and the answer.
    static let windowUtilisation = 0.75
    /// The ordinary input envelope.
    static let defaultEnvelopeChars = 8_000

    /// Whether the mode may be offered for this model at all.
    ///
    /// About the MODEL, not the user. Tier gating is separate, because "your
    /// plan does not include this" and "this model cannot do this" are different
    /// messages and merging them produces the unhelpful one.
    static func isEligible(_ model: LLMModel) -> Bool {
        guard let tokens = model.contextTokens else { return false }
        return tokens >= minimumContextTokens
    }

    /// Largest input this model may be sent in full-context mode.
    ///
    /// Returns the ordinary envelope for an ineligible model rather than
    /// trapping, so a caller that forgets to check degrades to normal behaviour
    /// instead of building a request the provider will reject.
    static func maximumInputChars(for model: LLMModel) -> Int {
        guard isEligible(model), let tokens = model.contextTokens else {
            return defaultEnvelopeChars
        }
        return Int(Double(tokens) * windowUtilisation * charsPerToken)
    }

    /// Conservative input-token estimate for what will actually be sent. The
    /// vendor—not Cruxwing—owns the price, so a made-up cross-provider credit
    /// conversion would be less honest than this measurable quantity.
    static func estimatedInputTokens(for inputChars: Int) -> Int {
        Int(ceil(Double(max(0, inputChars)) / charsPerToken))
    }

    /// What the composer needs to show before sending.
    struct Quote: Equatable {
        /// Whether the mode would actually apply to this send.
        let active: Bool
        /// Why not, when it was asked for and refused. Nil when it applies or
        /// was never requested — a refusal must be stated, because silently
        /// falling back would leave the user believing the whole transcript went.
        let refusal: String?
        let limitChars: Int
        let estimatedInputTokens: Int
        /// True when even the larger envelope cannot hold everything.
        let truncated: Bool

        /// One line for the composer. It names what is sent; actual billing is
        /// governed by the provider and model the user configured.
        var summary: String {
            if let refusal { return refusal }
            guard active else { return "" }
            let thousands = limitChars / 1_000
            return truncated
                ? "Full context · about \(estimatedInputTokens) input tokens · sending the last \(thousands)k characters"
                : "Full context · about \(estimatedInputTokens) input tokens · sending everything"
        }
    }

    static func quote(model: LLMModel,
                      requested: Bool,
                      inputChars: Int) -> Quote {
        let ordinarySent = min(max(0, inputChars), defaultEnvelopeChars)
        guard requested else {
            return Quote(active: false, refusal: nil,
                         limitChars: defaultEnvelopeChars,
                         estimatedInputTokens: estimatedInputTokens(for: ordinarySent),
                         truncated: inputChars > defaultEnvelopeChars)
        }
        guard isEligible(model) else {
            return Quote(
                active: false,
                refusal: model.contextTokens == nil
                    ? "\(model.label) has no verified context window, so full context isn’t offered for it."
                    : "\(model.label)’s context window is too small for full context.",
                limitChars: defaultEnvelopeChars,
                estimatedInputTokens: estimatedInputTokens(for: ordinarySent),
                truncated: inputChars > defaultEnvelopeChars)
        }
        let limit = maximumInputChars(for: model)
        let sent = min(max(0, inputChars), limit)
        return Quote(active: true, refusal: nil, limitChars: limit,
                     estimatedInputTokens: estimatedInputTokens(for: sent),
                     truncated: inputChars > limit)
    }
}
