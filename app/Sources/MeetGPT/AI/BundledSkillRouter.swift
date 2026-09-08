import Foundation

/// Maps each quick-prompt button onto vendored open-source Agent Skills and
/// picks the most relevant one for the live meeting context.
///
/// Distilled `PromptSkill` guidance stays the primary short layer; a capped
/// SKILL.md body adds methodology depth. Selection is relevance-ranked only
/// within the exact-byte, per-prompt review scope in `runtime-allowlist.json`.
enum BundledSkillRouter {
    /// Soft cap so a single button can't flood the system prompt with a 16 KB skill.
    static let maxBodyChars = 3_500

    /// Prompt id → reviewed skill ids, in preferred order. This map and the
    /// allowlist's prompt scopes are tested as an exact bidirectional contract.
    static let map: [String: [String]] = [
        "agenda":      ["roadmap-communicator"],
        "brainstorm":  ["product-discovery"],
        "unresolved":  ["capture", "challenge"],
        "whattoask":   ["challenge", "stress-test", "product-discovery"],
        "factcheck":   ["research-summarizer", "stress-test"],
        "rhetoric":    ["stress-test", "challenge"],
        "answer":      ["executive-mentor", "research-summarizer"],
        "dispute":     ["challenge"],
        "risks":       ["postmortem", "stress-test"],
        "advice":      ["executive-mentor", "challenge"],
        "tasks":       ["capture"],
        "summary":     ["research-summarizer", "postmortem"],
        "logdecision": ["capture"],
        "steelman":    ["challenge", "stress-test", "anti-sycophancy"],
        "commitments": ["capture"],
    ]

    /// Compact guidance for a prompt button: relevance-picked skill, truncated
    /// and wrapped so the model treats it as methodology depth — not authority.
    static func guidance(for promptID: String?, query: String? = nil) -> String? {
        guard let promptID, let skill = pick(for: promptID, query: query) else { return nil }
        let formatted = format(skill, for: promptID)
        return formatted.isEmpty ? nil : formatted
    }

    /// Relevance-ranked skill for this button + optional live meeting text.
    static func pick(for promptID: String?, query: String? = nil) -> BundledSkill? {
        // Custom prompts intentionally use only their user-authored text and
        // the base safety instructions. Treating an unknown id as an empty
        // seed list used to scan and inject unrelated vendored methodology.
        guard let promptID, let preferred = map[promptID], !preferred.isEmpty else {
            return nil
        }
        return BundledSkillRelevance.pick(
            context: .init(promptID: promptID, query: query ?? ""),
            preferredIDs: preferred)
    }

    /// Ranked shortlist (for tests / debug UI). Preferred map seeds plus the
    /// reviewed methods allowed for this prompt.
    static func ranked(for promptID: String, query: String? = nil) -> [(skill: BundledSkill, score: Double)] {
        BundledSkillRelevance.rank(
            context: .init(promptID: promptID, query: query ?? ""),
            preferredIDs: map[promptID] ?? [])
    }

    /// Preferred map ids whose exact bytes are approved for this prompt.
    static func resolvedIDs(for promptID: String) -> [String] {
        (map[promptID] ?? []).filter { id in
            BundledSkillLibrary.runtimeSkill(id: id, for: promptID) != nil
        }
    }

    static func format(_ skill: BundledSkill, for promptID: String) -> String {
        // Defense in depth: formatting is the last point before third-party text
        // enters the model prompt. A direct caller must not bypass the
        // exact-byte, prompt-scoped local review.
        guard BundledSkillRuntimePolicy.allows(skill, for: promptID) else { return "" }
        var body = skill.body.trimmingCharacters(in: .whitespacesAndNewlines)
        // Drop sections that only make sense with upstream scripts/binaries we
        // deliberately do not vendor (keep methodology + output contracts).
        body = stripScriptHeavySections(body)
        // Prompt-injection / steganography defenses (unicode, role markers, overrides).
        body = BundledSkillSanitizer.sanitize(body)
        if body.count > maxBodyChars {
            body = String(body.prefix(maxBodyChars))
            if let lastBreak = body.lastIndex(where: { $0 == "\n" }) {
                body = String(body[..<lastBreak])
            }
            body += "\n…"
        }
        let title = skill.name.isEmpty ? skill.id : skill.name
        return BundledSkillSanitizer.wrapForPrompt(id: skill.id, title: title, body: body)
    }

    /// Remove fenced code / "run this script" heavy blocks that would waste tokens.
    private static func stripScriptHeavySections(_ text: String) -> String {
        var out: [String] = []
        var inFence = false
        var skippedSectionLevel: Int?
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let headingMarks = trimmed.prefix { $0 == "#" }
            let headingLevel = headingMarks.isEmpty || headingMarks.count > 6
                || trimmed.dropFirst(headingMarks.count).first != " "
                ? nil
                : headingMarks.count

            if let activeSkippedLevel = skippedSectionLevel {
                if let headingLevel, headingLevel <= activeSkippedLevel {
                    skippedSectionLevel = nil
                } else {
                    continue
                }
            }
            if trimmed.hasPrefix("```") {
                inFence.toggle()
                continue
            }
            if inFence { continue }
            if let headingLevel {
                let title = trimmed.dropFirst(headingLevel)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                if title == "tooling" || title == "tools" || title.hasPrefix("scripts")
                    || title.contains(".py") {
                    skippedSectionLevel = headingLevel
                    continue
                }
            }
            // Skip obvious script-invocation lines.
            if trimmed.hasPrefix("python ") || trimmed.hasPrefix("python3 ")
                || trimmed.contains(".py ") || trimmed.hasSuffix(".py")
                || trimmed.hasPrefix("./") && trimmed.contains(".py") {
                continue
            }
            out.append(line)
        }
        return out.joined(separator: "\n")
    }
}
