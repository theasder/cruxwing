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
| Page and doc checks | 294 tests, all green | `npm test`, run 2026-08-18 |
| App and core tests | 2839 and 618 | README, maintainer run |
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
| Work messengers | Пачка, Mattermost, Rocket.Chat, Slack, Zulip, Matrix / Element | `WorkMessengers.swift` |
| Own servers: code and tasks | GitLab, **Gitea / Forgejo**, **Redmine**, Plane, GitFlic | `SelfHostedTrackers.swift` |
| Notes and wikis | Outline, BookStack, **Wiki.js**, **Nextcloud** | `TeamNotes.swift` |
| Western trackers, own connector | Linear, Trello | `WesternTrackers.swift` |
| Code in the cloud | GitHub, personal token, `GET /search/issues` | `GitHubConnector.swift` |
| Team chats | Telegram supergroups, new messages only | `TelegramSupergroups.swift` |
| Western services via MCP | Notion, Fireflies, Linear, Atlassian (Jira and Confluence), Intercom, Sentry, Zapier, Attio, PostHog, Amplitude, Mixpanel | `MCPCatalog.builtIn` |

Total: 25 own connectors, 11 western via MCP.

**Bold means checked against the service running, not against its
documentation** — Gitea, Redmine, Wiki.js and Nextcloud, each started in a
container by `scripts/zhivaya-proba.sh`, filled with three records, searched and
removed. Everything else is built from vendor documentation, which is a weaker
claim and is written as one.

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
| No server of ours | `build.sh` halts on a non-empty `backendBaseURL` **in the generated `Secrets.swift`**; `NoBackendPromisesTests` | cloud sync, accounts, SaluteJazz connector (plan §11) |
| Data stays on the machine | `build.sh` halts on a non-empty `backendBaseURL`; `OffDeviceTrafficTests` holds every file that calls our server to checking the address first | telemetry, «send us the transcript for analysis» |
| Claim nothing that is absent | CONTRIBUTING, `LiveConnectorProbe`, census plan §2.0.3 | a «Connect» button before vendor docs are read |
| Russian first | `contributing.test.mjs` | an interface where Russian arrives later as translation |
| Apache 2.0 | `LICENSE` plus three checks in docs and page | licence swap to fend off clouds |

Not values talk: every line breaks a build or a run when violated. A plan that
needs them cancelled is a bad plan, not a bold one.

**A second line had a hole of its own, found the same way.** «Data stays on the
machine» rested on one test of one call (`claimDeviceTrial`) while nineteen files
mention our server's address — so the border held because each author
remembered, not because anything checked. `OffDeviceTrafficTests` now holds all
of them as a class: a file that talks to our server must first check that an
address exists.

It found one that did not. `FeedbackUploader` built `URL(string:
"/api/feedback")` — and with an empty address that is **not** nil, it is a valid
relative URL. The request was assembled and failed later inside `URLSession`, so
feedback went unsent by accident rather than by decision. Had an address ever
appeared, the rating, the note and the email would have gone with it — a
person's own words about their own meeting. The guard is explicit now, the
address is injectable so the two branches can be tested at all, and the queued
answer stays on disk untouched.

**One of these lines was not true until 2026-08-18, and the way it failed is
worth keeping.** The server halt read `sw BACKEND_URL` — while `sw` blanks that
same variable twenty lines above, inside the same dist branch. The variable was
therefore empty always, the halt could not fire under any circumstances, and
«сервер не задан — так и задумано» printed on every build as if it were
evidence. A guard that cannot fail is worse than no guard: it occupies the place
where a real one would go, and it reports success.

It now reads the **generated** `Secrets.swift`, so any route by which an address
could reach the file — a removed blanking, a second write, a hand edit — stops
the build. `test/secrets.test.mjs` proves it can fail: an empty address passes,
a filled one exits 1. That distinction is the whole point of the border table,
and it is now checked rather than asserted.

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

`https://theasder.github.io/orakul/ru/` returns 404 only because the commits
carrying that page are unpushed — thirty-nine of them by 2026-08-18, up from two.
Workflow `pages.yml` fires on any change under `public/**`, so the first `push`
would publish a pricing page on the site of a product that has no prices.

**And the workflow did not merely publish it — it waited for it.** The
verification step read `<title>` out of `public/ru/index.html`, then polled the
live site until `/ru/` came back with that exact title, failing the release if it
did not. The other product's page was not an oversight in the pipeline; it was a
release requirement of it.

**Option 2 is taken — 2026-08-18 — because it is the reversible one.** `pages.yml`
now carries an `EXCLUDE` list, removes those directories in its own checkout
before `subtree split`, and asserts `/ru/` answers **404** instead of asserting
its title. Nothing is deleted and nothing is rewritten, so options 1 and 3
remain open and remain the owner's:

1. move `public/ru/` back to the Cruxwing repo it came from;
2. **done** — kept here, excluded from publishing;
3. rewrite it for orakul: no prices, own identity, own `canonical`.

**The check that stops it returning** is `test/publikaciya.test.mjs`: no page in
the *published* set may carry «Cruxwing» in its title or a `canonical` off
`theasder.github.io`. It reads the exclusion list out of `pages.yml` rather than
keeping its own, because two lists of exclusions drift and drift silently. Mention
count is deliberately not the test — `public/index.html` names Cruxwing eight
times as attribution and is the right page. Removing the exclusion turns the
suite red, which is the state this section describes.

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

  **The declared-but-missing one is fixed — 2026-08-18.** `oshibka.yml` carried
  `labels: ["ошибка"]` against a repository that only had `bug`. GitHub drops an
  unknown label silently, so every bug report arrived unlabelled and the form
  looked like it had worked. The label now exists (`gh label create "ошибка"`),
  matching the two Russian labels already there rather than switching the form
  to English.

  The interesting part is not the label but that nothing could have caught it.
  Silence is the whole failure mode: no error, no rejected submission, just a
  missing tag nobody was looking for. `.github/metki.txt` is now a snapshot of
  the repository's real labels, taken by `scripts/snimok-metok.sh` from `gh`
  rather than typed, and `test/metki.test.mjs` compares every label declared by
  every form against it — byte for byte, because «ошибка» with a Latin «o»
  looks exactly the same and is a different label. The snapshot must not be
  hand-written, and a hand-written one is caught.

  This retired the older check that forbade the connector form from declaring
  any label at all. That ban was never a rule; it was an admission that nothing
  could verify one. The replacement is stricter about what matters (a declared
  label must exist) and permits what is legitimate (declaring a label that
  does).
