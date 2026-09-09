# Architecture and trust boundaries

Last reviewed: 2026-08-26.

This document describes the checked-in macOS application and the stricter
`MEETGPT_DIST=1` public-distribution path. It is not a claim that every source
file is active in that build. The fork still compiles some inherited Cruxwing
account, backend, paywall-API, and tariff types behind an empty backend
configuration; those are compatibility debt, not public Cruxwing services.

For user-facing behavior start with [`../README.md`](../README.md). For current
evidence and unresolved work see
[`../app/PROJECT_STATUS.md`](../app/PROJECT_STATUS.md). The enforceable security
claims and reporting status are in [`../SECURITY.md`](../SECURITY.md).

## Repository shape

| Area | Responsibility |
|---|---|
| `app/` | Native macOS 14+ application: capture, transcription, assistant UI, persistence, connected services, and packaging. |
| `mvp/` | Portable `CruxwingCore` library and CLI: archive/search, Russian normalization, and connector policy. The app links it as a local Swift package. |
| `public/` | Static project page. It is not an application backend. |
| `scripts/`, `test/` | Repository policy, provenance, packaging, documentation, and security checks. |

`MeetGPT` source/target names and `MEETGPT_*` build variables are inherited
compatibility names. The public product identity and local data root are
`ai.cruxwing.desktop`.

## Runtime data flow

```text
Microphone (AVFoundation) ─┐
                           ├─> in-process audio chunks ─> selected transcriber
System audio               │                              │
(ScreenCaptureKit) ────────┘                              ├─> live transcript
                                                          └─> optional post-call refinement

transcript + question + selected context/evidence
                       └─> direct model-provider request ─> streamed answer

transcript + answers + context snapshot ─> local session JSON ─> archive/search
connected-service token ─> selected service API ─> bounded result ─> prompt/search/UI
```

ScreenCaptureKit's Screen Recording permission is used to capture system
audio; the capture request does not ask for video frames. Microphone and system
audio are processed as separate live streams.

The default public candidate transcribes on-device. A user can instead add a
Deepgram key at runtime and choose the key-gated Deepgram row. WhisperKit or
FluidAudio may download model assets on first use and cache them; this is
network traffic, but call audio is not part of a model-asset download. Local
inference then runs inside the application process.

For eligible local recordings, Cruxwing can retain up to about 60 minutes of the
system-audio PCM in process memory for a whole-call refinement or speaker pass.
That buffer is not part of `SavedSession` and is not intentionally written as
an audio file. It can outlive the visible recording while an opted-in post-call
consumer still needs it, and it is discarded after the relevant pass, reset,
or a new workspace boundary. Swift memory release is not a secure-erasure
guarantee. The microphone does not enter this full-session retained buffer,
although its live chunks still pass through the selected transcriber.

## Outbound behavior

An empty first-party backend address is a public-build gate, not a network
sandbox. The application can make the following third-party calls when their
trigger is present:

| Path | Trigger and data sent | Credential and destination |
|---|---|---|
| Model assets | First use of an on-device transcription or diarization model; library/model identifiers and normal HTTP metadata, not meeting audio. | Download behavior and cache location are owned by WhisperKit/FluidAudio and their upstream model hosts. |
| LLM inference | A question or enabled assistant workflow. A request can include system instructions, the question, transcript excerpts (or full transcript when full-context is explicitly selected), attached notes/documents, dialog history, and bounded connected-service evidence. The master automatic-request switch defaults off. When off, goal/title/digest/check loops, automatic Fireflies merging, and clarification/follow-up/action-proposal passes do not invoke a model; when enabled, each pass is a separate provider request. An explicit action can still fan out into model rounds for connected-source reads, council synthesis, retries, or global-Auto provider failover. Connected-source reads obey the global app pause and per-app mute, and the visible answer names consulted/refused sources. | Direct vendor endpoint for a provider configured by the user. The user's runtime key is sent to that vendor for authentication. It is not sent to an Cruxwing server. |
| Connected services | User connects a service and then searches, imports, or writes; configured Telegram and Google Calendar polling may resume at launch. Fireflies post-call enhancement and Team Watch polling can also run after their settings are enabled. | Official hosted API/MCP endpoint or a self-hosted address entered by the user; OAuth/token credentials come from Keychain. Service-side storage and retention follow that service's policy. |
| Exports | A user invokes a Google Workspace or similar write operation. The chosen content is sent to that service. Local file exports go only to the path selected in the macOS save panel. | Connected-service token from Keychain, or a user-selected local path. |

Outbound secret redaction is enabled by default for LLM prompts and can remove
recognized credential patterns and user-specified terms. It is a best-effort
content filter, not a formal data-loss-prevention boundary; users must review
the provider and the material they attach.

### Cloud-transcription paths

The public UI and source tree contain several paths with different reachability.
They must not be summarized as one “cloud” switch:

