import CryptoKit
import Foundation

/// Local authority for allowing vendored methodology into a model prompt.
///
/// Upstream `risk:` metadata is useful evidence, but it is neither complete nor
/// controlled by Cruxwing. The checked-in allowlist is therefore the authority:
/// every approved record pins the exact source bytes and the built-in prompts
/// for which those bytes were reviewed. Missing, malformed, stale, duplicated,
/// or scope-mismatched policy data means deny.
enum BundledSkillRuntimePolicy {
    struct Review: Decodable, Equatable, Sendable {
        let id: String
        let decision: String
        let sourceRepo: String
        let sourceCommit: String
        let sourceSHA256: String
        let license: String
        let promptIDs: [String]
        let rationale: String

        private enum CodingKeys: String, CodingKey {
            case id, decision, license, rationale
            case sourceRepo = "source_repo"
            case sourceCommit = "source_commit"
            case sourceSHA256 = "source_sha256"
            case promptIDs = "prompt_ids"
        }
    }

    private struct Document: Decodable {
        let schemaVersion: Int
        let defaultDecision: String
        let scope: String
        let reviewRevision: Int
        let reviewedAt: String
        let reviewedSkillCount: Int
        let reviewedSkills: [Review]

        private enum CodingKeys: String, CodingKey {
            case scope
            case schemaVersion = "schema_version"
            case defaultDecision = "default_decision"
            case reviewRevision = "review_revision"
            case reviewedAt = "reviewed_at"
            case reviewedSkillCount = "reviewed_skill_count"
            case reviewedSkills = "reviewed_skills"
        }
    }

    static let reviewsByID: [String: Review] = load()
    static var reviewedIDs: Set<String> { Set(reviewsByID.keys) }

    /// A vendored entry is eligible only for a prompt named in its local review.
    /// An absent upstream verdict can be superseded by this exact-byte review;
    /// an explicit unknown, critical, or malformed verdict remains a veto.
    static func allows(_ skill: BundledSkill, for promptID: String) -> Bool {
        guard !BundledSkillSanitizer.quarantineIDs.contains(skill.id),
              let review = reviewsByID[skill.id],
              review.decision == "allow",
              review.promptIDs.contains(promptID),
              skill.sourceSHA256 == review.sourceSHA256
        else { return false }

        switch skill.risk {
        case .safe, .notApplicable, .unspecified:
            return true
        case .unknown, .critical, .unrecognized:
            return false
        }
    }

    static func allowsForAnyReviewedPrompt(_ skill: BundledSkill) -> Bool {
        guard let review = reviewsByID[skill.id] else { return false }
        return review.promptIDs.contains { allows(skill, for: $0) }
    }

    /// Kept internal so tests can prove malformed documents fail closed without
    /// replacing the process-wide bundle policy.
    static func validatedReviews(from data: Data) -> [String: Review]? {
        guard let document = try? JSONDecoder().decode(Document.self, from: data),
              document.schemaVersion == 1,
              document.defaultDecision == "deny",
              document.scope == "automatic-prompt-methodology-only",
              document.reviewRevision > 0,
              document.reviewedSkillCount == document.reviewedSkills.count,
              document.reviewedAt.range(
                of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
        else { return nil }

        var result: [String: Review] = [:]
        for review in document.reviewedSkills {
            guard review.decision == "allow",
                  review.id.range(
                    of: #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#, options: .regularExpression) != nil,
                  review.sourceRepo.range(
                    of: #"^[^/\s]+/[^/\s]+$"#, options: .regularExpression) != nil,
                  review.sourceCommit.range(
                    of: #"^[0-9a-f]{40}$"#, options: .regularExpression) != nil,
                  review.sourceSHA256.range(
                    of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil,
                  !review.license.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !review.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !review.promptIDs.isEmpty,
                  Set(review.promptIDs).count == review.promptIDs.count,
                  result.updateValue(review, forKey: review.id) == nil
            else { return nil }
        }
        return result
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func load() -> [String: Review] {
        guard let root = SkillResources.skillsDirectory,
              let data = try? Data(contentsOf: root.appendingPathComponent("runtime-allowlist.json")),
              let reviews = validatedReviews(from: data)
        else {
            Log.general.error("Skill runtime allowlist unavailable or invalid — third-party prompt guidance disabled")
            return [:]
        }
        return reviews
    }
}
