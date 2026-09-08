# Cruxwing

A call assistant that answers "what did we decide?" with a quote from the call
where it was said. On your own computer, free.

**This repository is the Russian-speech edition.** The whole application — system
audio capture with no bot, on-device transcription, search across your own calls.
The interface, the command line and the system prompts are in Russian, and the
lexicon is built for Russian technical speech; the documentation is in English.
Its own identity (`ai.orakul.desktop`). All three test suites run in CI.

```
record a call   →   transcribe   →   fix the terms    →  to archive  →  search
  microphone           on           cross-alphabet        works         works
  and call audio     device            lexicon
```

## Running it in five minutes

You need Swift 6.0+ (Xcode 16+) and Node 20+. `mvp/` — the part shown below —
has no external dependencies at all. The application in `app/` has four:
WhisperKit and FluidAudio for speech recognition, the MCP SDK for connectors,
ViewInspector for view tests. Those pull in twenty-three more — 27 packages in
total in `app/Package.resolved`, and you will see that many `Fetching` lines on
the first build. The five minutes are about `mvp/`.

After cloning, `npm run doctor` only checks tool versions and checkout
integrity: it installs nothing, downloads nothing and asks for no keys. The root
package has no dependencies, so `npm install` is not needed; `.nvmrc` pins the
same Node 22 that CI uses (Node 20 is the minimum).

**Nothing here is downloadable yet, and the reason is provenance rather than
naming.** Measured 2026-09-08: the repository is `github.com/theasder/cruxwing`,
<https://cruxwing.ai> answers 200, and GitHub Pages answers 200 at
<https://theasder.github.io/cruxwing/>. What has not been resolved is the
historical `v0.1.0`: it predates this branch and fails its artifact-provenance
check, so the old release is not passed off as the current one.

To publish, cut both DMGs from a single commit and check them with
`scripts/audit-dmg.sh`. This change deliberately does not publish a release.

```bash
# From the root of a checkout you already have; to start from nothing:
# git clone https://github.com/theasder/cruxwing.git cruxwing
cd mvp && swift build -c release

cat > расшифровка.txt <<'TXT'
Аня: По тарифам — что решили в итоге?
Борис: Годовой не трогаем до декабря, месячный поднимаем на пятнадцать процентов.
Аня: Кто делает?
Борис: Я, к пятнице выкачу в биллинг.
TXT

.build/release/orakul добавить расшифровка.txt "Планёрка по тарифам"
.build/release/orakul найти что решили по тарифам
```

The command line lives in `mvp/`, the application in `app/`. This used to say
`cd app`, and the very first command broke: `app/` builds `MeetGPT`, and there is
no `.build/release/orakul` there.

```
Добавлено: «Планёрка по тарифам» (27AE25B5-…)
«Планёрка по тарифам», 12 августа 2026
    Аня: По тарифам — что решили в итоге
    Борис: Годовой не трогаем до декабря, месячный поднимаем на пятнадцать процентов.
```

The date is the day the call was added. Search is lexical: it returns the line
where the word occurred rather than paraphrasing it. That is the whole trick —
the answer is always in the transcript's words, not its own.

Ask about something the calls never covered and you get a refusal, not an
invention:

```
$ orakul найти когда корпоратив
В сохранённых звонках об этом не говорили. Ответ придумывать не буду.
```

It tells a typo apart from an absent conversation. Search is lexicon-based, and
"тарифф" with an extra letter matches nothing — but answering "never discussed"
to that would pass sentence on a topic that was in fact discussed:

```
$ orakul найти тарифф
В сохранённых звонках об этом не говорили. Ответ придумывать не буду.
Похоже на опечатку — в архиве есть «тарифам».
```

The word is not substituted silently: replacing the question means answering a
different one. A miss in the inflection needs no hint — "тарифя" is found as it
is, because search strips endings on its own.

A call can be deleted by the start of its identifier, like a git commit:
`orakul удалить 49290B26`. A prefix shorter than four characters is refused, and
if several calls match it, nothing is deleted and the list is shown. Deletion
cannot be undone, so guessing is not allowed here.

Tests run as three independent commands: `cd app && swift test`,
`cd mvp && swift test`, and `npm test` at the root. The last suite checks the
page, the documentation, build security and the application's identity.

