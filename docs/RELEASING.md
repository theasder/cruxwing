# Releasing Cruxwing

This document describes cutting a new release of the sources from `main` plus two
macOS DMGs. It does not declare the current release ready. Measured 2026-09-08:
the repository is `github.com/theasder/cruxwing` and GitHub Pages answers 200, so
the identity blocker recorded here earlier is gone; what remains is the historical
`v0.1.0`, which does not pass this branch's checks.

## What is automated — and what is not

`.github/workflows/release-candidate.yml` is run manually against an existing
annotated tag `vX.Y.Z`. It:

1. checks that it is running in `theasder/cruxwing`;
2. compares the tag against `CFBundleShortVersionString`, requires a clean
   checkout and that the commit belongs to `origin/main`'s history, then runs
   `node scripts/scan-history-secrets.mjs` over every reachable Git object and the
   current inputs;
3. re-runs the three ordinary test suites at the tag's exact commit;
4. builds, signs and notarizes arm64 and x86_64 from the Apple credentials the
   owner supplied;
5. checks both DMGs with `scripts/audit-dmg.sh`;
6. computes `SHA256SUMS` and creates `provenance.json` and the Homebrew cask from
   the real bytes;
7. signs the computed hashes with a GitHub/Sigstore attestation bound to that
   specific workflow run;
8. keeps the result as a private Actions artifact for 14 days.

The workflow **does not create a GitHub Release, does not move the tag, does not
write to another repository and publishes nothing**. Publication stays a separate
action by the owner, after downloading and re-checking the candidate.

An attestation proves which GitHub workflow produced those particular hashes. It
does not prove the program is safe, that the review was any good, or that the build
is byte-for-byte reproducible. The `CruxwingCommit` and `CruxwingSourceHash` values
embedded in the application are narrower still: they are the artifact's own
self-report. So both checks are needed, and neither may be called a security audit
or a reproducible build.

## One-time setup by the owner

Before the first run the owner has to do these themselves:

- protect `main`: pull request, mandatory CI and no force-push;
- protect the `v*` tag pattern against deletion and overwriting;
- create the `release` GitHub Environment, permit only `v*` tags in it and assign
  a mandatory reviewer;
- enable mandatory Code Owner review: `.github/CODEOWNERS` makes the single
  maintainer the owner of the whole tree, because any source file, test or script
  can end up in a signed release;
- after making the repository public, add the read-only `Dependency review` check
  to the required set: public GitHub enables the dependency graph itself, and a
  commit-pinned workflow then stops being skipped automatically;
- add five secrets to the `release` Environment:
  `APPLE_DEVELOPER_ID_P12_BASE64`, `APPLE_DEVELOPER_ID_P12_PASSWORD`,
  `APPLE_NOTARY_KEY_P8_BASE64`, `APPLE_NOTARY_KEY_ID` and
  `APPLE_NOTARY_ISSUER_ID`;
- enable GitHub Private Vulnerability Reporting, as [`SECURITY.md`](../SECURITY.md)
  requires.

The two base64 values are the contents of the exported Developer ID Application
certificate (`.p12`) and the App Store Connect key (`.p8`), not paths to files on a
laptop. The password belongs to the `.p12`. The workflow creates a separate
temporary Keychain, deletes it after notarization, and prints no values.

AI provider keys are not needed here and are not put into GitHub Secrets. Each user
enters their own key in **Settings → AI → Provider keys** after installing;
Cruxwing keeps it in its own macOS Keychain entry.

Rule files and secrets do not by themselves switch protection on. Until the owner
has configured the ruleset, the environment reviewer and the secrets in GitHub's
interface, the presence of a workflow in the repository must not be passed off as a
protected release process.

