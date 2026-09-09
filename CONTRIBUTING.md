# How to take part

In Russian. Issues, pull requests and discussion are in Russian, and that is not
a formality: the project exists because a Russian-speaking developer has to
explain their problem in someone else's language in someone else's tracker.
English is accepted too — nobody will turn you away.

## Quick start

The repository is `github.com/theasder/cruxwing`. Clone it, or use the checkout
you already have.

```bash
# git clone https://github.com/theasder/cruxwing.git cruxwing && cd cruxwing
npm run doctor                 # only checks the environment, installs nothing
cd app && swift build          # Swift 6.0+ (Xcode 16+)
swift test                     # application tests
cd ../mvp && swift test        # core tests: lexicon, search, connectors
cd .. && npm test              # page, copy and identity tests
```

Nothing has to be installed by hand. But the first build of `app/` downloads
27 packages: four direct — WhisperKit, FluidAudio, MCP SDK, ViewInspector — and
twenty-three pulled in behind them (swift-nio, swift-crypto, async-http-client
and the rest of the server plumbing). You will see that many `Fetching` lines;
verified by a build from a clean clone on 2026-08-13. It needs the network and a
few minutes. `mvp/` and `npm test` pull nothing: `package.json` has no
dependencies at all, and Node runs the page tests itself.

`.nvmrc` pins Node 22 — the same line CI uses. The suite works on Node 20+, which
is declared in `package.json`; `npm install` and `npm ci` need not be run, because
the root package has no dependencies.

**If you added a file to `mvp/Sources/OrakulCore` and the application build "does
not see" it.** The error looks like `cannot find <Type> in scope` even though the
file is there and the import exists. SwiftPM keeps the file list of a path
dependency in a cache and does not notice the new file; the manifest's timestamp
does not help, because the list is computed from content. One command fixes it:

```bash
cd app && swift package clean && swift build
```

**If the installer build stops at the notarization profile.** The message names
the command: `xcrun notarytool store-credentials orakul-notary`. A human types the
password — it is not stored in the repository and must not be. The check comes
first, before compilation: on 2026-08-13 the profile vanished from the keychain,
and that was discovered after six minutes of building arm64.

The installer build does this itself (`app/build.sh`); an ordinary build does not:
cleaning costs two minutes, and there is no reason to pay them on every edit.

## What gets into the project fastest

1. **Russian strings on screen.** A task with a known number, and the direction
   reversed on 2026-09-09: the interface is moving to English. Of the 437 strings
   a person reads in `app/Sources/MeetGPT/Views` and `Onboarding`, 0 still carry
   a Cyrillic letter. That is a ceiling, not a work list: it may only fall, and
   `test/russkie-stroki.test.mjs` holds it to equality, so a new Russian string
   has to be explained exactly as much as a missed one. Vendor names stay as their
   owners spell them — «Пачка», «Яндекс Трекер» — and so does the language engine
   underneath (`RecallIndex`'s stopwords, `RussianLexicon`, the injection phrases
   the guards match on): it reads Russian speech, and translating it would stop
   the product working. Pick a screen, translate it, and lower the number in
   §6.4 in the same commit.

   The number is held by `test/russkie-stroki.test.mjs`, and held in both
   directions: if it grows the suite is red, if it shrinks it is red too, because
   the ceiling has to be lowered in the plan (`docs/ROADMAP.md`, §6.4). Do not take
   the documented `grep` one-liner from the plan as the check: it is line-based and
   cannot see a call split across two lines.

