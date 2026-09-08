import Testing
import Foundation
@testable import MeetGPT

// Reported from a real call: "after credits were over, features such as blind
// spot were still working". The server rejects an exhausted pool with 429, but
// the background loops swallowed the error with `try?` and kept re-dialing
// every cadence — nothing latched, nothing was surfaced.
@Suite("Credit exhaustion recognition")
struct CreditExhaustionTests {
    @Test("a 429 with the server's upgrade message latches, with the message")
    func recognizesQuota() {
        let error = LLMError.http(
            "Brainstorm", 429,
            #"{"error":"You need 2 compute credits, but only 0 remain this period — upgrade or add credits to continue.","upgrade":true}"#)
        let message = CreditExhaustion.quotaMessage(from: error, managed: true)
        #expect(message?.contains("upgrade or add credits") == true)
        // The JSON envelope is unwrapped — a banner must not show raw JSON.
        #expect(message?.contains("{") == false)
    }

    @Test("other failures never latch the quota gate")
    func ignoresOtherErrors() {
        #expect(CreditExhaustion.quotaMessage(
            from: LLMError.http("Backend", 503, "down"), managed: true) == nil)
        #expect(CreditExhaustion.quotaMessage(
            from: LLMError.http("Backend", 403, "tier gate"), managed: true) == nil)
        #expect(CreditExhaustion.quotaMessage(
            from: LLMError.badResponse("Backend"), managed: true) == nil)
        #expect(CreditExhaustion.quotaMessage(
            from: URLError(.timedOut), managed: true) == nil)
    }

    @Test("a 429 with no readable body still latches with a usable sentence")
    func fallbackMessage() {
        let message = CreditExhaustion.quotaMessage(
            from: LLMError.http("Backend", 429, ""), managed: true)
        #expect(message?.isEmpty == false)
        #expect(message?.contains("credit") == true)
    }

    @Test("a direct provider 429 is never relabeled as Orakul credits")
    func directProviderQuotaStaysProviderOwned() {
        let error = LLMError.http(
            "OpenAI", 429, #"{"code":"insufficient_quota"}"#)
        #expect(CreditExhaustion.quotaMessage(from: error, managed: false) == nil)
        #expect(CreditExhaustion.quotaMessage(
            from: LLMError.http("Anthropic", 429, #"{"error":"credits exhausted"}"#),
            managed: false) == nil)
    }
}

@Suite("Tariff allowances")
struct TariffAllowanceTests {
    @Test("every tier exposes the commercial copilot, compute, and grounding limits")
    func allowanceMatrix() {
        #expect(TariffAllowance.forTier(.free) == .init(
            copilotHours: 2, computeCredits: 15, groundedCycles: 3))
        #expect(TariffAllowance.forTier(.pro) == .init(
            copilotHours: 20, computeCredits: 250, groundedCycles: 20))
        #expect(TariffAllowance.forTier(.premium) == .init(
            copilotHours: 40, computeCredits: 750, groundedCycles: 100))
        #expect(TariffAllowance.forTier(.ultra) == .init(
            copilotHours: 60, computeCredits: 1_500, groundedCycles: 300))
    }

    @Test("remaining copilot time includes the active recording and never goes negative")
    func copilotRemaining() {
        let pro = TariffAllowance.forTier(.pro)
        #expect(pro.remainingCopilotSeconds(usedSeconds: 3_600, activeSeconds: 600)
            == 20 * 3_600 - 4_200)
        #expect(pro.remainingCopilotSeconds(usedSeconds: 100_000, activeSeconds: 0) == 0)
    }

    @Test("grounded research is allowed only below the monthly cycle limit")
    func groundedLimit() {
        let free = TariffAllowance.forTier(.free)
        #expect(free.canRunGroundedCycle(used: 2))
        #expect(!free.canRunGroundedCycle(used: 3))
    }

    @Test("direct BYOK is never disabled by an inherited managed allowance")
    func directBYOKBypassesManagedLimits() {
        #expect(UsageLimitPolicy.permits(
            managedLimitsEnabled: false, withinManagedLimit: false))
        #expect(UsageLimitPolicy.remaining(
            managedLimitsEnabled: false, managedRemaining: 0) == .max)
    }

    @Test("the optional managed gateway still enforces its own allowance")
    func managedGatewayKeepsItsLimits() {
        #expect(!UsageLimitPolicy.permits(
            managedLimitsEnabled: true, withinManagedLimit: false))
        #expect(UsageLimitPolicy.permits(
            managedLimitsEnabled: true, withinManagedLimit: true))
        #expect(UsageLimitPolicy.remaining(
            managedLimitsEnabled: true, managedRemaining: -1) == 0)
    }

    @Test("paid usage windows follow the subscription activation anchor")
    func billingAnchor() {
        let formatter = ISO8601DateFormatter()
        let anchor = formatter.date(from: "2026-01-15T10:00:00Z")!
        let now = formatter.date(from: "2026-07-11T12:00:00Z")!
        #expect(formatter.string(from: TariffPeriod.currentStart(anchor: anchor, now: now))
            == "2026-06-15T10:00:00Z")
    }
}

