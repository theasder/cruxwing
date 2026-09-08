# orakul.ai — research and plan (v1)

A Cruxwing branch for the Russian-speaking developer community. This file is the
working document: research first, then the decisions the research supports, then
what is still assumption. Every claim that came from a source is cited; every
claim that did not is marked **ASSUMPTION** so it cannot quietly become fact.

Status: v1, 2026-08-11. Research covers the Q&A gap, in-call pain, the tool
landscape and the model choice. Not yet researched: Telegram chat structure at
first hand, willingness to pay, GitHub-stars mechanics.

Implementation note: this file preserves the v1 decision history. Current
source boundaries, removals, and release blockers live in
[`../app/PROJECT_STATUS.md`](../app/PROJECT_STATUS.md) and
[`ARCHITECTURE.md`](ARCHITECTURE.md); later compatibility work means historical
statements here are not release attestations.

---

## 1. The gap this product enters

### 1.1 The Q&A layer collapsed, and nothing replaced it

Stack Overflow's decline is measured, not vibes: April 2025 publications fell
**64% year-on-year and 90% from the April 2020 peak**, with the slide starting
June 2020 and LLMs accelerating rather than starting it.[^so-decline] The
cultural cause is older than the traffic loss — moderation that reads as hostile
to newcomers, questions closed as "duplicate" or "too simple", and a bar for an
acceptable question so high that new participants stopped trying, which starves
the veterans of interesting questions in turn.[^so-mod]

That is the global story. The Russian-language layer inherits it **and** is
thinner to begin with. On Хабр Q&A the recurring complaints are structural, not
incidental: questions arrive with too little information to answer, threads die
almost immediately once they are no longer new, and the tag system duplicates and
overlaps itself.[^qna] A question that goes stale in a day is a question whose
answer is never found again by the next person with the same problem — the
searchability failure and the response-time failure are one failure.

**Measured by us 2026-08-13, not taken from somebody else's survey.** The first
page of the new-questions feed on Хабр Q&A — twenty of them — covers **seven
days**: from "8 minutes ago" back to 6 August.[^qna-new] That is fewer than three
questions a day for the entire Russian-language IT question-and-answer service.
For comparison: at its peak Stack Overflow counted thousands a day.

The composition of the feed matters more than the volume. Of those twenty
questions, seven relate to software development: axis in Pandas, selectively
copying columns from a page, auto-refresh on selecting an option, react versus its
frameworks, editable fields, duplicated selects in Firefox, ChatGPT as an
architecture tutor. Another seven are networking and administration (VPN, 3X-UI,
Asterisk, RDS, the kernel), and six are general technical support: "what is this
Wi-Fi connector?", "how do I fix the lid sticking on a MacBook Air M1?". So
development questions run at roughly one a day.

The unanswered-questions feed gives the other half of the picture: on its first
page, next to a question eight minutes old, sit questions from 2
July.[^qna-noanswer] A month and a half without an answer — and that is the first
page, not the tail of the archive.

**The caveat without which the number lies:** this is one measurement on one day,
and only of the first pages of two feeds. Not a time series and not a sample
across the whole site. It can be re-checked by hand in a minute at the two
addresses in the footnotes — and that is what it rests on.

**Moderation: the brief asked about bias, and it has specific names (read
2026-08-13).** Not from third-party reviews, but in the discussion of Хабр's own
2026 rules, where authors argue with moderation directly.[^habr-rules] The
complaints recur and all three are about one thing: somebody else makes the
decision, and there is no way to contest it.

| Mechanism | The complaint |
|---|---|
| Karma | "karma can be driven negative on any pretext" — with no way to contest it |
| Selectivity | the political rules are applied to ordinary users but not to corporate blogs |
| Opacity | a person cannot see which comment cost them the karma |

There is no formal appeal procedure: support requests go unanswered, according to
the commenters themselves.

**Why this matters to us specifically.** The complaint here is not "the moderators
are unkind" but "the status of an answer depends on someone else's decision, which
is neither explained nor contestable". An answer from your own call has none of
that: it has an author, a date and a recording, and no third party who can take it
away. This is not "a forum, but nicer" — it is a different source of truth.

**What this means for orakul:** the opportunity is not "build a better forum".
The forum model is what died. The opportunity is answering from the material a
team already produces — its calls, its repos, its trackers — where the answer is
specific to *this* codebase and *this* team's decisions, and cannot be closed as
a duplicate.

### 1.2 For a developer, the call itself IS the pain

Corrected after a founder note, and it changes the pitch more than it changes
the code. The framing above — decisions get lost, so make meetings searchable —
is a **manager's** pain. A developer's pain is one level earlier: the meeting
exists at all. Russian practitioner writing states it outright, up to
"Продуктивность в тишине: отказ от совещаний как идеал", and complains directly
about the volume of calls in a working day.[^calls-quiet]

This matters for the metric. The stated goal is GitHub stars in a Russian
*developer* ecosystem, so the adopter is a developer even when the payer is a
lead. A page that opens on decision hygiene is written for the person who
approves the invoice, not the person who stars the repo.

**Positioning, therefore:** not "better meetings" but *you did not have to be
there*. The tool reads the call so attendance becomes optional for the ones
where you were needed for five minutes out of sixty. What it must never claim is
that it can excuse you — that is a decision made by people, and a landing page
promising otherwise sells something it cannot deliver.

### 1.3 The pain is inside the calls, not around them

Searching in Russian for what actually goes wrong during developer calls returns
the Cruxwing thesis almost verbatim. Teams report that as the number of calls and
chats grows, real control of the project *falls*.[^calls-manage] Two recurring
failures:

- **Agreements live only in heads and chats** — the explicit recommendation in
  Russian practitioner writing is that agreements must not stay in memory or
  in chat threads, but be recorded in structured form.[^calls-agreements]
- **Re-deciding**: having reached agreement and progress, teams find themselves
  going back and working through what was already worked through
  before.[^calls-agreements]

That second one is F1 — cross-meeting recall — described independently, in
Russian, by Russian practitioners. It is the strongest signal in this research
that the existing Cruxwing engine aims at a real Russian pain rather than a
translated American one.

Note what is *not* the pain: platform quality. SberJazz gives 100 participants
free with unlimited duration, TrueConf scales to 1500 in broadcast mode, and
SberJazz already ships automatic speech-to-text via SaluteSpeech into the
chat.[^vks] Competing on video plumbing is a losing move. Competing on *what the
call leaves behind* is not — a raw transcript dumped into a chat is precisely the
"agreement living in a chat" that the practitioners complain about.

---

### 1.4 The quick start was walked from a clean clone (2026-08-13)

Everything README and CONTRIBUTING promise was carried out as written, in an
empty folder, rather than "ought to work".

| step | result |
|---|---|
| `git clone` | the clone is complete and needs no neighbouring repository |
| `cd mvp && swift build -c release` | 73 s |
| the transcript example | the output matched README word for word, including the answer line; the refusal on a question about nothing was word for word too |
| `cd app && swift build` | 176 s, 27 packages downloaded, no errors |
| `cd app && swift test` | 2654 passed, 11 skipped (they need real models, recordings, a live service) |
| `cd mvp && swift test` | 294 passed |
| `npm test` | 158 checks, 154 passed, 4 skipped with a stated reason — they need the author's neighbouring repository |

One place disagreed, and it is fixed: `app/` has four direct dependencies, but the
build prints **27** `Fetching` lines. "Four" standing next to the twenty-seven a
person observes reads as an understatement.

The point of the measurement is not that everything matched. The point is that
before it, this was an assumption: a test suite checks the code, not whether the
lines from README can be carried out on a machine that has nothing on it.

## 2. Integration targets, ranked by what teams actually run

Russian teams did not standardise on one stack; the market is fragmented across
several credible trackers, which raises the value of a connector layer and lowers
the value of betting on any single one.

