# Vendored Agent Skills — attribution and licenses

Orakul ships exactly nine third-party Agent Skills as methodology data. Each
`SKILL.md` has been individually reviewed for the built-in prompt scopes named
in `runtime-allowlist.json`; there is no bundled catalog of unreviewed skills.
All nine are MIT-licensed and remain copyright their original authors.

`INGEST_MANIFEST.json` is the machine-readable source record. It pins each
shipped file to an upstream repository, path, full commit SHA, SHA-256 digest,
license file, and immutable license provenance. `skill-metadata.json` contains
the matching routing metadata. Repository tests require the live folders,
provenance, metadata, and runtime policy to describe the same exact set.

## Shipped skills

| Skill | Upstream source | Reviewed built-in prompt scopes |
|---|---|---|
| `anti-sycophancy` | [sickn33/agentic-awesome-skills](https://github.com/sickn33/agentic-awesome-skills/blob/ab5f6c205a548d2f4bec411728c79b9c156fc696/skills/anti-sycophancy/SKILL.md) | `steelman` |
| `capture` | [alirezarezvani/claude-skills](https://github.com/alirezarezvani/claude-skills/blob/6d9630f83c2cb51615142dbb54e4091cddfdc4b8/productivity/capture/skills/capture/SKILL.md) | `commitments`, `logdecision`, `tasks`, `unresolved` |
| `challenge` | [alirezarezvani/claude-skills](https://github.com/alirezarezvani/claude-skills/blob/f2bac0a8f29b71846cc62d9d580249c2a3246030/c-level-advisor/executive-mentor/skills/challenge/SKILL.md) | `advice`, `dispute`, `rhetoric`, `steelman`, `unresolved`, `whattoask` |
| `executive-mentor` | [alirezarezvani/claude-skills](https://github.com/alirezarezvani/claude-skills/blob/f2bac0a8f29b71846cc62d9d580249c2a3246030/c-level-advisor/executive-mentor/skills/executive-mentor/SKILL.md) | `advice`, `answer` |
| `postmortem` | [alirezarezvani/claude-skills](https://github.com/alirezarezvani/claude-skills/blob/f2bac0a8f29b71846cc62d9d580249c2a3246030/c-level-advisor/executive-mentor/skills/postmortem/SKILL.md) | `risks`, `summary` |
| `product-discovery` | [alirezarezvani/claude-skills](https://github.com/alirezarezvani/claude-skills/blob/f2bac0a8f29b71846cc62d9d580249c2a3246030/product-team/skills/product-discovery/SKILL.md) | `brainstorm`, `whattoask` |
| `research-summarizer` | [alirezarezvani/claude-skills](https://github.com/alirezarezvani/claude-skills/blob/f2bac0a8f29b71846cc62d9d580249c2a3246030/product-team/research-summarizer/skills/research-summarizer/SKILL.md) | `answer`, `factcheck`, `summary` |
| `roadmap-communicator` | [alirezarezvani/claude-skills](https://github.com/alirezarezvani/claude-skills/blob/f2bac0a8f29b71846cc62d9d580249c2a3246030/product-team/skills/roadmap-communicator/SKILL.md) | `agenda` |
| `stress-test` | [alirezarezvani/claude-skills](https://github.com/alirezarezvani/claude-skills/blob/f2bac0a8f29b71846cc62d9d580249c2a3246030/c-level-advisor/executive-mentor/skills/stress-test/SKILL.md) | `factcheck`, `risks`, `rhetoric`, `steelman`, `whattoask` |

## License evidence

| Repository | License | Bundled full text | Immutable upstream source |
|---|---|---|---|
| `sickn33/agentic-awesome-skills` | MIT | `LICENSE-MIT-agentic-awesome.txt` | [LICENSE at `ab5f6c2`](https://github.com/sickn33/agentic-awesome-skills/blob/ab5f6c205a548d2f4bec411728c79b9c156fc696/LICENSE) |
| `alirezarezvani/claude-skills` | MIT | `LICENSE-MIT-alirezarezvani.txt` | [LICENSE at `f2bac0a`](https://github.com/alirezarezvani/claude-skills/blob/f2bac0a8f29b71846cc62d9d580249c2a3246030/LICENSE) |

The manifest pins the exact SHA-256 digest of both full license files. The
CycloneDX 1.6 SBOM at `Support/Legal/Orakul.cdx.json` records these nine data
components separately from executable Swift packages and embedded library
sources. `Support/Legal/MANIFEST.sha256` covers the SBOM and legal payload.

## Runtime boundary

The runtime policy is default-deny and prompt-scoped. A skill enters ranking
only when its identifier, exact file digest, local review, and requested prompt
scope all match. Invalid or stale policy data disables third-party guidance.
Before inclusion, the selected body is capped, script fences are removed,
invisible Unicode and instruction-like lines are neutralized, and the result is
wrapped as untrusted methodology. See `SECURITY.md` for the threat model.

The earlier bulk-ingest scan is retained in `SECURITY-AUDIT.md` as historical
evidence only. The 1,101 non-reviewed files that remained after provenance
cleanup, together with their unused notices and metadata, are not distributed.
They remain recoverable from repository history if a maintainer later chooses
to review a specific method.

The former `role-matrix.json` is also not distributed. Its 120 prompt hints
claimed derivation from a 306-skill pool but had no surviving per-hint source
record and referenced 89 methods outside the reviewed bundle. The role picker
remains, backed by ten small first-party constants and generic role framing in
compiled Swift; prompt-specific methodology comes only from the governed layers
described above.

## Adding or updating a skill

Do not expand the bundle by copying a catalog wholesale. For each proposed
file, review its full content and license, then update all four linked records:

1. Add `<id>/SKILL.md` without local edits and record its immutable source and
   SHA-256 in `INGEST_MANIFEST.json`.
2. Bundle and pin the complete upstream license text; add routing metadata to
   `skill-metadata.json`.
3. Add an exact-byte review with narrow prompt scopes and rationale to
   `runtime-allowlist.json`, then map those same scopes in
   `BundledSkillRouter.map`.
4. Run `node scripts/generate-sbom.mjs`, the provenance/SBOM tests, and the
   bundled-skill Swift tests before review.

Passing sanitization is not content review, and an upstream `risk:` label is
advisory rather than authorization.