@Suite("Copilot cadence")
struct CopilotCadenceTests {
    @Test("expensive background lenses run on bounded cadences")
    func cadence() {
        #expect(CopilotCadence.blindSpotSeconds == 120)
        #expect(CopilotCadence.blindSpotPaidSeconds == 90)
        #expect(CopilotCadence.agendaSeconds == 300)
        #expect(CopilotCadence.factCheckSeconds == 300)
        #expect(CopilotCadence.rhetoricSeconds == 300)
        #expect(CopilotCadence.facilitationSeconds == 300)
        #expect(CopilotCadence.maxGroundingSources == 2)
    }

    @Test("all 16 Settings combinations reallocate only the funded hourly budget")
    func adaptiveBlindSpotCadenceBudget() {
        let tiers: [Tier] = [.free, .pro, .premium, .ultra]
        for tier in tiers {
            for mask in 0..<16 {
                let agenda = mask & 1 != 0
                let factCheck = mask & 2 != 0
                let rhetoric = mask & 4 != 0
                let facilitation = mask & 8 != 0
                let interval = CopilotCadence.blindSpotSeconds(
                    for: tier,
                    agendaEnabled: agenda,
                    factCheckEnabled: factCheck,
                    rhetoricEnabled: rhetoric,
                    facilitationEnabled: facilitation)
                let scans = 3_600 / Int(interval)
                let specialists = (factCheck ? 12 : 0)
                    + (agenda ? 4 : 0)
                    + (rhetoric ? 4 : 0)
                    + (facilitation ? 4 : 0)
                let spend = scans * CopilotCadence.blindSpotCreditsPerScan(for: tier)
                    + specialists
                #expect(spend <= CopilotCadence.copilotCreditsPerHour(for: tier),
                        "\(tier) mask \(mask) spent \(spend)")
            }
        }
    }

    @Test("disabling optional watches makes Blind Spot faster; all-on preserves tariffs")
    func adaptiveBlindSpotCadenceEndpoints() {
        let tiers: [Tier] = [.free, .pro, .premium, .ultra]
        let allOff = tiers.map {
            CopilotCadence.blindSpotSeconds(
                for: $0, agendaEnabled: false, factCheckEnabled: false,
                rhetoricEnabled: false, facilitationEnabled: false)
        }
        let allOn = tiers.map {
            CopilotCadence.blindSpotSeconds(
                for: $0, agendaEnabled: true, factCheckEnabled: true,
                rhetoricEnabled: true, facilitationEnabled: true)
        }
        let defaultAgendaOnly = tiers.map {
            CopilotCadence.blindSpotSeconds(
                for: $0, agendaEnabled: true, factCheckEnabled: false,
                rhetoricEnabled: false, facilitationEnabled: false)
        }

        #expect(allOff == [67, 75, 79, 82])
        #expect(defaultAgendaOnly == [72, 79, 80, 82])
        #expect(allOn == [CopilotCadence.blindSpotSeconds, 90, 90, 90])
        #expect(zip(allOff, allOn).allSatisfy { $0 <= $1 })
    }

}
