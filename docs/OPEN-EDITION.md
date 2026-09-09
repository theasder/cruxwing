# The open edition: what goes into it and why exactly that

The owner's decision of 28 August: the open edition must be **much simpler** than
the commercial one, the prompts do not go into it, and **privacy is the point of
it**. The strategic half is in
`cruxwing-marketing/docs/business/OSS-LAUNCH-PLAN.md` (BD-033). This is the
engineering half: the boundary, the generator, and what is left to finish.

## Why a generator rather than a branch

The published repository gets **one initial commit and no history**. The reason is
not tidiness: the history carries both the prompt layer and internal commit
messages — mentions of respondents, decisions, prices, backend addresses. Deleting
files in the last commit removes none of that, because `git log -p` hands over
everything.

Hence `scripts/make-open-edition.sh`: it assembles `dist-open/` from this tree
rather than maintaining a second copy. Updating the open edition is another run of
the generator, not a merge between diverging branches.

## What turned out to be lucky

The open edition did not have to be cut out of a 324-file application. The `mvp/`
core is already separated from the platform and from the network — its
`Package.swift` says so outright, and the portability tests hold it there. The
feature set needed — recording, on-device transcription, storage, search with a
quote — is already in it.

## The boundary

**Included (18 core files out of 36):** `AudioAccumulator`, `ExternalTranscriber`,
`MeetingPipeline`, `TranscriptFile`, `TranscriptCleanup`, `SessionStore`,
`RecallIndex`, `RecallAnswer`, `SearchCoverage`, `RussianLexicon`, `LexiconPack`,
`CP1251`, `InvisibleText`, `SpeechCorpus`, `SpeechEval`, `CommandLineApp`,
`LocalNotes`, `PromptCatalog`. Plus the `OrakulApp` shell and the command line.

**Not included (18 files):** the whole connector family — `ConnectorAddress`,
`ConnectorCache`, `ConnectorCaseMemory`, `ConnectorHealth`, `ConnectorManifest`,
`ConnectorProbeReport`, `ConnectorQuery`, `ConnectorSession`, `GitHubConnector`,
`ManifestConnector`, `RussianTrackers`, `SelfHostedTrackers`, `WesternTrackers`,
`WorkMessengers`, `TelegramSupergroups` — and also `TeamNotes`, `IssueLabel`,
`VendorText`.

**Prompts are a separate case, and the distinction matters.**
`PromptCatalog.swift` is a JSON *parser*: ninety lines and nothing of value. The
value is in the catalogue itself, `prompts.ru.json`. So the generator takes the
parser and substitutes a **minimal** catalogue with one button and one
deliberately boring prompt: "answer from the transcript below, cite the
timecodes". There is nothing there to steal, and the surface works.

**Tests are filtered by content, not by filename.** That is not a detail: tests are
named after the behaviour they pin — `StemQuestionTests`, `HostileServiceTests`,
`OrderIntoNowhereTests` — and a filename filter quietly leaves twenty of them
behind, after which the build breaks a long way from the cause.

## What the generator already does

- Assembles the tree from an allow-list rather than by subtraction from the whole.
- Copies `LICENSE` (MPL 2.0), `README.public.md` → `README.md`, `CONTRIBUTING`,
  `SECURITY`, `CODE_OF_CONDUCT`.
- **Refuses to hand over the tree** if a single forbidden type, a reference to the
  skills library, or a `.git` directory is left in it. And it prints the list of
  files, not a single line saying "error".

The 28 August run gives **46 Swift files** against 324 in the application and 39 in
`mvp/`.

## Four edits: made by the generator, not in the sources

The edits are applied to the **output tree**, not to `mvp/`: the full product needs
those branches of code. Each is anchored to exact text and **stops the build if the
anchor moved** — a refactor upstream halts the generator instead of quietly
dragging a hole through.

Two of the four turned out to be comments rather than code — something I failed to
distinguish in the first version of this document:

| File | Was | Became |
|---|---|---|
| `Sources/orakul/main.swift` | the `ask` command in full | removed, brackets rebalanced |
| `CommandLineApp.swift` | the help text, the service list, three connector environment variables | removed; `ORAKUL_ENGINE` kept — that one is transcription |
| `LexiconPack.swift` | a comment referring to `ManifestConnector` | rewritten without the type name |
| `InvisibleText.swift` | a comment referring to `VendorText` | the same |

## What else turned up while checking the output

Three things that would have broken the build or the launch on a Mac:

- **`Package.swift` promised resources the tree does not have.** The generator now
  substitutes a generated minimal `prompts.json` for `prompts.ru.json`, removes
  `Resources/connectors`, and **checks that every promised resource exists**. A
  missing resource fails `swift build` a long way from the cause.
- **The lexicon was not being copied.** `Resources/lexicon` is needed by
  `LexiconPack` and `RussianLexicon`; it is copied now.
- **README did not reach the output, and the wrong CONTRIBUTING did.** The full
  CONTRIBUTING is five hundred lines about connectors, trackers and messengers that
  the open edition does not have; a contributor sent to a file about things that do
  not exist stops believing the rest. The generator writes a short CONTRIBUTING for
  this tree, with a clause of its own: we never accept telemetry, that is the
  product.

