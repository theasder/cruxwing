import Foundation
import Testing
@testable import MeetGPT

@Suite("Bundled skill runtime policy")
struct BundledSkillRuntimePolicyTests {
    @Test("checked-in allowlist is structurally valid and exact-byte matched")
    func checkedInPolicyIsValid() throws {
        let root = try #require(SkillResources.skillsDirectory)
        let data = try Data(contentsOf: root.appendingPathComponent("runtime-allowlist.json"))
        let reviews = try #require(BundledSkillRuntimePolicy.validatedReviews(from: data))
        #expect(reviews.count == 9)
        #expect(Set(reviews.keys) == BundledSkillRuntimePolicy.reviewedIDs)

        for (id, review) in reviews {
            let skill = try #require(BundledSkillLibrary.all.first { $0.id == id })
            #expect(skill.sourceSHA256 == review.sourceSHA256)
            #expect(review.promptIDs.allSatisfy {
                BundledSkillRuntimePolicy.allows(skill, for: $0)
            })
        }
    }

    @Test("missing, malformed, stale and wrong-scope inputs fail closed")
    func runtimeAuthorizationFailsClosed() throws {
        let reviewed = try #require(BundledSkillLibrary.runtimeSkill(id: "capture", for: "tasks"))
        #expect(BundledSkillRuntimePolicy.allows(reviewed, for: "tasks"))
        #expect(!BundledSkillRuntimePolicy.allows(reviewed, for: "agenda"))

        var stale = reviewed
        stale.sourceSHA256 = String(repeating: "0", count: 64)
        #expect(!BundledSkillRuntimePolicy.allows(stale, for: "tasks"))

        let synthetic = BundledSkill(
            id: reviewed.id,
            name: reviewed.name,
            description: reviewed.description,
            body: reviewed.body,
            risk: .safe)
        #expect(!BundledSkillRuntimePolicy.allows(synthetic, for: "tasks"))

        var explicitUnknown = reviewed
        explicitUnknown.risk = .unknown
        #expect(!BundledSkillRuntimePolicy.allows(explicitUnknown, for: "tasks"))
        var explicitCritical = reviewed
        explicitCritical.risk = .critical
        #expect(!BundledSkillRuntimePolicy.allows(explicitCritical, for: "tasks"))
    }

    @Test("invalid policy documents authorize nothing")
    func malformedDocumentsAreRejected() throws {
        let root = try #require(SkillResources.skillsDirectory)
        let original = try String(
            contentsOf: root.appendingPathComponent("runtime-allowlist.json"),
            encoding: .utf8)

        let permissiveDefault = original.replacingOccurrences(
            of: #""default_decision": "deny""#,
            with: #""default_decision": "allow""#)
        #expect(BundledSkillRuntimePolicy.validatedReviews(
            from: Data(permissiveDefault.utf8)) == nil)

        let staleCount = original.replacingOccurrences(
            of: #""reviewed_skill_count": 9"#,
            with: #""reviewed_skill_count": 99"#)
        #expect(BundledSkillRuntimePolicy.validatedReviews(
            from: Data(staleCount.utf8)) == nil)

        let badDigest = original.replacingOccurrences(
            of: BundledSkillRuntimePolicy.reviewsByID["capture"]!.sourceSHA256,
            with: "not-a-sha256")
        #expect(BundledSkillRuntimePolicy.validatedReviews(
            from: Data(badDigest.utf8)) == nil)
    }
}
