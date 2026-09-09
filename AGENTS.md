# Cruxwing repository rules

These rules apply to the whole repository. Before changing anything, read:

- [`CONTRIBUTING.md`](CONTRIBUTING.md) for the development and review contract;
- [`SECURITY.md`](SECURITY.md) for the public data boundary and the currently
  blocked vulnerability-reporting route;
- [`app/PROJECT_STATUS.md`](app/PROJECT_STATUS.md) for verified capabilities and
  acknowledged debt; and
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) before changing persistence,
  credentials, networking, packaging, or release automation.

## Public-build invariants

- AI and transcription are local or runtime BYOK. A user must add, replace, and
  remove their own provider credentials. Never provision, infer, bundle, commit,
  log, upload, or add a build-time fallback for those credentials.
- Do not add or activate a first-party Cruxwing/Cruxwing backend, account,
  subscription, tariff, paywall, checkout, StoreKit, promo, telemetry, analytics,
  crash-report, feedback-upload, or device-trial path in the public target.
  Inherited compatibility types are removal debt, not extension points.
- Every new outbound path must document its trigger, destination, payload,
  credential source, default state, persistence/retention, and failure behavior
  in `SECURITY.md` and `docs/ARCHITECTURE.md`, with a non-vacuous regression test.
- Keep secrets in the macOS Keychain. `UserDefaults`, source, examples, fixtures,
  resources, generated public-build files, logs, and CI output are not secret
  stores.
- Do not weaken a privacy, provenance, signing, history-secret, SBOM, license, or
  release gate to make a check pass. Fix the implementation or the evidence.

## Publication boundary

Automated agents must not push, create or move tags, create or publish releases,
upload artifacts, publish a Homebrew cask, change repository protections,
configure GitHub Environments or secrets, or use Apple signing/notarization
credentials. Agents may prepare and verify local changes and an unpublished
candidate when explicitly asked. Final publication is always a deliberate owner
action under [`docs/RELEASING.md`](docs/RELEASING.md).

Preserve unrelated work in a dirty tree. Use the smallest relevant checks from
`CONTRIBUTING.md`; a release claim requires all gates in `docs/RELEASING.md`, not
only a successful local build.
