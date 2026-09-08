# Security

Cruxwing listens to your work calls. That is the worst class of program to take
on trust, so what follows is not "we take security seriously" but what exactly happens
to a recording and where data goes.

## The boundary of this document

The statements below apply to the public DIST build (`MEETGPT_DIST=1`) from a
verified commit of this branch. They do not carry over automatically to an old DMG,
a local build with `app/.env`, or a fork that changed the settings. The sources
contain several disabled Cruxwing paths; they are listed rather than passed off as
removed. A technical map of the boundaries is in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## What leaves the machine

The public DIST build has no configured first-party Orakul backend. `app/build.sh`
stops if a non-empty address ends up in the `Secrets.swift` that is actually
compiled, and `Config` does not substitute another product's address. That is a
verifiable configuration boundary, not a network sandbox: the inherited backend,
account, paywall API and plan types still compile and remain P1 debt to remove or
isolate. A direct BYOK launch, meanwhile, does not read an old Orakul account
session from the Keychain and does not subscribe to managed-session notifications.

The real classes of outbound traffic are these:

1. **Downloading local models.** WhisperKit and FluidAudio may download weights on
   first use and then cache them. Call audio must not be part of a download
   request, but the fact of network activity and ordinary HTTP metadata remain
   visible to the model host.
2. **A request to the chosen AI provider.** The user adds, replaces and deletes the
   model key themselves in Settings; there is no fallback key in the build. The
   provider receives the key for authorization and the contents of that specific
   request: the system instruction, the question, the needed part of the
   transcript, attached notes and documents, the dialogue history and the selected
   results from connected services. Full context mode can send considerably more of
   the transcript. The shared toggle for automatic AI requests is off on a new
   installation. While it is off, Orakul does not run the model for the goal, the
   title, a background summary or checks, and does not add passes for
   clarifications, follow-up questions or suggested actions to an explicit
   question; automatic LLM consolidation of Fireflies does not run either. If the
   user turns the toggle on, each such pass becomes a separate request to their
   provider. An explicit action may itself use more than one request — to read
   connected sources, poll a council of models, retry, or fall back to another
   provider in global Auto — and that is not background work. Reading sources
   obeys the shared connected-applications toggle and each application's
   individual mute; the sources used and rejected are named in the answer itself.
   The secret filter is on by default, but it is a heuristic, not a DLP guarantee.
   In direct BYOK mode Orakul does not sell credits, does not count local product
   activity, and does not cut requests off at an inherited monthly limit. Billing,
   rate limits and quotas are applied by the chosen provider to the user's own
   account.
3. **A request to a connected service.** It goes to the official API/MCP of
   Telegram, Google, Fireflies and other chosen services, or to the address of a
   self-hosted installation the user supplied. The request may read, search, import
   or write the selected material. If Telegram or Google Calendar reminders were
   explicitly configured earlier, their background polling may resume on the next
   launch. Team Watch and deferred enrichment from Fireflies likewise run in the
   background only after the corresponding source has been configured.
4. **Cloud transcription on the user's key.** Deepgram is visible in the public
   settings, but the engine is unavailable until the user saves their own key in
   the Keychain; once selected, both live audio tracks go straight to Deepgram.
   Deleting the key first closes a starting, active or paused cloud route; a
   failure to delete from the Keychain is not reported as success. An old
   unavailable cloud setting is normalised to local and is not re-enabled merely by
   a key appearing — the engine has to be chosen explicitly. AssemblyAI is a
   separate post-call tool: after the user adds their own key, only an explicit
   speaker-separation action uploads the retained system track. The inherited
   OpenAI Whisper and server Whisper remain in the sources as compatibility
   clients, but hidden engines fail closed in the public build: an old setting is
   normalised to local, and an OpenAI chat key does not count as consent to upload
   audio. No AI or transcription key is read from `.env` or baked into the bundle.
   The full table of paths and triggers is in the architecture document.

The public app target does not compile first-party analytics, the feedback
uploader, StoreKit purchases, checkout, promo codes or the anonymous device trial;
the privacy manifest declares zero collection by the Orakul developer and no
tracking. That does not mean the chosen external provider stores nothing: its
processing, logs, training, region and deletion periods are governed by your
contract with it.

By default, launching makes no unrequested calls to the developer's server.
`LaunchSendsNothingTests` checks the real launch path and separately requires the
caveat about resumable Telegram/Google Calendar polling above. The check does not
prove the absence of any packet in every scenario; new network paths must be
described here and covered by a behavioural test.

## What is written down

Fragments of the microphone and system audio are held in memory during live
transcription. For local final processing the application may hold up to roughly
60 minutes of **system** audio in memory after Stop — for as long as the chosen
post-call pass might still use it. That is not a saved audio recording and it is
not part of `SavedSession`; the buffer is cleared after its consumers, on reset, or
before a new session. Freeing memory in Swift is not a guaranteed cryptographic
erasure. Video and screenshots are not requested: macOS needs the "Screen
Recording" permission for system audio via ScreenCaptureKit.

The application's persistent files live in
`~/Library/Application Support/ai.orakul.desktop`:

- `Sessions/*.json` — unencrypted transcripts, answers and model history, the
  digest, attached text and notes, prompts and the results of working passes.
  After a rewrite, one `*.json.recovery` remains beside it holding the previous
  confirmed-readable version;
