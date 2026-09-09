# How to take part

In English. Issues, pull requests and discussion are in English. Awkward grammar
is no reason for rejection, and a question that is unclear in substance is a
reason to ask again, not to close — see [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## Adding a connector

Often a connector is a JSON file rather than Swift. Put the answers to four
questions — method, address, search parameter, response shape — into
`mvp/Sources/CruxwingCore/Resources/connectors/<service>.json`, and a shared engine
runs them: the deadline, distinguishable errors, and the rule that an unfamiliar
response is a refusal rather than an empty result all come for free.

```json
{
  "id": "service", "title": "Service",
  "docs": "https://link/to/the/method/in/the/vendor/reference",
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

Two fields are mandatory and the manifest will not load without them: `docs`, and
a parameter or body carrying `{query}` or `{queryWords}`.

The substitutions the engine knows:

| Substitution | What it carries |
|---|---|
| `{query}` | the person's words, as typed |
| `{queryWords}` | the same words with the characters that would be read as another system's search syntax stripped out |
| `{limit}` | how many rows to ask for |
| `{token}` | the key from the Keychain |
| `{basic}` | the key encoded for HTTP Basic, so nobody encodes it by hand |
| `{tokenHead}` / `{tokenTail}` | the two halves of a `head:tail` key, for services that want them in different headers |
| `{page}` / `{perPage}` | position and page size, for enumeration |

Use `{queryWords}` whenever the service parses its search parameter as a
*language* rather than a string — Slack, Mattermost, Trello, BookStack,
Rocket.Chat and Jira all do. A question assembled from speech contains ordinary
punctuation, and a colon in it will be read as an instruction. There is no error
for this: the answer simply comes back about something else, and the person reads
a confident "nothing found".

**The secret travels in a header**, even where the vendor's usual way is
`?key=…&token=…`. A full address is written into proxy logs, the service's own
access log and error reports, and outlives a revoked key. A manifest with
`{token}` or `{basic}` in the path or in query parameters will not load.

If a service has no search by word, a bounded enumeration is accepted instead —
`scan`, with `pages`, `perPage`, the fields to `match` on our side, and where the
service reports `more` and `total`. The engine allows no more than ten pages, and
returns coverage with the results, so the person sees "not found among the last
500 of 40,000" rather than "nothing found". Those are different answers.

Some services cannot be described this way at all — a dictionary instead of a
list, a nested body, authorization assembled from two halves. Those are written
in code; `mvp/Sources/CruxwingCore/WorkMessengers.swift` is the model, and
`mvp/Sources/CruxwingCore/WesternTrackers.swift` shows a cloud service, which is
never asked for an address: one host for everybody belongs in code, because an
extra settings field is an extra typo the person will blame on their token.

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

**If you added a file to `mvp/Sources/CruxwingCore` and the application build "does
not see" it.** The error looks like `cannot find <Type> in scope` even though the
file is there and the import exists. SwiftPM keeps the file list of a path
dependency in a cache and does not notice the new file; the manifest's timestamp
does not help, because the list is computed from content. One command fixes it:

```bash
cd app && swift package clean && swift build
```

**If the installer build stops at the notarization profile.** The message names
the command: `xcrun notarytool store-credentials cruxwing-notary`. A human types the
password — it is not stored in the repository and must not be. The check comes
first, before compilation: on 2026-08-13 the profile vanished from the keychain,
and that was discovered after six minutes of building arm64.

The installer build does this itself (`app/build.sh`); an ordinary build does not:
cleaning costs two minutes, and there is no reason to pay them on every edit.

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

**Nothing paid.** There are no plans, limits or paid screens in cruxwing; this is
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
not in its command line at all — the pattern `pgrep -f "cruxwing/app.*dist-all\.sh"`
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
that is what a lawyer looks at in a company deciding whether cruxwing may be
installed on a work laptop.