- **Deepgram is visible and runtime-BYOK-gated.** Settings always exposes key
  management. The engine row remains disabled until the user saves their own
  Deepgram key in Keychain; selecting it streams both live PCM tracks directly
  to Deepgram over WebSockets. There is no backend token grant or first-party
  usage report. Removing the key first closes any starting, active, or paused
  stream and moves the route to on-device transcription; a failed Keychain
  deletion is reported rather than presented as success.
- **AssemblyAI is an explicit post-call tool.** Settings exposes a separate
  runtime key. Once the key and opt-in setting exist, an explicit diarization
  action uploads the retained whole-call system-audio WAV directly to
  AssemblyAI and polls for speaker-labelled text. Stopping a local recording
  does not by itself trigger this upload.
- **OpenAI Whisper is retained code, not a public route.** Hidden engines fail
  closed: an old saved value is normalized to on-device transcription, and an
  OpenAI chat key never authorizes an audio upload. Restoring the feature would
  require a visible row and a separate transcription credential.
- **Inherited server Whisper is retained code, not a public route.** Its client
  can upload chunks to a configured backend, but hidden engines fail closed
  even if inherited development configuration exists.
- **Fireflies is a connected-service path, not an Cruxwing transcription key.**
  Fireflies records under the user's separate setup; Cruxwing can later fetch and
  merge that service's transcript when enhancement is enabled.

The tracked `Secrets.swift` contains no AI/transcription credential fallback.
Every model, Deepgram, and AssemblyAI key comes from the user's runtime
Keychain entry; `build.sh` and `.env` do not accept them. The public build also
rejects a non-empty backend address and scans the finished bundle for credential
shapes. Local generated configuration remains for explicit connector OAuth and
development compatibility values; a locally configured binary is not a public
candidate.

Direct BYOK does not consume an Cruxwing credit balance or inherited monthly
Copilot/research allowance, and it does not write the legacy local
meeting/request counters. The selected vendor can still bill or rate-limit the
user's own account. Managed-plan accounting remains compiled only as part of
the compatibility surface described below.

An unavailable saved cloud selection is normalized to Local. Adding a key later
only makes that provider selectable; it does not silently restore cloud audio
transmission without a new explicit engine selection.

“Runtime BYOK” is therefore a supported statement for the reachable model and
cloud-transcription providers. It does not make a provider private: the selected
vendor receives the request/audio and applies its own billing, logging,
retention, residency, and training policy.

## Persistence and retention

| Store | Contents and boundary |
|---|---|
| macOS Keychain | User-entered LLM keys, connector/OAuth tokens, and any compatible account session. Entries use the Cruxwing bundle-scoped service/account namespace. Keychain protects storage; it does not prevent a credential from being sent to the vendor it authenticates. |
| `~/Library/Application Support/ai.cruxwing.desktop/Sessions/*.json` plus `*.json.recovery` | Plaintext saved-call records: transcript, model answers/history, digest, selected context text/notes, suggestions, fact/watch results, and follow-up data. After an overwrite, one recovery file retains the previous verified-readable version. A corrupt primary falls back to it and produces a visible incomplete-History warning. The directory is requested as `0700` and files as `0600`; this limits other OS users, not every process running as the same user. There is no application-level encryption or automatic age-based deletion. |
| `.../Telegram/messages.json` plus `.recovery` | Plaintext Telegram message text and metadata, bot identity, and polling offset for explicitly allowed chats. The token remains in Keychain. Ordinary updates retain one previous verified-readable snapshot. Bot changes and allowlist pruning deliberately discard prior content instead; reset erases primary, recovery, and same-target staging files. The same requested `0700`/`0600` permissions and same-user limitation apply. The archive persists until reset; it has no time-based retention policy. |
| `.../team-watch.log` and `.1` | For each matching Slack Team Watch message: timestamp, service/channel, matched keyword, author, and the first 140 characters. The intended permissions are `0600` under a `0700` directory. Rotation is size-based, not time-based: after the active file exceeds 512 KiB, the next append attempts to replace one `.1` backup and start a new file. File, permission, append, and rotation errors are currently swallowed, so the log is diagnostic only: a failure may lose an entry, fail to tighten permissions, or fail to enforce the intended bound. There is no scheduled deletion. |
| `UserDefaults` | Non-secret preferences and UI state, including provider/model choice, Team Watch keywords, recording-consent acknowledgement, selected-folder paths/bookmarks, and feature toggles. Secrets must not be written here. |
| Dependency-owned model caches | Downloaded transcription/diarization weights. Their cache format and cleanup are owned by the respective libraries; they do not contain Cruxwing session JSON. |
| User-selected exports | Files written to a path the user chooses. Once exported, their permissions, synchronization, backup, and deletion are outside Cruxwing's application-support boundary. |