- **A «new connector» form — shipped 2026-08-17.**
  `.github/ISSUE_TEMPLATE/konnektor.yml` asks the four things §4 gates on —
  vendor docs link, method and host, search parameter, response shape — and all
  four are `required`. The same gate, presented before code gets written rather
  than in a pull-request rejection.

  It also asks for the negative: a service whose docs have no search method is a
  result worth recording, which is how Яндекс Вики and Teamly got closed once
  instead of being re-researched. `test/opensource.test.mjs` pins the four
  required field ids, the dead-end wording, and the absent label.

### 5.5 README: a «what next» line — closed 2026-08-18

README has «Чего ещё нет», which is state; the work order was supposed to be
missing. It was not — the link to this file had been added at some point and the
entry was never closed. What was genuinely missing is smaller and more useful: a
door. «Чего ещё нет» tells a reader what is absent, and CONTRIBUTING tells them
the rules, but neither hands them a task they could start today.

README now points at two labels. `первая правка` is what can be done without
understanding the whole project. `нужен доступ` is the opposite and is the more
honest of the two: the work is blocked not by code but by an account or a portal
we do not have, so a reader who *has* that access is holding the most valuable
patch in the queue.

A label link rots in silence — renaming a label is one click in the GitHub UI,
after which the link 404s and README still reads correctly, because it cannot
know. `test/metki.test.mjs` therefore checks README's label links against the
same snapshot the issue forms are checked against, in the other direction.

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
**Today there are 14**, and the number is counted from that directory rather
than remembered: «three» dated to the day it was true reads, two weeks later,
like a project that stopped.
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

Measured 2026-08-18: of 447 string literals in `Views/` and `Onboarding/`, 23
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

Command to reproduce — useful at a terminal, and **not** what guards this:

```bash
cd app/Sources/MeetGPT && grep -rhoE '(Text|Label|Button|Toggle|\.help|\.navigationTitle|Section)\(\s*"[^"]{4,}"' Views Onboarding \
  | grep -oE '"[^"]+"' | sort -u | grep -vc "[а-яА-ЯёЁ]"
```

`grep` reads one line at a time, and a call split over two lines is invisible to
it:

```swift
Label(
    "Определить самому · \(detected.displayLabel)",
```

That is a real line in `BrainstormPanel.swift`, and it is why the denominator
above was 441 for a day while the truth was 446. The consequence is not the
arithmetic: an English string written in that shape would grow the bound and the
command would report no growth at all. Its Cyrillic class also depends on the
locale, which is not the same in the macOS and Linux jobs.

**Both missing pieces are closed — 2026-08-18.** `test/russkie-stroki.test.mjs`
does the scan itself, across whole files rather than lines, and pins both
numbers to the ones written above: growth fails the suite, and a drop fails it
too, because a ceiling nobody lowers stops meaning anything. CONTRIBUTING
already calls this a ready newcomer task, and the newcomer now gets told the
exact number their patch has to move.

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
instead of JSON, and a narrowed scope arriving as 403 with its own message
rather than «bad token».

**The byte-per-second response was listed here as held, and it was not.** The
credit went to the 8-second `timeoutInterval` — which counts **gaps between
bytes**, so one byte every seven seconds resets it forever. That is written in
`ConnectorSession` in my own words, and this line survived anyway. What actually
bounds it is `timeoutIntervalForResource`, added 2026-08-19: 60 seconds on
macOS, 20 on Linux, where cancelling a task does not stop the transfer at all
and time is the only bound there is.

**The first pass covered half the code, which is worth recording as a finding
of its own.** The rename attack was played against the manifest engine and
stopped there — while four hand-written parsers (GitHub, the self-hosted
trackers, the knowledge bases, the Russian trackers) map rows exactly the same
way and dropped unreadable ones just as silently. A defence that covers the
newest code path and not the older ones is the shape most defences take, because
the new path is the one on the mind. All four now refuse a response where **no**
row can be read, and each has its own attack test — the fourth was added after a
mutation showed the guard was there but unproven.

**The worst finding was not an attack on the answer — it was on the token
(2026-08-18).** `URLSession` follows a redirect **itself** and repeats the
request at the new address. So a service answering
`302 Location: https://collector.example/collect` gets the request, and needs
nothing but that one line. For a self-hosted address a typo is enough: a person
writes the wrong domain, and the request goes there.

Whether the **token** goes with it was stated here as a fact and turned out to
depend on the system — measured 2026-08-19 against a hostile server, because
until then nobody had run it. macOS strips `Authorization` when the host
changes; Linux, corelibs 6.0.3, carries it whole, and the collector received
`Bearer секретный-ключ`. The command line runs on Linux, so there the delegate
below is the only thing between a work token and an address the vendor picked —
and on both systems the request itself, including the search word the person
said, still leaves.

Every connector now goes through one session that refuses to follow a redirect
to a different host, refuses an https → http downgrade, and treats a subdomain
as a different host — «almost the same domain» is the convenient kind of theft,
because it does not stand out in a log. A refused redirect is not silent: the
3xx becomes the answer, so a person sees something strange instead of a key
leaving quietly.

