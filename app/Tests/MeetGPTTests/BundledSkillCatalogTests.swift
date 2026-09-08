import Testing
import Foundation
@testable import MeetGPT

/// Invariants over the complete reviewed set shipped in the application bundle,
/// not merely one parser fixture. Resource loading deliberately degrades to an
/// empty list, so publication tests must make missing or malformed inputs loud.
@Suite("Bundled skill catalog")
struct BundledSkillCatalogTests {
    /// `a-z0-9` words joined by single hyphens — the Agent Skills naming rule,
    /// and what keeps a folder name usable as a stable id.
    private static let idPattern = try! NSRegularExpression(
        pattern: "^[a-z0-9]+(-[a-z0-9]+)*$")

    /// Generous: the open standard caps `description` at 1024, while this app
    /// consumes skills rather than publishing them. This only catches a runaway
    /// value, such as a body accidentally folded into the field.
    private static let maxDescriptionChars = 2_000

    @Test("the complete shipped set is exactly the reviewed set")
    func catalogSize() {
        #expect(BundledSkillLibrary.all.count == 9)
        #expect(Set(BundledSkillLibrary.all.map(\.id)) == BundledSkillRuntimePolicy.reviewedIDs)
    }

    @Test("every skill has a usable description")
    func descriptionsAreUsable() {
        for skill in BundledSkillLibrary.all {
            let description = skill.description.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(!description.isEmpty, "\(skill.id) has no description — it can never win a route")
            #expect(
                description.count <= Self.maxDescriptionChars,
                "\(skill.id) description is \(description.count) chars")
        }
    }

    @Test("no description is a leftover YAML block-scalar indicator")
    func descriptionsAreNotScalarIndicators() {
        for skill in BundledSkillLibrary.all {
            let description = skill.description.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(
                ![">", ">-", ">+", "|", "|-", "|+"].contains(description),
                "\(skill.id) description is the block indicator \(description) — the scalar was not read")
        }
    }

    @Test("no name or description keeps its surrounding quotes")
    func valuesAreUnquoted() {
        for skill in BundledSkillLibrary.all {
            for (field, value) in [("name", skill.name), ("description", skill.description)] {
                guard let first = value.first, first == "\"" || first == "'" else { continue }
                #expect(
                    !value.hasSuffix(String(first)),
                    "\(skill.id) \(field) is still quoted: \(value.prefix(40))")
            }
        }
    }

    @Test("every folder name is a valid skill id")
    func folderNamesAreValidIDs() {
        for skill in BundledSkillLibrary.all {
            let range = NSRange(skill.id.startIndex..., in: skill.id)
            #expect(
                Self.idPattern.firstMatch(in: skill.id, range: range) != nil,
                "\(skill.id) is not a valid skill id")
            #expect(skill.id.count <= 64, "\(skill.id) exceeds the 64-char id limit")
        }
    }

    /// Collisions are resolved by suffixing the upstream owner
    /// (`ab-testing` → `ab-testing-sickn33`), so the folder is either the name or
    /// the name plus a suffix. Anything else means the two drifted apart.
    @Test("each folder name agrees with its name field")
    func folderNamesAgreeWithNameField() {
        for skill in BundledSkillLibrary.all {
            #expect(
                skill.id == skill.name || skill.id.hasPrefix(skill.name + "-"),
                "\(skill.id) declares name '\(skill.name)'")
        }
    }

    @Test("every router seed resolves to a real skill")
    func routerSeedsResolve() {
        for (promptID, seeds) in BundledSkillRouter.map {
            for seed in seeds {
                #expect(
                    BundledSkillLibrary.runtimeSkill(id: seed, for: promptID) != nil,
                    "\(promptID) seeds '\(seed)', which is not in the reviewed bundle")
            }
        }
    }

    @Test("router seeds have usable descriptions")
    func routerSeedsHaveUsableDescriptions() {
        for (promptID, seeds) in BundledSkillRouter.map {
            for seed in seeds {
                guard let skill = BundledSkillLibrary.runtimeSkill(id: seed, for: promptID)
                else { continue }
                #expect(
                    !skill.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "\(promptID) seed '\(seed)' has no description — relevance ranks on it")
            }
        }
    }

    @Test("no skill id collides after quarantine")
    func idsAreUnique() {
        let ids = BundledSkillLibrary.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("only exact-byte locally reviewed skills enter automatic ranking")
    func rankableRequiresLocalReview() {
        let rankable = BundledSkillLibrary.rankable
        #expect(!rankable.isEmpty)
        #expect(rankable.count == BundledSkillRuntimePolicy.reviewsByID.count)
        #expect(Set(rankable.map(\.id)) == BundledSkillRuntimePolicy.reviewedIDs)
        #expect(rankable.allSatisfy(BundledSkillRuntimePolicy.allowsForAnyReviewedPrompt))
        #expect(rankable.count < 20, "runtime review expanded beyond a deliberately small set")
    }

    @Test("no unreviewed skill file is shipped")
    func shippedFilesMatchPolicy() throws {
        let root = try #require(SkillResources.skillsDirectory)
        let entries = try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey])
        let shippedIDs = Set(entries.compactMap { entry -> String? in
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true,
                  FileManager.default.fileExists(
                    atPath: entry.appendingPathComponent("SKILL.md").path)
            else { return nil }
            return entry.lastPathComponent
        })
        #expect(shippedIDs == BundledSkillRuntimePolicy.reviewedIDs)
    }

    @Test("router map and allowlist prompt scopes are the same contract")
    func routerMapMatchesPolicyScopes() {
        var mappedScopes: [String: Set<String>] = [:]
        for (promptID, seeds) in BundledSkillRouter.map {
            #expect(!seeds.isEmpty, "\(promptID) has no reviewed methodology")
            for seed in seeds {
                mappedScopes[seed, default: []].insert(promptID)
                guard let skill = BundledSkillLibrary.runtimeSkill(id: seed, for: promptID) else {
                    Issue.record("\(promptID) seed '\(seed)' is absent")
                    continue
                }
                #expect(BundledSkillRuntimePolicy.allows(skill, for: promptID))
            }
        }
        let reviewedScopes = BundledSkillRuntimePolicy.reviewsByID.mapValues { Set($0.promptIDs) }
        #expect(mappedScopes == reviewedScopes)
    }

    /// Backstop for the fail-closed default. `SkillRisk.unrecognized` keeps an
    /// unknown verdict out of the ranker, but silently gating a skill is a poor
    /// outcome too — if an ingest starts writing `risk: high`, that should be a
    /// build failure and a deliberate mapping decision, not a quiet exclusion.
    @Test("no shipped skill carries a risk value this build does not recognize")
    func noUnrecognizedRiskValues() {
        let offenders = BundledSkillLibrary.all
            .filter { $0.risk == .unrecognized }
            .map(\.id)
        #expect(
            offenders.isEmpty,
            "unrecognized risk: values — map them in SkillRisk or fix the frontmatter: \(offenders)")
    }

    /// These two upstream files were locally patched with risk labels after
    /// ingest. Keeping edited vendor bodies would break immutable provenance,
    /// and neither skill is needed by the meeting router, so they stay removed.
    @Test("downstream-modified action skills are not shipped")
    func downstreamModifiedActionSkillsAreAbsent() {
        for id in ["google-workspace-cli", "baoyu-post-to-x"] {
            #expect(!BundledSkillLibrary.all.contains(where: { $0.id == id }))
        }
    }
}