An ordinary run **skips** some of the integration and measurement checks: they
need real models, recordings, a live service or a quiet machine. The reason is
visible in the output; a skip is not passed off as proof. Speed budgets are among
them: `cd app && CRUXWING_PERF=1 swift test --filter Performance`. Measured
2026-08-13: search across 250 calls — 2.04 s, best of three.

Checking a connector against your own service, with the same code the
application uses:

```bash
ORAKUL_PROBE_SERVICE=mattermost ORAKUL_PROBE_TOKEN=… \
ORAKUL_PROBE_HOST=chat.company.ru ORAKUL_PROBE_SCOPE=team-id \
bash scripts/test-filter.sh app LiveConnectorProbe
```

Without those variables this test is skipped: an ordinary run does not touch the
network. The token is read from the environment, written nowhere, and never
reaches the output. Services: `pachca`, `mattermost`, `rocketChat`, `zulip`,
`matrix`, `gitlab`, `gitea`, `redmine`, `outline`.

Building the installer: `(cd app && bash dist-all.sh)` — both architectures,
arm64 and x86_64. The fast single-architecture variant,
`(cd app && MEETGPT_ARCH=arm64 ./notarize.sh && ./dmg.sh)`, leaves the second DMG
at yesterday's build, and the check below will say so.
To check both built or downloaded DMGs explicitly:
`bash scripts/audit-dmg.sh app/dist/orakul-AppleSilicon.dmg app/dist/orakul-Intel.dmg`.
The script verifies the signature and the attached notarization ticket, reads the
full commit and the SHA-256 of sources, manifests, lockfile and packaging inputs
out of each file, and compares them against the current tree. This is freshness
diagnostics from the artifact's own self-report, not proof of a reproducible
build: the stamp is reported by the DMG itself.
A new public release must contain both files — `orakul-AppleSilicon.dmg` and
`orakul-Intel.dmg` — from one commit, with a Developer ID signature and an Apple
notarization ticket. The stamp inside a DMG shows which source state that
particular file belongs to; the historical `v0.1.0` does not match this tree and
is deliberately rejected by the new check.

The maintainer's full path — protected tag, manual workflow with no publishing, a
single `SHA256SUMS`, GitHub/Sigstore attestation, verification of the download and
only then a draft release — is described in
[`docs/RELEASING.md`](docs/RELEASING.md). The workflow does not create the release
itself: Apple credentials and approval of the `release` Environment are added by
the owner, and AI provider keys are not needed there. Each user enters those
themselves in Settings → AI after installing.

Once a dedicated tap exists, installation will be able to look like one command:

```bash
brew install --cask theasder/orakul/orakul
```

The tap (`theasder/homebrew-orakul`) **does not exist yet**. It also needs the
correct public repository identity and a fresh release first: the cask template
itself already builds from the repository, and `bash scripts/refresh-cask.sh`
computes the sums over both images and prints the finished file. Cruxwing is not
submitted to the main `homebrew-cask`: they require the project to be well known,
and with zero stars there is nothing to argue about.
To check for yourself: `spctl -a -vv -t open --context context:primary-signature
orakul-AppleSilicon.dmg` should answer `accepted, source=Notarized Developer ID`.

If you already have whisper.cpp installed, transcription works too — Cruxwing runs
your own program, substituting the path for `{файл}`:

```bash
export ORAKUL_ENGINE="whisper-cli -m ~/models/ggml-large-v3.bin -l ru -otxt -f {файл}"
orakul расшифровать звонок.wav "Планёрка по тарифам"
orakul найти что решили по тарифам
```

A 16 kHz WAV is required. If the rate differs, Cruxwing will not resample it
silently; it says what the rate is and gives you an `ffmpeg` command: a bad
resampler damages recognition more quietly than a refusal does.

Cruxwing does not ship a model of its own: gigabytes of weights at install time is
no longer "running it in five minutes".

### Private speaker labels · Beta

In the application, choose the local engine and turn on "Определять говорящих на
этом Mac" before the call starts. After stopping, give the number of other
voices, from one to four, and press "Подписать говорящих". The microphone is
labelled "Вы", the remaining voices "Спикер 2", "Спикер 3" and onward in order of
first appearance. The number can be corrected and processing run again.

