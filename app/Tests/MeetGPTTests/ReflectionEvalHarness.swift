import Foundation
import Testing
@testable import MeetGPT

/// The eval harness: judge REAL recorded sessions with the deterministic
/// critics and print the rates.
///
/// It lives in the test target because that is the only thing in this package
/// that can import the app, and it is gated on an environment variable so a
/// machine with no corpus (CI, a fresh checkout) stays green instead of
/// reporting a perfect score over zero sessions.
///
///     CRUXWING_EVAL_CORPUS="$HOME/Library/Application Support/ai.orakul.desktop/Sessions" \
///       swift test --filter ReflectionEvalHarness
///
/// Nothing here calls a model. The corpus is the user's own history: every
/// saved session carries the transcript alongside the blind spots, answers and
/// digest produced from it, so the harness measures production output for free.
@Suite("Reflection eval harness")
struct ReflectionEvalHarness {

    private static var corpusRoot: URL? {
        guard let path = ProcessInfo.processInfo.environment["CRUXWING_EVAL_CORPUS"],
              !path.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    private static var hasCorpus: Bool { corpusRoot != nil }

    /// A checked-in default makes this a regression gate rather than a report
    /// that can never fail. A corpus owner may tighten it for a particular run.
    private static var maximumRuleViolationRate: Double {
        let raw = ProcessInfo.processInfo.environment["ORAKUL_REFLECTION_MAX_RULE_RATE"]
        guard let raw, let value = Double(raw), (0...1).contains(value) else { return 0.25 }
        return value
    }

    @Test(
        "judge the recorded corpus and enforce the per-rule violation ceiling",
        .enabled(
            if: Self.hasCorpus,
            "Set CRUXWING_EVAL_CORPUS to an Orakul Sessions directory to run this private-corpus eval."))
    func evaluateCorpus() throws {
        let corpusRoot = try #require(Self.corpusRoot)

        let store = SessionStore(root: corpusRoot)
        let (summary, scores) = ReflectionEval.run(store: store)
        print("\n" + ReflectionEval.render(summary) + "\n")

        // The sessions with the most to answer for, so a regression points at a
        // meeting rather than at a percentage.
        let worstSessions = scores
            .filter { !$0.tally.findings.isEmpty }
            .sorted { $0.tally.findings.count > $1.tally.findings.count }
            .prefix(5)
        if !worstSessions.isEmpty {
            print("Worst sessions:")
            for score in worstSessions {
                print("  \(score.tally.findings.count) finding(s) — \(score.title)")
            }
            print("")
        }

        #expect(summary.sessions > 0,
                "the configured corpus contains no readable sessions")
        #expect(summary.judged.values.reduce(0, +) > 0,
                "sessions loaded, but the critics did not judge any persisted output")
        for rule in summary.rules {
            #expect(rule.rate <= Self.maximumRuleViolationRate,
                    Comment(rawValue:
                        "\(rule.rule) violated \(rule.hits)/\(rule.judged) items; "
                        + "ceiling is \(Self.maximumRuleViolationRate)"))
        }
    }
}