- `Telegram/messages.json` — unencrypted texts and metadata of allowed chats, the
  bot identifier and the polling position; the token is not there. After an
  ordinary update a `messages.json.recovery` may sit beside it with the previous
  readable snapshot;
- `team-watch.log` — for every match: the time, the service/channel, the matched
  keyword, the author and the first 140 characters of the message.

For directories and the two JSON stores the code requests `0700`/`0600`
permissions. Team Watch also attempts to set `0600`. This is protection from
another system user, not from a process under the same account; the contents are
not encrypted.

JSON is first written and synced in full to a hidden file
`.name.<random-id>.tmp` in the same directory, then replaces the main file, after
which the directory entry is synced. A normal exit and the next successful write
remove such a staging file. If the process or macOS died between those steps, it
may remain until the next write of that object or an explicit deletion of the
archive. "Delete call", "Delete all history" and disconnecting Telegram delete the
main file, the recovery and every staging file belonging to that specific object,
and report an error if enumeration, deletion or syncing did not complete.

Recovery is not a hidden, indefinite wastebasket. Changing the Telegram bot and
narrowing the list of allowed chats first delete and sync the recovery/staging
files holding the old contents, then atomically replace the main snapshot with the
reduced one. If the main JSON became corrupt, the application reads the last
confirmed recovery copy; for a session it marks History explicitly as incomplete.
The next write does not replace that single sound copy with a corrupt main file;
Telegram re-checks both copies before every write, not only at startup. A
successful ordinary rewrite again leaves exactly one previous readable version.

Team Watch has no time-based retention. Once the current log exceeds 512 KiB, the
next write attempts to replace the single `.1` copy and start a new file. Errors in
directory creation, writing, permission changes and rotation are currently ignored.
So the log may lose a line, end up with unexpected permissions, or exceed its
intended size; it cannot be treated as a reliable audit log. There is no automatic
cleanup by age.

AI and cloud-transcription provider keys and connection tokens live in the macOS
Keychain, not in `UserDefaults`. The user adds, replaces and deletes keys
themselves; the project does not issue them. Writing a secret into an ordinary
settings plist fails a check. `UserDefaults` still holds non-secret settings, Team
Watch keywords, the consent confirmation and security-scoped bookmarks for chosen
folders. Reading an old `google.tokens` from settings is permitted only to migrate
it into the Keychain, after which it is deleted.

Local model weights are cached by third-party libraries. The user's exports sit
wherever they chose and may end up in their iCloud, backup or corporate sync,
already outside this boundary.

The inherited directory `~/Library/Application Support/MeetGPT` may have held
another product's data, so Orakul does not read or import it automatically: without
an explicit choice by the user, the owner of such transcripts and messages cannot
be determined reliably.

## How to report a vulnerability

**The confidential channel is not yet verified working.** The repository name is no
longer the obstacle: this repository is `github.com/theasder/cruxwing`, and the
redirect to a different product that earlier versions of this file warned about is
gone.

What remains is the owner's to do: enable GitHub Private Vulnerability Reporting,
then confirm from a separate account that the **Security → Report a vulnerability**
tab really does accept a private report. Until that confirmation exists, do not
open a public issue about a suspected vulnerability, and do not read this file as
evidence that a channel is already working.

There is deliberately no security email address here. A mailbox is the easiest
thing to add and the easiest way to lose reports quietly when nobody is watching
it; an address that is published but unmonitored is worse than none. The GitHub
tab, once enabled and verified, is the channel.

What helps get to the bottom of it faster:

* the version — `OrakulSourceHash` and `OrakulCommit` from
  `orakul.app/Contents/Info.plist`;
* macOS and the processor (Apple Silicon or Intel);
* what happens and how to reproduce it.

If you think you have found a data leak or a permissions bypass, write even if you
are unsure: a false alarm costs less than a missed one.

## What we count as a vulnerability

* undocumented sending of audio, transcripts, context or keys, or sending without
  the user trigger described above;
* access to keys bypassing the Keychain;
* a first-party backend, telemetry, crash/feedback upload or commercial path
  turning out to be active in the public build;
* a credential or a first-party backend address ending up in the public bundle;
* recording that continues after it is stopped;
* substitution of the signature or notarization ticket of a published installer.

Not a vulnerability: an error from a provider when the key is wrong, a refusal to
connect to a service with a self-signed certificate, the documented download of
weights, and the application asking for the macOS permissions it needs.

## Check it yourself

```bash
bash scripts/audit-dmg.sh app/dist/orakul-AppleSilicon.dmg app/dist/orakul-Intel.dmg
cd app && swift test                      # the runner prints the current count itself
```

`audit-dmg.sh` ties the signature to the bundle id `ai.orakul.desktop` and the
publisher's TeamIdentifier from `config/app.json`, checks Gatekeeper, the attached
notarization ticket and the architecture of each image. It then compares the full
SHA-256 and commit from the DMG's self-report against the current tree. That last
part is freshness diagnostics, not proof of a reproducible build: the artifact
itself reports those two values.

Separately — a connector against your own service, with your token, using the same
code as the application:

```bash
cd app
ORAKUL_PROBE_SERVICE=mattermost ORAKUL_PROBE_TOKEN=… \
ORAKUL_PROBE_HOST=chat.company.ru swift test --filter LiveConnectorProbe
```