The first run downloads about 34 MB of models. Audio and embeddings stay on the
Mac, voice prints are not saved; labels are written only to this call's local
history on this Mac. For a call longer than an hour, only the fully saved part is
processed. This is a beta feature: check the labels before sending a transcript
out.

### Seeing how search works

```swift
import OrakulCore

let store = SessionStore(root: URL(fileURLWithPath: "/tmp/orakul"))
try store.save(.init(id: "s1",
                     title: "Планёрка по тарифам",
                     date: "2026-07-24",
                     digest: "Решили перейти на оплату за использование."))

if let hit = store.index().search("что решили по тарифам").first {
    print(hit.session.title, "—", hit.excerpt)
    // Планёрка по тарифам — Решили перейти на оплату за использование
}
```

## Why it is built this way

**Search is lexical, not semantic.** In the English-language version, embedding
search failed to find a call *by its title*: two phrasings out of three came back
empty, because cosine similarity between sentences rewards topical likeness while
a question about a title asks about a name. On top of that, the system sentence
model on macOS is English-language and answers Russian text with a meaningless
vector. So what is here is honest lexical search with Russian morphology: it
understands cases, it does not understand synonyms. A question about "цены" will
not find a call where people said "тарифы", and there is a separate test for that.

Morphology is not "cases in general" but a list of endings, and it had a hole.
The class of words ending in "-ние" (обновление, подключение, решение,
тестирование, согласование) was findable in no case but the nominative:
"развёртывание" was trimmed to "развёртыван" while "развёртыванием" became
"развёртывани". Two different stems for one word — that is, an honest "never
discussed" about something that was discussed. Fixed on 14 August; the analysis
is in `docs/RESEARCH-AND-PLAN.md`, §6.7. The same section states what ending
trimming cannot and will not do: verbs are not reduced across aspect,
"выкатываем" will not be found by "выкатить".

**The lexicon fixes the transcript afterwards rather than hinting beforehand.**
Measured on live Russian speech: three engines disagreed on 29% of terms, and
every disputed one turned out to be code-switching — "прод", "промпт", "API",
"джейлбрейк". And they disagree not in hearing but in alphabet: Whisper writes
`Prompt`, Parakeet writes "Промпт". A cross-alphabet lexicon raised agreement
from 71% to 89%. A decoder hint does not solve this problem and is capable of
deleting speech: on an English corpus such a glossary drove the model to WER 0.95
with 2757 omissions.

**Recording, transcription, archive and search are computed on the device.** The
network appears only because of a choice you made: a question to your chosen
provider, a request to a connected service, or the resumption at startup of a
connector poll you switched on earlier. The address and the bounds of every such
request are described in [SECURITY.md](SECURITY.md).

## What is inside

| Module | What it does |
|---|---|
| `RecallIndex` | Search across your own calls: Russian stems, rare words weigh more, a match in the title counts double |
| `RussianLexicon` | The canonical spelling of terms, including cross-alphabet (`prod` → "прод", "апи" → `API`) |
| `SessionStore` | The on-disk archive: one file per call, atomic writes, a corrupt file does not bring down the rest |
| `MeetingPipeline` | The end-to-end path from sound to archive; the transcriber is plugged in from outside |
| `ExternalTranscriber` | Transcription by someone else's engine: 16 kHz WAV, `{файл}` substitution, engine errors arrive intact |
| `SpeechEval` | Recognition scoring: WER and engine disagreement without a reference |
| `PromptCatalog` | Quick-action buttons, their text in JSON |

The core knows nothing about SwiftUI, CoreML or ScreenCaptureKit. A Windows port
costs exactly what lies outside `OrakulCore`: audio capture (WASAPI instead of
ScreenCaptureKit) and the shell.

This is held in place by a test rather than by intent: `PortabilityTests` allows
the core only those system modules that exist outside Apple too — `Foundation`
and `FoundationNetworking`. An `import AppKit` for the sake of one convenient
function would break nothing on macOS and would silently double the cost of the
port — so it is caught by a test suite rather than by a future developer six
months from now.