2. **A connector to a Russian service.** This is the main shortage and the main
   reason orakul is a separate product at all. Bitrix24 was connected on
   2026-08-13, but from the documentation rather than against a live portal — if
   you have a portal, the most valuable thing right now is one command from §2.0.1
   of the plan and an answer on whether search works. The sweep of the list is
   finished and the census is in §2.0.3 of the plan: five connected, three not,
   with a named reason for every "not". **Megaplan is ruled out** (no long-lived
   key, sign-in is by login and password), **Aspro.Cloud** is waiting for a
   description of its task-list method with a search parameter and a response
   shape. Find it and that is a day's work, and it is needed. WEEEK was connected
   after its public API reference was published.

   If a service is self-hosted, a live check does not depend on an account:
   `bash scripts/zhivaya-proba.sh gitea` brings the service up in a container,
   fills it with tasks, searches, and deletes the container. Gitea and Redmine were
   verified that way; adding your own service there is a useful change too.

   The secret travels in a **header**, even when the service's standard way is
   `?key=…&token=…`. The address is written in full into proxy logs, into the
   service's own access log and into error reports, and lives there longer than a
   revoked key does. Trello is exactly that case: the OAuth header was used. A
   manifest with `{token}` or `{basic}` in the path or in query parameters simply
   will not load.

   The model is `mvp/Sources/OrakulCore/RussianTrackers.swift`, and the blueprint
   with the reasoning behind every decision is `docs/RESEARCH-AND-PLAN.md`, §2.2.

   It is easier to start from the "Новый коннектор" form (New issue → Новый
   коннектор): it asks exactly the four things on which a service passes or fails —
   method, address, search parameter, response shape. If you cannot find one of
   them in the vendor's reference, open the issue anyway and write what is missing:
   that is how Yandex Wiki and Teamly were closed, and it is written down so nobody
   searches a second time.

   **Often a connector is a JSON file, not a Swift file.** The answers to those
   same four questions go into
   `mvp/Sources/OrakulCore/Resources/connectors/<service>.json`, and a shared
   engine executes them: the deadline, distinguishable errors and the rule
   "an unfamiliar response is a refusal, not an empty result" come for free. Gitea,
   GitLab, Redmine, Outline, Pachca, Plane, GitFlic and BookStack are described
   this way — you can look at them as models. Plane and GitFlic differ: they have
   no search by word, and they show an enumeration with a bound (see `scan` below).
   BookStack shows something else — `stripTags`: it highlights the match inside the
   text, and a `<strong>` in a hint read aloud during a call is not wanted. Wiki.js
   shows how to describe GraphQL: the whole query sits in the body and a refusal
   arrives with code 200, so the service's words are taken from `errors[0].message`
   (a number may appear in the path — that is a step into an array). Nextcloud
   shows what to do about Basic: `{basic}` encodes the token as base64, and a person
   writes "name:application password" on one line without encoding anything by
   hand. Trello shows how to hand a service two values: the secret stays the token,
   while the non-secret application key is declared in `parameters` and travels in
   the header with it.

   **A cloud service is not asked for an address.** If the service is one and the
   same for everybody (`api.linear.app`, `api.trello.com`), the address is written
   in code next to the enumeration rather than in a settings field: an extra field
   is an extra typo, and the person will look for the cause in their own token.
   Such connectors live in `WesternTrackers.swift`.

   ```json
   {
     "id": "сервис", "title": "Сервис",
     "docs": "https://ссылка/на/метод/в/документации/вендора",
     "verifiedOn": "2026-08-18",
     "request": {
       "method": "GET", "path": "/api/v1/search",
       "query":   [{ "name": "q", "value": "{query}" },
                   { "name": "limit", "value": "{limit}" }],
       "headers": [{ "name": "Authorization", "value": "Bearer {token}" }],
       "body": null
     },
     "response": {
       "list": ["data"], "title": ["title"], "author": ["user_id"],
       "context": null, "key": [], "state": ["state"]
     }
   }
   ```

   Substitutions: `{query}` is the person's word, `{limit}` how many rows we ask
   for, `{token}` the key from the Keychain. Paths (`["document","title"]`) read
   nested fields. The body is a string template if search goes by `POST`, as in
   Outline; quotes inside the word are escaped automatically.

   **`{queryWords}` instead of `{query}` — if the service's search parameter is a
   LANGUAGE rather than a string.** In Slack, Mattermost, Trello, BookStack,
   Rocket.Chat and Jira it is parsed as an expression: `in:`, `from:`, `@member`,
   `[tag=value]`, and in Rocket.Chat regular expressions as well. The question is
   assembled from speech on a call, and an ordinary Russian colon — "Сроки: до
   пятницы" — will be read by the service as an INSTRUCTION. There will be no error
   about it: the answer comes back about something else, and the person sees a
   confident "nothing found". `{queryWords}` strips the characters that break
   another system's search language and keeps the words. If the parameter is
   literal, use `{query}`, and it must not be translated without checking: that is
   verified separately.

   A key made of two halves separated by a colon (`mail:key`) arrives as
   `{tokenHead}` and `{tokenTail}` — they go into different headers, as in
   Rocket.Chat — or as `{basic}`, if the service accepts only Basic. For
   enumeration there are `{page}` and `{perPage}`.

   Two fields are mandatory, and without them the manifest will not load: `docs`,
   and a parameter (or body) carrying `{query}` or `{queryWords}`.

   Two more are optional but telling. `liveCheckedOn` is the date the description
   was verified against a WORKING service rather than from documentation; the list
   in the roadmap marks such services, and the mark is taken from this field rather
   than from words in a note. `stemSuffix` is the character a service uses for
   "the word starts with". A connector's third question goes as a stem ("тарифы" →
   "тариф"), because someone else's database holds "тарифами"; for a service that
   compares whole words a stem gives nothing, and there a character is needed. Set
   it only if the vendor documents it AND you have checked: in Mattermost "тариф*"
   finds things, in BookStack it finds zero — measured on live installations.

   **If the service has no search by word.** Since 2026-08-18 that is not a death
   sentence (roadmap, §7.2). A task list is accepted — but only as a declared list,
   and the code checks all three conditions, not your word for them:

   ```json
   "scan": {
     "pages": 5, "perPage": 100,
     "page":  [{ "name": "cursor", "value": "{perPage}:{page}:0" },
               { "name": "per_page", "value": "{perPage}" }],
     "match": [["name"], ["description"]],
     "more":  ["next_page_results"],
     "total": ["total_count"]
   }
   ```

   `pages` × `perPage` is the bound for one question; the engine will not allow
   more than ten pages. `match` are the fields the word is searched in on our side;
   an empty list means "a list instead of a search", and the manifest will not
   load. `more` is where the service says there is more to come; without it the end
   of the list is determined by a short page. `total` is where it names the full
   size.

   Why `total`: the engine returns coverage alongside the results, and the person
   sees not "nothing found" but "not found among the last 500 of 40,000". Those are
   different answers. If the list ended before the bound, it says so, and then the
   answer is complete.

   **If the address needs more than a host.** In Plane the project number sits
   inside the path. Such fields are declared, and a person fills them in:

   ```json
   "parameters": [{ "name": "project", "title": "Проект", "example": "550e8400-…" }]
   ```

   A substitution nobody declared will not load the manifest: `{project}` would
   travel into the address as literal characters, the service would answer 404, and
   the person would read that as a breakage rather than an unfilled setting.

   What a manifest cannot describe — and that is fine: Mattermost returns messages
   as a dictionary, Zulip requires Basic authorization from two halves, Matrix a
   nested body, Bitrix24 keeps the key in the path. Such services are written in
   code; the model is `WorkMessengers.swift`.

   **A domain lexicon pack.** There may be any number of packs: any `*.json` in
   `mvp/Sources/OrakulCore/Resources/lexicon/` is picked up on load. The format is
   the same as `base.json`, and there are two rules between packs, both checked at
   load time:

   - one word cannot be fixed differently in two packs. Otherwise the one whose
     filename comes first alphabetically wins — that is, the fix depends on a
     filename;
   - a word your pack fixes must not appear in another pack's `ordinary` list.
     Those lists are accumulated refusals ("агент" is an insurance agent), and
     overriding them silently is not allowed. If you think a refusal is wrong, that
     is a separate conversation and a separate change.

   Tool names (`infrastructure`) are not subject to the second rule: they work only
   for search, and "редис" has to stay a vegetable in a transcript.

   And the main thing: a pack is a claim about what people in such a role actually
   say. It is verified against a corpus (below), not composed from memory.

   **If you want to help with the speech corpus.** The most valuable thing missing
   is recordings of Russian technical speech with transcripts (roadmap, §6.3). A
   corpus is a folder with a `corpus.json`:

   ```json
   {"items": [
     {"id": "doklad-1", "genre": "talk", "consent": "public",
      "source": "https://example.com/доклад", "seconds": 900,
      "reference": "doklad-1.reference.txt",
      "engines": {"whisper-large": "doklad-1.whisper.txt"}}
   ]}
   ```

   `genre` is a talk or a call; they must not be added into one figure, because a
   talk is read more evenly. `consent` is the basis on which you hold the
   recording: `public` for a published talk, `participants` for a call with the
   participants' consent. Recordings without an answer to that question are not
   accepted — other people's voices are on a call. `reference` is a
   human-annotated transcript; without it only engine disagreement is computed,
   with it a real WER.

   Check before sending: `bash scripts/corpus-check.sh /path/to/folder`.

   **How to show a connector works without showing the token.** The check runs
   against a live service — which means only someone with an account there can do
   it, while the change has to be accepted by someone who has no account. A
   document is needed between you:

   ```bash
   ORAKUL_TOKEN=… ORAKUL_HOST=… orakul спросить <сервис> тарифы
   ```

   The report shows what went to the server and what it answered: method and
   address, headers, response code, whether the shape was recognised and how many
   rows arrived. The token is scrubbed out of it — by header name, by value, by the
   halves of a composite key, and by percent-encoding if the key travelled into the
   address. This is pinned by the `ConnectorProbeReportTests` suite, and what is
   checked there is the leak rather than the output format: this text will be pasted
   into a public pull request.

   **The title of a found task does not reach the report** — since 2026-08-20.
   Previously the first row of the result was printed in full, that is, a real task
   from your tracker. Now its length and alphabet are printed ("17 characters,
   Cyrillic"): enough to see that the RIGHT field was read, not enough to read your
   task.

   Re-read the report before sending anyway. The request body remains: it holds the
   word you searched for, and for some services the address of your project too.
   Nobody can scrub that for you — we removed what we printed ourselves, not what
   you typed in.
3. **Words the lexicon is missing.** `RussianLexicon` fixes a transcript after
   recognition, and its table was assembled from a single measurement. A term that
   is misheard on your calls is a ready-made row for it.

   This too is data, not Swift:
   `mvp/Sources/OrakulCore/Resources/lexicon/base.json`. Acronyms (`acronyms`) are
   written in capital Latin letters, loanwords (`loanwords`) in Cyrillic: a
   transcript of a Russian call where half the words are Latin reads as foreign.

   Three rules are checked when a pack loads, not at review:

   - **words of the language are not taken.** "Агент" is an insurance agent,
     "ветка" is a tree branch. Fixing such a word spoils a normal phrase, so the
     `ordinary` list holds them, and an attempt to add one from there fails the
     load;
   - **no duplicates.** Two canonical forms for one word mean the result depends on
     traversal order;
   - **the alphabet matches the half.** `АПИ` among acronyms or `prod` among
     loanwords fixes a word in the wrong direction — exactly the engine
     disagreement the lexicon was written for.

   A refusal arrives with an explanation, not an error code. If your word ran into
   one, write about it in an issue: the `ordinary` list is extended by precisely
   such cases, and a refusal written down once saves the next person the same
   evening.
## Rules that other people's pull requests break against

**Do not claim what does not exist.** A "Connect" button for a service with no
suitable API is worse than no button. Before adding a connector, check the method,
the address, the search parameter and the response shape in the vendor's
documentation — and cite it in a comment. Two services out of the first five
trackers fell out on exactly this check, and that is the right outcome.

The same applies to an empty result instead of a refusal. Not every service uses
HTTP codes: Bitrix24 answers `200` and puts the refusal in the body, so the body is
checked before the list is parsed. And an empty list is accepted only in a familiar
shape: a response without a single known key is a refusal, not "there is nothing".
Otherwise a revoked key looks to a person like "no tasks found", and they will file
a second one on top of an existing one. More in §2.2 of the plan, points 5.1 and
5.2.

**Check a guard by mutation, and the mutation too.**

```bash
python3 scripts/mutaciya.py --file path/to/file.swift \
    --old 'the string we damage' --new 'what we replace it with' \
    -- swift test --package-path mvp --filter SuiteName
```

It returns 0 if the suite failed (the guard works), 1 if it passed (the guard is
blind), 2 if there was nothing to damage. The last matters more than the first two:
a replacement that never found its string leaves the run green, and that reads as
"the check is strong". In this repository that lie was told four times in a row, so
the script refuses to be silent: it requires the string to be found and the file to
change, and it verifies the restoration by checksum.

**Every function is covered by a test.** Not "there are tests", but: the test fails
if the function is broken. A test that checks a made-up address passes and means
nothing.

**Tests do not go to the network.** HTTP is passed in from outside
(`RussianTrackers.HTTP`), keys go into a fake Keychain (`InMemoryKeychain`). A test
that goes to Yandex Tracker is testing Yandex Tracker.

**Nothing paid.** There are no plans, limits or paid screens in orakul; this is
pinned by `NoTariffsTests`. A feature available "only on a plan" will not get into
the project.

**Local stays local.** Recording, transcription, archive and search are computed on
the computer. The network is allowed only as an explicitly chosen request to a
provider or a connected service; a new address and the data it carries must be
described in `SECURITY.md` and covered by a boundary test.

One green run is not a result. The suite is large and runs in parallel, so a test
that takes shared state from a neighbour does not fail every time. On 2026-08-13
two such were found: one checked, as a precondition, a session that other suites
set, and the second demanded a particular first place in the ranking, which depends
on whether the embedding index had finished building. Both failed about once in
five runs and both said nothing about the product.

They are caught by a loop that saves the output, not by `swift test | grep`: in live
output the culprit twice failed to appear.

```bash
for i in 1 2 3 4 5; do
  swift test > /tmp/run$i.log 2>&1
  grep -q "failed after" /tmp/run$i.log && { grep -n "recorded an issue" /tmp/run$i.log; break; }
done
```

If you changed tests, run the whole suite several times.

**Speed is checked by a separate command.** Latency budgets — search across a year
of calls, term restoration in a two-hour transcript — are covered by tests that an
ordinary `swift test` skips: on a busy machine they measure the neighbouring
compiler rather than the code. If you are changing `DecisionRecallService`,
`GlossaryRestore` or the index, run them yourself:

```bash
cd app && CRUXWING_PERF=1 swift test --filter Performance
```

Measured on this machine on 2026-08-13: search across 250 calls — 2.04 s (best of
three); restoring a two-hour transcript fits within the post-call budget. A green
ordinary run says nothing about this: without the variable both suites are marked
skipped and counted in the total as passed.

**Secrets live only in the Keychain.** Provider keys and tracker tokens live in the
Keychain (`ProviderKeyStore`, `RussianTrackerStore`), never in UserDefaults and
never in code. An empty string removes the entry rather than saving emptiness:
otherwise a cleared field leaves a dead key behind and the service looks configured.

## If a change touches the core — check Linux before sending

```bash
bash scripts/proverka-linux.sh    # ~40 seconds, needs docker
```

The core builds on two systems, and the difference between them is not theoretical:
`URLSession.bytes(for:)` and `waitsForConnectivity` exist only on Apple, and on
Linux the first does not exist at all while the second is read-only. Both changes
arrived in one commit, built on macOS, every suite was green, and for four days
nobody knew that the command line did not build for its second system.

The script does the same thing in the same image as the `linux-core` job in CI —
which is verified by `test/proverka-linux.test.mjs`, so that "it works locally" does
not start meaning less than it appears to.

## Running part of the suite

`swift test --filter Name` with a typo in the name prints

```
✔ Test run with 0 tests passed after 0.001 seconds.
```

and returns zero. A typo looks exactly like a successful run — and this is not
theory: in one night I fell for it twice, once concluding that a check did not catch
a mutation when it simply had not run.

```bash
bash scripts/test-filter.sh mvp RussianCaseSearchTests
bash scripts/test-filter.sh app AgendaCheckServiceTests
```

The script fails if the filter matched no checks at all. Filter by the name of the
suite structure: Cyrillic names from `@Test("…")` do not reach the filter.

## If you are running an image build

`cd app && bash dist-all.sh` builds two architectures and takes about ten minutes.
While it runs the repository is frozen: editing any file in `app/Sources` or
`mvp/Sources` fails it with `input file ... was modified during the build`, and a
commit mid-build produces two images claiming different commits.

Do not check this by eye:

```bash
bash scripts/build-running.sh && echo "do not edit" || echo "safe to edit"
```

The script recognises the build by the process's working directory rather than by
its command line: the build starts as `cd app && bash dist-all.sh`, and the path is
not in its command line at all — the pattern `pgrep -f "orakul/app.*dist-all\.sh"`
never matched and silently allowed editing. Someone else's build from `/tmp` is not
mistaken for ours. Both sides are covered by checks in
`test/build-running.test.mjs`.

Safe during a build: `test/*.mjs`, `public/*.html`, `README.md`, `docs/`,
`scripts/` — only the two `Sources` directories go into the source fingerprint.

A public release is not a continuation of this command and not a side effect of a
local build. The maintainer's order of operations, the tag rules, the GitHub
Environment, the names of the owner-supplied Apple secrets, `SHA256SUMS` and
attestation are described in [`docs/RELEASING.md`](docs/RELEASING.md). The workflow
prepares a private candidate and deliberately does not create a GitHub Release.

## Conventions

Commits: `type: what was done` — `feat`, `fix`, `refactor`, `docs`, `test`,
`chore`, `perf`. First line in English, up to 72 characters.

Comments in code explain **why**, not what: the what is visible from the code.

## Licence

Mozilla Public License 2.0 — see [LICENSE](LICENSE). By sending a pull request you
agree that your contribution is distributed on the same terms.

MPL is file-level copyleft: changes to the project's files are published, while new
code beside them may stay closed. MPL has an explicit patent grant (section 2.1);
that is what a lawyer looks at in a company deciding whether orakul may be
installed on a work laptop.
