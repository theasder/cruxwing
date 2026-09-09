# Cruxwing for macOS

This directory contains Cruxwing's native macOS application. It captures system
audio and microphone audio, transcribes locally, stores calls on the Mac, and
can answer questions using a provider selected by the user.

Cruxwing is a public fork of Cruxwing. The product name, bundle identifier, and
user-facing paths are Cruxwing, but the Swift package, executable target, several
environment variables, and some source directories still use `MeetGPT` or
`MEETGPT_*`. Those names are compatibility debt, not a second product.

The portable archive, search, Russian-language normalization, connector
policies, and command-line application live in [`../mvp`](../mvp). The app uses
that package through a local SwiftPM dependency.

## Requirements

- macOS 14 or newer
- Xcode 16 or newer, including the Swift 6 command-line tools
- network access for the first dependency and model downloads

The full app is macOS-only because it uses SwiftUI, ScreenCaptureKit,
AVFoundation, Security, and other Apple frameworks. `CruxwingCore` and the
command-line application are also built and tested on Linux.

## Build and test

A clean clone builds without an `.env` file and without generated credentials:

```sh
cd app
swift build
swift test
```

To create a signed development `.app` bundle:

```sh
cd app
MEETGPT_NO_INSTALL=1 ./build.sh
open build/cruxwing.app
```

Without `MEETGPT_NO_INSTALL=1`, the script tries to install the bundle at the
stable path `/Applications/cruxwing.app`. A stable path and signing identity help
macOS keep Microphone and Screen Recording permissions across rebuilds. If no
development identity is available, the script uses ad-hoc signing and those
permissions may need to be granted again.

Run the other repository checks from the repository root:

```sh
(cd mvp && swift test)
npm test
```

Some live connector, model, media, performance, accessibility, and Apple
distribution checks require explicit environment flags, credentials, hardware,
or interactive macOS permissions. A normal green test run does not claim that
those external paths were exercised.

## Local configuration and credentials

No first-party Cruxwing backend is configured by default. The distributed app is
intended to transcribe on-device and send an AI request only to the provider
whose key the user entered in Settings. User provider keys are stored in the
macOS Keychain.

The master switch for automatic model requests defaults off. While it is off,
recording does not invoke goal/title/digest/check models and an explicit ask
does not add clarification, follow-up, or action-proposal passes; automatic
Fireflies merging is also suppressed. An explicit action can still fan out for
connected-source reads, council synthesis, retries, or global-Auto provider
failover; each vendor request is billed under the user's provider account.
Connected-source reads obey the global app pause and per-app mute, and the
answer names any source it consulted or refused.

`Sources/MeetGPT/Secrets.swift` is a tracked, credential-free fallback. A clean
clone and `swift test` compile that file directly; builds do not rewrite it.

For a local experiment, copy [`.env.example`](.env.example) to `.env` and run
`build.sh`. The script writes an ignored
`Sources/MeetGPT/LocalSecrets.generated.swift` and enables it only for that
local build. LLM provider keys are deliberately excluded from this mechanism:
every build reads those only from the user's Keychain. The generated file is
limited to explicit connector OAuth and transcription/development compatibility
configuration; those supplied values can be embedded in the local binary, so
do not distribute that binary.

Distribution builds set `MEETGPT_DIST=1`. They compile the safe fallback rather
than the local generated configuration, use the sandbox entitlements, reject a
non-empty backend address, and scan the finished app bundle for credential
shapes and exact values from `.env`.

Do not add secrets to source, plist files, resources, examples, tests, or build
logs. See [`../SECURITY.md`](../SECURITY.md) for the project's security promises
and the currently blocked confidential-reporting route that must be restored
before publication.

## Repository map

- `Sources/MeetGPT/` — application source; the directory name is inherited
- `Tests/MeetGPTTests/` — app unit, integration, and source-policy tests
- `Support/` — plist, entitlements, privacy manifest, and icon
- `build.sh` — local bundle builder and shared distribution staging step
- `notarize.sh`, `dmg.sh`, `dist-all.sh` — Developer ID release tooling
- `appstore.sh` — separate Mac App Store packaging lane
- `Sources/MeetGPT/Resources/Skills/` — vendored third-party Agent Skills and
  their provenance material

