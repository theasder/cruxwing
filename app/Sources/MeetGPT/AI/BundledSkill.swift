import Foundation

/// A real, third-party Agent Skill vendored into the app and loaded at runtime
/// from the bundle (`Resources/Skills/<id>/SKILL.md`; see ATTRIBUTION.md for
/// sources + licenses). Only permissively licensed skills are bundled.
///
/// The `body` (SKILL.md content below the frontmatter) layers onto the system
/// prompt exactly like a `PromptSkill` or `CallTheme` pack via
/// `SystemInstructions.system(skills:)`.
/// Upstream risk hint from a skill's frontmatter (`risk:`). This is advisory
/// evidence, not runtime authorization; the local hash-pinned review policy in
/// `runtime-allowlist.json` is the authority.
enum SkillRisk: String, Sendable {
    case safe
    case notApplicable = "none"
    /// The ingest audit ran and could not classify the skill.
    case unknown
    case critical
    /// No `risk:` field at all — the hand-curated skills that predate the ingest.
    case unspecified = ""
    /// A `risk:` value this enum does not know, e.g. a future ingest writing
    /// `high` or a typo like `crit`. Gated with `critical`: an unrecognized
    /// verdict is not a safe verdict, and mapping it onto `unknown` would let a
    /// one-character slip silently promote a skill into the auto-injectable set.
    /// `BundledSkillCatalogTests` fails the build if a shipped skill lands here,
    /// so this is a backstop, not a resting place.
    case unrecognized = "\u{1}unrecognized"

    init(frontmatter value: String) {
        self = SkillRisk(rawValue: value.lowercased()) ?? .unrecognized
    }

}

struct BundledSkill: Identifiable, Equatable, Sendable {
    let id: String           // folder name, e.g. "internal-comms"
    let name: String         // frontmatter `name`
    let description: String  // frontmatter `description` — used to judge relevance
    let body: String         // markdown below the frontmatter
    /// Upstream frontmatter hint; local policy still decides runtime eligibility.
    var risk: SkillRisk = .unspecified
    /// SHA-256 of the exact vendored SKILL.md bytes. Nil for synthetic parser
    /// fixtures; only bundle-loaded, digest-matching content can be authorized.
    var sourceSHA256: String? = nil

    /// Parse a SKILL.md into a `BundledSkill`. Pure and self-contained so it can
    /// be unit-tested without the bundle. The frontmatter is the leading
    /// `---` … `---` block of `key: value` lines; everything after is the body.
    ///
    /// Only `name` and `description` are read, but they must be read the way real
    /// SKILL.md files write them. A line-at-a-time scan silently loses the value
    /// whenever a vendored skill uses a block scalar (`description: >`) or wraps a
    /// quoted string across lines — and an empty `description` is invisible to
    /// `BundledSkillRelevance`, so the skill ships but can never win a route.
    /// Handled here: folded/literal block scalars with any chomping indicator,
    /// multi-line quoted scalars, surrounding quotes, and indented sub-keys of a
    /// nested map (`metadata:`) which must not shadow the top-level fields.
    static func parse(id: String, markdown: String) -> BundledSkill {
        var name = id
        var description = ""
        var body = markdown
        var risk = SkillRisk.unspecified

        let lines = markdown.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return BundledSkill(id: id, name: name, description: description, body: body)
        }