The forbidden-type check now runs **over the whole output**, including
`Package.swift` and the markdown, not only over `Sources` and `Tests`.

## What a run produces

46 Swift files: 18 core files, the shell, the command line and 24 tests. Against
324 in the application. At the root: `README.md`, `LICENSE` (MPL 2.0),
`CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, `Package.swift`. Forbidden
types in the output: zero.

## Verified: it builds and passes tests

**Swift 6.0.3 on Linux, 28 August.** The toolchain was installed in the environment
specifically for this check — the `OrakulCore` core is declared platform-independent,
and that turned out to be true, so it can be built and run somewhere other than a
Mac.

- `swift build --target OrakulCore` — **builds**, 18 files.
- `swift build` — **builds in full**, including the `orakul` executable.
- `swift test` — **300 tests pass**.
- The binary runs and prints a trimmed help text: no `ask` command, no
  connector environment variables, `ORAKUL_ENGINE` in place.

**Five breakages that only a real run found, and not one of which was caught by the
content checks:**

1. **The button catalogue would not load.** `PromptCatalog.bundled()` looks for a
   resource named `prompts.ru`, and the generator was writing `prompts.json` —
   three tests failed on `resourceMissing`. The filename is preserved; only the
   contents became English.
2. **A minimal one-button catalogue is not enough.** The tests require at least six
   buttons, all offline, and a mandatory `what-decided`. The catalogue now has six
   deliberately simple English buttons.
3. **The catalogue's locale** was checked as `ru-RU`. That is a fact about a Russian
   product, not an invariant; the expectation in the test is translated to `en-US`,
   with an anchor so the edit fails if the test is rewritten.
4. **The command list and the help text drifted apart.** I removed `ask` from
   the help but not from the command array, and the test that holds them consistent
   failed — rightly: a command the help says nothing about is a trap.
5. **`ReadmeQuickstartTests` reads the repository's README** and checks CLI
   behaviour against it. That contract belongs to the full product's Russian README;
   in the open edition the README is different, so the suite is excluded. Plus one
   row of a parameterised test that demanded a hint for `ask` — the row was
   removed, not the test.

## What is still unverified and needs a Mac

The shell. `OrakulApp` is declared under `#if os(macOS)` and by definition does not
build on Linux: SwiftUI, ScreenCaptureKit, the microphone. Everything verified above
is the core, the command line and the tests. Audio capture and the window **have
been built by nobody**.

## Two inconsistencies visible only if you run the binary

Both have to be resolved before publication, because both hit the first impression.

- ~~**The interface speaks Russian.**~~ **Done 9 September.** The README was
  English while the product launched in Russian, and that contradiction was
  visible in ten seconds. The user-facing strings are now English across the
  application and the command line; the language engine underneath — stemming,
  lexicon, stop words, the injection phrases the guards match on — stays Russian,
  because it reads Russian speech.
- ~~The binary is called `orakul` while the brand is Cruxwing.~~ **Done 28 August.**

## The rename to Cruxwing

The owner's decision: one name, as in BD-032. The generator does the rename, over
the output tree like the other edits: `mvp/` keeps its own identity until the
sources are renamed separately and deliberately.

What changes: the package `Orakul` → `Cruxwing`, the targets `OrakulCore` →
`CruxwingCore` and `OrakulApp` → `CruxwingApp`, the executable `orakul` →
`cruxwing`, the test target, directory and file names, every `import`, the
environment variables `ORAKUL_*` → `CRUXWING_*`, the bundle identifier
`ai.orakul.desktop` → `ai.cruxwing.desktop`, and the product name in the copy.

Two details this breaks on if done carelessly:

- **Replacement order runs from long to short.** Otherwise `OrakulCore` first
  becomes `CruxwingCore` under the `Orakul` → `Cruxwing` rule, and the rule for
  `OrakulCore` never fires.
- **Directories and filenames carry the name too.** SwiftPM finds a target by its
  directory: a renamed target with an unrenamed directory simply does not build.
- **`LICENSE` is not rewritten.** It is verbatim legal text; its absence from the
  extension list is deliberate.

**Verified after the rename:** `swift build` builds, `swift test` — **300 tests
pass**, the `cruxwing` binary runs. Not one occurrence of
`orakul`/`Orakul`/`ORAKUL` is left in the output. The suite "one product word on
every surface" fired separately — that is what it was written for.

**The identifiers do not collide:** the commercial application is
`com.meetgpt.macapp` (and `com.cruxwing.mac` in the App Store plans), the open
edition `ai.cruxwing.desktop`. But if someone installs both, the Mac ends up with
two applications sharing a name — the display name at least is worth separating,
for example "Cruxwing Local".

## Publication order

1. `swift build && swift test` in `dist-open/` — the generator is already green.
2. Run the secret scan over the new tree — it is cheap, and a miss has no undo.
3. `theasder/cruxwing` → private (do not delete).
4. A new public repository, `git init`, one commit, push.
