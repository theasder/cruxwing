#!/usr/bin/env bash
# Materialise the open edition into dist-open/ from this tree.
#
# The open edition is NOT the full app with files deleted. It is a smaller
# product: capture, on-device transcription, local storage, cross-call search
# with an exact quote, and a question box that talks only to a model on
# 127.0.0.1. Everything that makes the assistant an assistant — prompts,
# blind-spot scans, agenda and rhetoric checks, fact-checking, connectors,
# accounts, the managed backend — stays out.
#
# Why a generator rather than a branch: the published repository gets ONE
# initial commit and no history, because history carries both the prompt layer
# and internal commit messages. Regenerating is how the open edition gets
# updated later, from a single source of truth.
#
# See docs/OPEN-EDITION.md for the manifest and the reasoning behind each line.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/dist-open}"

KEEP_CORE=(
  AudioAccumulator ExternalTranscriber MeetingPipeline
  TranscriptFile TranscriptCleanup SessionStore
  RecallIndex RecallAnswer SearchCoverage
  RussianLexicon LexiconPack CP1251 InvisibleText
  SpeechCorpus SpeechEval
  CommandLineApp LocalNotes PromptCatalog
)

DENY_CORE=(
  ConnectorAddress ConnectorCache ConnectorCaseMemory ConnectorHealth
  ConnectorManifest ConnectorProbeReport ConnectorQuery ConnectorSession
  GitHubConnector ManifestConnector RussianTrackers SelfHostedTrackers
  WesternTrackers WorkMessengers TelegramSupergroups
  TeamNotes IssueLabel VendorText
)

rm -rf "$OUT"
mkdir -p "$OUT/Sources/CruxwingCore/Resources" "$OUT/Sources/CruxwingApp" "$OUT/Sources/cruxwing" "$OUT/Tests/CruxwingCoreTests"

for f in "${KEEP_CORE[@]}"; do
  src="$ROOT/mvp/Sources/CruxwingCore/$f.swift"
  [ -f "$src" ] || { echo "missing keep file: $f.swift" >&2; exit 1; }
  cp "$src" "$OUT/Sources/CruxwingCore/$f.swift"
done

cp "$ROOT/mvp/Sources/CruxwingApp/"*.swift "$OUT/Sources/CruxwingApp/"
cp "$ROOT/mvp/Sources/cruxwing/"*.swift    "$OUT/Sources/cruxwing/"

# Tests follow their subject: a test that exercises a denied type is a denied
# test. Filtering by CONTENT and not by filename is deliberate — these tests are
# named after the behaviour they pin ("StemQuestionTests", "HostileServiceTests",
# "OrderIntoNowhereTests"), so a name filter silently keeps twenty of them and
# the build breaks somewhere far from the cause.
for t in "$ROOT/mvp/Tests/CruxwingCoreTests/"*.swift; do
  name="$(basename "$t")"; skip=0
  for d in "${DENY_CORE[@]}"; do
    grep -qw "$d" "$t" && { skip=1; break; }
  done
  # ReadmeQuickstartTests reads the repository README and checks the CLI keeps
  # every promise printed there. That contract belongs to the Russian README of
  # the full product; the open edition ships a different document.
  case "$name" in ReadmeQuickstartTests.swift) skip=1 ;; esac
  [ "$skip" = 1 ] || cp "$t" "$OUT/Tests/CruxwingCoreTests/$name"
done

