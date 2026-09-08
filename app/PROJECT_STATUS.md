# Orakul macOS application status

Last reviewed: 2026-08-26.

This is a concise engineering snapshot, not a release announcement or a
historical test diary. Code and automated checks remain the executable source
of truth; when this document disagrees with them, update or remove the claim.

## Current shape

- Orakul is a public, local-first fork of Cruxwing.
- `app/` is the native macOS 14 application.
- `mvp/` provides `OrakulCore`, the cross-platform command-line application,
  local archive and search, Russian-language normalization, and connector
  policies. The app links it as a local Swift package.
- Product identity is Orakul (`ai.orakul.desktop`), while internal `MeetGPT`
  names and `MEETGPT_*` build variables remain compatibility debt.
- Clean-clone checks require the eventual release tree to build without an
  `.env` file or an untracked source prerequisite. The current migration
  worktree must not be published until its intended files are committed and
  those checks pass from a fresh clone.

## Security and network posture

- Public distribution builds have no default first-party backend address.
- On-device transcription is the default; audio is not intentionally sent to a
  transcription service in that mode.
- Users enter model-provider credentials in Settings, and those values are
  stored in the macOS Keychain.
- Model-provider keys are never read from `.env` or generated into any build;
  local and distribution builds both resolve them only from Keychain.
- Direct BYOK has no Orakul credits, subscription allowance, monthly research
  cap, or local product-analytics counters. The selected provider applies its
  own billing and rate limits to the user's account.
- Automatic model requests default off behind one master consent switch. With
  it off, recording does not invoke goal/title/digest/check models and an
  explicit question does not add clarification, follow-up, or action-proposal
  passes; automatic Fireflies merging is also suppressed. Explicit actions can
  still fan out for connected-source reads, council synthesis, retries, or
  global-Auto provider failover. Reads obey global/per-app source controls and
  their attribution is appended to the visible answer.
- The tracked `Secrets.swift` contains only safe defaults. Local `build.sh` runs
  may create the ignored `LocalSecrets.generated.swift` for explicit connector
  OAuth and transcription-development configuration; distribution builds do
  not enable that configuration and scan the finished bundle for credentials.
- Connected-service traffic is user-initiated and goes to the service address
  the user configured.

First-party funnel analytics, the first-meeting feedback collector/uploader,
StoreKit purchase/receipt code, web checkout, promo redemption, and anonymous
device-trial routes have been removed from the app target. Source-policy tests
reject their endpoints, UI hooks, and production symbols if they return.
Inherited account, read-only plan/usage API, backend, and tariff types remain
compiled behind an empty first-party backend configuration; that remaining
product surface is P1 release-isolation debt, not an Orakul feature or a claim of
fully structural release isolation.
Direct BYOK launch does not read a legacy Orakul account session from Keychain
or subscribe to managed-session notifications.

## Verification available today

- The macOS app and `OrakulCore` have substantial Swift test suites.
- `OrakulCore`, the command-line program, and their tests run in Linux CI.
- Root Node tests check documentation, identity, packaging policy, and selected
  security invariants.
- The app ships nine reviewed, hash-pinned Agent Skills behind a default-deny,
  prompt-scoped runtime policy; tests require the bundle, metadata, provenance,
  and policy to describe the same exact set.
- A deterministic CycloneDX 1.6 SBOM distinguishes shipped Swift packages,
  embedded sources, and skill data, and is covered by the legal checksum
  manifest copied into the app bundle.
- Release scripts include bundle-level secret checks, signing checks, source
  stamps, notarization, and two-architecture packaging paths.

This evidence has limits. Source-shape tests are not substitutes for behavioral
tests. The normal suite skips checks that need live provider accounts,
interactive macOS permissions, media fixtures, accessibility, performance
conditions, or Apple signing services. Exact test counts are deliberately not
recorded here because they age immediately and do not measure product maturity.

## Open before a confident public release

1. Commit the intended public tree in reviewable slices and make both
   clean-clone integrity checks pass. Until a clone contains the same sources
   and deletions as this worktree, it is not a release candidate.
2. **P1 structural gate:** remove or target-isolate the remaining inherited server, identity, account,
   paywall API, and tariff code so the no-backend promise is structural rather
   than configured. Telemetry, feedback upload, StoreKit purchase, checkout,
   promo-redemption, and device-trial code have already been removed from the
   app target.
3. Have the owner configure and exercise the standalone candidate workflow:
   protect tags and the `release` Environment, add Apple credentials, approve a
   clean reviewed tag, verify the downloaded `SHA256SUMS` and signed
   attestation, and only then publish. The workflow prepares but intentionally
   does not publish a release; details are in `../docs/RELEASING.md`.
4. Restore only still-relevant app coverage and measurement checks in the root
   CI workflow. The inactive nested workflow and its obsolete Cruxwing contract
   jobs have been removed.
5. Replace stale Cruxwing/MeetGPT names in source and tooling through a planned
   migration that preserves the bundle identifier, Keychain migration, signing,
   and macOS privacy permissions.

## Maintainability priorities

- Decompose `AppState` into recording, transcription, assistant, connector,
  export, and account-compatibility coordinators.
- Keep the portable public API intentionally small and make `OrakulCore`
  consumable from the repository root or document it as an internal package.
- Add formatting, linting, strict-concurrency, dependency-update, and coverage
  policies with narrow, reviewable adoption rather than a repository-wide
  warning dump.
- Replace `OrakulCore`'s acknowledged cross-platform remove-then-move archive
  write. The macOS app stores now use same-volume atomic replacement, a
  verified-readable recovery copy, synchronized directory mutations, and
  explicit artifact erasure; the portable core still needs an equivalent that
  behaves consistently in swift-corelibs-foundation.
- Exercise the clean-tag candidate workflow under enforced review, then keep
  final publication an explicit owner action after downloaded-artifact audit.

## What is not claimed

- The macOS application is not presented as audited or production-hardened.
- Passing automated tests does not prove every connector or model provider works
  against its current live API.
- The nine vendored methods have scoped content review; that does not make
  sanitization a formal isolation boundary or guarantee model output quality.
- Mac App Store readiness, universal live permission behavior, and a fully
  reproducible release pipeline are not complete.
- Internal compatibility names do not imply that Orakul depends on a Cruxwing
  service; the default public build has no such service configured.

## Where decisions belong

- Product and usage overview: [`../README.md`](../README.md)
- Developer workflow: [`README.md`](README.md) and
  [`../CONTRIBUTING.md`](../CONTRIBUTING.md)
- Security boundary and reporting: [`../SECURITY.md`](../SECURITY.md)
- Community expectations: [`../CODE_OF_CONDUCT.md`](../CODE_OF_CONDUCT.md)
- License: [`../LICENSE`](../LICENSE)

Update this file when a statement above materially changes. Do not append
session logs, temporary measurements, exact test totals, business plans, or
resolved incident narratives; those belong in version control, focused issues,
or a dated design/incident document.
