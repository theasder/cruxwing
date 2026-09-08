import Foundation

/// Legacy capability-tier adapter retained while tariff-shaped call sites are
/// isolated from the public target. It never derives access from engagement.
enum TierPolicy {
    static func effectiveTier(stats _: UsageStats, floor: Tier) -> Tier {
        floor
    }

    static func status(stats _: UsageStats, tier: Tier) -> String {
        let allowance = TariffAllowance.forTier(tier)
        return "\(tier.label) · \(allowance.copilotHours)h Copilot · \(allowance.computeCredits) credits / month"
    }
}
