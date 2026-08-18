# orakul — roadmap

## 1. What this file is

`docs/RESEARCH-AND-PLAN.md` answers «why built this way»: research, dead ends
checked, decisions with causes. This file answers the other question — **what
next, in what order**.

Same rules as the rest of the repo:

- every number here is measured, and the command or link stands next to it;
- an unchecked thing is marked **ASSUMPTION** and does not count as fact;
- a task with unread vendor docs is a question, not a promise;
- horizons, not release dates: one maintainer, and order is more honest than
  calendar.

State: v1, 2026-08-17.

---

## 2. Where we stand (counted 2026-08-17)

### 2.1 Repository

| What | Value | Measured by |
|---|---|---|
| Public since | 2026-08-13 | `gh repo view theasder/orakul --json createdAt` |
| Stars and forks | 0 and 0 | same |
| Open issues | 3, all «нужен доступ» and «первая правка» | `gh issue list` |
| Discussions | off | `hasDiscussionsEnabled: false` |
| Page | <https://theasder.github.io/orakul/> serves «orakul.ai — звонок, который можно спросить» | `curl` |
| Page and doc checks | 252 tests, all green | `npm test`, run 2026-08-18 |
| App and core tests | 2822 and 521 | README, maintainer run |
| Full-run stability | one suite fails intermittently — see below | six consecutive full runs 2026-08-18 |

Repo is four days old. Everything below about growth starts from that, not from
an assumption the audience already exists.

**«All green» needs one caveat, stated because a table that hides it is worse
than no table.** `BlindSpotSchedulerRaceTests` failed twice on full runs on
2026-08-18 and passed every time it ran alone. The mechanism is understood in
outline: several suites write the same process-wide settings
(`brainstormEnabled`, `connectedAppsGroundingEnabled`), six of them through the
`SharedDefaults` gate and three without it, so a neighbour could flip a flag in
the middle of a wait. Those three now take the gate too.

What that is **not**: a demonstrated fix. Six further full runs — three gated,
three deliberately ungated, one of them under concurrent load — all passed, so
the change is a removed inconsistency rather than a proven repair. If it recurs,
the next step is capturing which neighbour wrote what, not another guess.

### 2.2 Connectors, counted from code, not from the page

| Layer | Connected | Where in code |
|---|---|---|
| Russian trackers | Яндекс Трекер, Kaiten, YouGile, WEEEK, Битрикс24 | `mvp/Sources/OrakulCore/RussianTrackers.swift` |
| Work messengers | Пачка, Mattermost, Rocket.Chat, Zulip, Matrix | `WorkMessengers.swift` |
| Own servers: code and tasks | GitLab, Gitea and Forgejo, Redmine | `SelfHostedTrackers.swift` |
| Notes | Outline | `TeamNotes.swift` |
| Code in the cloud | GitHub, personal token, `GET /search/issues` | `GitHubConnector.swift` |
| Team chats | Telegram supergroups, new messages only | `TelegramSupergroups.swift` |
| Western services via MCP | Notion, Fireflies, Linear, Atlassian (Jira and Confluence), Intercom, Sentry, Zapier, Attio, PostHog, Amplitude, Mixpanel | `MCPCatalog.builtIn` |

Total: 25 own connectors, 11 western via MCP.

### 2.3 What reaches the downloader is not the same thing

The MCP catalog holds six more descriptors: Asana, HubSpot, Affinity, Zoom,
Gmail, Google Analytics. They need a **pre-registered** app, meaning credentials
inside the build, and credentials stay out of shipped installers on purpose
(`app/build.sh`: a dist build emits only explicitly named settings — §5.2; plan
§9.1). So downloaded orakul has no such six buttons.

Not a defect — a consequence of the rule. What was a defect is §5.2: four
credential names slipped past the list that used to enforce it, closed
2026-08-17 and made structural 2026-08-18.

The claim above is checked at the mechanism, not at the machine. The old test
asked whether credentials happened to be present in whatever build ran it and
asserted the matching branch — true under any behaviour, and blind to a seventh
service added past the gate. Now `configuredDescriptor` is exercised directly:
an empty id or an empty secret yields nothing, both halves yield a descriptor
(otherwise «shows nothing» could be achieved by working never), and an unknown
id is refused even with credentials.

---

## 3. Borders this plan does not move

| Border | Enforced by | What it deletes from any plan |
|---|---|---|
| Nothing paid | `NoTariffsTests` | subscriptions, team tiers, pro version |
| No server of ours | `build.sh` halts the build on non-empty `BACKEND_URL`; `NoBackendPromisesTests` | cloud sync, accounts, SaluteJazz connector (plan §11) |
| Data stays on the machine | button catalog fails to load when a button needs network | telemetry, «send us the transcript for analysis» |
| Claim nothing that is absent | CONTRIBUTING, `LiveConnectorProbe`, census plan §2.0.3 | a «Connect» button before vendor docs are read |
| Russian first | `contributing.test.mjs` | an interface where Russian arrives later as translation |
| Apache 2.0 | `LICENSE` plus three checks in docs and page | licence swap to fend off clouds |

Not values talk: every line breaks a build or a run when violated. A plan that
needs them cancelled is a bad plan, not a bold one.

---

## 4. How the queue gets chosen

One question sets the order: **how many people it cuts off before first launch**
— cost comes second.

1. Cut off by platform: no Windows — hits everyone at once.
2. Cut off by visibility: nobody knows the repo exists — hits everyone who could
   have come.
3. Cut off by stack: no connector to what the team runs — hits a part, but
   exactly the part the product exists separately for.
4. Everything else.

Above that, a hard gate for integrations: **method, host, search parameter and
response shape found in vendor docs**. Not found — the task stays a question and
does not enter a horizon. Pyrus, Мегаплан, Яндекс Вики, Teamly and GigaChat fell
on this, and that is the right outcome, not debt.

---

## 5. Horizon 0 — weeks: fix what is broken and what breaks on the first `git push`

### 5.1 Page `/ru` belongs to another product

`public/ru/` sits in the repo and holds a **Cruxwing landing**, not orakul: 53
mentions of cruxwing and zero of orakul, `rel="canonical"` points at
`https://cruxwing.ai/ru/`, and the pricing block promises paid plans — straight
against plan §5, «free, whole».

**And that canonical is a 404 (checked 2026-08-18).** `https://cruxwing.ai/ru`
and `/ru/` both answer 404, as does every file under them, while `/demo-film/`
at the root answers 200 — the directory has never been published. The page is
committed on the deploying branch of the other repository; the site there is
simply older than it. So publishing this copy on the orakul site would announce
a canonical pointing at an address that does not exist — on top of it being
another product's page with prices.

Right now `https://theasder.github.io/orakul/ru/` returns 404, only because the
two commits carrying that page are unpushed: local `main` leads `origin/main` by
two (`git rev-list --left-right --count origin/main...main` → `0 2`). Workflow
`pages.yml` fires on any change under `public/**` — so the first `push`
publishes a pricing page on the site of a product that has no prices.

**Do one of three before pushing, deliberately:**

1. move `public/ru/` back to the Cruxwing repo it came from;
2. keep it here, exclude it from publishing — `pages.yml` builds the branch from
   the whole `public/`, so the exclusion has to be written;
3. rewrite it for orakul: no prices, own identity, own `canonical`.

**What is missing so it cannot return:** a check that fails when the published
directory holds a page with «Cruxwing» in the title or a `canonical` on a
foreign domain. Today `ru-landing.test.mjs` pins that page, not its right to be
here.

### 5.2 Nothing ships unless it is named — closed 2026-08-18

**What was wrong.** `build.sh` substitutes values through `sw`, and for names
listed in `SECRET_VARS` a DIST build gets an empty string back. The list is
written by hand: 44 names pass through `sw`, 26 sit in the list. Four of the
uncovered eighteen were credentials:

```
GMAIL_CLIENT_ID  GMAIL_CLIENT_SECRET
GOOGLE_ANALYTICS_CLIENT_ID  GOOGLE_ANALYTICS_CLIENT_SECRET
```

Listed in one command:

```bash
node -e 'const b=require("fs").readFileSync("app/build.sh","utf8");
const vars=/SECRET_VARS="([^"]+)"/.exec(b)[1].split(/\s+/);
const used=[...new Set([...b.matchAll(/\$\(sw ([A-Z0-9_]+)\)/g)].map(m=>m[1]))];
console.log(used.filter(v=>!vars.includes(v)).join("\n"))'
```

The remaining fourteen are settings (`TRANSCRIPTION_*`, `LLM_GATEWAY`,
`DEFAULT_TIER`) and do not belong in the list; `BACKEND_URL` is covered by a
separate, stricter check.

The class had fired before: the inherited `Secrets.swift` carried live Google
client credentials and they shipped inside published DMGs — recorded at the top
of `test/secrets.test.mjs`. Such a leak was caught only by the check scanning
the built binary, and **that check is skipped when the app is not built**, which
is everyone except the person cutting the release.

**What changed, in two steps.** First (2026-08-17) `sw` began blanking by
**shape of the name** — `*_CLIENT_ID`, `*_CLIENT_SECRET`, `*_TOKEN`,
`*_API_KEY` — so a new credential was covered on arrival. That left a gap this
file recorded rather than hid: a secret whose name has no recognisable shape
still depended on the hand-written list, and `SLACK_CHANNEL_IDS`,
`CONFLUENCE_SITE` and `CONFLUENCE_EMAIL` are exactly that.

Second (2026-08-18) the rule was **inverted**. A dist build now emits only what
is named explicitly — `BACKEND_URL`, `BACKEND_CERT_PINS`, `DEFAULT_TIER`,
`LLM_GATEWAY`, `ENSEMBLE_*`, `TEAM_WATCH_AUTO_ACK`, `TRANSCRIPTION_*` — and
blanks everything else, whatever it is called. The gap closes structurally: to
reach the binary, a value has to be spoken for. The cost changes sign too. The
failure is no longer «a secret left silently» but «a setting did not arrive»,
which shows up on the first launch.

`SECRET_VARS` stays in the file as a list of known secrets for a reader, and no
longer decides anything — said in a comment beside it, because a list that looks
operative and is not is its own trap.

**Second guard, on the artefact rather than the generator.**
`app/assert-no-env-values.sh` compares the built file with `.env` literally: if a
value from there occurs in the binary, it shipped, and by which route is a
detail. Two things it refuses to do — search via `strings` (that skips UTF-8, and
the first version reported «clean» about a planted Cyrillic value) and print the
value it found (a check that leaks a secret into the build log opens the hole it
is looking for).

Finding it exposed a bigger gap than the one it was written for. Both binary
checks ran only on the App Store lane and the Intel build; `notarize.sh` — the
path that produces the DMG people download — called neither. There was nothing
to fail, so this surfaced by reading the call sites, not by a red run. Both now
run there, **before** `codesign`: a signed build with a secret is a signed
secret. A check holds every release path to calling both.

**How it is proved.** `test/secrets.test.mjs` lifts the `sw` function straight
out of `build.sh` and runs it under `bash` with `DIST=1` against a planted
`.env`. Two cases, and the second is the one that matters: a made-up name
(`PARTNER_HANDSHAKE`) that appears in no list must come back empty **because
nobody named it**, while `DEFAULT_TIER` must survive — otherwise «nothing
leaked» would be achieved by shipping nothing. Behaviour, not a text scan: a
scan passes just as happily on a filter placed after the value is returned.

Mutation-checked in all three directions: remove the default-deny branch, narrow
it back to `*_API_KEY`, or empty the allowlist so even public settings vanish —
each one fails the suite. One earlier attempt at the third mutation edited a
line that left `DEFAULT_TIER` allowed and reported a false «guard is weak».

### 5.3 Install in one command — code done 2026-08-18, one owner action left

Shipped DMGs are signed and notarised, and installed by hand. For a developer,
distribution means `brew`. Landing in the main `homebrew-cask` runs into
notability: their rules name no numeric threshold, the criterion is stated in
words[^cask], and with zero stars there is nothing to argue. An own tap sets no
such condition:

```
brew install --cask theasder/orakul/orakul
```

**Done:** `packaging/homebrew/orakul.rb.template` plus `scripts/refresh-cask.sh`,
which builds the cask from the images that were actually produced — version read
from `Info.plist`, minimum macOS from `config/app.json` (translated to Homebrew's
codename), and both `sha256` sums computed from the files themselves. It refuses
to emit anything if either image is missing: a cask for one architecture means
the other half of your users find out after installing. `test/cask.test.mjs`
runs the script against stand-in images and checks all of it, including that the
app name in the cask matches the one `dmg.sh` actually ships — the two differ in
`build/`, and installing under the wrong name means macOS treats it as a
different application, so microphone and screen-recording permissions do not
carry over.

**Left, and it is not code:** create `theasder/homebrew-orakul` and push the
generated file. Homebrew resolves a tap to a repository named
`homebrew-<tap>`, so it cannot live beside the sources.

**Check before believing it works:** install from the tap on a clean machine and
run `spctl -a -vv`; the answer must stay what README promises,
`accepted, source=Notarized Developer ID`.

### 5.4 A door for the contributor

The project metric is stars and installs, and the first contributor comes for a
clear task, not for code.

- **Turn Discussions on.** An issue means «broke». The first question is usually
  another one: «does Kaiten work for you on an own domain». Today such a
  question has nowhere to live but issues, where it looks like breakage. Still
  open: it is a repository setting, not a file.
- **Labels — checked 2026-08-17, they are real.** `первая правка` and
  `нужен доступ` exist as repository labels (`gh label list`), not as one-off
  strings on three issues.

  One label is **not** real, and it is declared: `oshibka.yml` carries
  `labels: ["ошибка"]`, and no such label exists — the repo has `bug`. GitHub
  drops an unknown label silently, so every bug report arrives unlabelled and
  the form looks like it worked. Fix is one command,
  `gh label create "ошибка" --description "Что-то работает не так, как написано"`,
  or point the form at `bug`. Until then the connector form below declares no
  label at all, and a check keeps it that way.
- **A «new connector» form — shipped 2026-08-17.**
  `.github/ISSUE_TEMPLATE/konnektor.yml` asks the four things §4 gates on —
  vendor docs link, method and host, search parameter, response shape — and all
  four are `required`. The same gate, presented before code gets written rather
  than in a pull-request rejection.

  It also asks for the negative: a service whose docs have no search method is a
  result worth recording, which is how Яндекс Вики and Teamly got closed once
  instead of being re-researched. `test/opensource.test.mjs` pins the four
  required field ids, the dead-end wording, and the absent label.

### 5.5 README: a «what next» line

README has «Чего ещё нет» — that is state. The work order is absent, so a person
willing to help cannot see what their patch joins. One line with a link to this
file.

---

## 6. Horizon 1 — months: stop cutting the audience off

### 6.1 Core and command line outside macOS

The cheapest way to drop the platform cut is not the app but **the core plus the
command line**: search across own calls, the glossary, the connectors and the
external transcriber (`ExternalTranscriber`) depend on nothing platform-bound.
`PortabilityTests` already guards it: the core gets one system module,
`Foundation`.

Exactly three things block it, all visible in the manifest:

| Blocker | Where | Fix |
|---|---|---|
| `import AVFoundation` | `mvp/Sources/orakul`, command line | put under `#if canImport(AVFoundation)`; other systems keep the path through `ExternalTranscriber` |
| `import SwiftUI` | `mvp/Sources/OrakulApp`, window | declare target and product conditionally, so a Linux build does not fall apart on the window |
| `platforms: [.macOS(.v14)]` | `mvp/Package.swift` | SwiftPM ignores the field on Linux, but verify by a run, not by reasoning |

**Done 2026-08-17, and it found what the import check could not.** The three
blockers above are fixed and a `linux-core` job builds `OrakulCore` and the
command line on `ubuntu-latest` in `swift:6.0`. Measured, not reasoned: the
first Linux build failed outright.

- **`URLRequest`, `URLSession`, `HTTPURLResponse` are not in `Foundation`
  outside Apple.** swift-corelibs-foundation keeps them in `FoundationNetworking`,
  so six core files — every connector — failed to compile. `PortabilityTests`
  read imports and answered «portable» the whole time, which is the exact
  difference between a check on intention and a build.