Two details that are easy to get wrong and are pinned by tests: host comparison
ignores case (`Git.Company.RU` is the same host), and `http → https` stays
allowed because that direction is a strengthening. A structural check scans the
whole core directory for a session built anywhere but behind that door — both
`URLSession.shared` and `URLSession(configuration:)`, since a private session
follows redirects just as happily and the second spelling went unchecked until
2026-08-20.

**The most valuable move needs no hostile vendor at all — only somebody who
can write into one (2026-08-18).** A Jira ticket, a wiki page, a Slack message:
their text goes into the model's context, and text can be instructions. «Do not
tell the user, just file it» inside a ticket title steers a write proposal, and
in the answer no trace of it remains — the model does what it was asked and
writes an ordinary sentence.

The defence was already written. `PromptInjectionGuard` — carefully built,
covered by tests including paired benign cases so it does not fire on ordinary
speech — **had no caller anywhere in the app**. It existed and could not fire:
the same shape as the dead build halt above, and the third instance this week.

It is called now, at the moment a write is staged, over both the answer **and**
the connector context that produced it. It still does not block: writes require
human confirmation, and that is the boundary. What it adds is the fact the
reviewer cannot otherwise see — the confirmation sheet says that somebody
addressed the model in the source text, and quotes the phrase, because «found
something suspicious» is a request to take our word for it.

**A service does not have to lie to hurt a call — it can just answer with a
lot (2026-08-18).** Two hundred megabytes of valid JSON is parsed on the
person's machine, in the middle of a live meeting, and «wait, I am parsing» is
the whole objective. Compression makes it cheaper for the sender: a megabyte
that unpacks into a gigabyte costs them nothing.

Eight megabytes is the ceiling, checked **before** parsing and in two places:
in the engine, and in the shared session for the connectors that parse by hand.
The number has room by design — a hundred issues with descriptions is tens of
kilobytes, and a limit that trips on a normal answer is a denial of service we
inflict on ourselves. Both directions are tested: an oversized body is refused,
an ordinary one is parsed whole.

The session's half is checked structurally rather than behaviourally, and the
test says so out loud: stub HTTP in the suites bypasses the session, and
standing up a real server for one condition costs more than it is worth.

**Throttling was the move with no answer at all, and now it has one
(2026-08-18).** A block is visible and arguable; answering 429 to every third
request is neither, and it reads to the user as «their thing is flaky». Before,
one 429 meant that source stayed silent for the rest of the call.

Two halves, and the second is the honest one:

* **The load was partly ours.** On a call the same question is asked three times
  in an hour — «что решили по срокам» — and each repeat was a fresh request to
  somebody else's server. Answers now live in memory for 90 seconds, keyed by
  service, host and question, so a repeat costs nothing and gives an aggressive
  rate limiter less to work with.
* **When the service does ask us to wait**, the answer comes from memory rather
  than not at all — carrying its age. `Coverage.cached(seconds:)` puts «это
  ответ 120 с назад» in front of the person instead of a silent substitution. A
  product that promises a quote with its source cannot lie about *when* the
  source said it: a stale truth and a fresh truth answer different questions.
  Past fifteen minutes nothing is served at all, because «what did we decide»
  can otherwise outlive the decision.

The cache belongs to a **session**, not to a request: the app passes the shared
one, the command line and the tests get their own. That distinction was not
foresight — a shared default made neighbouring tests receive each other's
answers within minutes of being written, which is the same global-state trap
this repository keeps stepping into.

