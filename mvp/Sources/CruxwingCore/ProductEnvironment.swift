import Foundation

/// Environment variables under the product's current name, honouring the old one.
///
/// The product took a single name on 2026-09-09 and `ORAKUL_*` became
/// `CRUXWING_*`. Those variables are not ours to break: they live in other
/// people's shell profiles, CI jobs and wrapper scripts, and a renamed variable
/// fails the way that costs most — the value is simply not read, the program
/// behaves as though nothing was configured, and nothing says why.
///
/// So both names are read, the current one first. The old one is a fallback, not
/// an alias: writing new documentation against `ORAKUL_*` is what this is meant
/// to make unnecessary.
public enum ProductEnvironment {
    public static let currentPrefix = "CRUXWING_"
    public static let legacyPrefix = "ORAKUL_"

    /// - Parameter suffix: the part after the prefix, e.g. `"HOME"` for
    ///   `CRUXWING_HOME`.
    public static func value(
        _ suffix: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if let current = environment[currentPrefix + suffix] { return current }
        return environment[legacyPrefix + suffix]
    }

    /// Every name this reads, for diagnostics that want to say where a value
    /// came from rather than only what it was.
    public static func names(_ suffix: String) -> (current: String, legacy: String) {
        (currentPrefix + suffix, legacyPrefix + suffix)
    }
}