| Layer | Targets | Why this order |
|---|---|---|
| Task tracking | **Yandex Tracker** first, then **Kaiten** | Tracker already exposes an API and webhooks and integrates with GitHub/GitLab and messengers, so the connector has a documented surface; Kaiten is named alongside it as the Agile-team default.[^trackers][^tracker-api] |
| Task tracking (SMB) | WEEEK, YouGile, Planfix, Shtab | The small-team tier: YouGile is free to ten people with all features, Shtab has no headcount limit — this is where unfunded teams actually are.[^trackers][^trackers-smb] |
| Process/approvals | Pyrus | Different shape: built around requests and approvals (leave, contracts, invoices), so it is a workflow target rather than a task target.[^trackers] |
| Calls | Yandex Telemost, VK Teams, SberJazz/SaluteJazz, TrueConf | The four repeatedly named as the domestic ВКС set.[^vks][^vks-alt] |
| Notes | Yandex Wiki (Yandex 360), Teamly | Verified 2026-08-11: neither can be connected today — see §2.1. |

### 2.0 Open services a team hosts itself (verified 2026-08-12)

The conclusion of §2.1 below is about Russian clouds, and it stands. But it is not
about open services a team deploys on its own server: those do have text search,
and connecting runs up against nothing but a "server address" field.

| Service | Request | The particular |
|---|---|---|
| Mattermost | `POST /api/v4/teams/{id}/posts/search` | `is_or_search: false` — AND, not OR |
| Rocket.Chat | `GET /api/v1/chat.search?roomId=` | needs TWO values: the token and a user-id |
| Zulip | `GET /api/v1/messages?narrow=[{"operator":"search"}]` | Basic authorization, `mail:key` |
| Matrix / Element | `POST /_matrix/client/v3/search` | a body with `search_categories.room_events` |
| GitLab | `GET /api/v4/search?scope=issues&search=` | the `PRIVATE-TOKEN` header |
| Gitea / Forgejo | `GET /api/v1/repos/issues/search?q=&type=issues` | `Authorization: token`, not `Bearer` |
| Redmine | `GET /search.json?q=&issues=1` | the only one that wraps results in `results` |
| Bitrix24 | `POST /rest/{id}/{code}/tasks.task.list` | the key is in the address, not a header; the list sits under `result.tasks` with upper-case fields; the page is always 50; **a refusal arrives with HTTP 200** and `error`/`error_description` fields |
| Outline | `POST /api/documents.search` | the address is NOT required — it can be cloud-hosted |

Two details are pinned by tests, because the error text cannot reconstruct them:
Gitea answers 401 to the word `Bearer`, indistinguishable from a bad token;
Rocket.Chat without `roomId` returns an empty list, indistinguishable from
"nothing found".

**Outline closes what §2.1 left empty.** The notes section was closed as
impossible — and for Yandex Wiki and Teamly it still is. But an open wiki on your
own server returns `context`: a ready-made piece of text around the match, which is
exactly what a hint needs — words, not a link.

#### 2.0.0 The server address: where the path is trimmed and where it is not (decided 2026-08-13)

Three families of connectors treat a pasted address differently, and that is a
decision rather than an oversight.

| Who | The path from the address | Why |
|---|---|---|
| Kaiten | trimmed | the hint leads to a board, a person copies `.../boards/5`, and with `/api/latest` that is a 404 with no explanation. It did happen |
| Bitrix24 | parsed in full | the webhook is shown as one line, and the key sits inside it (§2.0.1) |
| GitLab, Gitea, Redmine, messengers | preserved | they are installed in a subdirectory (`company.ru/gitlab`); trimming would break a working configuration |

The temptation is to "make the behaviour consistent". It is wrong: for Kaiten
trimming fixes an error we observed, while for self-hosted servers it would break
what works for the sake of an error we have never seen — their hint asks for a
server address, not a page address. The difference is pinned by
`HostNormalisationPolicyTests`, so that whoever decides to unify them sees first
what would be lost.

### 2.0.1 Bitrix24: built from the documentation, not against a live portal (2026-08-13)

The Bitrix24 connector is written and covered by tests, but **has not been verified
against a real portal** — we have no portal with a webhook. It differs from the
other three trackers, and from the rule "do not claim what does not exist", in
exactly one respect: what was verified here is the vendor's documentation, not the
server's answer.

What was taken from the documentation of the `tasks.task.list` method: the address
`POST /rest/{user_id}/{webhook_code}/tasks.task.list`, search on `TITLE` by a
pattern with `%` and `_` **in the value**, the response
`{"result": {"tasks": []}}`, and a page size that is always fifty and cannot be set
by a parameter.

One place stayed ambiguous. Bitrix's general idiom for substring search is a prefix
on the field name (`%TITLE`), but the documentation for this particular method
shows the pattern in the value. What is described is what is implemented; if a live
check shows otherwise, one line changes in `body(for:limit:)`.

**How to check it in one command,** once a portal exists:

```bash
cd app && ORAKUL_PROBE_SERVICE=bitrix24 ORAKUL_PROBE_TOKEN='1/код' \
  ORAKUL_PROBE_HOST=фирма.bitrix24.ru ORAKUL_PROBE_QUERY=тариф \
  swift test --filter LiveConnectorProbe
```

### 2.0.2 Megaplan: ruled out by the same rule (verified 2026-08-13)

Megaplan was on the list of expected trackers and fails the same check that removed
two services earlier.

- **There is no long-lived key.** The token is obtained by exchanging a login and
  password: `POST /api/v3/auth/access_token`, `grant_type=password`. To refresh the
  token, the application would have to hold the password to a work account. For a
  product whose secrets live in the Keychain precisely so that no password is kept
  anywhere, that is not a small inconvenience but a change of terms.
- **The method reference is behind an account.** The public page says so outright:
  the description of all methods and entities is inside Megaplan, at
  `/api/v3/docs`.[^megaplan] So the task search parameter, the filter shape and the
  response shape cannot be verified from outside, and the CONTRIBUTING rule
  requires them to be verified before the button.

**What would change the conclusion:** an application key that does not require the
user's password, or a public description of the task-list method. Then it becomes
an ordinary day's work.

### 2.0.3 Trackers: the full census (verified 2026-08-16)

The sweep of the list is finished. Eight services, five connected, three not — and
every "not" has a named reason rather than "we did not get to it".

| Service | State | How it was settled |
|---|---|---|
| Яндекс Трекер | connected | OAuth token and organisation identifier; the header is chosen by the identifier's shape (§2.2) |
| Kaiten | connected | a token from the profile, with each team having its own address |
| YouGile | connected | an API key obtained through `POST /api-v2/auth/keys`; search through the current `GET /api-v2/task-list` |
| WEEEK | connected | a workspace Bearer token; the documented `GET /public/v1/tm/tasks?search=…`, creation into a numeric `projectId`[^weeek-api] |
| Битрикс24 | connected **from the documentation**, not against a live portal | the webhook in the path; §2.0.1 has the command for a live check |
| Pyrus | no | a different product shape: requests and approvals, not tasks (§2) |
| Мегаплан | no | no long-lived key, sign-in by login and password; the method reference is inside the account (§2.0.2) |
| Aspro.Cloud | no | no public method reference could be found: `aspro.cloud/api/` is a page saying an API exists, with no reference[^aspro] |

The wording about Aspro is deliberately narrow: **not "there is no API" but "we did
not find a reference from outside"**. If somebody has an account and shows the
task-list method, its search parameter and its response shape, that is a day's
work. WEEEK unblocked in exactly that way: the public method page now contains both
the `search` filter and the response shape, so the earlier research dead end was
lifted rather than forgotten.

The three refusals have one thing in common: the rule "do not claim what does not
exist" is checked before the button, not after the complaint. Two services fell out
on that check in the very first sweep, and that is the right outcome, not a loss.

## 2.1 Notes: why there is no connector (verified 2026-08-11)

The notes row stood marked "assumption" for a year. Checking the vendors'
documentation showed the assumption was wrong in an important part: API access
exists, the method we need does not.