        var index = 1
        var bodyStart = lines.count
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                bodyStart = index + 1
                break
            }
            // Indented lines belong to a nested map, so a `description:` under
            // `metadata:` must never win over the real top-level one.
            guard !isContinuation(line), let colon = line.firstIndex(of: ":") else {
                index += 1
                continue
            }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard key == "name" || key == "description" || key == "risk" else {
                index += 1
                continue
            }
            var value = String(line[line.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            if let style = BlockScalarStyle(indicator: value) {
                (value, index) = readBlockScalar(lines, from: index + 1, style: style)
            } else if let (joined, next) = readMultiLineQuoted(value, lines, from: index + 1) {
                (value, index) = (joined, next)
            } else {
                index += 1
            }
            value = unquoted(value)
            switch key {
            case "name" where !value.isEmpty: name = value
            case "description": description = value
            case "risk" where !value.isEmpty: risk = SkillRisk(frontmatter: value)
            default: break
            }
        }
        if bodyStart < lines.count {
            body = lines[bodyStart...].joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return BundledSkill(id: id, name: name, description: description, body: body, risk: risk)
    }

    // MARK: - Frontmatter scalars

    /// `>` folds line breaks into spaces; `|` keeps them.
    private enum BlockScalarStyle {
        case folded, literal

        /// A block scalar header is the indicator alone, optionally chomped
        /// (`>`, `>-`, `>+`, `|`, `|-`, `|+`). Chomping only affects trailing
        /// newlines, which a description never keeps, so it is accepted and ignored.
        init?(indicator: String) {
            switch indicator {
            case ">", ">-", ">+": self = .folded
            case "|", "|-", "|+": self = .literal
            default: return nil
            }
        }
    }

    private static func isContinuation(_ line: String) -> Bool {
        line.hasPrefix(" ") || line.hasPrefix("\t")
    }

    /// Collect the indented block that follows a block-scalar header. Returns the
    /// joined value and the index of the first line that is not part of it.
    private static func readBlockScalar(
        _ lines: [String], from start: Int, style: BlockScalarStyle
    ) -> (String, Int) {
        var collected: [String] = []
        var index = start
        while index < lines.count {
            let line = lines[index]
            // A blank line inside the block is content; anything at column 0 ends it.
            if !line.trimmingCharacters(in: .whitespaces).isEmpty, !isContinuation(line) { break }
            collected.append(line.trimmingCharacters(in: .whitespaces))
            index += 1
        }
        while collected.last?.isEmpty == true { collected.removeLast() }
        let separator = style == .folded ? " " : "\n"
        return (collected.joined(separator: separator)
            .trimmingCharacters(in: .whitespacesAndNewlines), index)
    }

    /// A quoted scalar may wrap across lines. Returns nil unless `value` opens a
    /// quote it does not close, in which case the continuation lines are folded in.
    private static func readMultiLineQuoted(
        _ value: String, _ lines: [String], from start: Int
    ) -> (String, Int)? {
        guard let quote = value.first, quote == "\"" || quote == "'" else { return nil }
        guard !(value.count > 1 && value.hasSuffix(String(quote))) else { return nil }
        var collected = [value]
        var index = start
        while index < lines.count {
            let line = lines[index]
            if !isContinuation(line) { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            collected.append(trimmed)
            index += 1
            if trimmed.hasSuffix(String(quote)) { break }
        }
        return (collected.joined(separator: " "), index)
    }

    /// Drop a matching pair of surrounding quotes. `BundledSkillSanitizer`
    /// interpolates `name` into the prompt header, so a stray quote is visible.
    private static func unquoted(_ value: String) -> String {
        guard let first = value.first, first == "\"" || first == "'",
              value.count > 1, value.hasSuffix(String(first)) else { return value }
        let inner = String(value.dropFirst().dropLast())
        return first == "\"" ? inner.replacingOccurrences(of: "\\\"", with: "\"") : inner
    }
}

/// Discovers and caches the vendored skills at first access. Empty if none are
/// bundled — a missing resource degrades to the app's built-in skills, never a
/// crash. Quarantined ids (see `BundledSkillSanitizer.quarantineIDs`) are never
/// loaded even if a `SKILL.md` folder is still on disk.
enum BundledSkillLibrary {
    /// Every shipped third-party skill is still re-authorized from its exact
    /// bytes. This keeps an accidentally added folder or stale vendor edit out
    /// of memory and out of model prompts even before repository tests run.
    static let all: [BundledSkill] = load(only: BundledSkillRuntimePolicy.reviewedIDs)
        .filter(BundledSkillRuntimePolicy.allowsForAnyReviewedPrompt)

    /// The relevance ranker has no broader catalog: the reviewed, shipped set
    /// is the complete runtime boundary.
    static let rankable: [BundledSkill] = all

    /// Runtime candidates reviewed for one specific built-in prompt.
    static func rankable(for promptID: String) -> [BundledSkill] {
        rankable.filter { BundledSkillRuntimePolicy.allows($0, for: promptID) }
    }

    static func runtimeSkill(id: String, for promptID: String) -> BundledSkill? {
        guard let skill = rankable.first(where: { $0.id == id }),
              BundledSkillRuntimePolicy.allows(skill, for: promptID) else { return nil }
        return skill
    }

    private static func load(only ids: Set<String>? = nil) -> [BundledSkill] {
        guard let root = SkillResources.skillsDirectory else {
            return []
        }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        var skills: [BundledSkill] = []
        for dir in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let id = dir.lastPathComponent
            if BundledSkillSanitizer.quarantineIDs.contains(id) { continue }
            if let ids, !ids.contains(id) { continue }
            let isDir = (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { continue }
            let skillFile = dir.appendingPathComponent("SKILL.md")
            guard let data = try? Data(contentsOf: skillFile),
                  let markdown = String(data: data, encoding: .utf8) else { continue }
            var skill = BundledSkill.parse(id: id, markdown: markdown)
            skill.sourceSHA256 = BundledSkillRuntimePolicy.sha256(data)
            skills.append(skill)
        }
        return skills
    }
}