An import check proves less than it seems, though, and that became clear on
17 August: the core, with its single `import Foundation`, would not build on Linux
at all — `URLRequest` and `URLSession` live in a separate module there, and six
connectors failed on the very first line. Now the core and the command line are
not merely built in a `swift:6.0` container on every pull request: a full
`swift test` runs there. corelibs differences (Windows-1251, URL parsing and
permissions under root) are pinned by separate Linux branches, with explicit skip
reasons where root makes an honest check of a refusal impossible. The analysis is
in [`docs/ROADMAP.md`](docs/ROADMAP.md), §6.1.

## What is still missing

- a recognition model of our own: Cruxwing uses the one you already have
  (`ExternalTranscriber`) and does not ship gigabytes of weights;
- universal history import from call services. Audio from Telemost, VK Teams,
  SaluteJazz, TrueConf and Jitsi is taken by system capture — you can record
  ongoing calls today; Jitsi is detected by window/application, TrueConf by a
  running client and microphone. For the past, Telemost has no enumeration, VK
  Teams has no calls in its Bot API, TrueConf's exact methods depend on a
  particular server's API, Jitsi recording lives in the owner's Jibri/JaaS
  infrastructure, and SaluteJazz requires a backend to issue a token — which
  Cruxwing does not have by design. The analysis of each is in
  `docs/RESEARCH-AND-PLAN.md`, §11;
- a Pyrus connector: its API has no text search over tasks, only a registry of a
  particular form. This is not about timing — it is how the API is built;
- knowledge-base connectors: Yandex Wiki's public documentation has page
  retrieval by address but no text search; for Teamly we found no public API
  description (details in `docs/RESEARCH-AND-PLAN.md`, §2.1);
- a Windows version: audio capture there is its own thing (WASAPI), and it has
  not been written.

The order in which this is worked through, and what blocks each item, is in
[`docs/ROADMAP.md`](docs/ROADMAP.md) (in English, as is `RESEARCH-AND-PLAN`).
The connector queue is there too: for each service it says not "when" but what
exactly is unknown and what would unblock it.

Connectors to Russian trackers — Yandex Tracker, Kaiten, YouGile and WEEEK — are
already here: connect by token under "Настройки → Подключённые приложения", in the
first block. They work in both directions: Cruxwing queries them during a call when
it has been given a goal, and files tasks from the outcome — provided you say
where to put them (a queue in Yandex, a board in Kaiten, a column in YouGile, a
project in WEEEK).