**Yandex Wiki.** The base is `https://api.wiki.yandex.net`, with authorization
exactly as in Yandex Tracker: `Authorization: OAuth <token>` plus `X-Org-Id`.
`GET /v1/pages?slug=…` — a page by its address — is documented. There is no
full-text search in the public reference: the overview page promises "search pages
by text using API methods", but the method itself, its parameters and its response
shape do not appear in the open documentation.

**Teamly.** No public API description could be found — only material about the
product and its own AI search.

**Conclusion.** No notes connector is written until a search method is confirmed.
Taking `GET /v1/pages?slug=` and calling it search is not allowed: it finds a page
whose address is already known, that is, it answers a question the user does not
have. Pyrus fell out on the same reasoning (see the header of
`RussianTrackers.swift`), and that is cheaper than a button that says nothing.

What would unblock the work: access to an organisation in Yandex 360 where the
search method can be called and its answer seen. Until then, the "Notes" row stays
in the list of things not done rather than in the list of integrations.

**Yonote was checked on 2026-08-18 and does not close this section.** The candidate
looked suitable: a product of the same kind as Outline, and Outline is already
connected here — so if the shape matched, the connector would be nearly written.
The check did not bear that out. The developer pages (`yonote.ru/developers`, the
same address with `?v=2`, `docs.yonote.ru`) serve navigation with no method
descriptions: neither the address, nor the search parameter, nor the response shape
is visible from outside. Third-party MCP clients agree on the base address
`app.yonote.ru/api` and token access, but one of them can only enumerate documents
(`documents_list`, `documents_info`), and enumeration does not count as search — by
the same rule that removed Pyrus and Yandex Wiki.

Somebody else's implementation cannot settle this question at all: it shows that it
worked for someone, not that the vendor promises it. What unblocks it is either a
public description of the method, or an account where the call can be made and its
answer seen.

### 2.2 The connector blueprint (as built, not as intended)

Five trackers are already written, so the blueprint describes working code —
`mvp/Sources/OrakulCore/RussianTrackers.swift` and its store. A new connector
repeats this shape; departing from it requires a reason in a comment.

**1. Three fields instead of one.** A token is almost never enough, and it falls
short in different ways:

| Field | What for | Example |
|---|---|---|
| token | access | a Yandex OAuth token, a Kaiten API key |
| second field | without it the request goes to the wrong place | `X-Org-Id` for Yandex, the team domain for Kaiten |
| destination | where to put a filed task | the `TREK` queue, board `4`, a column |

Each field's label lives next to the code that uses it (`secondaryPrompt`,
`destinationPrompt`) rather than in the interface: in the interface it drifts away
from its purpose at the first edit.

**2. Reading and writing are different rights.** `isConfigured` permits asking,
`canFileTasks` permits filing. A tracker connected read-only is a normal state, not
a half-finished one: the destination is needed only for writing.

**3. HTTP comes from outside.** `RussianTrackers.HTTP` is a closure — `live` on
`URLSession` in production, its own in a test. There is deliberately no default in
the initialiser: otherwise a forgotten argument in a test would quietly reach
somebody else's service.

**4. An 8-second deadline** — the same as for MCP sources. One wedged service costs
one source rather than the whole answer. That is the brief's low-latency
requirement, expressed as a number.

**5. Errors are distinguishable.** `notConfigured` / `unauthorised` / `forbidden` /
`rateLimited` / `tooLarge(bytes)` / `http(code)` / `vendor(code, description)` /
`webPage` / `unreadable`. The difference is not cosmetic: the first is fixed in
settings, the second by a new token, the third by waiting (and only by waiting: the
word "error" here would send a person to reissue a perfectly good token), the
fourth also by waiting but with an unknown cause, the fifth relays the service's own
words, and the sixth means the service changed its format and the connector needs
fixing.

`tooLarge` belongs to the same family: a service does not have to lie in order to
do harm, it is enough to answer with two hundred megabytes, and they will be parsed
on a person's machine in the middle of a call. Eight megabytes is a ceiling with
room to spare: a hundred tasks with descriptions weigh tens of kilobytes, and a
limit that trips on a normal response is a denial of service arranged against
oneself.

`forbidden` was separated from `unauthorised` in the engine long ago, but on
2026-08-19 it turned out that four family wrappers were collapsing it back. A 403
means the token is genuine and the search right was not granted to it: in GitLab
that is the `read_api` scope, in messengers a separate application right. The advice
"reissue your token" on a 403 yields the same token and a lost evening. The check
`test/perevod-oshibok.test.mjs` prevents distinct engine errors from collapsing into
one family error without a note that it is deliberate.

`webPage` was split out of `unreadable` on 2026-08-19. The cheapest way to cut you
off is not a 401 but a sign-in form: that is what an expired single-sign-on session
answers with, what a hotel Wi-Fi portal answers with, and what a service that would
rather not say "no" answers with. All three send code 200 and markup, so they look
like working operation. "Answered unintelligibly" sent a person to check the address
and the server version, when the address is right and what needs fixing is the
session or the network connection. It is recognised by the START of the body: a task
quoting `<html>` in its description is an ordinary thing, and mistaking it for a
sign-in form would break a working search.

`rateLimited` was split out of `http` on 2026-08-18, while working out how an
unfriendly service can do harm without blocking: throttling is cheaper than closing,
and it looks like ordinary operation. If the service sent `Retry-After`, the number
reaches the person.

**5.1. Success does not mean consent.** Bitrix24 answers `200` and puts the refusal
in the body: `{"error": …, "error_description": …}`. A connector that looks only at
the response code will show a revoked webhook as "no tasks found". Checking the body
before parsing the list is a rule, not a Bitrix peculiarity: many corporate APIs
behave the same way.

**5.2. An empty list only in a familiar shape.** A response without a single known
key is a refusal, not "there is nothing". `[]` and `{"content": []}` pass, because
the shape is recognised and there are zero rows; `{"detail": "…"}` does not. That
difference decides whether a person files a second task on top of an existing one.

**6. Read leniently, write strictly.** In search results a task with no title is
shown as "Без названия" — one malformed record is not worth the whole result set.
On creation it is the opposite: a response with no task key is an error, not a
success. Saying "the task was filed" when it was not is the worst thing a connector
can do.

**7. A hint instead of a bare goal.** What goes to the tracker is not "what did we
decide about deadlines" but the goal plus
`ConnectorProbeStrategy.trackerProbe.queryHint`: their ranking leans on the words in
tasks.

**7.1. Credentials do not have to travel in a header.** In Bitrix the webhook is the
path: `/rest/{id}/{code}/method`. Two consequences follow. First, the general "the
key travelled" check must not require a header — otherwise the service either drops
out of the check, or gets a header invented for it that the vendor does not expect.
Second, such a service's address must not be shown in an error message: the key is
inside it.

**7.2. The page size is not always ours.** In Bitrix it is always fifty and cannot
be set by a parameter, so the requested bound is applied after parsing. Silently
returning fifty where ten were asked for means quietly inflating the hint and eating
other sources out of a shared budget.

**8. We claim nothing without the vendor's documentation.** The method, the address,
the search parameter and the response shape are verified in the vendor's reference
and cited in a comment. Pyrus and both knowledge bases were filtered out by this
rule; WEEEK appeared only after a verifiable method page was published. That is
cheaper than a button that does not work.

**Architectural consequence.** Cruxwing's existing MCP connector layer is the
right substrate: each of these becomes a connector descriptor rather than a
special case, and the grounding deadline already in
`MCPConnectionManager.groundingDeadline` (8s — one wedged app costs one source
instead of the run) is exactly the latency discipline this brief asks for. The
blueprint work is therefore *connector descriptors + auth*, not new
architecture. Per-connector blueprints: next iteration.

---

## 2.3 Filing tasks into a tracker: what the APIs allow (verified 2026-08-11)

Reading from a tracker already works. The reverse path — filing a task from a
decision made on a call — runs into the fact that every service needs a destination
address, and each one's is different:

| Service | Method and path | Required fields |
|---|---|---|
| Yandex Tracker | `POST /v3/issues/` | `summary`, `queue` (the queue key, for example `TREK`) |
| Kaiten | `POST /api/latest/cards` | `title`, `board_id` (an integer) |
| YouGile | `POST /api-v2/tasks` | `title`; `columnId` — the column to put it in |
| WEEEK | `POST /public/v1/tm/tasks` | `title`; `locations: [{projectId}]` — a numeric project |

The shape of the settings follows from this: one token is not enough. Besides the
second field (the organisation for Yandex, the team domain for Kaiten) a third is
needed — exactly where to put the task. Without it, a "File a task" button would be
a button that sends a request into nowhere, and the error would arrive after the
call had ended.

The documentation disagrees with itself about YouGile: `columnId` is marked
optional in places. We require it anyway — a task with no column does not reach the
board, that is, it disappears from the user's point of view, and a redundant valid
parameter is never an error.

## 3. Model strategy

The brief asks for Russian fluency at minimum viable cost. The evidence says
those two goals do not point at the same model, and the honest read is
uncomfortable for a "use a Russian model" instinct:

- On the Russian-language **MERA** benchmark, GigaChat 3.1 Ultra scores **0.712**,
  above GPT-5.2 at 0.707 and well above GPT-4o at 0.642.[^llm-compare]
- On **12 practical tasks** tested 2026-07-15, GigaChat and YandexGPT **did not
  win a single one**.[^llm-compare]

A benchmark win and a practical loss in the same month is the clearest possible
warning against picking a model from a leaderboard. It is the same mistake as
choosing a diarization threshold from a tiny fixture set: the result does not
generalize to real calls.

### 3.0 GigaChat: not a judgement about the model but about the trusted root store (verified 2026-08-13)

GigaChat is not in orakul's provider list, and the reason is not quality. TLS does
not reach it from an ordinary macOS: the chain ends at the Ministry of Digital
Development's root, which is not in the system store.

A `curl` measurement, 2026-08-13:

| address | `ssl_verify_result` | what it means |
|---|---|---|
| `ngw.devices.sberbank.ru:9443` (exchanging a key for a token) | 19 | a self-signed certificate in the chain |
| `api.giga.chat` (OpenAI-compatible) | 20 | the issuer was not found locally |

The first one's chain: `CN=ngw.devices.sberbank.ru` → `Russian Trusted Sub CA` →
`Russian Trusted Root CA` (The Ministry of Digital Development and
Communications).

**Why this settles the question.** A "Connect" button that fails with "the server's
certificate is invalid" is worse than an absent button — the rule from CONTRIBUTING.
The application should not and will not install a root certificate on a person's
behalf: that changes trust for the whole system, not the settings of one product.

**What would change the conclusion.** A user who installs the Ministry's root
themselves gets a working OpenAI-compatible address `https://api.giga.chat/v1` with
a Bearer token. The token there lives thirty minutes and is obtained by exchanging a
key at `/api/v2/oauth` — that is not a static key like the other eight providers'
and would need a refresh branch of its own. If the root appears in macOS by default,
or Sber issues a chain from a generally trusted authority, this note goes stale.

**Decision for v1:**

1. **Open-weight first, Apache-2.0 by preference.** Qwen (3.6/3.7 series) is
   Apache 2.0 with strong multilingualism and tool use; DeepSeek V4 (MoE) is
   credible on price/quality.[^llm-oss] Permissive weights matter doubly here
   because the product itself ships open-source — a research-only licence in the
   default path would poison the repo's own promise.
2. **Domestic models as a routed option, not the default**, for teams whose
   requirement is data residency and local context — exactly the case where the
   comparison says they win.[^llm-compare]
3. **Own eval before adoption.** No model enters the default path on a published
   benchmark. The eval must be Russian *developer speech* — meeting audio with
   English technical terms inside Russian sentences — because that is the actual
   input, and it is not what MERA measures.

`RecallEmbedder` already routes by detected language, and the whole-file glossary
restore is measured WER-neutral, so the Russian path has existing bones. The
`DomainLexicon` will need a Russian-market vertical pack (banking/gov/telecom
acronyms) built under the same collision-audit rule that keeps ordinary words out.

---

### 3.1 The user enters the provider key (done)

Something easy to forget follows from the "there is no server" decision: the
finished installer contains not a single provider key — they are deliberately not
put there — which means that without a user's key the application does not answer at
all. A downloaded application that cannot answer a single question is not a free
product but a broken one.

Cruxwing removed key entry when the server gateway appeared: the keys moved to the
server and `Secrets` became empty. orakul inherited that code without the gateway,
that is, the worse half of the decision.

Hence `ProviderKeyStore`: the key is entered under "Настройки → ИИ → Ключи
провайдеров", lives in the Keychain, and takes precedence over anything baked in at
build time. The order is deliberate — the reverse would mean that a key from
somebody else's `.env`, accidentally caught in a build, silently overrides the one a
person has just typed and can see on screen.

A side effect that matters for positioning: spending runs on the user's own contract
with the provider. There is nothing for us to charge for, because we do not stand in
that chain — the same ground on which the product has no plans.

The order of providers in the list: DeepSeek, Qwen, GLM and Kimi first, then OpenAI,
Anthropic, Google. The basis is the expected price of a request, and nothing else.
There are references for Qwen and DeepSeek above; for GLM and Kimi we made no
measurements of our own, and what used to stand here was "cheaper with acceptable
Russian" — a quality judgement nobody had checked. The order in the list does not
substitute for it.

---

## 4. Product shape

**Russian interface.** Not a translation layer bolted on: this branch ships
Russian-first. Two rules from the existing codebase carry over — the app must not
recase ordinary Russian words (the `GlossaryRestore` collision audit), and the
vowel set in garble detection already covers Cyrillic, without which every
Russian word reads as "vowelless" and becomes fair game for fuzzy repair.

**The wedge**, in one line: *the call is the source of truth, and orakul makes it
searchable in Russian.* Answering «что мы решили по ценам?» from your own past
calls is something no Habr thread and no Telegram chat can do, because the
material is yours.

**One shape of error recurs more often than all the others put together.** Not a
crash and not a wrong calculation, but *a confident sentence about something that
did not happen*. In one night it was found eight times, and every time it looked
like working operation:

| what the person saw | what actually happened |
|---|---|
| "В сохранённых звонках об этом не говорили" | the archive is empty, there are no calls at all |
| the same | some of the archive files would not open and were not searched |
| the same | the question is all function words, search never ran |
| "Удалено: <identifier>" | no such meeting existed |
| ten tasks from the tracker | there are forty-seven; the first ten were shown |
| "Трекер ответил непонятным образом" | the server answered a clear 502 |
| `[#314, unknown]` | the service reported no state; it was invented |
| "В сохранённых звонках об этом не говорили" | the question has a one-letter typo; §6.8 |

The eighth case is the same sentence for the fourth time, and that is worth saying
plainly: of eight cases, four landed on a single message. A confident sentence
breaks not where it was written but where a new way of reaching it appeared. Such
sentences therefore have to be checked not once, but every time a new path to them
is created nearby.

What all eight have in common: the product asserted the result of an operation that
never took place. For a tool whose only promise is "answers with a quote and does
not invent", that is the principal class of defect: it does not break the work, it
quietly substitutes for it. Tests do not catch it, because the code does exactly
what it was meant to; it is caught only by running the built product and asking "is
that true?" of every confident sentence.

Hence the rule for new messages: **if a sentence asserts an outcome, find the case
where there was no outcome, and say so separately.**

**The 2026-08-13 sweep: where an error still turns into a happy result.** After
Bitrix, every place where parsing a response could return emptiness instead of a
refusal was checked. Closed: `RussianTrackers` (an unfamiliar shape, and a refusal
with code 200) and `SessionStore` (an unread archive directory). No `?? []` is left
in the core.

`FirefliesPastCalls` was the last one closed: parsing the meeting list returned an
empty list both when the response could not be understood and when there genuinely
were no meetings. Through import that showed as "there are no past calls" — and if
the service changed its schema, a person would have concluded there was nothing to
import.

