import Foundation

/// Settings written under the previous bundle identifier.
///
/// `UserDefaults.standard` is keyed by the bundle identifier, so renaming
/// `ai.orakul.desktop` to `ai.cruxwing.desktop` on 2026-09-09 pointed the app at
/// an empty plist. Nothing is deleted — the old file sits in
/// `~/Library/Preferences` — but everything a person had chosen appears to be
/// gone: the transcription engine resets, the glossary empties, the recording
/// consent they already gave is asked for again, and first-run onboarding
/// returns for someone who has used the app for months.
///
/// That is the same failure the Application Support move exists to prevent, in
/// the one store that is easiest to forget because nobody writes its path down.
enum LegacyPreferences {
    static let legacySuiteName = "ai.orakul.desktop"

    /// Copies the previous domain in when this one has nothing of its own.
    ///
    /// Guarded on a marker rather than on emptiness: `.standard` is never truly
    /// empty on macOS — the system writes its own keys into every domain — so a
    /// count would either run twice or never. The marker is written whatever the
    /// outcome, because a person with no previous install must not be re-checked
    /// on every launch.
    ///
    /// Existing values always win. Adoption fills gaps; it never overwrites a
    /// choice made under the new identity.
    @discardableResult
    static func adoptIfNeeded(
        into defaults: UserDefaults = .standard,
        legacySuiteName: String = legacySuiteName
    ) -> Int {
        let marker = "migration.adoptedLegacyDefaults"
        guard !defaults.bool(forKey: marker) else { return 0 }
        defer { defaults.set(true, forKey: marker) }

        guard let legacy = UserDefaults(suiteName: legacySuiteName) else { return 0 }
        var adopted = 0
        for (key, value) in legacy.persistentDomain(forName: legacySuiteName) ?? [:] {
            // Apple's own keys travel with the domain and mean nothing here.
            guard !key.hasPrefix("NS"), !key.hasPrefix("Apple"), !key.hasPrefix("com.apple") else { continue }
            guard defaults.object(forKey: key) == nil else { continue }
            defaults.set(value, forKey: key)
            adopted += 1
        }
        return adopted
    }
}