GitHub gives artifact attestations to public repositories on every current plan,
but to private and internal ones only on Enterprise Cloud. So in a private personal
repository this workflow is obliged to stop at the attestation: do not remove the
step for the sake of a green tick — run the release after a controlled move of the
verified repository to public, or on Enterprise Cloud. That limitation is recorded
in [`actions/attest`](https://github.com/actions/attest#readme).

## Preparing the tag

1. In a PR, update `CFBundleShortVersionString` in `app/Support/Info.plist` and the
   user-facing release notes. Do not edit the number after tagging.
2. Wait for the mandatory reviews and CI, then merge the PR into `main`.
3. From a fresh clean checkout, verify the future tag locally. Before creating the
   tag, `npm run doctor` and all three test suites are worth running.
4. Create an **annotated** tag and push only that:

   ```bash
   git switch main
   git pull --ff-only
   git status --short                 # the output must be empty
   git tag -a v0.2.0 -m "Cruxwing v0.2.0"
   git push origin v0.2.0
   ```

The release gate rejects a lightweight tag (`git tag v0.2.0`). The workflow neither
creates nor repairs a tag on the owner's behalf.

## Building a candidate

Run the workflow **from the tag itself**, passing the same tag as an input, then
approve the deployment in the `release` Environment:

```bash
gh workflow run release-candidate.yml --ref v0.2.0 -f tag=v0.2.0
```

The two values are duplicated deliberately: the workflow refuses to run if its own
definition did not come from `refs/tags/v0.2.0`. An ordinary run from `main` with
the tag only in the input field is not a release. A successful run leaves an
artifact `cruxwing-vX.Y.Z-release-candidate` containing:

```text
cruxwing-AppleSilicon.dmg
cruxwing-Intel.dmg
cruxwing.rb
provenance.json
SHA256SUMS
cruxwing-attestation.sigstore.json
```

For local diagnostics of images that are already built and notarized, the same
boundary is available without GitHub:

```bash
npm run release:check -- v0.2.0
# release:check already includes the full scripts/scan-history-secrets.mjs
bash scripts/audit-dmg.sh \
  app/dist/cruxwing-AppleSilicon.dmg \
  app/dist/cruxwing-Intel.dmg
bash scripts/release-manifest.sh v0.2.0
```

A local `provenance.json` carries no GitHub signature: it is a readable manifest,
not an attestation. The signed Sigstore bundle appears only in the workflow.

## Verify the download, and only then publish

An Actions artifact is a zip container. After downloading, unpack it into a
separate directory and run:

```bash
cd /path/to/cruxwing-v0.2.0-release-candidate
shasum -a 256 -c SHA256SUMS

gh attestation verify cruxwing-AppleSilicon.dmg \
  --repo theasder/cruxwing \
  --signer-workflow theasder/cruxwing/.github/workflows/release-candidate.yml \
  --source-ref refs/tags/v0.2.0 \
  --deny-self-hosted-runners
gh attestation verify cruxwing-Intel.dmg \
  --repo theasder/cruxwing \
  --signer-workflow theasder/cruxwing/.github/workflows/release-candidate.yml \
  --source-ref refs/tags/v0.2.0 \
  --deny-self-hosted-runners
```

For an offline check, first obtain the current root on a trusted machine and then
carry it across together with the candidate. The saved workflow bundle is signed
and therefore not part of its own `SHA256SUMS`:

```bash
gh attestation trusted-root > trusted_root.jsonl
gh attestation verify cruxwing-AppleSilicon.dmg \
  --repo theasder/cruxwing \
  --signer-workflow theasder/cruxwing/.github/workflows/release-candidate.yml \
  --source-ref refs/tags/v0.2.0 \
  --deny-self-hosted-runners \
  --bundle cruxwing-attestation.sigstore.json \
  --custom-trusted-root trusted_root.jsonl
```

On macOS, from a checkout of the same tag, repeat the substantive check of both
images:

```bash
git checkout v0.2.0
bash scripts/audit-dmg.sh \
  /path/to/cruxwing-AppleSilicon.dmg \
  /path/to/cruxwing-Intel.dmg
```

Only after that may the owner create a **draft**, read the release notes, check the
names and download the draft once more before publishing. For example:

```bash
gh release create v0.2.0 \
  cruxwing-AppleSilicon.dmg \
  cruxwing-Intel.dmg \
  SHA256SUMS provenance.json cruxwing-attestation.sigstore.json \
  --verify-tag --draft --generate-notes --title "Cruxwing v0.2.0"
```

The command is given as a manual step by the owner; the workflow does not invoke
it. After publishing, download the DMG from the public URL again and re-check the
SHA-256, the attestation, Gatekeeper and both architecture names. The Homebrew cask
moves into a separate `theasder/homebrew-cruxwing` only after the owner creates that
tap.

## A refusal is a result

A release must stop if the tag is lightweight, the version disagrees, the checkout
is dirty, the tag is not in `main`'s history, one of the DMGs is missing, a sidecar
does not match, Apple did not accept the signature or notarization, Gatekeeper
refused, or the attestation was not created. Those refusals must not be worked
around with an environment variable in the release workflow. A fix is made by a new
commit, a new review and a new tag; a published tag is not rewritten.
