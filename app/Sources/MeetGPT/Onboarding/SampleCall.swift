import Foundation

/// The 90-second fictional call a new user watches before their first real one.
///
/// It exists because the product only demonstrates itself during a live meeting,
/// and someone who installs on a Thursday evening has nothing to do until
/// Monday. Replaying a written call closes that gap without waiting for one.
///
/// Two properties are load-bearing:
///
///   * **It is canned, and says so.** The banner names it fiction in every frame,
///     the co-pilot output is labelled prepared, and `AppState.sampleRunActive`
///     keeps all of it out of history, the ledger and the usage counters.
///   * **It obeys the product's own evidence rule.** The prepared blind spot and
///     the prepared decision each quote a line that really is in the script,
///     verified by `SuggestionGrounding` — the same mechanical check applied to
///     live suggestions. Teaching a new user that the co-pilot quotes is only
///     honest if the demonstration quotes too.
///
/// The script itself is COPY, not logic: replacing it with a sales call or a
/// hiring debrief is a text edit, and the tests hold any new script to the same
/// grounding and ordering rules.
struct SampleCall {
    struct Line: Equatable {
        /// Position in the fictional call, in call-seconds (not wall clock).
        let atSeconds: Double
        let source: TranscriptSource
        let speaker: String
        let text: String
    }

    /// What the sample offers to log. Deliberately NOT `DecisionLogService`'s
    /// type: this never becomes a ledger row, and giving it the ledger's shape
    /// would invite exactly that mistake.
    struct PreparedDecision: Equatable {
        let text: String
        let owner: String
        /// The line in the script that supports it.
        let evidence: String
    }

    /// Replay rate. 87 call-seconds in about 11 wall-clock seconds: long enough
    /// to read, short enough that nobody reaches for Skip.
    static let playbackSpeed: Double = 8

    /// Shown on every prepared card. The sample never calls a model — that is
    /// what keeps it working offline, signed out, and free of Copilot hours — so
    /// the output has to say what it is.
    static let preparedLabel = "Prepared as an example — your own calls are analysed live."

    let title: String
    let goal: String
    let lines: [Line]
    let preparedSuggestion: Suggestion
    let preparedDecision: PreparedDecision

    var durationSeconds: Double { (lines.last?.atSeconds ?? 0) + Self.tailSeconds }
    var wallClockSeconds: Double { durationSeconds / Self.playbackSpeed }

    /// Everything said in the call, for grounding checks.
    var fullTranscriptText: String { lines.map(\.text).joined(separator: " ") }

    /// Lines revealed by a given point in the replay — a growing prefix, so the
    /// transcript never rewrites itself mid-sample.
    ///
    /// Strictly BEFORE the clock, not at it: a replay that has run for zero
    /// seconds has said nothing, and the opening line landing before the first
    /// tick makes the sample look pre-filled rather than live.
    func lines(throughWallClock seconds: Double) -> [Line] {
        let callSeconds = seconds * Self.playbackSpeed
        return lines.filter { $0.atSeconds < callSeconds }
    }

    /// Real transcript rows, so the sample renders through the same view the
    /// live product uses rather than a mock built to flatter it.
    func transcriptEntries(startingAt start: Date = Date()) -> [TranscriptEntry] {
        lines.map { line in
            TranscriptEntry(
                source: line.source,
                text: line.text,
                timestamp: start.addingTimeInterval(line.atSeconds),
                speaker: line.speaker)
        }
    }

    /// A card lands one beat AFTER the line it quotes, never before it.
    var suggestionAtWallClock: Double {
        wallClock(afterLineQuoting: preparedSuggestion.evidence)
    }

    var decisionAtWallClock: Double {
        wallClock(afterLineQuoting: preparedDecision.evidence)
    }

    private func wallClock(afterLineQuoting evidence: String?) -> Double {
        guard let evidence else { return wallClockSeconds }
        let match = lines.first {
            SuggestionGrounding.contains(evidence: evidence, in: $0.text)
        }
        guard let match else { return wallClockSeconds }
        return min(wallClockSeconds,
                   (match.atSeconds + Self.cardDelaySeconds) / Self.playbackSpeed)
    }

    /// Room after the last line so the closing beat is not cut off.
    private static let tailSeconds: Double = 4
    /// How long after its quote a card lands, in call-seconds.
    private static let cardDelaySeconds: Double = 3
}

extension SampleCall {
    /// A product call deciding a ship date. Chosen because the decision is
    /// concrete, the blind spot is real rather than clever, and the shape is
    /// recognisable to the people this app is for.
    static let mobileBeta = SampleCall(
        title: "The mobile beta — do we ship it or not",
        goal: "Decide whether the mobile beta ships this month",
        lines: [
            Line(atSeconds: 0, source: .system, speaker: "Dima",
                 text: "Right, the mobile beta. Where are we?"),
            Line(atSeconds: 5, source: .system, speaker: "Polina",
                 text: "Testing accepted everything except offline sync."),
            Line(atSeconds: 12, source: .mic, speaker: "You",
                 text: "How bad is it, honestly?"),
            Line(atSeconds: 17, source: .system, speaker: "Polina",
                 text: "It touches about four per cent of sessions. Reading is not the scary part — the write queue is."),
            Line(atSeconds: 26, source: .system, speaker: "Mark",
                 text: "Support will feel it if it breaks. Last time thirty tickets came in."),
            Line(atSeconds: 34, source: .system, speaker: "Dima",
                 text: "So we hold the whole beta over four per cent of sessions?"),
            Line(atSeconds: 40, source: .system, speaker: "Polina",
                 text: "I would ship behind a flag on the twenty-second and fix it in a patch."),
            Line(atSeconds: 48, source: .mic, speaker: "You",
                 text: "Mark, can support live with that?"),
            Line(atSeconds: 52, source: .system, speaker: "Mark",
                 text: "If the flag is off by default, yes."),
            Line(atSeconds: 57, source: .system, speaker: "Polina",
                 text: "Off by default, on for the internal group."),
            Line(atSeconds: 63, source: .system, speaker: "Dima",
                 text: "Then we decide it this way — the beta ships behind a flag on the twenty-second, and the patch is on Polina."),
            Line(atSeconds: 72, source: .system, speaker: "Mark",
                 text: "I will write the note for support as soon as the date is fixed."),
            Line(atSeconds: 78, source: .mic, speaker: "You",
                 text: "Anything else on this?"),
            Line(atSeconds: 83, source: .system, speaker: "Polina",
                 text: "Nothing from me."),
        ],
        preparedSuggestion: Suggestion(
            title: "Nobody asked what happens to the records already sitting in the offline queue",
            detail: "The flag hides the feature on the twenty-second. It does not decide what the client does with records that entered the queue before the flag was turned off — and that is exactly the path by which support got thirty tickets.",
            kind: .question,
            evidence: "ship behind a flag on the twenty-second and fix it in a patch"),
        preparedDecision: PreparedDecision(
            text: "The mobile beta ships behind a flag on the twenty-second — off by default, on for the internal group. The patch is on Polina.",
            owner: "Polina",
            evidence: "the beta ships behind a flag on the twenty-second, and the patch is on Polina")
    )
}