It was done as written down: `parsedMeetingList` returns `nil` on an
unintelligible response, import raises an error on `nil`, and the old shape stayed
as a thin wrapper for the places where there is nothing to distinguish — nine checks
did not have to be touched.

**Separately: a check that will not exist (2026-08-13).** The fan-out of sources for
a hint is assembled as a task group: five connected trackers are polled at once
rather than in turn, otherwise each one's eight-second deadline would add up to
thirty-two seconds in the middle of a call. That is true, but **it could not be
pinned by a check**.

Two attempts, both hollow:

1. Counting `group.addTask` with a threshold of "at least three" — deleting a whole
   family of sources compiles and leaves the counter above the threshold.
2. Naming the families in the file — the names remain in declarations and arithmetic
   even after the polling itself is deleted.

Mutation exposed both. Measuring duration is even less suitable: on a loaded machine
a sequential fan-out fits in the same milliseconds, and such a check would fail for
a random contributor while saying nothing about the product.

The check was deleted. A green check that catches nothing is worse than an absent
one: it closes the question. Here the question is left open honestly.

The sweep's result: emptiness is nowhere passed off as an answer any more. Each case
has checks on both sides: returning to silence fails them, and so does declaring
genuine emptiness an error. The second half matters as much as the first: without
it, "nothing found" would disappear from the places where it is true.

**The class has a second half, found on 2026-08-13: not an assertion about an
outcome, but an instruction that will not work.** It has to be checked differently —
the question is not "is this true?" but "will it work for someone who follows it?".

| what is written | what happens to someone who follows it |
|---|---|
| "platform.moonshot.cn → API keys" beside the key field | a key from there answers 401: the request goes to `api.moonshot.ai`, and registering on the Chinese half is usually impossible without a local phone number |
| README: "Building the installer: `MEETGPT_ARCH=arm64 ./notarize.sh && ./dmg.sh`" | one DMG of two is built; the second stays at yesterday's build, while the audit example requires both to be passed explicitly |

Both halves of one fact — the console and the request address, the build command and
the explicit arguments of the image audit — drift apart precisely because they sit
separately. Hence the second rule: **keep the halves together or tie them with a
check**; `ProviderConsoleMatchTests` and the README-against-`audit-dmg.sh` check
exist for exactly that.

---

## 5. Business model — free, entirely

The owner's decision: there are no paid tiers. Not "prices have not been set yet"
but none at all — plans, paid buttons and subscription gating were removed from the
product, from the catalogue, from the page and from the code.

This is not only about money. The boundary ran along infrastructure: free was what
is computed on the user's machine, paid was what we pay for. With the second half
removed, the product gains a property that previously had to be promised in words:
**everything works without the network, because there is simply nothing else**. A
button that requires the network no longer loads — not as a matter of taste, but
because a catalogue containing one fails a check at build time.

What was deleted:

- `config/plans.ru.json` and its tests — the tier catalogue;
- the `to-tracker` and `week-digest` buttons — the only ones needing our server;
- the buttons' `tier` field — the place where a paid tier grows back;
- `PromptCatalog.Tier`, `available(for:)`, `unavailabilityReason(...)` — the gating
  mechanism, which now has nothing left to gate;
- the "Тарифы" section on the page.

The metric is unchanged: stars and installs. It became more honest — in a repository
with nothing to sell, the README is the entire marketing.

**What it costs.** The tracker connectors and the weekly digest were the
justification for a paid tier; they left with it. That is a deliberate trade: a
product that works entirely on the device is easier to promise and impossible to
spoil by quietly moving a feature behind a paywall.

### 5.1 The server address is not baked in — and that is checked at build time (2026-08-12)

The "there is no server" decision is not enough while a place remains in the code
where an address can return. On 2026-08-12 it turned out that it was there:
`build.sh` honestly left `BACKEND_URL` empty for a DIST build, and
`Config.backendBaseURL` substituted a default production address for the empty
value — `api.cruxwing.ai`, another product's server, which exists and answers.
Because of that, account sign-in, billing and the promise of "models without your
own keys" came alive in the orakul installer.

Hence a rule, not a one-off fix:

1. `build.sh` in DIST mode **prints an empty string** for `BACKEND_URL` and
   **stops the build** if the value is non-empty. The check is inverted relative to
   cruxwing: there a working-copy address was forbidden while a production one was
   mandatory; here any address is forbidden.
2. `Config.resolveBackendBaseURL` returns an empty string and **substitutes
   nothing**. The parsing was lifted out of the computed property into a separate
   function precisely so it could be checked against all inputs rather than only the
   one the developer's machine was built with.
3. Everything requiring a server is gated on `backendBaseURL.isEmpty`: sign-in (four
   places), the "Аккаунт" settings section, the "Проверить в вебе" button, the
   credits rail. `NoBackendPromisesTests` checks the screen's **rendering**, not the
   presence of a line in the source.

Why in this much detail: the error was invisible to every check that read
configuration. The only way to see it was to mount the built DMG and look for the
address in the binary. That is the checking rule for the whole project: check what
goes to the user, not what it was assembled from.

---

## 6. Russian ASR on developer speech — the top risk, now measured by others

This was named the highest technical risk in v1 because every downstream feature
reads the transcript. The research changes the risk from unknown to *known and
addressable*, with one large caveat about how it is usually measured.

### 6.1 The published numbers are not measured on speech like ours

GigaAM's headline **3.3% WER on CPU** — reported as 2.4× better than Whisper
large-v3-turbo on an RTX 4090 — was measured on **TTS fragments from
audiobooks**, and conclusions shifted once real production recordings were
used.[^asr-gigaam] Clean-speech accuracy for the best Russian systems is
**95–98%**, but real conditions (noise, interruptions, accents, rare terms) are
explicitly called out as where that falls apart.[^asr-accuracy]

An audiobook is the one input a meeting never is: one speaker, no interruption,
studio audio, no jargon. This is the same fixture-versus-reality trap already
paid for twice in this codebase — the diarization threshold chosen from three
files, and the speaker-count metric that was uncorrelated with attribution.
**No ASR model
enters the default path on a published WER.**

### 6.2 Code-switching is the specific failure, and we already built for it

Russian developers do not speak Russian. They speak Russian with English
technical terms inside the sentence, and that is a named ASR failure mode:
mixing languages leaves parts of the recording unidentifiable, and algorithms do
poorly on narrow technical terms absent from their training
data.[^asr-codeswitch]

This is precisely the case `GlossaryRestore` exists for. The decoder-prompt
glossary was measured harmful at scale (term recall bought by deleting speech —
WER 0.95 with 2757 deletions on the large tier), so the whole-file pass decodes
with **no glossary at all** and vocabulary is restored afterwards as text, where
a mistake can only touch one token and can never make speech disappear. The
architecture answering the top risk is already written and measured.

### 6.3 Whole file, not chunks

VAD chunking physically segments speech and causes hallucinations and word loss
at segment boundaries; complete audio is recognised **better than the sum of its
parts**.[^asr-gigaam] Cruxwing's whole-file post-call pass is therefore the right
shape and must not be "optimised" into chunked decoding.

### 6.4 Measured by us, on Russian developer speech

The first measurement of our own rather than somebody else's benchmark. The corpus:
three fragments of a Russian talk on AI safety (`cruxwing-api/data/russian`),
transcribed by three engines — Whisper large, Parakeet, Fireflies. There is no
human-annotated reference, so WER was not computed; what was computed is the
disagreement between the engines, because disagreement by itself proves an error.

| fragment | terms spoken | disputed | agreement |
|---|---|---|---|
| w900 | 4 | 2 | 50% |
| w2700 | 8 | 1 | 88% |
| w4300 | 4 | 1 | 75% |
| **average** | | | **71%** |

Whisper and Parakeet disagree on **11–14% of words**. On fragment w2700 Parakeet has
57 omissions against 3 insertions — the engine is not making mistakes, it is falling
silent, and that is exactly the ailment an aggregate WER cannot tell apart from
distortion.