- `FoundationNetworking` is therefore now in `PortabilityTests.allowed`, with
  the reason next to it. The guard still refuses AppKit, SwiftUI,
  ScreenCaptureKit and the rest — the list grew by one module that exists on
  Linux and Windows, not by a door.
- Microphone capture sits under `#if canImport(AVFoundation)`. Where it is
  absent, `record` **throws with an explanation** instead of returning an empty
  buffer: an empty buffer would have been written out as a WAV of silence, and
  «recorded» with nothing recorded is the defect class of plan §4.

**The suite runs there too, and it took three fixes.** The first Linux run gave
9 issues in three classes. All three are closed, and CI now runs `swift test`
on Linux as well — 411 tests pass, 3 skip with a stated reason.

| Class | What it actually was | Fix |
|---|---|---|
| Windows-1251 | `data(using: .windowsCP1251)` returns nil on corelibs: the encoding is simply absent. A CP1251 transcript — the kind Windows writes — was readable **only on macOS**. Product gap, not test noise | Own table, `CP1251`, used on every platform. `CP1251EquivalenceTests` compares it with Foundation's across all 256 bytes wherever Foundation has one, so a hand-typed table cannot quietly disagree |
| Foundation behaviour | `URL(string: "")` is nil on Darwin and **non-nil** on corelibs, so a task with no link came back carrying a link to nowhere. `replaceItemAt` answers «file doesn't exist» on re-save, so a second `orakul добавить` with the same id failed on Linux | `RussianTrackers.link(_:)` refuses an empty string before building a URL; `SessionStore.save` removes and renames instead of `replaceItemAt`, keeping the write atomic where it matters |
| Permissions | The container runs as root, and `chmod 000` does not stop root — the refusals those tests assert cannot happen there | `PermissionProbe` asks by **doing**: creates a directory, strips its permissions, tries to read it. Where permissions do not bite, the two tests skip with the reason printed. Not `getuid() == 0` — the question is whether permissions stop us, not who we are |

The first class is the one that mattered for the audience this is written for:
Windows writes CP1251, and the whole point of §6.1 is that Windows is where the
users are.

**Then the program itself was run, and that found what no test could
(2026-08-18).** `orakul записать` on Linux printed «Записываю 5 с. Говорите…»
and only afterwards admitted recording does not exist on that system. Every test
was green: the function behaved exactly as designed, while the program invited
someone to speak into a microphone that cannot be there — the defect class of
plan §4, in its purest form. The check now happens before the invitation, and
`scripts/smoke-linux.sh` runs the built binary on every pull request: add a call,
quote it back, refuse an invented question, tell a typo from silence, and refuse
recording without pretending to start it. Removing the guard makes that script
fail with «человека позвали говорить в микрофон, которого нет».

A suite that reads sources cannot see this. Only running what ships can.

**What it cost and what it bought.** Nine files in the core and the test target,
one new codec, one new probe. In exchange «the core is portable» stopped being a
claim about imports and became a job that builds it, and tests it, on every pull
request.

Windows stays open after that: no audio capture, no shell there. But a command
line working on an already-made transcript is a product shippable to today's
majority without waiting for the port. **ASSUMPTION**: the macOS share among
Russian-speaking developers is unmeasured (plan §7.1); the direction of the
error is clear, the size is not.

### 6.2 Declarative connectors

The tracker and messenger market here is fragmented — plan §2 concluded that,
and the same fact means connectors will always be short. Today each one is a
Swift file, so only somebody building a macOS project can add one. A person
holding an **account in the needed service** but no Mac finds the door shut —
and that person is exactly who can show the real server answer.

**First slice landed 2026-08-18.** `ConnectorManifest` (the description),
`ManifestConnector` (one engine), and three manifests under
`mvp/Sources/OrakulCore/Resources/connectors/` — `gitea`, `gitlab`, `redmine`.
The engine carries the rules the five hand-written connectors established
(plan §2.2): an 8-second deadline, distinguishable errors, «read soft, write
strict», and 2xx-with-an-unknown-shape treated as a refusal rather than an
empty result.

**The gate is executable, not advisory.** A manifest without a `docs` link, or
without a parameter that substitutes `{query}`, fails to load at all — the same
two questions the «new connector» form asks, now enforced by code. The second
one is §7.2 made concrete: listing is not search.

**What makes it trustworthy is the parity test.** `ManifestConnectorTests`
compares the manifest path against `SelfHostedTrackers` — the whole request
(URL with every query item, every header, the timeout) and the parsed result,
for all three services. Description-by-data is worth having only if it can be
trusted with what already works; a lost header or a dropped parameter turns
«describe your service in JSON» into an invitation to make things worse.

Mutation-checked, all four failing as they must: `Bearer` in place of Gitea's
`token`, a dropped `type=issues`, GitLab's `iid` swapped for `id`, Redmine's
`results` envelope removed.

**Production switched the same day.** `SelfHostedTrackers.search` now builds its
request and parses the reply through the manifest, keeping its own type, its
Russian error text and the host rules; the hand-written branches stay as a
fallback for a missing or rejected manifest — a connector must not stop working
because a resource file went absent.

**And the switch found a hole the parity test could not.** Renaming Gitea's
search parameter from `q` to `qq` in the manifest changed the live request and
**nothing failed**: the suite pinned the path, `type=issues` and the auth
header, but never the name of the search parameter — the one thing the whole
gate exists for. A service answering that request returns its entire task feed
or nothing, and both look like a working search. Now
`SelfHostedTrackersTests` asserts the term arrives in the parameter the vendor
documents (`q`, `search`, `q`), and the same mutation fails.

That check does double duty: it also proves production really reads the
manifest, rather than quietly falling back.

**Extended to RPC, and Outline moved over (2026-08-18).** Search there is a
`POST` with the term in the **body**, and the title sits one level below the row
(`document.title`), so the manifest grew a JSON body template and path-based
field lookup. Done for Outline on purpose: Yonote, the first candidate in §7.3,
has an API of the same shape — if it is confirmed, its connector becomes a JSON
file rather than a Swift one.

**Migration broke the parity test, silently, and mutation caught it.** Once
`search` runs through the manifest, comparing «manifest against production»
compares the manifest with itself — it passes on any corruption. Replacing
Outline's `Bearer` with `token`, or quoting `limit` so a number became a string,
changed nothing. Four connectors were in that state at once.

The reference path is now called directly (`legacySearch`), so parity compares
two genuinely different implementations again, and all six mutations fail:
`Bearer`↔`token` both ways, a quoted `limit`, a shortened title path, `iid`→`id`,
Redmine's envelope removed. The fallback also stops being untested code — an
unexercised fallback is not a fallback.

**Пачка next, and the format is now documented (2026-08-18).** Five services are
described as data — Gitea, GitLab, Redmine, Outline, Пачка — and CONTRIBUTING
carries the schema with a worked example, so «add a connector» is a JSON file
for the common case. Пачка needed one addition: an `author` path, tolerant of an
id arriving as a number (Пачка) or a string (Mattermost). Demanding a field type
in the manifest would be describing JSON rather than describing a service.

**It also cost a distinction, and the existing suite caught that.** The engine
mapped 401 and 403 alike onto «bad token», which erased Пачка's meaning for 403:
the token is genuine, the `search:messages` right was never granted. Those are
different repairs — issue a new token versus grant a permission — and the wrong
advice costs half an hour. The engine now has a separate `forbidden`, and each
caller decides: trackers and the wiki still say «bad token», Пачка says «right
not granted».

**WEEEK is the sixth, and the first Russian tracker (2026-08-18).** It needed
the schema to learn something real: WEEEK answers **200 with `success: false`**
on refusal, so a connector reading only the HTTP code shows a revoked token as
«no tasks found». The manifest now carries `requireTrue`, and — because the
existing suite caught the regression immediately — `errorCode`/`errorMessage`
too: «invalid_token — Token revoked» tells a person to issue a new token, while
«the service answered unclearly» sends them to check the address and the
version. That difference is a wasted evening.

Parity also found a divergence worth keeping rather than copying: the
hand-written path sets `Content-Type: application/json` on a **GET with no
body**. The manifest does not reproduce it, and the test says so out loud, so it
stays a decision instead of becoming the next person's discovery.