Both JSON stores use a same-directory hidden staging file named
`.destination.<random-id>.tmp`. The staging bytes are synchronized before an
atomic namespace replacement, and the containing directory is synchronized
after replacement, recovery rotation, and deletion. A hard process or OS stop
can leave a staging file; the next successful write for that destination and
the explicit erase paths remove it. Erase operations remove staging and
recovery artifacts before the primary, surface enumeration/removal/sync errors,
and only let the UI claim an empty archive after re-listing disk state.

Recovery policy depends on the operation. A normal overwrite rotates a
successfully decoded primary into recovery. Every Telegram write revalidates
the primary immediately before choosing that policy; if recovery is the only
readable copy, the write keeps it while replacing the corrupt primary. A
destructive Telegram identity/allowlist transition removes recovery and earlier
staging artifacts, synchronizes that cleanup, and only then atomically replaces
the still-valid primary with its reduced snapshot. These copies improve crash
recovery; they do not provide encryption, secure erase, or an independent
backup.

The application does not automatically import the inherited
`~/Library/Application Support/MeetGPT` directory. An automatic import could
expose another product's transcripts without a trustworthy owner marker.

## Trust boundaries

- **The local process is trusted with meeting content.** A process compromise,
  malicious dependency, debugger, same-user filesystem access, or compromised
  macOS account is outside the protection offered by file modes and Keychain.
- **The Keychain is the credential boundary.** Provider and service tokens are
  not ordinary settings, but they must leave that boundary when authenticating
  to the selected vendor.
- **Every selected provider/service is an independent data controller.** Cruxwing
  cannot enforce its retention, training, residency, logging, or deletion
  policy. The user must choose a suitable account and jurisdiction.
- **Vendored Agent Skills are reviewed untrusted methodology data.** Digest,
  allowlist, scope, and sanitization checks constrain their use; they are not a
  process sandbox and do not prove model output safe.
- **The public build pipeline is a supply-chain boundary.** Swift packages,
  model assets, GitHub Actions, Apple signing/notarization, generated SBOMs,
  checksums, and attestations each prove a narrower property. None is a general
  security audit or a byte-for-byte reproducible-build guarantee.

The privacy manifest declares that the Cruxwing developer collects no data and
does not track users. That statement does not describe data a user directs to
an external model, transcription vendor, or connected work service.

## Compatibility and debt boundary

The following are deliberately documented rather than disguised as completed:

- inherited account, identity, backend-gateway, paywall API, and tariff types
  still compile, although the public build's empty backend keeps those paths
  unavailable;
- direct BYOK neither reads a legacy Cruxwing account session from Keychain nor
  subscribes to managed-session notifications; managed compatibility can do so
  only when its backend gateway is explicitly enabled;
- hidden OpenAI Whisper and server-Whisper compatibility clients remain, but
  public runtime availability rejects them and normalizes stale preferences to
  on-device transcription;
- several source, target, executable, and environment names still say
  `MeetGPT` or `MEETGPT_*`;
- `AppState` owns too many domains, making network and lifecycle review harder;
- source-shape tests prove selected invariants but cannot substitute for live
  provider, permission, failure, and packet-level tests; and
- model downloads and live vendor APIs are not reproducible or availability
  guarantees merely because the application builds.

Removal or target isolation of these paths is preferable to accumulating more
configuration guards around them.

## Release gates

A public release requires all of the following, in addition to normal tests:

1. enable and verify Private Vulnerability Reporting, and protect
   `main`, release tags, Code Owner review, and the `release` Environment;
2. review a clean commit, scan the complete reachable Git history and current
   inputs for secrets, and verify licenses, notices, the skill allowlist, SBOM,
   and privacy manifest;
3. create an annotated version tag that matches the app version and is in the
   protected `main` history;
4. build Apple Silicon and Intel candidates from that exact tag with the
   owner-supplied Apple credentials, then verify bundle secret gates,
   Gatekeeper, notarization, architecture, hashes, and source stamps;
5. download and independently verify `SHA256SUMS`, provenance, and the
   workflow-bound attestation; and
6. have the owner create and inspect a draft, then publish deliberately.

The workflow prepares an unpublished candidate and must not publish, move tags,
or bypass a failed gate. The complete procedure and its limits are in
[`RELEASING.md`](RELEASING.md).

## Changing a boundary

A pull request that changes capture, persistence, credentials, network calls,
connected services, logging, packaging, or release automation must state:

1. what new data exists;
2. where it lives and for how long;
3. which user action or persisted setting triggers it;
4. every destination and credential used;
5. behavior on cancellation, timeout, partial failure, and relaunch;
6. the exact `SECURITY.md` and architecture update; and
7. a test that would fail if the old unsafe behavior returned.

If any answer is unknown, keep the feature out of the public target until it is
known and reviewable.