# The prompt CATALOGUE is the asset; the parser is not. Ship the parser with a
# minimal catalogue so the button surface still works and nothing is copied.
# The parser looks for "prompts.ru" by name and the tests require at least six
# offline buttons including "what-decided", so the file keeps its name and the
# shape stays real — only the texts are ours to give away, and these are the
# plainest six that still make the surface work.
cat > "$OUT/Sources/CruxwingCore/Resources/prompts.ru.json" <<'JSON'
{
  "version": 1,
  "locale": "en-US",
  "buttons": [
    { "id": "what-decided", "label": "What did we decide?",
      "prompt": "Answer from the transcript below and cite the timestamps.",
      "offline": true,
      "adapted": "Deliberately plain. The open edition ships no prompt library." },
    { "id": "open-questions", "label": "Open questions",
      "prompt": "List the questions raised in the transcript below that were not answered. Cite the timestamps.",
      "offline": true, "adapted": "A list, not an interpretation." },
    { "id": "action-items", "label": "Who agreed to what",
      "prompt": "List the commitments in the transcript below, with who made each one. Cite the timestamps.",
      "offline": true, "adapted": "Names and timestamps, no inference about intent." },
    { "id": "who-said", "label": "Who said this",
      "prompt": "Find where the following was said in the transcript below and quote it with the timestamp.",
      "offline": true, "adapted": "Search, phrased as a question." },
    { "id": "timeline", "label": "Order of events",
      "prompt": "List what was discussed in the transcript below in order, with timestamps.",
      "offline": true, "adapted": "Ordering only — no summarising." },
    { "id": "unclear-terms", "label": "Terms to check",
      "prompt": "List words in the transcript below that look like transcription errors or unfamiliar terms, with timestamps.",
      "offline": true, "adapted": "Feeds the term dictionary; catches ASR damage." }
  ]
}
JSON

for f in LICENSE SECURITY.md CODE_OF_CONDUCT.md; do
  [ -f "$ROOT/$f" ] && cp "$ROOT/$f" "$OUT/$f"
done
[ -f "$ROOT/README.public.md" ] || { echo "missing README.public.md at repo root" >&2; exit 1; }
cp "$ROOT/README.public.md" "$OUT/README.md"

# CONTRIBUTING is written fresh rather than copied. The full one is 500 lines
# about connectors, trackers and messengers — none of which exist here, and a
# contributor sent to a file that does not ship stops trusting the rest.
cat > "$OUT/CONTRIBUTING.md" <<'CONTRIB'
# Contributing

Thanks for looking. This is a small project on purpose: capture, transcribe on
device, store, search. If a change makes it bigger, say why in the pull request.

## Build and test

```bash
swift build
swift test
```

Swift 6.0+ (Xcode 16+). No external dependencies — that is deliberate, and a pull
request adding one needs to argue for it.

Some tests skip unless real recordings or a quiet machine are present. The reason
is printed. A skip is never counted as a pass, and please do not make it one.

## What we look for

- **Tests that pin behaviour, not implementation.** If the test has to change
  whenever the code is refactored, it is testing the wrong thing.
- **Comments that say why.** What the code does is visible in the code.
- **No network in tests.** HTTP is passed in from outside so it can be faked.
- **No telemetry, ever.** This build makes no request to anything but loopback,
  and that is the product. A pull request that adds an analytics call, a crash
  reporter or a version check will be closed, however well meant.

## Reporting a security issue

Not in a public issue — see [SECURITY.md](SECURITY.md). For a program that
listens to meetings that is the first question anyone should ask, and it deserves
a written answer.

## Licence

By contributing you agree your work ships under the
[Mozilla Public License 2.0](LICENSE), like the rest of this repository.
CONTRIB
cp -R "$ROOT/mvp/Sources/CruxwingCore/Resources/lexicon" "$OUT/Sources/CruxwingCore/Resources/lexicon"
cp "$ROOT/mvp/Package.swift" "$OUT/Package.swift"
[ -d "$ROOT/mvp/Support" ] && cp -R "$ROOT/mvp/Support" "$OUT/Support"

# ---- patches: the four places the commercial tree couples to connectors ----
#
# Applied to the OUTPUT, never to mvp/: the full product needs those code paths.
# Every patch is anchored on exact text and aborts if the anchor moved, so a
# refactor upstream stops the generator instead of quietly shipping a hole.
# (python3 ships with the Xcode command line tools, which you need for swift anyway.)
python3 - "$OUT" <<'PATCH'
import sys, io, re, os
out = sys.argv[1]