**Still code, deliberately, and now for stated reasons:** Mattermost returns
messages as a dictionary keyed by id, Zulip wants Basic auth built from two
halves, Matrix a nested body, Битрикс24 keeps the key in the path, Яндекс Трекер
searches by POST with a body and a second credential. Each is a separate
property of the format; descriptors must cover the frequent case, not every
case.

What it does **not** cancel: the rule «claim nothing that is absent». A
descriptor without a docs link is not accepted, and a live service answer still
gets checked by `LiveConnectorProbe` — same environment variables, no keys in
the repo.

What it does not cover: services needing a protocol rather than a request —
Битрикс24 with the key inside the path, Matrix with a request body, MCP with
client registration. Those stay code, and that is fine: data descriptors must
cover the frequent case, not every case.

### 6.3 A corpus of Russian developer speech

The top product risk is recognition quality on our speech. Plan §10 already
downgraded it from «unknown» to a task: assemble a corpus, then measure T-one
against the model shipping now. Without a corpus, any accuracy claim is somebody
else's benchmark on somebody else's speech (plan §6.1).

The hard part is collection, not measurement — and until 2026-08-18 there was no
answer to «what does a valid contribution look like», so every collector would
have built a different thing and no two measurements could be compared.

**A corpus is now a described format** (`SpeechCorpus`, `corpus.json` beside the
transcripts), and three of its fields exist for honesty rather than parsing:

* `genre` — `talk` or `call`. The measurement prints them **separately** and
  says so out loud when the corpus has no calls. Pooling them promises accuracy
  that a call will not deliver: code-switching (plan §6.2) is weaker in a talk.
* `consent` — `public` for a published talk, `participants` for a call. A call
  recording carries other people's voices; an item that cannot answer this
  question does not load at all, because «forgot to write it» and «there was no
  consent» are indistinguishable from outside.
* `source` — where it came from. Without it a measurement cannot be reproduced,
  which means it cannot be disputed either.

**Checked before use:** `bash scripts/corpus-check.sh <folder>` (or
`orakul корпус <folder>`) parses the manifest, verifies every named file
exists, refuses duplicate ids, and prints the per-genre counts. A missing file
does not fail a measurement — it silently shrinks the corpus, and the average is
then computed over the remainder and looks convincing.

**The measurement itself now computes two different numbers.** Where a
human-marked reference exists, it is WER — a real recognition error, printed per
engine, before and after the glossary. Where it does not, it stays engine
disagreement, which proves an error when engines differ and proves nothing when
they agree. Run it with `CRUXWING_RU_CORPUS=<folder> swift test --filter
probeRussianCorpus`. There is deliberately no threshold: this is a measurement,
not a gate.

**Still missing, and it is not code: the recordings.** Public Russian technical
talks are the first approximation — with the caveat above that a talk is not a
call. Calls need participant consent, and the format makes recording that
consent a condition of entry rather than a promise.

### 6.4 Russian strings to the end

Measured 2026-08-18: of 441 string literals in `Views/` and `Onboarding/`, 23
carry no Cyrillic letter — down from 44 on 2026-08-17. That is an **upper bound,
not a work list**: what is left is names (`GitHub`, `orakul`), bare
interpolations (`"\($0)"`, `"+\(apps.count)"`, `"\(field.title) — \(service.title)"`),
quote wrappers (`"“\(evidence)”"`) and an example placeholder
(`https://mcp.example.com/mcp`). No English sentence remains on those two
surfaces.

The count went 22 → 23 on 2026-08-18, and the guard caught it: the Plane
settings row labels its fields `"\(field.title) — \(service.title)"`, which
reads as Russian on screen and carries no Cyrillic letter in source. The bound
counts a class, not a defect — and a growth that needs an explanation is exactly
what it is for.

Eighteen strings were translated across nine views — the ones a person actually
reads: `Refining…`, `Detach`, `Settings (⌘,)`, `Remove all N meetings`,
`N item(s) will be created`, `N fact(s) to review`, `N of N left`, and the
accessibility labels beside them, which are the half that usually stays English
because nobody sees it.

Command to reproduce:

```bash
cd app/Sources/MeetGPT && grep -rhoE '(Text|Label|Button|Toggle|\.help|\.navigationTitle|Section)\(\s*"[^"]{4,}"' Views Onboarding \
  | grep -oE '"[^"]+"' | sort -u | grep -vc "[а-яА-ЯёЁ]"
```

CONTRIBUTING already calls this a ready newcomer task. The missing pieces: the
number inside the repo, and a check that stops it growing.

---

## 7. Integrations: queue and open questions

### 7.1 Admission rule

Four questions to vendor docs — method, host, search parameter, response shape —
plus a link in the comment and a `LiveConnectorProbe` run against the live
service. Since 2026-08-18 the third question takes a second answer: **«none, and
here is the list method instead»**, admitted under the bounded terms in §7.2. No
service below is scheduled: each carries what exactly is unknown and what
unblocks it.

### 7.2 Listing is not search — decided 2026-08-18

The rule was: no text search parameter, no connector. It closed Pyrus and Яндекс
Вики correctly — they have no cross-cutting listing either — and closed Plane,
GitFlic and GitVerse for a different reason: their task list is documented, only
the search is missing.

**Decision: a listing is admitted, on three terms, and all three are enforced by
code rather than promised in a comment.**

1. **A declared bound.** `scan.pages` × `scan.perPage` rows per question, no
   more, and the engine caps `pages` at `ManifestConnector.scanPageLimit` = 10.
   The manifest author is the party who wants the bound raised — «what if it
   turns up» — and the cost lands on somebody else's service: Plane allows sixty
   requests per minute per client.
2. **A declared filter.** `scan.match` names the fields the word is matched
   against on our side. An empty list refuses to load — a listing without a
   filter is a list, not a search.
3. **Coverage travels with the answer.** `ManifestConnector.run` returns
   `Coverage`, and it separates three answers that «nothing found» flattens into
   one: the service searched and found nothing (`.searched`); the list ended
   before the bound, so we read all of it (`.wholeList`); the bound cut it off
   (`.latest(scanned:total:)`) — «not found among the latest 500 of 40 000».

The third term is the point. The failure this rule exists to prevent already
happened once as «ten tasks out of forty-seven» (plan §4): a part presented as
the whole. On a small team's tracker — three hundred tasks, not forty thousand —
`.wholeList` is a complete answer and says so, which is why a flat «no» was
costing real coverage.

**Second service under it, shipped 2026-08-18: GitFlic.** Everything was read
that day and none of it assumed: host `api.gitflic.ru` (self-hosted installs
answer on `host:8080/rest-api`), header `Authorization: token <access token>` —
**not** `Bearer`, which GitFlic refuses indistinguishably from a bad token —
list `GET /project/{ownerAlias}/{projectAlias}/issue`, paging `page` (**counted
from zero**) and `size` (default 10, maximum undocumented), response
`_embedded.issueModelList[]` with `title`, `description`, `localId`,
`status.title` in Russian, and `page.totalElements`[^gitflic]. Five pages of
fifty per question: gitflic.ru allows 500 requests an hour, so the bound is one
percent of somebody's hourly quota, and a test keeps it there.

It also forced one engine change, and the change is narrow on purpose. Spring
omits `_embedded` entirely when a list is empty, so a project with no tasks
answered «сервис ответил непонятным образом» — sending a person to fix a working
server. A manifest can now name an `emptyMarker`: a path that must be present
for a missing container to count as an empty list. GitFlic's is
`page.totalElements`, which arrives even at zero. Garbage without it is still a
refusal, and a test mutates exactly that.

**First manifest written under it: Plane** (`mvp/…/connectors/plane.json`).
Read 2026-08-18: the list method documents `cursor`, `per_page`, `expand`,
`fields`, `order_by`, `external_id`, `external_source` — and no text
search[^plane]. Five pages of a hundred, matched on `name` and `description`,
`total_count` carried through to the person. Pinned by `ScanConnectorTests`,
including a parse of the vendor's own sample response rather than one written to
fit our parser.

**Reachable since 2026-08-18.** A manifest becomes a working connector only
through a `Service` case — that is what routes a person's question to it — and
Plane now has one, in `SelfHostedTrackers`. Two things had to exist first, and
both are general rather than Plane-specific:

* **Somewhere to keep the fields.** The settings surface held a host and a token
  and nothing else. Now a service can declare fields (`parameters` in the
  manifest), the settings row renders one input per field with the vendor's own
  example, and each is kept in the Keychain beside the token — `selfhosted.plane.field.workspace`.
  «Отключить» clears them too: a project id left behind would attach itself to
  the next token, possibly somebody else's.
* **The coverage reaching the answer.** `SelfHostedTrackers.run` returns the note
  next to the items, and `ConnectorQuery` prints it — including under «ничего не
  нашлось», which is the case that lies without it. From the command line the
  fields travel as `ORAKUL_FIELD_workspace=…`, and the names come from the
  manifest rather than a second list in the CLI.

«Подключено» in settings is now decided by the same code as the connector's own
`isConfigured`, not by a second list of conditions in the view — otherwise the
row shows a tick, saving succeeds, and every question answers «трекер не
подключён».

Manifests written but not yet routed to anybody: none. A check keeps that list
equal to what the code says — a manifest is reachable exactly when its `id`
matches a `Service` case, and either half of the pair drifting is the error that
made this paragraph wrong the first time it was written.

**Not shipped, and why:** GitFlic and GitVerse need their response shape read
from the vendor's own docs first. GitFlic's is recorded as
`_embedded.issueModelList` but its paging fields are not; GitVerse's issue
response shape is nowhere in what was read. Both are now blocked on a fact, not
on a rule — which is a different queue.

A side effect worth naming: the manifest gained `parameters`, the fields a person
fills in themselves. Plane needs a workspace and a project inside the path, and
until now such a service could not be described by data at all. An undeclared
`{placeholder}` refuses to load: it would otherwise travel into the URL
literally, and the service's 404 reads as breakage rather than as an unfilled
setting.

### 7.3 Russia: a queue with questions

