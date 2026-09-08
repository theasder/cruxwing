import Foundation

/// A small first-party role profile used by the picker and generic output frame.
/// Prompt-specific methodology comes only from Orakul's built-in prompt layer
/// and the separately reviewed nine-skill runtime bundle.
struct RolePosition: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let symbol: String
}

enum RoleSkillMatrix {
    /// Explicit first-party UI choices. Keeping this small table in compiled
    /// source avoids a second, independently mutable prompt-data corpus.
    static let positions: [RolePosition] = [
        .init(id: "founder-ceo", label: "Основатель / гендиректор", symbol: "star.circle"),
        .init(id: "product-manager", label: "Продакт-менеджер", symbol: "shippingbox"),
        .init(id: "sales-ae", label: "Продажи / аккаунт-менеджер", symbol: "dollarsign.circle"),
        .init(id: "marketing-manager", label: "Маркетинг", symbol: "megaphone"),
        .init(id: "ops-lead", label: "BizOps / операционный директор", symbol: "gearshape"),
        .init(
            id: "tech-lead", label: "Инженер / техлид",
            symbol: "chevron.left.forwardslash.chevron.right"),
        .init(
            id: "engineering-manager", label: "Руководитель разработки",
            symbol: "wrench.and.screwdriver"),
        .init(
            id: "customer-success", label: "Клиентский успех",
            symbol: "heart.text.square"),
        .init(id: "project-manager", label: "Проектный менеджер", symbol: "checklist"),
        .init(id: "recruiter-hr", label: "Рекрутинг / HR", symbol: "person.badge.plus"),
    ]

    static func position(id: String?) -> RolePosition? {
        guard let id else { return nil }
        return positions.first { $0.id == id }
    }

    /// Generic role framing. The previous 120 role×button hints were distilled
    /// from an untraceable bulk skill pool and are deliberately not shipped.
    /// Sentinel id for "the user wrote their own role" (Config.userCustomRole).
    static let customRoleID = "custom"

    static func guidance(roleID: String?, promptID _: String?) -> String? {
        if roleID == customRoleID {
            let text = Config.userCustomRole.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            // No per-button hints for free-text roles — the description itself
            // is the frame.
            return "ROLE — The user describes their role as: \(text). Frame every output for that role's work."
        }
        guard let role = position(id: roleID) else { return nil }
        return "ROLE — The user is a \(role.label). Frame every output for that role's work."
    }
}