**The disputed terms are precisely code-switching:** "прод", "промпт", "API",
"джейлбрейк". Russian phrases with English roots, exactly where the research
predicted the failure.[^asr-codeswitch] Not one disputed term turned out to be an
ordinary Russian word.

The conclusion for the product, and it confirms the architecture: fixing this in the
decoder is pointless — a term the model has never heard it will not hear with a hint
either. It is fixed after transcription, as text, where a mistake costs one token
and cannot swallow speech. That is, `GlossaryRestore` with a Russian lexicon is not
an "improvement" but the principal mechanism for this market.

### 6.5 Candidate models

| Model | Why it is a candidate | Caveat |
|---|---|---|
| **T-one** (T-Bank) | 70M params, streaming, and reported to lead open models on **noisy, compressed call-centre Russian** — beating GigaAM v2 (242M) and Whisper large-v3 (1.5B) on internal benchmarks[^asr-tone] | "Internal benchmarks"; call-centre audio is closer to a meeting than an audiobook, but is still not a meeting |
| **GigaAM** | Strong Russian numbers, CPU-viable | Headline figure from audiobook TTS[^asr-gigaam] |
| **Whisper** (current engine) | Already shipped, multilingual, handles code-switching by design | Beaten on Russian by both above, on their own benchmarks |

**Decision:** T-one is the first model to evaluate, on our own corpus, against
shipped Whisper. Streaming at 70M parameters is the right shape for on-device.
The eval set must be *Russian developer meeting speech with English terms*, and
it must be built before any model is adopted — the corpus is the deliverable, not
the model choice.

---

## 6.6 The product's vocabulary is set by the demo film, not by a translator

orakul's Russian copy is checked against
`cruxwing-marketing/public/demo-film/scene.ru.js` — an already-recorded Russian
track, that is, the product's voice as people have heard it. I managed to write my
own variant first and diverged from it on three words:

| In the film | What I had |
|---|---|
| **звонок** ("Резюме звонка", "об этом звонке") | созвон |
| **слепые зоны** | спорные места |
| **владелец**, "без владельца" | "ответственный не назван" |

Every one of my words is ordinary Russian. The problem is not the words but that
two words for one thing read as two different products: a user who sees "звонок" in
the film and "созвон" in the application concludes they are different things.

It is checked by a test that reads the track file itself rather than a copy of it:
diverging silently is no longer possible.

---

## 6.7 Cases: the central promise did not work on an entire class of words (verified 2026-08-14)

Search reduces the question's word and the speech's word to one stem by trimming
endings. The class of nouns ending in "-ние" drifted apart entirely:

| Said on the call | Asked | Speech stem | Question stem |
|---|---|---|---|
| развёртывание | развёртыванием | `развёртыван` | `развёртывани` |
| обновление | обновления | `обновлен` | `обновлени` |
| решение | решению | `решен` | `решени` |

The nominative lost "ие" entirely, the oblique cases only the last letter. Two
different stems for one word — that is, an honest "в сохранённых звонках об этом не
говорили" about something that was in fact discussed. The class is ordinary work
vocabulary: развёртывание, обновление, подключение, решение, тестирование,
согласование, требование. Adjectives drifted the same way in the instrumental:
"годовой" → `годов`, "годовым" → unchanged.

**What catches this and what does not.** Not one of 3006 checks was failing. The
result-quality measurement (`hit@1` on ten questions of a realistic shape) showed
10 out of 10 before the fix and 10 out of 10 after — this class is absent from the
corpus. It was found by running search on ordinary Russian words, not by reading
code and not by measurement.

**What was fixed.** The ending list gained the "и" family ("иями", "ием", "ией",
"иям", "иях", "ия", "ию", "ии") and the adjectival instrumental ("ым", "им"); the
trimming loop starts at four characters, otherwise the longest ending never fires.
Hyphenated compounds now enter the index both whole and in parts: "кластер" finds
"Kubernetes-кластер".

**In the application this did not exist at all.** Word analysis there amounted to
"a lexicon term or the word as it is" — no ending trimming whatsoever, alongside a
comment saying the step was the same as in the command line. For a Russian question,
the intersection of word sets is the whole of search: the other half is the macOS
system model's embedding, and that model is English-language. Both sides now call
`RecallIndex.searchToken`.

**What ending trimming cannot and will not do.** A verb is not reduced across aspect
and derivation: "выкатываем" will not be found by "выкатить", nor "переносим" by
"перенос". That is not the same flaw — suffix trimming cannot do it in principle,
and a real stemmer (Snowball) does not reduce that pair either. It is written on the
page plainly rather than passed over.

## 6.8 A typo was passed off as the absence of a conversation (verified 2026-08-14)

Found by running it rather than by reading the code: the same way as §6.7. An
archive of one call about pricing, six queries typed in a row.

| Query | What happened | Why |
|---|---|---|
| `тариф`, `ТАРИФЫ`, `деплоя` | finds it | stem and case agree |
| `что решили по тарифам` | finds it | function words are discarded |
| `тарифф` | "в сохранённых звонках об этом не говорили" | an extra letter |
| `рскатываем` | the same | a missing letter |

Search is lexicon-based, and a one-letter miss matches nothing. That in itself is
not the flaw — the flaw is what was said in reply. The sentence "об этом не
говорили" is an assertion about the archive's contents, and a person leaves
convinced the topic never came up, when it is sitting one line above. A single typo
is the commonest way to fail to find something that is right there; for an audience
typing a question between two calls, that is not a rare case.

**What was done.** On an empty answer, the archive's words are searched for ones
that differ by a single typo: an extra letter, a missing one, a wrong one, or two
adjacent ones transposed (`RecallIndex.isOneEditApart`). Transposition is not a
luxury: "таирфы" is typed no less often than "тарифф", and through substitutions
that distance is two. What is found is shown — "Похоже на опечатку — в архиве есть
«тарифам»" — and is not substituted silently: replacing the question means answering
a different one.

**Boundaries drawn deliberately.** Words shorter than four letters get no
suggestion: for "код" one letter is a third of the word, and "кот" is "similar" to
it in exactly the same way. A word that is in the archive gets no suggestion even if
something similar sits beside it. A miss in the ending did not need fixing: "тарифя"
is found as it is, endings being discarded on general grounds. The first draft of
the check demanded a suggestion for that too — that is, demanded that the whole be
repaired.

**The cost.** For the sake of the words' spellings, the first draft re-parsed the
entire archive: over 608 thousand words a miss cost 4.52 s against 2.52 s for a hit
— an extra 1.8 s, exactly the cost of building the index. Now similar words are
sought among the already-parsed stems, and the text is reached only to recover the
spelling of the stems found, with the pass breaking off as soon as each has one: a
miss takes 2.19 s, cheaper than a hit. `SearchPerformanceTests` holds this by
comparing the suggestion's time against the parsing time in the same run: an
absolute ceiling here would lie along with the machine's load.

Checks: `NearMissTests`, twelve of them. Five properties are confirmed by damaging
the source; the sixth, the early exit on a length difference, does not break under
damage, and that is recorded beside it — the pass cuts off a two-letter difference
even without it.

## 7. A separate application, and why Windows comes first

**orakul is not a Cruxwing build under a different name.** The identity is fully
separated (`config/app.json`, checked by `test/identity.test.mjs`): bundle id
`ai.orakul.desktop` against `com.meetgpt.macapp`, its own installer volume, its own
set of settings and its own Keychain service.

This is not cosmetic. macOS ties the screen-recording and microphone permissions to
the bundle id: if they coincide, two programs share one grant, and revoking it from
one without taking it from the other is impossible. A shared `UserDefaults` suite
would mean that installing orakul changes Cruxwing's settings on the same machine.
The installers are named `orakul-*` and go into a directory of their own — a file
named Cruxwing cannot be overwritten and vice versa.

### 7.1 Windows: not "later", and possibly ahead of macOS