What this audit does **not** claim. It covers connectors described by manifests
and the shared engine, plus the four hand-written parsers named above. A vendor can still do things nothing here detects —
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
| A connector built from docs, never against a live service | Битрикс24 sits in that state already, and it is stated plainly | For a hosted service, a live check by other hands (issue #1). For a **self-hosted** one no account is needed, only a container: `scripts/zhivaya-proba.sh` stands the service up, seeds it, searches, and removes it. Gitea, Redmine, Wiki.js and Nextcloud were checked that way 2026-08-19 |
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

`test/roadmap.test.mjs` holds **22 checks** against this file. They fall into
four kinds, and the kinds matter more than the list:

**Structure** — sections numbered and in order; every `plan §N` reference
resolves to a section that exists; every footnote is defined, used, and carries
an address and a read date; README points here.

**Counts measured, not remembered** — own connectors, page-and-doc tests, the
ceiling on English strings in the interface, the numbers §5.2 quotes about
`build.sh`, the page limit §7.2 names, the manifest count §6.2 names, and the
timeouts §10.1 names. Each is recomputed from code on every run, so «measured on
the 17th» cannot quietly become a memory.

The last three were added 2026-08-20 after the same failure twice in two days:
a number that was true when written and false a fortnight later, sitting in a
sentence that still reads correctly. «Three manifests» is the clearest case —
accurate on the day, and by now it describes a project that stopped, while
fourteen ship.

**Claims against code** — a service called connected exists in the code and the
reverse; a manifest is unreachable exactly when this file says it is; the scan
bound here equals the engine's; §8's package promises hold against the packaging
scripts; a queue row shows what it depends on.

**Guards that cannot fire.** Three of them turned up in one week — a build halt
reading a variable it had blanked itself, an entitlement check asserting
whichever branch the machine happened to be in, and `PromptInjectionGuard`, with
no caller anywhere in the app. None would ever have been found by running the
suite: all three were green. They are visible only by asking who calls them, so
`test/reachable-guards.test.mjs` asks that of every type whose name ends in
Guard, Sanitizer, Policy, Validator or Checker, and fails on one that nothing
invokes. It also checks itself against a planted lonely guard, because
«the list is empty» otherwise means both «all good» and «the selection is
broken».

**Auditing the audit: §10.1 carried three false claims, and one of them
credited a defence that does nothing.** Yesterday's duplicate guard happened
because I had not read that section before writing code for it. Reading it
against the code found:

* «a byte-per-second response (the 8-second deadline)» — listed as **held**.
  It was not: `timeoutInterval` counts gaps between bytes, so one byte every
  seven seconds resets it forever. That sentence is in `ConnectorSession` in my
  own words, written the day the resource timeout was added, and this line
  survived beside it;
* the redirect carrying `Authorization` — stated flatly, measured a day later as
  **platform-dependent**: macOS strips it, Linux carries it whole. The source
  comment was corrected then and the plan was not;
* the structural scan — described as looking for `URLSession.shared`, while a
  private session is the same hole in the other spelling.

All three are corrected with what was measured, including which system it was
measured on. Two are now pinned rather than trusted: the timeouts named in
§10.1 must be the numbers in `ConnectorSession`, and the spellings it names must
be the ones the check actually looks for. Change a constant and the plan fails
until it agrees.

A section describing defences is the last place a stale sentence is noticed:
everything in it sounds like something that was done.

**I duplicated a guard, and the copy found a hole in the original.** Yesterday's
entry below says nothing was holding that door shut. That was wrong: a check in
`RedirectPolicyTests` has walked the whole core directory for `URLSession.shared`
since the redirect work — §10.1 even says so, and I did not read it before
writing a second one.

Two guards on one rule is the thing this file already forbids: two places to
repair, and one gets forgotten. The copy is gone. What survived is the part the
core test cannot see — that every family's transport leads to that door, and
that the **application**, which injects these transports and could inject
anything, defaults to them.

Comparing the two paid for itself: the original looked for `URLSession.shared`
and let `URLSession(configuration:)` through, which is the same hole by the
other spelling — a private session follows redirects just as happily and knows
nothing about the size or time bounds. It is closed, and both spellings are
mutation-checked.

**Every defence written against a hostile service lives behind one door, and
nothing was holding it shut.** The redirect refusal — which on Linux is the only
thing keeping a token from an address the vendor chose, measured — the streaming
size limit and the time bound are all in `ConnectorSession`. No connector family
implements any of them. They get them by going through that door.

All seven families do, checked one by one. The point is what a new one would
do: `URLSession.shared.data(for: request)` compiles, looks ordinary, passes
every test that family has, and quietly revokes all three protections at once.
The difference is invisible in review because it is about what the code does
**not** say.

`test/odna-dver-v-set.test.mjs` refuses a session built anywhere in the core but
that one file, requires every family's transport to lead to it, and checks the
application's side too — the app injects these transports and could inject
anything. Mutations: a family routed past the door, a family with its own
session, a brand-new family file added, and an application default replaced by a
raw closure. All four fail.

The check is worth its weight for the same reason the census one was: today the
answer is «all of them», and that is exactly when a rule costs nothing to write
down.

**The census in §2.2 had lost six connectors, and the guard was watching one
family out of five.** Slack, Plane, GitFlic, BookStack, Wiki.js and Nextcloud
were all shipping and all missing from the table. What made it invisible is that
the **total** beside the table was right: 25 is 25, counted from code by a check
that has been there all along. A correct number next to a stale list reads as a
maintained list.

The check compared §2.2 only against `RussianTrackers.swift`. Russian trackers
therefore never drifted, and the four families nobody looked at drifted the
whole time — the same shape as the copy guard that scanned one directory out of
six. It now walks all five families, which is 22 services, and fails naming the
service and the file it came from.

The table also says which connectors were checked against **the service running**
rather than its documentation: Gitea, Redmine, Wiki.js, Nextcloud. That claim is
not held by the bold type — it is held by the manifests, whose notes record the
live run, and a check that refuses a bold name without one.

**Yesterday's fix handed a hostile service a lever, so it is bounded now.** The
connector asks a second spelling of a Russian word when it has learned that a
service compares bytes. Nothing distinguishes a database that genuinely does
from one that merely answers the two spellings differently on purpose — and the
second is worth doing, because it makes us double our own traffic to them, after
which they can throttle us with a straight face.

The rule that closes it is one the repository already believes: «the throttling
people complain about is partly our own», written for the cache. A `429` now
stops the second spelling for that service and host. The knowledge is kept, not
erased — the service is still known to compare bytes — it simply is not acted on
while the service is asking for less. Half the answers beats «сервис просит
обращаться реже».

The suppression is keyed by service **and host**, because one company's
throttled GitLab must not silence another's, and a mutation that keys it by
service alone fails.

**«Nothing the connector can do» lasted one day.** Yesterday's entry recorded
case-sensitive Russian search on SQLite-backed installs and called it the
service's business. That was too quick. The transcript hands us lowercase words
because that is how people speak, so on those installs answers vanished — and
from the person's chair that is not somebody else's database, it is a product
that does not find things.

An empty answer is already the end of the conversation, so a second question
costs nothing there: when the service itself did the searching, the word
contains Cyrillic, and the result came back empty, the connector asks once more
with the first letter flipped. Measured against live Nextcloud: the service
returns **0** entries for «вход», the connector returns «Вход по SSO.md».

Bounds are deliberate. Only on an empty result — no extra request on the path
that worked. Only for Cyrillic — Latin case is folded by every database, so the
request would be paid for nothing. Only the first letter — «ТАРИФЫ» is not how
people write. And **only where the service searches**: a listing (`scan`) is
filtered on our side, already case-insensitively, so a retry there would buy
nothing and double a bound that §7.2 exists to keep. That last limit was not
foresight — the test «страниц читается не больше объявленного» failed and was
right.

**That limit is closed — 2026-08-19.** Partial results used to suppress the
retry: Redmine returned one of two matching tasks for «тарифы» and the second
stayed invisible, because from here one result is indistinguishable from all of
them. Waiting for an empty answer was never going to work — such a service may
never give one.

So the question is asked twice **once per service**, and the answer is
remembered. Same results both ways: the database folds case itself, and the
second spelling is never asked again. Different results: it compares bytes, and
from then on both spellings go every time and are merged. The price of knowing
is one extra request per service per session; the price of not knowing was half
the answers. Live proof: Redmine now returns both tasks where it returned one.

Three things this cost, all of which the suites caught rather than me:

* **the extra question could destroy the first answer.** A service that replied
  to the first request and throttled the second (429) left the person with
  nothing — an answer they already had. The second question is a refinement;
  its failure now means «did not learn», never «did not find»;
* the merge deduplicates by key, and by title where a service has no key — a
  wiki page has no number, and without the second mark one page appeared twice;
* eight tests read the **last** recorded request or counted calls. They now read
  the first, or say two and why. Neither is a weakening: the question they
  answer is where the person's word goes.

The memory can be cleared, and one app test does clear it, because a
process-wide store makes neighbouring tests depend on the order they run in —
this repository has already been bitten by exactly that with the shared cache.

Three existing tests read the last recorded request; the retry made that the
second one. They now read the first, which is what they always meant: the
question is where the person's word goes.

**Two services out of four search Russian case-sensitively, and it is the same
cause.** Nextcloud 29 was verified live and behaves exactly as Redmine did:
«Тарифы» finds the file, «тарифы» finds nothing, Latin `SSO` is unaffected. Both
ship SQLite by default, and SQLite's `LIKE` folds case for ASCII only. This is
no longer a quirk of one connector — it is what a small self-hosted install does
to Russian search, and the transcript hands us lowercase words, because that is
how people speak.

Nothing in the connector can fix it and nothing pretends to. It is recorded in
both manifest notes, where somebody debugging «it found half of my files» will
meet it.

Two other facts about Nextcloud earned their place in the note: the unified
search matches **file names by substring**, so «тарифы» does not find «пересчёт
тарифов» — a Russian ending is enough to miss — and `subline` arrives empty for
files, so the hint carries no context. Both are the service's data rather than
our loss, and neither is visible in the documentation.

**The probe script could not fail on an empty answer.** It printed «коннектор
ответил пустотой» and exited zero: the live probe counts any reply as success,
which is right for the probe and wrong for the script, because the script seeds
the data itself and two of three records contain the word. It now exits 1, and
that was found the honest way — the first Nextcloud run returned nothing, and the
script called it a pass.

**The injection guard had no Russian in it.** Its phrase list was English plus
Latin transliteration — `ignoriruy predydushchie` was caught, «Игнорируй
предыдущие инструкции» was not. In a Russian product, where the pages and
tickets arriving through connectors are written in Russian, that is the wrong
way round. Found while examining MCP tool descriptions, not by looking at the
guard.

The addition follows the same rule the file already sets for itself: every
phrase names the assistant's own instructions or hides an action from the
person, and the imperative form is required. «Поиск игнорирует регистр» appears
in honest descriptions; «игнорируй» is not something you say to a colleague. The
benign half is tested as seriously as the attacking half — «Не говори заказчику
про сроки» must survive, or the guard fires in every meeting and stops being
read.

**Tool metadata gets a stricter threshold than speech, deliberately.** An MCP
server is third-party code the person connects, and it describes itself: name,
description, hints. The known attack is a read-shaped tool whose description
carries instructions for the model — which passes a mutation-word check
untouched, because it contains no write verbs. The same signals now refuse the
tool outright rather than flagging it, and a few phrases are added that would be
absurd in an honest description («disregard your», «your system prompt»,
«системный промпт»).

The asymmetry is the point, not an inconsistency. Identical words, different
base rate: a meeting is full of people saying anything, a description field is
machine text from a stranger. Both mutations that widen the metadata list to
ordinary words («instructions», «prompt») fail the suite by breaking honest
tools — the cost of over-refusal is a source the person loses, and it is checked
in both directions.

**Wiki.js is now verified by a script rather than by hand.** Yesterday it was
stood up manually, and the bug it exposed took the rest of the tick — so the
verification itself was never made repeatable and never recorded, which is the
state this file exists to prevent. `scripts/zhivaya-proba.sh wikijs` now starts
Postgres and Wiki.js on their own network, finalises the install, enables the
API, mints a key, writes three pages and searches: thirty-eight seconds from
nothing to an answer, containers and network removed afterwards.

Two things about that service are worth knowing before somebody spends an
evening on them, and both are in the manifest note now. An API key created while
the API is switched off is issued happily and then refused on use — which looks
exactly like a broken connector. And the `ru` locale is not installed by
default, so a page created with it fails on a foreign key; the page text is
Russian regardless, which is what the search is actually about.

The refusal path is verified in the same place: with guest read revoked, Wiki.js
answers `200`, `data.pages: null`, `errors[0].message: "Forbidden"` — the exact
shape the manifest declares `errorMessage` and `errorCode` for, and the one that
spent two days masquerading as «nothing found».

**The chain was four links long and every link broke silently.** Following the
same question one layer further — does this reach the person? — the answer was
no, twice more. The engine distinguished a refusal; the family wrapper flattened
it (fixed). The wrapper was fixed; the grounding path ran `try? await
client.search(query)`, so a refusal and «your wiki has nothing about this» both
became `nil` and vanished. There was nowhere to read it even if it had been
kept.

This is the competitor scenario in its most effective form. A service that
withdraws access does not have to break anything: from inside orakul, a revoked
token is indistinguishable from a product that has quietly got worse at
answering, and the person has nobody to blame but us.

Dropping the source **during the call** stays right — one failed source should
cost one source, not the answer. What changed is that the refusal survives as a
fact: `ConnectorHealth` keeps the service, the vendor's own words and the time,
and the connector's own settings row shows «Последний отказ: …» where somebody
is already deciding what to do with that connector. Success clears it, because a
stale complaint sends a person to repair something that already works.

The check covers the whole chain rather than the newest link: refusals must be
recorded at every source, `record` and `recordSuccess` must appear the same
number of times, and both settings sections must read the record and print the
**service's words** rather than a paraphrase of them.

**The same defect had three more instances, so it is now a class with a check.**
Yesterday's finding — an engine error quietly becoming a different one inside a
family wrapper — was not one bug. Asking the question of every wrapper found
`.forbidden` collapsing into `.unauthorised` in **four** of the five families.

The engine separates 403 from 401 on purpose and says why: «токен не принят»
sends a person to issue a new token, «нет права» sends them to grant a
permission. A 403 from GitLab means the token is missing `read_api`; reissuing
it produces an identical token and another wasted evening. Four wrappers gave
exactly that advice.

`test/perevod-oshibok.test.mjs` now fails when two distinct engine errors reach
the same family case. Merging is not forbidden — it must be **named**: the
marker «СЛИЯНИЕ НАМЕРЕННОЕ» beside the branch lifts the refusal and leaves a
trace, because there are legitimate merges and a rule with no exit turns into a
rule people delete.

Its first run reported three collapses and two were nonsense — the scan had
picked up `.slack` and `.plane`, which are **service** names, not errors. A
check that is wrong two times out of three stops being read, so the error names
are now taken from `ManifestConnector.ConnectorError` itself rather than from a
list written here.

**Three existing tests had to change, and that is the point.** They asserted
that 401 and 403 produce the same answer — they pinned the defect rather than the
behaviour, which is why every suite stayed green through all four instances. A
test that encodes a bug protects it.

**A live Wiki.js disproved a comment, and the defect was one layer below every
test.** Wiki.js 2 was stood up in a container with Postgres, seeded through its
own GraphQL API, and its access revoked — which is what a service withdrawing
access actually looks like: `200`, `data.pages: null`, `errors[0].message:
"Forbidden"`. The connector answered **«непонятный ответ»**, sending the person
to check the address and the server version. The address was right, the version
irrelevant, the access gone.

The engine was correct. `ManifestConnector` distinguishes a refusal in the body
from an unreadable answer, and that was tested — **on the engine**. The
application does not call the engine; it calls the family wrapper, and two
wrappers mapped `.vendor` straight back to `.unreadable`. Every test was green
because they all stopped one layer above the person.

The comment there had even named the condition for opening the branch: «their
refusals arrive as an HTTP code, not as a body with a flag — if such a service
appears, open it». Such a service was already in that family. And a second one
ships in another: Slack declares `requireTrue: ["ok"]` with `errorCode:
["error"]`, so `invalid_auth` — a word that tells you to reissue a token — was
being replaced by advice about server versions.

Both are open now, with the third family opened deliberately though no manifest
of its own refuses that way today: `.vendor` comes from the shared engine, so
leaving the swallow in place would just be waiting for the first manifest that
does. The regression test crosses the boundary the old ones never did, using the
exact body the live Wiki.js returned.

**Everything above stands on certificate validation, and nothing was watching
it.** The rule about `http`, the refusal to follow a redirect off-host, the
secret kept in a header rather than the address — all of it assumes the
connection is encrypted to the party we meant. One line,
`completionHandler(.useCredential, URLCredential(trust: trust))` without
`SecTrustEvaluateWithError`, cancels the lot: anyone in the middle becomes the
service, and the token travels to them over «https».

The code is clean today — pinning tightens trust rather than loosening it, and
there are no App Transport Security exceptions anywhere. The point is that the
request **will** come, and it is a reasonable one: self-hosted GitLab and Gitea
often run behind a company's own certificate authority, so «allow self-signed»
is the natural thing for exactly our audience to ask. The right answer is to
trust that specific certificate, the way `CertPinning` already does, not to
switch validation off. `test/doverie-tls.test.mjs` now fails on trust granted
without chain validation, on a challenge handler that neither defers to the
system nor refuses, and on `NSAllowsArbitraryLoads` appearing in a plist —
checked by planting the very edit somebody will one day be tempted to make.

**Measured 2026-08-19, and the answer was «not that gate, the other one».** The
question was whether ATS refuses `http://192.168.…` from the bundled app, making
the local-network allowance theoretical. Measuring it needed a bundle rather than
a test target, so one was built around the app's own `Info.plist`: it reached a
private address over plaintext and got 200. ATS is not the obstacle, and
`NSAllowsLocalNetworking` is not needed.

The first attempt measured nothing — the hostile server binds to `127.0.0.1`, so
both probes failed with `-1004` «could not connect» rather than the `-1022` ATS
returns. Two failures that look alike and mean opposite things: one says the rule
blocks you, the other says nobody was listening.

What the measurement did surface is a different gate on the machine this runs on.
macOS 15 asks the person before an app may reach the local network, and the app
declared microphone, screen capture and speech recognition — but nothing for the
network. That prompt arrives at the worst possible moment: seconds after somebody
pastes a work tracker's token, deciding right then whether this program is
trustworthy, with no reason given. `NSLocalNetworkUsageDescription` now says what
it is for and where the request goes, and `test/dostup-k-seti.test.mjs` holds it
to the rule that permits local plaintext in the first place — remove the private
ranges from `ConnectorAddress` and the pair stops making sense, so the suite says
so.

**Forty-five commits, none pushed, and CI is what checks the second platform.**
The Linux breakage went four days undetected not because the job is wrong — it
would have caught both errors on the first run — but because the job runs on
push. Between writing code and hearing from CI there was no step at all, so the
answer is a step: `scripts/proverka-linux.sh` runs the same commands, in the
same `swift:6.0` image, in about forty seconds.

It is checked against the real bug rather than trusted: putting
`waitsForConnectivity` back gives a clean macOS build with zero errors and an
exit code of 1 from the script, quoting «cannot assign to property». That is
the four-day defect, found in forty seconds.

Two lists of the same steps drift, and this repository has now watched that
happen with form labels and with published directories, so
`test/proverka-linux.test.mjs` holds the script against the `linux-core` job:
a step added to CI and missing from the script fails the suite, as does a
different container image. Otherwise «green locally» quietly starts meaning less
than it says.

**The size limit does not work on Linux, and now says so.** The delegate that
replaced `bytes(for:)` was new and load-bearing, so it was pushed the way a
hostile service would push it: twenty overlapping requests, each carrying its own
tag, plus a batch mixing oversized responses with ordinary ones. Both pass, and
both were mutation-checked — a shared buffer instead of per-task state mixes the
answers (one service's task appearing in another's results, which no person
could detect), and a continuation allowed to resume twice **kills the test
process** rather than failing it, caught only by the exit status the previous day
had fixed.

Running the same on Linux found something worse than a flaky test:
`dataTask.cancel()` **does not stop delivery** there. Measured — after
cancelling, 62 450 more chunks arrived within five seconds; after
`invalidateAndCancel()` on the whole session, 72 414. An endless response with no
bound killed the container outright (OOM). So on Linux:

* the caller **is** protected — the overrun is spotted on the first chunk past
  the limit and the error returns at once, and our buffer stops growing;
* the transfer is **not** stopped — the library keeps reading until the
  resource timeout.

Time is therefore the only bound that exists there, which is why it is now
tighter on Linux (20 s against 60 s on macOS): a tracker search that takes
twenty seconds is broken anyway, and a third of the window is a third of what a
hostile service can pour in. Claiming the eight-megabyte cap protects Linux would
have been the comfortable thing to write and false.

The suite was split along the same line rather than papered over: the oversized
**finite** response is checked on both systems, and prompt abort only on macOS,
where prompt abort exists. Left as it was, that test did not fail on Linux — it
hung the run for four minutes, and a suite that hangs teaches nothing.

**The socket check went into CI, and running it there found the core had not
compiled on Linux for four days.** The step was written, and then — before
trusting it — run inside the same `swift:6.0` image the job uses. It failed
immediately, and not for the reason it was written:

* `URLSession.bytes(for:)` **does not exist** in swift-corelibs-foundation, so
  the streaming size limit added two days earlier broke the Linux build of
  `OrakulCore` outright;
* `waitsForConnectivity` is **get-only** there, so the timeout work broke it a
  second time.

Both landed in the same commit, both were invisible on macOS, and CI had not
run because nothing had been pushed. The command line ships on Linux — that is
what §6.1 is for — so this was not a CI inconvenience: the product did not
build for its second platform and every suite was green.

The streaming limit is now a `URLSessionDataDelegate` that works the same on
both systems — chunks counted as they arrive, the task cancelled on the first
one past the limit — rather than an Apple-only API with the protection quietly
dropped on Linux. Per-task state is keyed by task identifier, because one
delegate serves the whole session and a shared buffer would put one service's
answer into another's.

**The script that runs it could not fail.** Written the day before, it ended in
`| grep … || true`: three red tests, exit code zero. Wiring that into CI would
have added a step incapable of reporting anything. It now propagates the
status — and refuses a **skipped** suite, which needed its own answer, because
Swift Testing prints «6 tests passed after 0.001 seconds» for a suite disabled
by `.enabled(if:)`. Parsing that line would have been green exactly when
nothing ran, so the proof is the stranger's hit counter instead: no visit, no
run.

**The defences met a real socket, and the first thing they refuted was their own
comment.** Everything written against a hostile service had been tested through a
stubbed `http` closure — which never touches URLSession, and therefore cannot
tell «the rule is correct» from «the rule is applied». A perfect redirect policy
with an unwired delegate passes exactly the same. `scripts/vrazhdebnyj-server.py`
now plays the hostile vendor and, on a second port, the stranger it tries to
hand the request to; `scripts/vrazhdebnaya-proba.sh` runs the suite against it.

The comment on `RedirectPolicy` claimed that `URLSession` carries the
`Authorization` header to the foreign host. Measured, it depends on the system,
and nobody had ever run it:

| | Follows the redirect | Sends `Authorization` to the stranger |
|---|---|---|
| macOS | yes | **no** — Foundation strips it |
| Linux, corelibs 6.0.3 | yes | **yes** — the collector got `Bearer секретный-ключ` |

So the claim was right on Linux and wrong on macOS, and «Foundation protects
you» is not a thing that exists. The command line runs on Linux (§6.1), which
makes this delegate the only thing between a tracker token and an address the
vendor picked. Verified in a container with the delegate in place: the response
is the 302 itself and the collector's counter stays at zero.

The rule stays «do not follow», not «strip the header», for a reason the
measurement makes concrete: on both systems the **request itself** still reaches
the stranger, and a connector's query parameter holds the word the person is
searching for — the content of their call. And header-stripping is another
library's behaviour, promised by nobody here, absent on one of the two systems
we ship.

The trap is checked before it is trusted: the default session must reach the
collector, or «nobody reached the stranger» would be green with a broken
collector.

**Two connectors stopped being built from documentation — 2026-08-19.** The
admission rule wants a run against a live service, and that had been reading as
«wait for somebody with an account». For a service you install yourself, no
account exists to wait for: `scripts/zhivaya-proba.sh` starts it in a container,
creates three issues (two containing the word, one not), searches, and removes
the container. The search token is created separately from the seeding token and
is **read-only**, so a missing scope is found by the script rather than by a
person.

Gitea 1.22.6 answered correctly: both matching issues, not the third, regardless
of case.

Redmine 5 answered — and returned **one of the two**. The cause is not ours and
is worth writing down: the official image runs on SQLite, whose `LIKE` folds
case for ASCII only, so «Тарифы» and «тарифы» are different words to it.
Confirmed against Redmine's own API rather than inferred — `q=тарифы` returns
#1, `q=Тарифы` returns #3. On PostgreSQL or MySQL with an ordinary collation
this does not happen. So on a small default install, Russian search is
case-sensitive; that belongs to the person operating it, not to the connector,
and it is now in the manifest note where somebody debugging «it only found half»
will find it.

Nothing about this was visible from the documentation, and both connectors had
been passing their suites for a week.

**A login page is the cheapest way to cut someone off.** Not `401` — a form.
An expired single-sign-on session, a hotel captive portal, and a service that
would rather not say no all answer `200` with HTML, which is to say they all
look like the system working. The engine called that «unreadable» and told the
person to check the address and the server version: the address is fine, and
the version has nothing to do with it. It is now its own answer, with its own
sentence about sessions and captive networks, in all five connector families —
the compiler named every one of them the moment the case was added.

It is deliberately decided on the **start** of the body, not on the body
containing markup: a task whose description quotes `<html>` is ordinary, and
mistaking it for a login page would break a working search. Turning the check
from «starts with» to «contains» fails the suite.

**Two mutations came back green and neither was a hole.** Requiring the JSON
parse to have failed first is unreachable as a difference — valid JSON cannot
begin with `<` — and dropping the 512-byte window does not change a `hasPrefix`.
Both are equivalent mutants, and recording them as «the guard is weak» would
have been the wrong report; the mutation that tests the real claim is the one
above.

**Checked and needing nothing: the nesting bomb.** Eight megabytes of `[` passes
the size limit entirely, so the shape had to be measured rather than reasoned
about. `JSONSerialization` refuses past roughly 512 levels and throws instead of
overflowing the stack; the suite pins that with a 100 000-level payload, and
because the suite runs on Linux too, that is a measurement of corelibs rather
than an assumption about it.

**A secret in the address is a secret in somebody's logs.** A hostile service
does not have to attack for this one — it only has to document the convenient
way. Trello's own API is `?key=…&token=…`, and a manifest author copying the
vendor's documentation would put the key straight into the URL, where it is
written to proxy logs, the service's own access log and every error report, and
stays there long after the token is revoked. A header goes into none of them.

All fourteen manifests already send the secret as a header, and for Trello that
was a deliberate choice recorded in its `note`. A decision written as prose in
one manifest is not a rule — the next author is not obliged to read it — so it
is now enforced in `validate()`, for `path`, for `query`, and for `scan.page`,
which is the one that gets forgotten because it does not look like a query
string. CONTRIBUTING states it before the code is written; the loader refuses it
after.

**Limit, stated rather than papered over:** the rule covers the two secrets the
engine substitutes, `{token}` and `{basic}`. A person-filled parameter that
happens to be secret — Trello's `{key}` — cannot be recognised as one, because
`Parameter` is a name and a value with nothing to mark it. Making that
enforceable means teaching the manifest which fields are secret, which is a
larger change than this one.

**HTTP 200 is not an answer.** GraphQL replies 200 to everything and puts the
refusal in `errors`, and its normal shape for a refusal is not «no list» but
«the list is here, it is empty, and there is a complaint beside it»:

    {"data": {"pages": {"search": {"results": [], "totalHits": 0}}},
     "errors": [{"message": "rate limit exceeded"}]}

The engine read the complaint only when the list container was missing entirely
(`rows == nil`). With an empty list present, that branch was skipped, and the
answer became «searched, found nothing» — a conclusion about the person's own
wiki rather than about our connector. They will not go and check it. Wiki.js,
Linear and Fireflies itself all answer this way; the connector this was found
in, Wiki.js, ships with `errorMessage` declared and it still could not fire.

The over-correction is the more likely mistake and is guarded too: a check that
shouts «refused» at every empty answer lies more often than the bug did, because
empty answers vastly outnumber refusals. An empty list with no complaint, and an
empty list with an empty `errors: []`, both stay an ordinary empty result.

**Considered and not done:** a `.partial` coverage case for results arriving
*alongside* an error. Every manifest here queries a single search field, so
rows-plus-error cannot occur — it would be a case that can never fire, which is
the defect §13 already tracks.

**A guard that fires too late is not a guard.** The eight-megabyte response
limit had been in place since the hostile-vendor exercise, and it was checked
after `session.data(for:)` returned — a call that buffers the entire body in
memory first. A service answering with ten gigabytes was therefore allowed to
allocate ten gigabytes, and only then told that its answer was rather large.
The limit was real, the check ran, and the machine was already dead. It now
streams and stops on the byte that crosses the line.

The test measures **bytes actually consumed**, not that an error was thrown:
«it threw» is equally green whether the limit fired at eight megabytes or after
a gigabyte sat in memory, which is precisely how the old version passed for
weeks.

A service does not have to send anything to do damage — it can simply not close
the connection. `timeoutIntervalForRequest` counts *gaps* between bytes, so one
byte every twenty seconds resets it forever, and the second limit,
`timeoutIntervalForResource`, defaults to **seven days**: effectively absent.
The whole exchange is now bounded to a minute. A tracker search that takes a
minute is already a broken search.

**The protocol the person typed.** A service address is filled in by hand, and
the token travels to whatever address that is. `http://git.company.ru`, copied
from an old bookmark, sent a work tracker's key in clear text to anyone sitting
between — hotel Wi-Fi, a proxy, the next desk. No competitor has to do anything
for this one. Three connector families each pasted the same line, and all three
kept `http` whenever the person had typed it: the scheme was only ever added
when it was missing entirely. `ConnectorAddress` now owns the single rule —
plaintext is kept only for an address that cannot leave the local network
(`localhost`, `.local`, `10.x`, `192.168.x`, `172.16–31.x`), and upgraded
everywhere else.

The expensive part was not the rule but its edge: for team notes an empty
address means «the vendor's cloud», so returning nothing for an address that
merely fails to parse would have redirected a self-hosted key straight into a
third party — quieter and worse than the `http` it replaced. Nothing means
«nobody typed anything», and only that.

`test/connector-address.test.mjs` guards the class rather than the three
instances: a fourth family added next year with its own `"https://\(value)"`
would pass every Swift test, which only knows the three services it was written
with.

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
