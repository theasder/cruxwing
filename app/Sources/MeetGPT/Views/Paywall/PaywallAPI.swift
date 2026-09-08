import Foundation

/// A tariff option from the backend's billing catalog (regionally priced).
struct PaywallPlan: Identifiable, Decodable {
    struct Allowances: Decodable, Equatable {
        let copilotHours: Int
        let computeCredits: Int
        let groundedCycles: Int
    }

    let id: String
    let name: String
    let tier: String
    let interval: String
    let priceCents: Int
    let currency: String
    let offer: Bool
    let offerEndsAt: Date?
    let purchasable: Bool
    let allowances: Allowances
    let features: [String]

    var priceLabel: String {
        let dollars = Double(priceCents) / 100
        let per = interval == "year" ? "yr" : "mo"
        return String(format: "$%.0f/%@", dollars, per)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, tier, interval, priceCents, currency, offer, offerEndsAt
        case purchasable, allowances, features
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        tier = try c.decode(String.self, forKey: .tier)
        interval = try c.decode(String.self, forKey: .interval)
        priceCents = try c.decode(Int.self, forKey: .priceCents)
        currency = try c.decode(String.self, forKey: .currency)
        offer = try c.decode(Bool.self, forKey: .offer)
        purchasable = try c.decodeIfPresent(Bool.self, forKey: .purchasable) ?? (tier != "free")
        allowances = try c.decodeIfPresent(Allowances.self, forKey: .allowances)
            ?? Self.fallbackAllowances(tier: tier)
        features = try c.decode([String].self, forKey: .features)
        if let iso = try c.decodeIfPresent(String.self, forKey: .offerEndsAt) {
            offerEndsAt = ISO8601DateFormatter().date(from: iso)
        } else {
            offerEndsAt = nil
        }
    }

    private static func fallbackAllowances(tier: String) -> Allowances {
        let mapped = TariffAllowance.forTier(Tier(rawValue: tier) ?? .free)
        return Allowances(copilotHours: mapped.copilotHours,
                          computeCredits: mapped.computeCredits,
                          groundedCycles: mapped.groundedCycles)
    }
}

struct PaywallUsage: Decodable {
    struct CreditFrame: Decodable { let computeCredits: Int }
    let tier: String
    let allowances: PaywallPlan.Allowances
    let used: CreditFrame
    let remaining: CreditFrame
    let periodStart: String
}

/// Thin client for the backend billing endpoints.
enum PaywallAPI {
    private static var root: String {
        let base = Config.backendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return base.hasSuffix("/") ? String(base.dropLast()) : base
    }

    /// The user's region drives regional pricing (server applies multipliers).
    private static var region: String {
        Locale.current.region?.identifier ?? ""
    }

    static func plans() async throws -> [PaywallPlan] {
        guard !root.isEmpty,
              let url = URL(string: "\(root)/api/billing/plans?region=\(region)")
        else { return [] }
        let (data, _) = try await BackendPinning.shared.data(from: url)
        struct Response: Decodable { let plans: [PaywallPlan] }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.plans
    }

    /// Developer tier preview, sent so the credits rail reports the SAME plan the
    /// model picker is gating on. Without it Settings previews Pro while the rail
    /// keeps showing the real entitlement. nil outside dev builds, and the server
    /// ignores it unless explicitly enabled and not in production.
    static func applyDevTierPreview(to request: inout URLRequest) {
        guard let preview = Config.devTierOverride else { return }
        request.setValue(preview.rawValue, forHTTPHeaderField: "X-Dev-Tier")
    }

    static func usage() async throws -> PaywallUsage? {
        guard !root.isEmpty,
              let token = await WheesprAuth.validAccessToken(),
              let url = URL(string: "\(root)/api/billing/usage") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        applyDevTierPreview(to: &request)
        let (data, response) = try await BackendPinning.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }
        return try JSONDecoder().decode(PaywallUsage.self, from: data)
    }

    /// The active plan's tier from the profile, or nil when no plan is active.
    static func activePlanTier() async throws -> Tier? {
        guard !root.isEmpty,
              let token = await WheesprAuth.validAccessToken(),
              let url = URL(string: "\(root)/auth/profile") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await BackendPinning.shared.data(for: request)
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let user = object?["user"] as? [String: Any],
              let plan = user["plan"] as? [String: Any],
              (plan["status"] as? String) == "active" || (plan["unlimited"] as? Bool) == true else {
            Config.billingPeriodAnchor = nil
            return nil
        }
        if let activatedAt = plan["activatedAt"] as? String {
            Config.billingPeriodAnchor = ISO8601DateFormatter().date(from: activatedAt)
        }
        let tierName = ((plan["metadata"] as? [String: Any])?["tier"] as? String) ?? "premium"
        return Tier(rawValue: tierName) ?? .premium
    }

    /// M2d — the server is the tier truth when the backend serves LLM: refresh
    /// the purchased tier at launch so cancellations downgrade and purchases
    /// made on another device arrive. Semantics: signed out → keep the cached
    /// tier (re-checked on next sign-in); signed in + no active plan → clear
    /// it; network failure → leave the cache untouched.
    static func refreshEntitlement() async {
        guard Config.llmViaBackend else { return }
        guard await WheesprAuth.validAccessToken() != nil else { return }
        do {
            Config.purchasedTier = try await activePlanTier()
        } catch {
            // Offline / backend down: the cached entitlement stands.
        }
    }
}
