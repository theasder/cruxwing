// Safe configuration for a plain clone, tests, and every distribution build.
//
// Local `app/build.sh` runs may generate the ignored
// `LocalSecrets.generated.swift` and compile it with ORAKUL_LOCAL_CONFIG.
// This tracked file is never rewritten by a build: a routine local build must
// not turn credentials into a commit-ready Git diff.
#if !ORAKUL_LOCAL_CONFIG
enum Secrets {
    // Local/test builds may use the gitignored .env Desktop OAuth client.
    // MEETGPT_DIST=1 blanks both values: sw() пропускает только публичные настройки.
    static let googleClientID  = ""
    // A native OAuth client cannot keep this credential confidential. Local and
    // tester builds may inject it from the gitignored .env; public distribution
    // builds still scrub it so they cannot accidentally reuse a private project.
    static let googleClientSecret = ""
    static let backendBaseURL  = ""
    static let backendCertPins = ""
    static let transcriptionEngine = "local"
    static let transcriptionChunkSeconds = "6"
    static let transcriptionChunkOverlapSeconds = "1.5"
    static let transcriptionBoundarySlackSeconds = "0"
    static let defaultTier     = "free"
    // NOT read from .env: "1" only when this is a dev build (MEETGPT_DIST unset).
    // Gates the in-app Developer tools (tier preview). Dist builds bake "0".
    static let devMode         = "0"
    static let localWhisperModel = "base"
    static let transcriptionVAD = "on"
    static let transcriptionLanguage = "multi"
    static let llmGateway      = "direct"
    static let ensemblePanel   = ""
    static let ensembleChairman = ""
    static let hubSpotClientID = ""
    static let hubSpotClientSecret = ""
    static let asanaClientID = ""
    static let asanaClientSecret = ""
    static let affinityClientID = ""
    static let affinityClientSecret = ""
    static let zoomClientID = ""
    static let zoomClientSecret = ""
    static let googleSignInClientID = ""
    static let googleSignInClientSecret = ""
    static let gmailClientID = ""
    static let gmailClientSecret = ""
    static let googleAnalyticsClientID = ""
    static let googleAnalyticsClientSecret = ""
    static let slackBotToken   = ""
    static let slackChannelIDs = ""
    static let confluenceSite  = ""
    static let confluenceEmail = ""
    static let confluenceToken = ""
    static let teamWatchAutoAck = "off"
}
#endif