def edit(rel, fn):
    p = os.path.join(out, rel)
    src = io.open(p, encoding='utf-8').read()
    new = fn(src)
    if new is None:
        sys.exit("patch anchor not found in %s — look at it by hand" % rel)
    io.open(p, 'w', encoding='utf-8').write(new)

# 1. CLI: drop the whole `спросить`/`ask` command. It exists to query connectors.
def drop_ask_case(s):
    start = s.find('case "спросить", "ask":')
    if start == -1: return None
    end = s.find('\ndefault:', start)
    if end == -1: return None
    return s[:start] + s[end + 1:]
edit('Sources/cruxwing/main.swift', drop_ask_case)

# 2. Help text: the command line, the service list, and the three connector
#    environment variables. CRUXWING_ENGINE stays — that is transcription.
def trim_help(s):
    line = '      cruxwing спросить <сервис> <вопрос>   спросить подключённый сервис\n'
    if line not in s: return None
    s = s.replace(line, '', 1)
    block_start = s.find('    Сервисы: \\(ConnectorQuery.services')
    block_end = s.find('    Расшифровка идёт вашим движком')
    if block_start == -1 or block_end == -1 or block_end < block_start: return None
    return s[:block_start] + s[block_end:]
edit('Sources/CruxwingCore/CommandLineApp.swift', trim_help)

# 2b. The command NAME list, not just the help text. A test pins that the two
#     agree, and it is right to: a command the help does not mention is a trap.
def drop_ask_command(s):
    if '"спросить", "корпус",' not in s: return None
    return s.replace('"спросить", "корпус",', '"корпус",', 1)
edit('Sources/CruxwingCore/CommandLineApp.swift', drop_ask_command)

# 3-4. Two comments that name a type the open edition does not ship. Comments,
#      not code — but a reader who greps for the name and finds nothing is owed
#      a sentence that still makes sense on its own.
def fix_invisible(s):
    old = 'чужого сервиса при отказе показываются человеку (`VendorText`). Ради'
    if old not in s: return None
    return s.replace(old, 'чужого сервиса при отказе показываются человеку. Ради', 1)
edit('Sources/CruxwingCore/InvisibleText.swift', fix_invisible)

# 5. One assertion pins the bundled catalogue as the Russian one. That is a fact
#    about the full product, not an invariant, and the open edition ships English.
def fix_locale_expectation(s):
    if '#expect(catalog.locale == "ru-RU")' not in s: return None
    return s.replace('#expect(catalog.locale == "ru-RU")',
                     '#expect(catalog.locale == "en-US")', 1)
edit('Tests/CruxwingCoreTests/PromptCatalogTests.swift', fix_locale_expectation)

# 6. One row of a parameterised test asks that a typo suggest a command the open
#    edition does not have. Drop the row, not the test: the other row still pins
#    that suggestions cover commands executed outside `run`, which is the point
#    of that test and stays true.
def drop_ask_suggestion(s):
    row = '        ("сросить", "спросить"),\n'
    if row not in s: return None
    s = s.replace(row, '', 1)
    old_doc = '    /// Команды `записать` и `спросить` выполняются в main.swift и до `run`'
    if old_doc in s:
        s = s.replace(old_doc, '    /// Команда `записать` выполняется в main.swift и до `run`', 1)
    return s
edit('Tests/CruxwingCoreTests/CommandLineAppTests.swift', drop_ask_suggestion)

def fix_lexicon(s):
    old = ('/// Внутреннее, а не приватное: тем же вопросом «это кириллица?» задаётся\n'
           '/// ManifestConnector, когда решает, повторять ли поиск с другой буквы. Второе')
    if old not in s: return None
    new = ('/// Внутреннее, а не приватное: тем же вопросом «это кириллица?» задаётся\n'
           '/// поиск, когда решает, повторять ли запрос с другой буквы. Второе')
    return s.replace(old, new, 1)
edit('Sources/CruxwingCore/LexiconPack.swift', fix_lexicon)
PATCH