## Network and privacy boundary

The default Cruxwing build has no account service, subscription service,
telemetry endpoint, or first-party inference gateway. Its expected operational
network surface is downloading model assets, calling a provider configured by
the user, or calling a work service connected by the user. Local transcription
does not upload audio.

The fork still contains inherited Cruxwing types for accounts, tariffs,
paywall APIs, and backend gateways. With an empty backend address these paths
are expected to stop before a request is made, and tests enforce that default.
Direct BYOK startup does not read an inherited Cruxwing account session from
Keychain or subscribe to managed-session notifications.
They remain architectural debt: configuration is a weaker boundary than
removing the unused product surface. First-party analytics, first-meeting
feedback upload, StoreKit purchase, checkout, promo-redemption, and anonymous
device-trial code have been removed from the app target; source-policy tests
prevent those endpoints and UI hooks returning.

## Vendored Agent Skills

The application bundle contains exactly nine individually reviewed third-party
`SKILL.md` methodology files. Every built-in quick prompt has a reviewed route;
custom prompts do not select third-party skills. The former 1,101-file
catalog-only corpus is not shipped.

Runtime authorization is default-deny, exact-byte, and prompt-scoped. A missing,
malformed, stale, or scope-mismatched `runtime-allowlist.json` disables
third-party guidance. Selected text is still capped, stripped of script fences,
sanitized, and wrapped as untrusted methodology; those transformations are
defense in depth, not a substitute for review.

Attribution, immutable source and license provenance, the allowlist, and the
historical ingest scan are in `Sources/MeetGPT/Resources/Skills/`. The generated
CycloneDX 1.6 SBOM at `Support/Legal/Cruxwing.cdx.json` distinguishes shipped
Swift/package code, embedded library sources, and the nine skill data
components; the legal checksum manifest covers it.

## Distribution

The release scripts can build, sign, notarize, and package Apple Silicon and
Intel artifacts, but they require a paid Apple Developer identity and stored
notary credentials:

```sh
cd app
./dist-all.sh
```

Do not infer release readiness from a successful local build. A release also
needs a clean reviewed commit, both architectures, artifact secret scans,
license and notice review, Gatekeeper verification, and the relevant live
permission checks. Packaging now stops inside this repository and prints an
explicit audit command. The manual clean-tag candidate workflow now rebuilds,
audits, hashes and signs provenance for both DMGs, but deliberately does not
publish them. GitHub protection, owner-supplied Apple credentials, approval,
download verification and publication remain maintainer actions; the complete
contract is in [`../docs/RELEASING.md`](../docs/RELEASING.md).

## Known engineering debt

- Rename the `MeetGPT` package, target, executable, paths, and `MEETGPT_*`
  variables without breaking upgrades or macOS permission identity.
- **P1 structural gate:** remove or isolate the remaining inherited account, paywall API, backend, and
  tariff code from the public Cruxwing target. First-party analytics, feedback
  upload, StoreKit purchase, checkout, promo-redemption, and anonymous
  device-trial code are already removed.
- Split the oversized `AppState` and other large files into domain services with
  narrower ownership and tests.
- Keep the reviewed skill bundle intentionally small; each addition requires a
  full content/license review, exact digest and prompt scope, SBOM regeneration,
  and matching provenance tests.
- Decide which legacy app coverage and measurement jobs are still meaningful
  for Cruxwing, then add only those to the root workflow; the inactive nested
  workflow has been removed.
- Configure and exercise the protected release environment described in
  `../docs/RELEASING.md`; publishing remains an explicit owner action after
  verifying the workflow candidate.

These are not hidden roadmap items or claims of completion. Current priorities
and evidence belong in [`PROJECT_STATUS.md`](PROJECT_STATUS.md).

## Project rules

Before contributing, read the repository-level documents:

- [`../README.md`](../README.md) — product scope and user-facing quick start
- [`../CONTRIBUTING.md`](../CONTRIBUTING.md) — development and review rules
- [`../SECURITY.md`](../SECURITY.md) — data-flow promises and vulnerability reports
- [`../CODE_OF_CONDUCT.md`](../CODE_OF_CONDUCT.md) — community expectations
- [`../LICENSE`](../LICENSE) — Apache License 2.0