Cruxwing is a native macOS application: capture through ScreenCaptureKit, models
through CoreML. In the Russian market that constraint bites harder than in the
American one: the corporate fleet here is predominantly Windows, and a product for
developers available only on a Mac cuts off most of the audience before the first
launch. **ASSUMPTION** — the macOS share among Russian developers has not been
measured, and that is the next research question; but the direction of the error is
clear.

What a port actually costs (an honest estimate, not "recompile it"):

| Layer | macOS today | Windows |
|---|---|---|
| System audio capture | ScreenCaptureKit | **WASAPI loopback** — an entirely different implementation |
| Transcription | CoreML | ONNX Runtime / whisper.cpp — the same model, a different runtime |
| Meeting search, glossary, answers with a quote | shared code | **ports unchanged** |
| Interface | SwiftUI | a separate layer |

The core — the thing the product exists for — is platform-independent. What is
platform-specific is capture and the shell. That makes Windows expensive but not "a
second product": the boundary runs where it already runs in the code.

---

## 8. Telegram: fragmentation that has a number

Telegram is the de facto replacement for the forum, and its trouble is structural
rather than cultural. Every source is collapsed into one chat feed, so finding what
you need is hard by design.[^tg-search] The scale is visible in somebody else's
attempt to fix it: the author of the "StackOverflow from Telegram IT chats" project
joined roughly **250 topical chats** by hand and used a separate service to filter
question-shaped messages out of the general stream.[^tg-so] There is no shortage of
channel search tools (Teleteg, TGStat) and directories (TLGRM) — that is, everyone
acknowledges the problem and solves it from outside, by searching other people's
chats.[^tg-search]

**The conclusion for orakul, and it is a limiting one.** The temptation is to "build
search over Telegram chats". That is a mistake for three reasons: other people's
chats are not our content, an answer in a chat has no status as a decision, and a
market for such search tools already exists. orakul's value is the opposite: **not
finding an answer among strangers but finding it in your own calls**, where it has
already been said and where it has an author and a date. Telegram appears in the
product as a context source for your own team (your own chats, by explicit
connection), not as a search index over the ecosystem.

---

## 8.1 Telegram: old history is unavailable, new history is archived (verified 2026-08-16)

§8 measured the fragmentation and named search over work chats the obvious
continuation. Checking the Bot API closes that: **a bot can neither read nor search
history**.

- `getUpdates` returns only new events and keeps undelivered ones for **no longer
  than 24 hours**;
- it does not see messages sent before the bot was added at all;
- there is no "find in the conversation" method in the Bot API.

So an honest "search across your entire Telegram history" connector does not exist.
The only way to reach old history is MTProto with a user session — that is, asking a
developer to hand the application their personal Telegram account. For a product
that promises everything stays on the computer, that is not an implementation detail
but a change of promise.

What is implemented is the narrower path that requires nobody's account: a separate
bot, added to explicitly allowed supergroups, receives messages **from the moment of
connection**. Privacy Mode must be off, or the bot must be an administrator. Orakul
checks this on connection, saves the token in the Keychain and the messages in a
local archive, and performs search with the same `RecallIndex`. The bot sends
nothing. Disconnecting deletes both the token and the accumulated archive.

This is a prospective-only integration, not a history import. The interface
therefore says so outright: "история начинается после подключения". For old messages
what remains is an explicit import of the user's own export; the product will not
disguise an MTProto session as an ordinary API token.

---

## 9. GitHub integration (architecture draft)

The project's metric is stars and installs, so GitHub here is not "one more
connector" but the shop window. Two different things that must not be confused:

**9.1. The repository as the product.** An open core under Apache 2.0. What decides
the fate of a star: a README that runs first time, and a clear boundary between open
and paid. The rule: everything that processes the user's speech is open; only what
runs on our infrastructure is closed.

**9.2. GitHub as a context source.** It ties a call to the code: the discussion
"let's split billing into a separate service" and the PR that does it are one
decision in two places.

| What | How | Why this way |
|---|---|---|
| Reading issues/PRs | GitHub REST + an MCP connector | The same layer as the trackers: a connector, not a special case |
| Tying a decision to a PR | by the number and the branch name spoken on the call | A PR number in speech is the most reliable anchor; it is recognised as a digit, not a term |
| Writing back | a draft comment, sent by a person | The product's rule: it sends nothing itself |
| Privacy | only on an explicit repository connection | Code does not reach the model without separate consent |

**Latency.** The same deadline as the other connectors (8 s): one wedged source
costs one source rather than the whole answer.

---

## 9.1 GitHub: why a token rather than OAuth (verified 2026-08-12)

The draft above assumed a connection like the others: through MCP, in one click. A
live check refuted that.

`https://api.githubcopilot.com/mcp/` answers per the specification: 401 and a
`WWW-Authenticate` carrying a metadata address. The resource metadata points at the
authorization server `https://github.com/login/oauth`. Its metadata sits at a
non-standard path (`/.well-known/oauth-authorization-server/login/oauth` rather than
under the issuer) and contains:

```
authorization_endpoint: https://github.com/login/oauth/authorize
token_endpoint:         https://github.com/login/oauth/access_token
code_challenge_methods_supported: ["S256"]
registration_endpoint:  ABSENT
```

PKCE is there, **dynamic client registration is not**. The application's entire MCP
catalogue is built on it: the client registers on the fly and the user sets nothing
up in advance. For GitHub that path is closed.

The second option — a pre-registered OAuth application with a baked-in secret, as
with HubSpot — does not work either: secrets deliberately do not reach the finished
installers (`build.sh`, `SECRET_VARS`), so in a downloaded orakul that line simply
will not exist.

What remains is a personal token — something GitHub supports itself, and which
matches how the rest of the product is arranged: provider keys and tracker tokens
are pasted in by hand. Implemented in `GitHubConnector`, searching through
`GET /search/issues`.

Two details found on the live API and pinned by tests: without `is:issue` GitHub
answers 422 to some tokens, and the API version is fixed by the
`X-GitHub-Api-Version` header — otherwise the response format is free to change
under us. Repositories are mandatory: without them search runs across the whole of
GitHub and brings back other people's issues, indistinguishable from the team's own
context.

---

## 10. What is still unknown

1. ~~Telegram dev-chat structure and technically honest connector boundary~~ —
   researched and implemented in §8.1. Remaining unknown is adoption: whether
   teams will connect their own work chats. That is now a tester question, not
   an architecture guess.
2. ~~Willingness to pay, and where the tier boundary sits~~ — the question was
   removed by a decision: there are no plans, and that is pinned by
   `NoTariffsTests`. The paid boundary is not being sought, because there is
   nothing paid.
3. ~~Note-taking tool landscape~~ — verified in §2.1. What remains is narrower than
   it was: access to an organisation in Yandex 360 is needed to call the wiki search
   method and see its answer. Without that, no connector is written.
4. ~~Whether Russian ASR quality on developer speech is good enough~~ —
   researched in §6. Downgraded from unknown to a build task: assemble a Russian
   developer-meeting eval corpus, then measure T-one against shipped Whisper on
   it. Still the top risk, but now a measurable one.

