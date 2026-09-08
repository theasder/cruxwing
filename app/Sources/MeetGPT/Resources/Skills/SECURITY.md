# Skills security

Third-party Agent Skills are untrusted methodology data. Orakul ships only the
nine files listed in `runtime-allowlist.json`; the former unreviewed catalog is
not present in the application bundle.

## Authorization and prompt use

A vendored skill must pass every boundary below before its text can reach a
model prompt:

1. **Local exact-byte review.** `runtime-allowlist.json` defaults to deny and
   pins an approved identifier, source repository, full commit SHA, file
   SHA-256, license, rationale, and narrow built-in prompt scopes. If the whole
   document is missing or malformed, all third-party guidance is disabled.
2. **Runtime match.** The loader reads only reviewed identifiers and hashes the
   actual bundled bytes. Unknown folders, changed files, duplicate reviews, and
   requests outside a reviewed prompt scope are denied.
3. **Explicit-risk veto.** Upstream `risk:` metadata is advisory because it is
   incomplete and not controlled by Orakul. A local review may cover a missing
   value, but an explicit `unknown`, `critical`, or unrecognized value still
   vetoes runtime use.
4. **Quarantine.** `BundledSkillSanitizer.quarantineIDs` remains a defense in
   depth against identifiers previously associated with harmful or
   action-taking behavior.
5. **Transform and contain.** Script fences are removed; invisible Unicode,
   role markers, and common override lines are neutralized; the body is capped;
   and the result is wrapped between `UNTRUSTED_THIRD_PARTY_SKILL` delimiters.
6. **Final authorization.** `BundledSkillRouter.format(_:for:)` repeats the
   exact-byte and prompt-scope decision at the final formatting boundary.

Every built-in quick prompt retains at least one reviewed method. Custom prompt
identifiers do not route third-party skills.

## What this boundary does and does not prove

The local review is the authority; an upstream label or a regex scan is not.
The nine shipped skills were selected as analysis or note-organization methods,
not account, file, network, publication, server-administration, or financial
action workflows. Only their `SKILL.md` files are bundled—no upstream scripts,
examples folders, plugins, or executable assets.

Sanitization and delimiters reduce prompt-injection exposure but are not a
formal model-isolation boundary. The small corpus, exact-byte authorization,
prompt scoping, and final deny check are what make review tractable. A model can
still produce a poor answer, so ordinary output review and least-privilege
provider/connector design remain necessary.

`SECURITY-AUDIT.md` records the earlier 1,193-candidate pattern scan. It is
historical evidence, not permission to ship or execute a candidate. The current
set is defined jointly by the live folders, `INGEST_MANIFEST.json`,
`skill-metadata.json`, and `runtime-allowlist.json`; tests require exact equality.

## Change policy

Treat every new or modified `SKILL.md` as a new review. Do not preserve an old
approval across a byte change, broaden prompt scopes without reading the full
method, or add a license notice without immutable source and digest evidence.
Regenerate `Support/Legal/Orakul.cdx.json` after any accepted change and run:

```sh
node scripts/generate-sbom.mjs --check
node --test test/skills-provenance.test.mjs test/sbom.test.mjs
swift test --package-path app --filter BundledSkill
```

The repository tests are publication guards, not a substitute for human legal
or security review.