Bitrix24 connects as well, but differently — by a webhook whose key sits directly
in the address. And an honest caveat: it is **built from the documentation, not
verified against a live portal**, because we have no portal. Bitrix answers
HTTP 200 and puts the error in the body, so a revoked webhook can look like
"nothing found"; we do handle that branch, but on a fabricated response. The
analysis is in `docs/RESEARCH-AND-PLAN.md`, §2.0.1; if you have a portal, help us
check it: issue [#1](https://github.com/theasder/cruxwing/issues/1).

Telegram supergroups connect through a separate bot. The Bot API does not hand
over old history, so Cruxwing receives and locally indexes only new messages from
explicitly named supergroups after connecting. The token stays in the Keychain,
the bot sends nothing, and on disconnection the accumulated archive is deleted.

How to build a closed integration build, grant testers minimal rights and then
revoke access is described in
[`app/docs/TESTER-INTEGRATIONS.md`](app/docs/TESTER-INTEGRATIONS.md). Working keys
are not committed to a branch or a fork.

About the two folders. `mvp/` holds the first version, written from scratch: the
command line, the search core and the lexicon, without system audio capture. The
quick start above goes through it because it builds in a minute and can be seen
whole. `app/` holds the application: audio capture, on-device transcription,
connectors, the installer. Everything below about integrations, keys and plans is
about `app/`.

## Your own provider key

Keys are deliberately not baked into the finished installers, so model answers run
on your key: "Настройки → ИИ → Ключи провайдеров". The key lives in the Keychain
and survives a restart; spending goes through your contract with the provider —
Cruxwing does not stand in that chain.

Automatic requests to the model are switched off on a new installation by one
shared toggle. While it is off, recording does not by itself start goal and title
suggestions, a summary, or background checks, and after an explicit question it
does not make extra passes for clarifications and next steps. Turn it on and every
pass, plus automatic Fireflies consolidation, is paid for by your provider. An
explicit action may itself use several requests — to read connected sources, poll
a council of models, retry, or fall back to another provider in global Auto. A
global pause and muting an individual application forbid reading it, and the
answer names the sources it used or rejected.

**YandexGPT** comes first: the only path on which data stays in Russia. Besides a
key it needs a catalogue identifier (`b1g…`), otherwise the request goes out with
a model the service does not know. It is chosen for where data is stored, not for
strength: across twelve practical tasks the domestic models won none
(`docs/RESEARCH-AND-PLAN.md`, §3).

Then come the ones that are cheaper and answer Russian confidently enough
(DeepSeek, Qwen, GLM, Kimi), then OpenAI, Anthropic, Google. Beside each one it
says where to get a key.

GigaChat is not connected: in its public documentation neither the token issuance
address nor the root certificate requirement is consistent — the same rule that
ruled out Pyrus.

## What it costs

Nothing. There are no plans, no paid features, no account needed. Recording,
transcription, archive and search work on your computer. Requests to the model go
on your key and are paid under your contract with the provider; Cruxwing takes no
money and is not an intermediary in that request.

In the application this means: every model in the catalogue is open, not two out
of twelve; there is no pricing screen; there is no "Тариф" row in settings. The
plan machinery inside still compiles as Cruxwing compatibility, but the direct
BYOK path keeps no local product statistics and limits no requests by hours,
credits or cycles. Structurally isolating the remaining types is a P1 before
release.

## How to take part

Issues and pull requests are in Russian. What is needed most, and the rules under
which it is accepted, are written in [CONTRIBUTING.md](CONTRIBUTING.md); the
shortest of those rules is: do not claim what does not exist.

Once the repository's canonical name is restored, you will be able to start from a
ready task — the label
["первая правка"](https://github.com/theasder/cruxwing/labels/%D0%BF%D0%B5%D1%80%D0%B2%D0%B0%D1%8F%20%D0%BF%D1%80%D0%B0%D0%B2%D0%BA%D0%B0):
it holds work that can be done without understanding the whole project. The label
["нужен доступ"](https://github.com/theasder/cruxwing/labels/%D0%BD%D1%83%D0%B6%D0%B5%D0%BD%20%D0%B4%D0%BE%D1%81%D1%82%D1%83%D0%BF)
is the opposite: the work is blocked not by code but by an account or a portal we
do not have. If you have such access, that will be the most useful change of all.

Every pull request is run in full: the native application and mvp on macOS; the
core, the command line and the whole mvp suite are additionally built and tested
on Linux; the page and documentation checks run on Linux too —
[.github/workflows/ci.yml](.github/workflows/ci.yml). Hearing about a breakage from
a robot in a minute beats hearing it from a person in a day.

What we are obliged to do in response to your change is in
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). It is not about politeness: it is the
duty to explain every closure and the right to demand a review. We are making a
tool for people who left forums where decisions are made in silence.

You can check which code a Linux package was built from the same way as for
macOS: the stamp is inside the file, not in the build log.
`bash scripts/audit-package.sh orakul_0.1.0-179_arm64.deb` reads it and recomputes
the hash over the tree.

**There is one maintainer here.** That is neither modesty nor an invitation to
pity: what to expect depends on it. An answer to an issue can take several days,
and during a holiday may not come at all. Promising deadlines nobody guaranteed is
worse than saying this plainly; the rule from
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) — explain every closure — holds even with
one person.

Found a security hole — not in a public issue, but by the instructions in
[SECURITY.md](SECURITY.md). That file also states exactly what leaves the machine:
for a program that listens to calls this is the first question, and it deserves a
written answer rather than a paragraph about how seriously we take it.

## Licence

Mozilla Public License 2.0 — see [LICENSE](LICENSE).

File-level copyleft: changes to this project's files return to the commons, while
your own code beside them may stay closed. That makes it possible to embed Cruxwing
in closed products while preventing improvements to our part from being carried
off into a closed fork.

MPL 2.0 has an explicit patent grant (section 2.1) — that is what a client
company's lawyer looks at, and it is precisely why Apache 2.0 was previously
chosen over MIT. The patent part was preserved in the move to MPL.