[^tg-search]: [Эффективный поиск в Telegram — Perfluence](https://perfluence.net/blog/article/kak-najti-nuzhnoe-v-telegram-rukovodstvo-dlya-prodvinutyh-polzovatelej)
[^tg-so]: [Я сделал StackOverflow из IT-чатов Telegram — Хабр](https://habr.com/ru/articles/574666/)
[^asr-gigaam]: [Как я снизил WER с 33% до 3.3% для русской речи на CPU: сравнение GigaAM, Whisper и Vosk — Хабр](https://habr.com/ru/articles/1002260/comments/); [Whisper или GigaAM для русского ASR в продакшене: три ловушки бенчмарка — Хабр](https://habr.com/ru/articles/1042574/)
[^asr-tone]: [Обгоняет GigaAM и Whisper: «Т-Банк» опубликовал T-one — iXBT](https://www.ixbt.com/news/2025/07/22/gigaam-whisper-t-one.html); [Бенчмарк качества ASR в телефонии — Хабр](https://habr.com/ru/articles/938438/)
[^asr-codeswitch]: [Технология распознавания речи: как она работает — Skillfactory](https://blog.skillfactory.ru/kak-rabotaet-tehnologiya-raspoznavaniya-rechi/)
[^asr-accuracy]: [Система распознавания речи: как работает ASR — Gravitel](https://gravitel.ru/blog/biznes/sistema-raspoznavaniya-rechi/)
[^so-decline]: [Stack Overflow умирает? Как ИИ вытесняет живые сообщества разработчиков — Хабр](https://habr.com/ru/companies/ru_mts/articles/912160/)
[^so-mod]: [Убивают ли LLM сайт StackOverflow? — Хабр](https://habr.com/ru/articles/875760/); [Почему умирает Stack Overflow — Skillbox Media](https://skillbox.ru/media/code/pochemu-umiraet-stack-overflow-i-kuda-teper-idti-za-otvetami/)
[^qna]: [Как правильно оформить вопрос на QNA.Habr — Хабр Q&A](https://qna.habr.com/q/1391680); [Правила — Хабр Q&A](https://qna.habr.com/help/rules)
[^qna-new]: Лента новых вопросов Хабр Q&A, первая страница, замер 2026-08-13: https://qna.habr.com/questions
[^habr-rules]: Обсуждение «Новые правила Хабра. Версия от 2026», комментарии, прочитано 2026-08-13: https://habr.com/ru/companies/habr/articles/1019036/comments/
[^megaplan]: Мегаплан, APIv3: авторизация и оговорка про документацию внутри аккаунта, проверено 2026-08-13: https://dev.megaplan.ru/apiv3/index.html
[^aspro]: Аспро.Cloud, страница про API без справочника методов, проверено 2026-08-13: https://aspro.cloud/api/
[^weeek-api]: WEEEK Public API, задачи: `GET`/`POST /public/v1/tm/tasks`, фильтр `search`, Bearer-токен и `locations.projectId`, проверено 2026-08-16: https://developers.weeek.net/api/task
[^trueconf-api]: TrueConf Server, REST API v4 и OAuth 2.0, проверено 2026-08-16: https://trueconf.com/docs/server/en/admin/api/ ; отчёты и записи: https://trueconf.com/docs/server/en/admin/reports/
[^jitsi-recording]: Jitsi self-host/Jibri recording: https://jitsi.github.io/handbook/docs/devops-guide/devops-guide-docker/ ; JaaS recording webhook and retention: https://developer.8x8.com/jaas/docs/jaas-prefs-recording
[^qna-noanswer]: Лента вопросов без ответа, первая страница, замер 2026-08-13: https://qna.habr.com/questions/without_answer
[^calls-quiet]: [Продуктивность в тишине: Отказ от совещаний как идеал — Хабр](https://habr.com/ru/articles/800645/); [Сколько раз в неделю – норма? О производственных совещаниях — Хабр](https://habr.com/ru/articles/834136/)
[^calls-manage]: [Как не бесить разработчиков и чётко управлять проектом](https://www.novostiitkanala.ru/news/detail.php?ID=196819)
[^calls-agreements]: [Про звонки и совещания — vc.ru](https://vc.ru/dev/1997848-effektivnye-zvonki-i-soveshchaniya-v-komande); [Созвоны, аватарки и немного тревожности — Хабр/YADRO](https://habr.com/ru/companies/yadro/articles/1062334/)
[^vks]: [Видеоконференции SberJazz](https://sberjazz.ko.ru/); [ТОП-13 платформ ВКС 2026 (on-premise)](https://iaassaaspaas.ru/rating/vks/on-premise-2026)
[^vks-alt]: [Аналоги Zoom в 2026 году — express.ms](https://express.ms/blog/obzory/alternativy-zoom-obzor-rynka-videosvyazi-v-2026-godu/)
[^trackers]: [ТОП-9 российских таск-трекеров в 2026 году — Хабр/Directum](https://habr.com/ru/companies/directum/articles/971170/)
[^tracker-api]: [Что умеют таск-трекеры в 2026 году — Хабр/YouGile](https://habr.com/ru/companies/yougile/articles/1023944/)
[^trackers-smb]: [Российские таск-трекеры в 2026: обзор рынка](https://sdelanounas.ru/blogs/175219/)
[^llm-compare]: [Сравнение отечественных LLM 2026 — AZONE-AI](https://azoneai.ru/blog/10-sravnenie-llm/); [Чем заменить ChatGPT в России в 2026 — autollab](https://autollab.ru/blog/chem-zamenit-chatgpt-v-rossii-2026)
[^llm-oss]: [Лучшая LLM для русского языка 2026 — ofox.ai](https://ofox.ai/ru/blog/luchshaya-llm-dlya-russkogo-yazyka-sravnenie-2026/)

## 11. ВКС (video conferencing): why there is no call connector to any of the four (verified 2026-08-12)

§2 named the four domestic video-conferencing platforms — Телемост, VK Teams,
SaluteJazz (formerly SberJazz), TrueConf — and left connectors to them in the plan.
Checking each one's documentation closes the question: **not one of them provides
the thing a connector is needed for**.

First, why one is needed at all, because that is not obvious. On the call itself
orakul needs nobody's API: it takes system audio, and the platform is
indistinguishable from a media player as far as it is concerned. A video-conferencing
connector would give exactly one thing — **past calls, during which orakul was not
running**: the list of meetings and their transcripts. That is what was checked.

| Platform | Meeting list | Recordings | Transcript | What blocks it |
|---|---|---|---|---|
| Яндекс Телемост | no | no | no | The API has three operations: `POST /v1/telemost-api/conferences`, `GET …/conferences/{id}`, and modification. A meeting can be created and read **by a known identifier** — it cannot be enumerated. Recordings arrive by email as a Yandex Disk link; there is no endpoint. Plus Yandex 360 for business on the organisation's domain is required |
| VK Teams | no | no | no | The Bot API is sending and receiving messages, chats, files, events. It has no calls at all. And the same wall as Telegram (§8.1): a bot sees only what is addressed to it |
| TrueConf | depends on the server | server reports | no portable one | REST API v4 and OAuth 2.0 exist in every server edition, but the exact methods and rights are documented by the server itself at `https://<server>/api/v4/docs/`. The public reference does not guarantee a portable method for listing or downloading recordings: implementing it needs the address and read-only access to that particular installation's documentation[^trueconf-api] |
| SaluteJazz | rooms | **yes** | **yes** | The only one whose API covers both recordings and transcriptions. It runs up against authorization: an **organisation SDK key** is required, and the vendor requires the transport token to be generated **on the application's backend**, then exchanged for an access token through `POST /auth/login` |

**Jitsi is a separate shape.** A current call is already detected by the browser
title or the official desktop bundle and recorded by system capture. Jitsi has no
universal cloud archive: a self-hosted recording is deposited by Jibri into the
owner's storage, and JaaS reports a finished recording by a webhook event. So a
historical import has to be configured against a particular organisation's Jibri
storage/finalize hook or JaaS webhook; there is no single "Jitsi key" for all
installations.[^jitsi-recording]

**The SaluteJazz conclusion, separately, because it is not about them but about
us.** Their API would fit. What does not fit is our architecture: orakul has no
backend on which the transport token is supposed to be generated, and there is
nowhere for one to come from — "there is no server" is checked at build time (§5.1).
Baking the SDK key into the client would mean handing the organisation's key to
everyone who downloaded the application. So this is not "we did not get to it" but a
direct consequence of a decision we made earlier and do not intend to reverse.

**What this changes in the product: nothing.** Recording a call on any of the four
platforms works today — by system capture, with no bot in the room and no vendor's
permission. What is missing is only the import of somebody else's past, and the
price of that is one line in "What is still missing", not a broken scenario.

**What would remain to be done if the decision changes.** Only SaluteJazz, and only
with a backend: `POST /auth/login` for an access token, then the list of recordings
and the meeting transcript — through the same `MCPGrounding` layer as the trackers,
with the same cache and the same live-service test (`LiveConnectorProbe`). The other
three will not become possible because we changed our minds.