# ---- Package.swift: point it at what the open tree actually contains ----
python3 - "$OUT" <<'PKG'
import sys, io, os, re
out = sys.argv[1]
p = os.path.join(out, 'Package.swift')
s = io.open(p, encoding='utf-8').read()

# Connector descriptions are data for a feature the open edition does not have.
# Left in place they break the build on a missing resource, which is a confusing
# way to find out we forgot to cut something.
m = re.search(r'\n[^\n]*\.copy\("Resources/connectors"\),?', s)
if not m:
    sys.exit('Package.swift: connectors resource anchor moved — look at it by hand')
s = s[:m.start()] + s[m.end():]
s = re.sub(r'\n(\s*//[^\n]*\n)*\s*// Коннекторы, описанные данными[^\n]*\n(\s*//[^\n]*\n)*', '\n', s)
io.open(p, 'w', encoding='utf-8').write(s)

# Every resource the manifest promises has to exist, or swift build fails late
# and far from the cause.
missing = [r for r in re.findall(r'\.copy\("([^"]+)"\)', s)
           if not os.path.exists(os.path.join(out, 'Sources/CruxwingCore', r))]
if missing:
    sys.exit('Package.swift promises resources that are not in the tree: ' + ', '.join(missing))
PKG

# ---- rename: the open edition ships as Cruxwing, one brand (BD-032) ----
#
# Done on the OUTPUT, like the patches: mvp/ keeps its own identity until the
# source tree is renamed on purpose. Order matters — longest first, or
# "CruxwingCore" becomes "CruxwingCore" via two passes and stops matching.
python3 - "$OUT" <<'RENAME'
import sys, os, io, re
out = sys.argv[1]

PAIRS = [
    ("CruxwingCoreTests", "CruxwingCoreTests"),
    ("CruxwingCore",      "CruxwingCore"),
    ("CruxwingApp",       "CruxwingApp"),
    ("CRUXWING_",         "CRUXWING_"),
    ("Cruxwing",          "Cruxwing"),
    ("cruxwing",          "cruxwing"),
    ("Cruxwing",          "Cruxwing"),
    ("оракул",          "cruxwing"),
]

TEXT = {".swift", ".json", ".md", ".plist", ".txt", ".yml", ".yaml"}

for root, dirs, files in os.walk(out):
    for f in files:
        if os.path.splitext(f)[1].lower() not in TEXT: continue
        p = os.path.join(root, f)
        s = io.open(p, encoding="utf-8", errors="strict").read()
        o = s
        for a, b in PAIRS: s = s.replace(a, b)
        if s != o: io.open(p, "w", encoding="utf-8").write(s)

# Directories and filenames carry the name too, and SwiftPM resolves targets by
# directory, so a renamed target with an unrenamed directory does not build.
for root, dirs, files in os.walk(out, topdown=False):
    for name in files + dirs:
        new = name
        for a, b in PAIRS: new = new.replace(a, b)
        if new != name:
            os.rename(os.path.join(root, name), os.path.join(root, new))

# The licence is a verbatim legal text: never rewritten.
RENAME
git_dummy=""

# ---- guards: fail loudly rather than publish something we meant to keep ----
fail=0
for d in "${DENY_CORE[@]}"; do
  if grep -rlw "$d" "$OUT" 2>/dev/null | grep -q .; then
    echo "STILL REFERENCED: $d" >&2
    grep -rlw "$d" "$OUT" 2>/dev/null | sed "s|$OUT/|    |" >&2
    fail=1
  fi
done
if grep -rq "Resources/Skills" "$OUT" 2>/dev/null; then
  echo "LEAK: the skill library is referenced in the output" >&2; fail=1
fi
if [ -e "$OUT/.git" ]; then
  echo "LEAK: the output carries a .git directory — the open repo gets ONE fresh commit" >&2; fail=1
fi
[ "$fail" = 0 ] || { echo "make-open-edition: refusing to hand over a leaking tree" >&2; exit 1; }

echo "open edition written to $OUT"
find "$OUT" -name '*.swift' | wc -l | xargs echo "  swift files:"