| Service | Known | Unknown, and how to learn it |
|---|---|---|
| **Yonote**, knowledge base | Checked 2026-08-18 and **still blocked**. The vendor's own developer pages return navigation without method reference (`/developers`, `/developers?v=2`, `docs.yonote.ru`). Third-party MCP clients agree on base `app.yonote.ru/api` and token auth[^yonote] | Whether a **search** method exists. One community client exposes only `documents_list` / `documents_info` — listing, which §7.2 does not accept as search. Unblocked by public method documentation, or by an account where the call can be made and its answer seen. Until then this is not «nearly written»: that phrasing was an assumption, and checking removed it |
| **GitVerse**, code | **Closed 2026-08-18, see §7.5** — the list method exists and returns the wrong things |
| **GitFlic**, code | **Connected 2026-08-18** under §7.2 — see there for the whole shape[^gitflic] | Nothing blocking. Open: the maximum `size` is undocumented, so 50 is a guess a live install would confirm or correct |
| **Compass**, messenger with an on-premise install | A bot API exists | Whether message search exists and whether the bot sees other people's conversation. The Telegram path ended exactly here (plan §8.1) — question first, code after |
| **Аспро.Cloud** | No method reference found from outside (plan §2.0.3) | Task list method, search parameter, response shape. Unblocked by somebody's account — issue [#2](https://github.com/theasder/orakul/issues/2) |
| **Битрикс24** | Connected **from the docs**, not against a live portal (plan §2.0.1) | Whether `TITLE` pattern search works. One command, a portal needed — issue [#1](https://github.com/theasder/orakul/issues/1) |

### 7.4 The West, and what teams run on their own servers

| Service | Known | To decide or learn |
|---|---|---|
| **Slack** | **Connected 2026-08-18 — see the decision below**[^slack] | Open: the method is marked legacy and the vendor points at `assistant.search.context`. Moving there waits until it is clear what scopes it demands |
| **Plane**, open, self-hosted | **Connected 2026-08-18** under §7.2: `GET /api/v1/workspaces/{workspace_slug}/projects/{project_id}/work-items/`, header `X-API-Key`, response `{results, total_count, next_page_results, …}`, items carrying `name`, `sequence_id`, `state.name`[^plane] | Nothing blocking. Open: whether a live workspace confirms the cursor format `perPage:page:is_prev` — the connector is built from the docs, not from a live install |
| **Jira and Confluence on an own server** | Cloud Atlassian connects via MCP; Data Center takes another path | Whether a portable search method with a personal token exists. The same case as GitLab and Redmine, which already work: ask for the server address |
| **BookStack** | **Connected 2026-08-18.** `GET /api/search?query=…&count=…` (count max 100), header `Authorization: Token <id>:<secret>` — the two halves are one string, not a login and a password; response `{data:[{name, type, url, preview_html:{name, content}}], total}`, 180 requests a minute[^bookstack] | Nothing blocking. It searches for itself, so no §7.2 bound is involved |
| **Wiki.js** | **Connected 2026-08-18.** GraphQL only: `POST /graphql`, `Authorization: Bearer`, `pages { search(query:) { results { id title description path locale } totalHits } }`[^wikijs] | Nothing blocking. `search` takes no limit, so the size of the answer is the server's choice |
| **Nextcloud** | **Connected 2026-08-18.** `GET /ocs/v2.php/search/providers/{provider}/search?term=…&limit=…`, headers `OCS-APIRequest: true` and `Accept: application/json`, response `ocs.data.entries[]` with `title`, `subline`, `resourceUrl`[^nextcloud] | Nothing blocking. The person picks the provider: `talk-message` searches the text of Talk messages, `files` only file names |
| **Local notes: Obsidian and any `.md` directory** | **Connected 2026-08-18**, now in the app too: a folder is chosen in Settings and kept as a security-scoped bookmark, and the source joins the fan-out during a call. No API, no token, no host — files read from disk, and unplugging the network changes nothing | Nothing blocking. Large vaults answered by §7.2's bound: 2000 files per question, freshest first, and the coverage travels into the prompt so a partial read cannot be quoted as a whole one |

**Two western trackers connected directly, 2026-08-18: Linear and Trello.**
Both also answer during a call, not only from the command line — the fan-out in
`MCPGrounding` had to learn them, which is a separate wiring from the settings
screen and was missed on the first pass. Both
are cloud services with one address, so unlike the self-hosted row they ask for
no host — a field a person can only get wrong.

* **Linear.** GraphQL only, `POST https://api.linear.app/graphql`,
  `searchIssues(term:, first:)` returning `nodes { identifier title description
  state { name } }`. The personal key travels in `Authorization` **as-is, with
  no `Bearer`** — that prefix belongs to OAuth tokens, and confusing them
  returns a 401 indistinguishable from an expired key[^linear]. `identifier` is
  a string (`ENG-123`), which is why the engine now prints a string key
  verbatim: «#ENG-123» is not something a person can find in their tracker.
* **Trello.** `GET /1/search?query=…`, and three parameters matter.
  `partial=true` — without it Trello matches whole words only, so «тариф» finds
  nothing and the search looks broken. `modelTypes=cards` — otherwise boards and
  members crowd the answer. And the two secrets go in an `Authorization: OAuth
  oauth_consumer_key="…", oauth_token="…"` header rather than the query string,
  where they would land in every proxy log[^trello].

**Not connected, and the reason is a missing fact, not a rule.** Todoist has a
documented filter endpoint (`query` parameter, `results` array), but its
`search:` filter syntax lives in the help centre rather than the API reference
and could not be read from the vendor's own pages — so the one thing that would
make it a search is unverified. Notion's search returns a page's title inside
`properties` under a key that varies per database, which a path-described
manifest cannot address; that is a shape problem, not a documentation one.

**Slack: a personal token, decided 2026-08-18.**

Slack does not let a bot search messages. `search.messages` takes a **user
token** with `search:read`, which grants exactly what that person can read —
their DMs included. That is why §7.4 called this a product decision rather than
a technical one.

**Decision: connect it, on two conditions.**

1. **Private conversations do not reach the answer.** Slack offers no «public
   channels only» filter, so the filtering is ours: matches from private
   channels and group DMs are dropped before anything reaches the prompt. The
   manifest says so in data (`skipWhen`), and a test drops a mixed response
   through the whole path — engine and messenger layer — to prove nothing but
   the public channel survives.
2. **The interface says what the token really grants.** Not in small print: the
   credential hint states that the token is personal, that Slack allows no bot
   here, that it covers everything that person can see including DMs, and that
   orakul discards the private part. A test pins those words, because this is
   the one screen where a person decides whether to hand that over.

What honesty requires naming: condition 1 is about what reaches the model and
the screen, not about what crosses the network. The private messages were
already fetched into memory — the API returns them and there is no way to ask it
not to. Claiming otherwise would be the exact kind of promise this file exists
to prevent.

The western layer also covers eleven MCP servers, and adding there is one
line in the catalog (plan §2.2). The shortage sits elsewhere: sources that work
**without our server and without the developer's account**.

### 7.5 Closed with cause — do not reopen

Pyrus (no text search), Мегаплан (no long-lived key), Яндекс Вики and Teamly (no
search method in public docs), GigaChat (the token endpoint and the root
certificate requirement do not agree), search across the whole Telegram history
(Bot API does not serve it, MTProto demands a personal account), connectors to
the four ВКС platforms (plan §11), SaluteJazz (needs our backend, which will not
exist).

**GitVerse — closed 2026-08-18, and not for the reason expected.** The search
parameter is indeed undocumented, which §7.2 would now forgive. What cannot be
forgiven is what the list returns: the vendor's own reference says of
`GET /repos/{owner}/{repo}/issues` — «Возвращает список задач (issues)
репозитория. **На данный момент содержит только запросы на слияние (Pull
Requests)**»[^gitverse]. Scanning it would search merge requests while answering
about tasks, so «ничего не нашлось» would be wrong on a repository that has the
task open in front of you. A connector whose emptiness cannot be trusted is
worse than none: this product's whole claim is that an answer is either quoted
or refused.

Reopening needs one new fact — that endpoint listing issues. Everything else is
ready: `page`/`per_page` (max 100), `Authorization: Bearer` or `token`, and the
mandatory `Accept: application/vnd.gitverse.object+json;version=1`.

Every «no» is dated and recorded in the plan with a cause. Reopening is allowed,
but only with a new fact — the way WEEEK returned when the vendor published the
method reference.

---

## 8. Horizon 2 — Windows and packaging

The port costs exactly what lies outside the core (plan §7.1): system audio
capture via WASAPI loopback, plus the shell. Recognition is the same model, a
different runtime: ONNX Runtime or whisper.cpp.

The entry condition is not a calendar but two facts: §6.1 closed (core and
command line build outside macOS in CI) and demand named by people rather than
by assumption. The second one is measurable: an issue «Windows needed» with
votes, not our guess about the corporate fleet.

**The deb exists as of 2026-08-18 — and the first one did not work.**
`scripts/package-linux.sh` builds `orakul_<version>_<arch>.deb`, and CI builds
and installs it on every pull request.

The first version installed cleanly and then failed to start: `error while
loading shared libraries: libswiftCore.so`. Every check passed, because every
check ran **inside `swift:6.0`** — the image that ships the Swift runtime by
definition. The artefact was verified in the environment that flatters it, which
is the same mistake as reading a config instead of the built product.

Three layers had to be peeled, each visible only by installing somewhere real:

1. the Swift runtime is not on a user's machine → `-static-stdlib`;
2. `libcurl` and `libstdc++` are system libraries → declared as `Depends:`, so
   the package manager installs them instead of the user decoding an error;
3. building on Ubuntu 24.04 requires `GLIBC_2.38`, absent from Debian 12 and
   Ubuntu 22.04 → the package is built on `swift:6.0-jammy` (glibc 2.35).

Verified by installing on **Debian 12, Ubuntu 22.04 and Ubuntu 24.04** — add a
call, quote it back, refuse an invented question. The same binary also runs on
Fedora 40 (one harmless linker warning), so an rpm is a packaging question
rather than a portability one. At the time of writing it was not built, and
neither Astra Linux nor ALT had anything installed on them — both were settled
later the same day, below.

CI now builds the package in one image and installs it in a **clean debian:12**,
in a job with no Swift container at all. A check of an installation performed
inside the build image is green always and means nothing.

**The rpm followed the same day, and needed its own toolchain.** Reusing the
Ubuntu-built binary produced a package `dnf` refuses: it carries a dependency on
`libcurl.so.4(CURL_OPENSSL_4)`, Ubuntu's versioned symbol, absent on Fedora. The
program itself runs there — rpm's dependency check is stricter than the loader,
and rightly so. So the rpm is built in `swift:6.0-rhel-ubi9` and installed into a
clean `fedora:40`: add a call, quote it back, refuse an invented question,
remove the package.

**One cause bit three times today: a shared `.build`.** The repository is mounted
into the container, so a build in one image reuses object files from another —
which is how the rpm twice came out with Ubuntu's dependencies, and how a jammy
rebuild silently kept a `GLIBC_2.38` requirement. Both packaging scripts now
build in a scratch directory named after the image's own `/etc/os-release`.

**And both scripts refused to invent a version.** Missing `git` inside the
Fedora image made the release number silently `0`; a package numbered after
nothing is worse than a failed build, so they now stop and ask for
`ORAKUL_RELEASE` explicitly.

**Astra Linux and ALT: tested 2026-08-18, and the first answer was «no».**
Both ship container images, so «plausible» could be replaced with a measurement —
and the measurement said the packages did not work there at all:

| System | glibc | Verdict on the first packages |
|---|---|---|
| ALT p10 | 2.32 | rpm refused: needs `GLIBC_2.34`, `GLIBCXX_3.4.29` |
| Astra Linux 1.7 | 2.28 | deb built on Ubuntu 22.04 (glibc 2.35) cannot run |

Building on an older base only moves the line. The fix that removes it is Swift's
**Static Linux SDK**: a musl binary with no glibc dependency whatsoever. The same
file then runs on ALT p10, Astra 1.7, Debian 12 and Fedora 40 — verified by
running it on each, with Astra reached by cross-compiling to x86_64 because its
image is amd64-only.

The package build now uses that SDK when it is installed and keeps the
glibc path as a fallback. A static package declares **no dependencies at all**:
`dpkg -i` installs it with no `apt` and no resolution step, which on an isolated
corporate machine is the difference between working and not.

**The rpm followed the same day.** It now packages the same static binary the
deb does, so it installs on **ALT p10** — the distribution that rejected it an
hour earlier for wanting `GLIBC_2.34` — and on Fedora 40. Verified by installing
on both and running add / quote / refuse.

That change also removed a rule: the rpm used to be built in an RHEL-family
image so its auto-generated dependencies would be right. With nothing to depend
on, the packaging image stopped mattering. Two of the guards I had written the
day before had to go with it — one demanded `Requires: libcurl`, the other
demanded the UBI image — because both pinned the method rather than the
property. The property they were protecting is unchanged and still checked:
the package runs where Swift never was.

| System | Package | Result |
|---|---|---|
| ALT p10 (glibc 2.32) | rpm, static | installs and works |
| Astra Linux 1.7 (glibc 2.28) | static binary, x86_64 | runs |
| Debian 12, Ubuntu 22.04 | deb, static, no `Depends` | installs with plain `dpkg -i` |
| Fedora 40 | rpm, static | installs and works |

The version is **not invented**. It comes from the same pair the macOS build
stamps — `CFBundleShortVersionString` in `app/Support/Info.plist` plus git
height — giving `0.1.0-179`. Two artefacts of one commit must answer «which
version» the same way, and a number typed into the packaging script diverges on
the second edit.

The package description says plainly what is not in it: the command line only,
no microphone recording, that being macOS-only. Someone installing it to record
a call would otherwise find out later and worse.

**What is still not done here.** The packages are built and installed by hand
or by CI; there is no repository to `apt install` from and nothing is signed, so
`dpkg -i` and `rpm -i` are the whole distribution story. Repositories and
signing are separate work, and the reason to name it is that a table saying
«installs and works» invites the reading «available from your package manager»,
which is not true.

This paragraph used to say the opposite of the table three lines above: it
declared the rpm unfinished and both Russian distributions unverified, hours
after they had been installed and checked. It survived because §8 had no checks
at all — every other section's numbers are pinned to code, this one's were
prose. `test/roadmap.test.mjs` now holds the table against the packaging
scripts and refuses exactly this contradiction.

---

## 9. Horizon 3 — a project, not a repository

- **Glossary as a shared resource — first slice 2026-08-18.** The two lists a
  contributor actually extends now live in
  `mvp/Sources/OrakulCore/Resources/lexicon/base.json`, not in Swift: adding a
  term is editing data, exactly as with connectors. A parity test holds the pack
  word-for-word against the tables the product still reads.

  The curation rule became **executable**. «A word enters only if it does not
  collide with ordinary Russian» was a comment plus six words inside a test;
  `LexiconPack.validate()` now refuses on load — an ordinary word (`агент` is a
  страховой агент), a duplicate (two canons make repair depend on traversal
  order), or the wrong alphabet (`АПИ` among acronyms, `prod` among loanwords
  repairs a word in the opposite direction). Each refusal explains itself, and
  the `ordinary` list grows with the attempts it rejects — a recorded refusal
  saves the next person the same evening.

  The two maps followed on 2026-08-18: `variants` (33 pairs — what was said →
  how it is written) and `infrastructure` (91 — a tool's spoken name → one
  search token) are in the pack as well. What stayed in Swift is the part that
  is actually logic: building the index and generating Russian case forms.

  They carry **different curation rules**, and the pack enforces the difference
  rather than describing it. `variants` rewrites the transcript, so an ordinary
  word on its left-hand side is refused exactly as in the lists — «агент» →
  `agent` would turn an insurance agent into jargon. `infrastructure` only
  affects search, so ordinary words are deliberately allowed there: «редис»
  stays a vegetable in the text and is still found by `redis`. Forbidding them
  would throw out the very names the table exists for. Both directions are
  pinned, because the first version of the rule was enforced in one direction
  only and no test noticed.

  **Domain packs per role: the architecture closed 2026-08-18, the content did
  not.** «The loader takes any number of files» was true and insufficient. Each
  pack validated itself, and two failures exist only between packs — each pack
  flawless on its own:

  * the same word repaired differently in two packs. Which one wins would be
    decided by the order files are read, that is by their names — the same
    defect as a duplicate inside one pack, only harder to see;
  * a word one pack repairs while another lists it as ordinary. Those refusal
    lists are accumulated experience («агент» is an insurance agent), and a new
    domain pack must not overturn one silently.

  Both are refused at load, not by a separate call somebody has to remember —
  and that distinction was itself found by mutation: removing the check from the
  loader passed, because the only test called validation by hand. Tool names
  stay exempt on purpose: they act on search only, so «редис» may be a vegetable
  in one pack and a search token in another.

  The rules exist **before** the first domain pack deliberately: a rule written
  after it was broken gets argued about rather than followed.

  What is left is content, and it is not something to invent. A pack is a claim
  about what a particular role actually says on calls; the way to earn it is the
  corpus of §6.3, not a list assembled from memory. CONTRIBUTING states the
  format and both rules.
- **A kit for an outside connector — the missing half landed 2026-08-18.**
  Checking a connector needs an account in the service; accepting the patch
  needs the maintainer, who has none. Between them there must be a document:
  what went to the server, what came back, whether the shape was recognised.
  `ConnectorProbeReport` renders exactly that, and CONTRIBUTING says how to
  attach it.

  The property that matters is that the token does **not** appear in it — the
  text goes into a public pull request, and a leak there would mean the checking
  tool opened the very hole the «secrets only in the Keychain» rule exists to
  close. It is scrubbed by header name, by value, by halves of a compound key
  (`почта:ключ`, `id/код`), and by percent-encoding, because a key inside a URL
  arrives encoded — unreadable to a human, decodable by anyone.

  That last case was found by mutation: the leak test passed while the guard was
  removed, because a Cyrillic token in a URL had been re-encoded and the test
  was searching for a string that was no longer there. The test proved nothing
  and looked green. Tokens in the fixtures are ASCII now, like real ones, and a
  separate case covers the encoded form.
- **A reproducible release — extended to Linux 2026-08-18.** The DMG has
  carried a stamp and `audit-dmg.sh` from the start; the packages I shipped this
  week carried nothing, so a `.deb` could not say what it was built from. Both
  now embed `build-info` — version, commit, source hash, the paths that hash
  covers, and the system it was built on — and `scripts/audit-package.sh` reads
  it back out of the file and recomputes.

  Two details are load-bearing. The hash covers **what actually ships**: the
  core and the command line, not the app sources, because stamping a package
  with the hash of code it does not contain promises traceability that is not
  there. And both sides compute with **one implementation** (`source-hash.sh`),
  because the DMG once raised a false alarm when the two pipelines wrote paths
  differently and disagreed on identical code. Verified in both directions: an
  untouched package matches, and one line added to a core file makes the audit
  report a mismatch.

  CI runs the audit on every pull request. Publishing the report alongside a
  release is what remains, and that needs a release to publish.
- **One maintainer — said out loud in README, 2026-08-18.** An issue may wait
  days, and during a holiday may not be answered at all. The obligation from
  CODE_OF_CONDUCT — explain every closure — holds regardless; what cannot be
  promised is speed, so it is not promised.

---

## 10. What will not happen, and why

| Not happening | Cause |
|---|---|
| Search across other people's Telegram chats | Foreign content, the answer holds no decision status, and such search engines already exist (plan §8) |
| A personal MTProto session | Asking for a personal account is a changed promise, not a detail (plan §8.1) |
| A SaluteJazz connector | Their API needs a token that belongs on a backend; no backend exists and none will (plan §11) |
| Tariffs, limits, paid features | Owner decision, pinned by `NoTariffsTests` (plan §5) |
| A recognition model in the bundle | Gigabytes of weights at install stop being «run in five minutes» |
| Telemetry and «quality improvement on your data» | Data does not leave the machine, and that is verified at build time |
| Writing to a tracker without a human | The product sends nothing itself: it drafts, the person sends |

---

## 10.1 If the vendor is not neutral — audit 2026-08-18

Every connector here reads somebody else's API, and several of those somebodies
sell a competing product. They cannot touch this repository; they can change
their own service, legally and without notice. So the question is not «will they
block us» — a block is visible — but **which hostile change leaves orakul
answering cheerfully while being wrong**.

Played as the attacker against the real code. What landed:

| Move | What it did before | Now |
|---|---|---|
| Rename a response field (`title` → `heading`) | Rows arrive, shape is recognised, every row yields nothing, and the answer is «ничего не нашлось» — forever, for every question | Rows present but **none** readable is a format change, not an empty result: refused loudly. One unreadable row among good ones is still skipped |
| Drop the «there is more» field | The scan fell back to «short page means the end», so a full page read as `.wholeList` — part presented as whole, exactly what §7.2 forbids | A declared marker that is absent means unknown, so coverage stays `.latest` and the answer says «last N», never «all» |
| Throttle instead of blocking (429) | «Трекер ответил ошибкой 429» — the word «ошибка» sends a person to reissue a token that is fine | Its own case, with `Retry-After` when the service sends it, and the text says the token is not the problem |

What already held, and why it is worth naming: HTTP 200 with an error in the
body (`requireTrue`), a refusal in a GraphQL `errors` array, an HTML login page
instead of JSON, a byte-per-second response (the 8-second deadline), and a
narrowed scope arriving as 403 with its own message rather than «bad token».

What this audit does **not** claim. It covers connectors described by manifests
and the shared engine. A vendor can still do things nothing here detects —
returning plausible but wrong rows, silently filtering results by who is asking,
or shipping a subtly different corpus to us than to a browser. Those are not
caught by parsing rules; they are caught by somebody comparing the answer with
what they know, which is why «quote the line, name the source» is the product's
first rule rather than a feature.

---

## 11. Risks

| Risk | How we learn it fired | What we do |
|---|---|---|
| Russian technical speech recognised worse than needed | Measurement on an own corpus (§6.3); until then we hold other people's numbers on other people's speech | The glossary already repairs the transcript afterwards: engine agreement 71% → 89%. Then model choice by an own measurement |
| macOS-only cuts off most of the audience | Demand in issues and «no Windows» refusals | §6.1, then §8 |
| A connector built from docs, never against a live service | Битрикс24 sits in that state already, and it is stated plainly | A live check by other hands (issue #1); until then a caveat in README, not silence |
| A confident sentence about something that never happened | Eight cases in one night (plan §4): the class is not closed, it repeats on new paths | Rule: for every sentence claiming an outcome, find the case where there was no outcome. Recheck whenever a new path reaches that sentence |
| One maintainer | The issue queue grows, answers slower than a day | Say it out loud in README; data-described connectors (§6.2) cut the share of tasks needing the maintainer |
| A secret ships in a public build | §5.2; it shipped once already | Closed 2026-08-18 by inversion: a dist build emits only explicitly named settings and blanks everything else, so a credential with an unrecognisable name no longer depends on a hand list. Proved by running `sw` itself against a planted `.env`. The path gap that remained is closed too, 2026-08-18: `app/assert-no-env-values.sh` reads the **built file** and looks for the literal values from `.env`, so a value baked by any future route — a new source file, a resource, a plist — is caught by ground truth rather than by naming. Printing a value is refused: the report names variables only |

---

## 12. Metrics

The metric is unchanged and honest: **stars and installs** (plan §5). In a repo
with nothing to sell, README is the whole marketing.

| What we count | With what |
|---|---|
| Stars and forks | `gh repo view theasder/orakul --json stargazerCount,forkCount` |
| Installs | the sum of `assets[].download_count` in `gh api repos/theasder/orakul/releases` |
| Connectors | from code, not from the page: `RussianTrackers.Service` and neighbouring types — the same way the census check does it |
| Time to the first answer on an issue | by hand while they are countable; otherwise it is a metric for its own sake |

What we do **not** count: page traffic through third-party counters. Putting
analytics on the site of a product promising the data stays put is exactly the
contradiction we hold against others.

---

## 13. How this file avoids going stale

`test/roadmap.test.mjs` holds **18 checks** against this file. They fall into
four kinds, and the kinds matter more than the list:

**Structure** — sections numbered and in order; every `plan §N` reference
resolves to a section that exists; every footnote is defined, used, and carries
an address and a read date; README points here.

**Counts measured, not remembered** — own connectors, page-and-doc tests, the
ceiling on English strings in the interface, the numbers §5.2 quotes about
`build.sh`. Each is recomputed from code on every run, so «measured on the 17th»
cannot quietly become a memory.

**Claims against code** — a service called connected exists in the code and the
reverse; a manifest is unreachable exactly when this file says it is; the scan
bound here equals the engine's; §8's package promises hold against the packaging
scripts; a queue row shows what it depends on.

**Contradictions inside one section** — a system the §8 table calls working
cannot be called untested three lines below, and something closed with cause in
the plan is not promised here as work. This kind was added after both had
happened.

The check does not make the plan right. It makes it **checkable** — and a wrong
but checkable plan gets fixed by one edit, while a wrong and uncheckable one
lives for years and spends other people's time.

The number above is itself checked. This section listed five checks while the
file ran seventeen — the section whose job is preventing staleness had gone stale
first, because nothing counted it. Adding a check now fails the suite until this
paragraph is updated, which is the cheapest possible way to keep a document
honest about itself.

[^cask]: Homebrew, Acceptable Casks: notability criteria stated without numeric thresholds, read 2026-08-17: https://docs.brew.sh/Acceptable-Casks
[^slack]: Slack, `search.messages`: **user token only** with the `search:read` scope — no bot token is accepted; arguments `query` (required), `count` (max 100, default 20), `page`, `cursor`, `sort`, `sort_dir`; response `{ok, query, messages: {total, matches: [{type, channel: {id, name, is_private, is_mpim}, text, username, ts, permalink}], pagination}}`; refusals arrive with HTTP 200 and `{"ok": false, "error": …}`; rate limit tier 2; marked legacy, with `assistant.search.context` named as the replacement. read 2026-08-18: https://docs.slack.dev/reference/methods/search.messages
[^linear]: Linear: single GraphQL endpoint `POST https://api.linear.app/graphql`; personal API keys go in `Authorization` with **no** `Bearer` prefix (OAuth tokens use `Bearer`); `searchIssues(term: String!, first: Int)` returns `nodes` of `{id, identifier, title, description, url, state {name}}`; refusals arrive with HTTP 200 and an `errors` array. read 2026-08-18: https://linear.app/developers/graphql

[^trello]: Trello: `GET https://api.trello.com/1/search`, `query` required (min 1 char), `modelTypes` (default all), `cards_limit` (max 1000, default 10), `partial` (default **false** — whole-word matching), `card_fields`; authorisation as query parameters or as `Authorization: OAuth oauth_consumer_key="{key}", oauth_token="{token}"`; response `{cards: [{id, name, desc, idShort, idBoard, closed}], boards, members}`. read 2026-08-18: https://developer.atlassian.com/cloud/trello/rest/api-group-search/ and https://developer.atlassian.com/cloud/trello/guides/rest-api/authorization/

[^wikijs]: Wiki.js: GraphQL at `POST /graphql`, token from Administration → API Access passed as `Authorization: Bearer`; `PageQuery.search(query: String!, path: String, locale: String): PageSearchResponse!` returning `results: [PageSearchResult]` of `{id: String!, title: String!, description: String!, path: String!, locale: String!}`, plus `suggestions` and `totalHits`; refusals arrive with HTTP 200 and an `errors` array. read 2026-08-18 from the vendor's docs — https://docs.requarks.io/dev/api — and their schema, `server/graph/schemas/page.graphql`

[^nextcloud]: Nextcloud unified search: `GET /ocs/v2.php/search/providers/{providerId}/search?term=…&limit=…`, provider list at `GET /ocs/v2.php/search/providers`; headers `OCS-APIRequest: true` and `Accept: application/json`; authentication is Basic with a username and an app password (Bearer only with OIDC); response `{ocs: {meta, data: {name, isPaginated, entries: [{thumbnailUrl, title, subline, resourceUrl, icon, rounded, attributes}], cursor}}}`. read 2026-08-18 from the developer manual — https://docs.nextcloud.com/server/stable/developer_manual/digging_deeper/search.html — and the response types in `core/ResponseDefinitions.php`

[^bookstack]: BookStack: `GET /api/search`, parameters `query` (required), `page` (min 1), `count` (min 1, **max 100**, default 20); auth `Authorization: Token <token_id>:<token_secret>`; 180 requests a minute per user by default; response `{data: [{id, name, slug, type, url, preview_html: {name, content}, tags, book, chapter}], total}` with the match wrapped in `<strong>` inside `preview_html`. read 2026-08-18 from the vendor's docs — https://demo.bookstackapp.com/api/docs — and confirmed against their own source and tests: `app/Search/SearchApiController.php` and `tests/Api/SearchApiTest.php`

[^plane]: Plane, list work items: `GET /api/v1/workspaces/{workspace_slug}/projects/{project_id}/work-items/`, header `X-API-Key`, query `cursor` / `per_page` (default 20, max 100) / `expand` / `fields` / `order_by` / `external_id` / `external_source` — **no text search parameter**; response `total_count`, `next_page_results`, `results[]` with `name`, `description`, `sequence_id`, `state.name`; re-read 2026-08-18: https://developers.plane.so/api-reference/issue/list-issues
[^gitverse]: GitVerse, public API: base `api.gitverse.ru`, `Authorization: Bearer` or `token`, mandatory header `Accept: application/vnd.gitverse.object+json;version=1`, paging `page` / `per_page` (max 100); the issue **list** is documented as returning pull requests only — «На данный момент содержит только запросы на слияние (Pull Requests)», entry 13 in the repositories section, re-read 2026-08-18: https://gitverse.ru/docs/public-api/repositories/ and https://gitverse.ru/docs/developers/public-api/
[^gitflic]: GitFlic: base `api.gitflic.ru` (self-hosted `host:8080/rest-api`), auth `Authorization: token <access token>`, 500 requests an hour — https://docs.gitflic.ru/latest/api/intro/; issue list `GET /project/{ownerAlias}/{projectAlias}/issue` with `_embedded.issueModelList[]` carrying `title`, `description`, `localId`, `status.title` — https://docs.gitflic.ru/api/issue/; paging `page` from zero and `size` (default 10), response `page` object with `size`, `totalElements`, `totalPages`, `number` — https://docs.gitflic.ru/api/pagination/. All three read 2026-08-18
[^yonote]: Yonote, developer page (API v1 and v2 preview), read 2026-08-17: https://yonote.ru/developers
