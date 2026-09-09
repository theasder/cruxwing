import Foundation

/// Legacy managed-gateway usage signals. Direct BYOK neither reads nor writes
/// these counters: Cruxwing does not need local product analytics or a funded
/// allowance when the user owns the provider account.
struct UsageStats {
    let meetings: Int          // completed recordings
    let aiRequests: Int        // Quick Prompts + ask-box runs
    let daysSinceFirstLaunch: Int
}

enum UsageTracker {
    private static let d = UserDefaults.standard
    private enum Key {
        static let firstLaunch = "usage.firstLaunch"
        static let meetings = "usage.meetings"
        static let aiRequests = "usage.aiRequests"
        static let tariffMonth = "usage.tariffMonth"
        static let copilotSeconds = "usage.copilotSeconds"
        static let groundedCycles = "usage.groundedCycles"
    }

    /// Set on first read, so day-0 is the first launch.
    static var firstLaunch: Date {
        if let date = d.object(forKey: Key.firstLaunch) as? Date { return date }
        let now = Date()
        d.set(now, forKey: Key.firstLaunch)
        return now
    }

    static var meetings: Int { d.integer(forKey: Key.meetings) }
    static var aiRequests: Int { d.integer(forKey: Key.aiRequests) }

    static func recordMeeting() {
        guard Config.managedUsageLimitsEnabled else { return }
        d.set(meetings + 1, forKey: Key.meetings)
    }

    static func recordAIRequest() {
        guard Config.managedUsageLimitsEnabled else { return }
        d.set(aiRequests + 1, forKey: Key.aiRequests)
    }

    static var copilotSecondsThisMonth: Int {
        rollTariffMonthIfNeeded()
        return d.integer(forKey: Key.copilotSeconds)
    }

    static var groundedCyclesThisMonth: Int {
        rollTariffMonthIfNeeded()
        return d.integer(forKey: Key.groundedCycles)
    }

    static func recordCopilot(seconds: Int) {
        guard Config.managedUsageLimitsEnabled, seconds > 0 else { return }
        rollTariffMonthIfNeeded()
        d.set(copilotSecondsThisMonth + seconds, forKey: Key.copilotSeconds)
    }

    /// Reserve one bounded MCP-grounded research cycle. The UI calls this
    /// before fan-out. Direct BYOK has no Cruxwing quota; the inherited managed
    /// gateway keeps its monthly reservation semantics.
    static func consumeGroundedCycle(for tier: Tier) -> Bool {
        guard Config.managedUsageLimitsEnabled else { return true }
        rollTariffMonthIfNeeded()
        let allowance = TariffAllowance.forTier(tier)
        let used = groundedCyclesThisMonth
        guard UsageLimitPolicy.permits(
            managedLimitsEnabled: Config.managedUsageLimitsEnabled,
            withinManagedLimit: allowance.canRunGroundedCycle(used: used)
        ) else { return false }
        guard Config.managedUsageLimitsEnabled else { return true }
        d.set(used + 1, forKey: Key.groundedCycles)
        return true
    }

    static var stats: UsageStats {
        let days = Calendar.current.dateComponents([.day], from: firstLaunch, to: Date()).day ?? 0
        return UsageStats(meetings: meetings, aiRequests: aiRequests, daysSinceFirstLaunch: max(0, days))
    }

    private static func rollTariffMonthIfNeeded(now: Date = Date()) {
        if Config.billingPeriodAnchor == nil,
           (Config.purchasedTier ?? .free).rank > Tier.free.rank,
           Config.llmViaBackend {
            // Paid entitlements use activation-anchored periods. Wait for the
            // profile fetch to restore the anchor instead of calendar rollover.
            return
        }
        let start = TariffPeriod.currentStart(anchor: Config.billingPeriodAnchor, now: now)
        let key = ISO8601DateFormatter().string(from: start)
        guard d.string(forKey: Key.tariffMonth) != key else { return }
        d.set(key, forKey: Key.tariffMonth)
        d.set(0, forKey: Key.copilotSeconds)
        d.set(0, forKey: Key.groundedCycles)
    }
}
