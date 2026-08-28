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
mkdir -p "$OUT/Sources/OrakulCore/Resources" "$OUT/Sources/OrakulApp" "$OUT/Sources/orakul" "$OUT/Tests/OrakulCoreTests"

for f in "${KEEP_CORE[@]}"; do
  src="$ROOT/mvp/Sources/OrakulCore/$f.swift"
  [ -f "$src" ] || { echo "missing keep file: $f.swift" >&2; exit 1; }
  cp "$src" "$OUT/Sources/OrakulCore/$f.swift"
done

cp "$ROOT/mvp/Sources/OrakulApp/"*.swift "$OUT/Sources/OrakulApp/"
cp "$ROOT/mvp/Sources/orakul/"*.swift    "$OUT/Sources/orakul/"

# Tests follow their subject: a test that exercises a denied type is a denied
# test. Filtering by CONTENT and not by filename is deliberate — these tests are
# named after the behaviour they pin ("StemQuestionTests", "HostileServiceTests",
# "OrderIntoNowhereTests"), so a name filter silently keeps twenty of them and
# the build breaks somewhere far from the cause.
for t in "$ROOT/mvp/Tests/OrakulCoreTests/"*.swift; do
  name="$(basename "$t")"; skip=0
  for d in "${DENY_CORE[@]}"; do
    grep -qw "$d" "$t" && { skip=1; break; }
  done
  [ "$skip" = 1 ] || cp "$t" "$OUT/Tests/OrakulCoreTests/$name"
done

# The prompt CATALOGUE is the asset; the parser is not. Ship the parser with a
# minimal catalogue so the button surface still works and nothing is copied.
cat > "$OUT/Sources/OrakulCore/Resources/prompts.json" <<'JSON'
{
  "version": 1,
  "buttons": [
    {
      "id": "recall",
      "label": "What did we decide?",
      "prompt": "Answer from the transcript below and cite the timestamps.",
      "offline": true,
      "why": "Deliberately plain. The open edition ships no prompt library."
    }
  ]
}
JSON

for f in LICENSE CONTRIBUTING.md SECURITY.md CODE_OF_CONDUCT.md; do
  [ -f "$ROOT/$f" ] && cp "$ROOT/$f" "$OUT/$f"
done
[ -f "$ROOT/README.public.md" ] && cp "$ROOT/README.public.md" "$OUT/README.md"
cp "$ROOT/mvp/Package.swift" "$OUT/Package.swift"
[ -d "$ROOT/mvp/Support" ] && cp -R "$ROOT/mvp/Support" "$OUT/Support"

# ---- guards: fail loudly rather than publish something we meant to keep ----
fail=0
for d in "${DENY_CORE[@]}"; do
  if grep -rlw "$d" "$OUT/Sources" "$OUT/Tests" 2>/dev/null | grep -q .; then
    echo "STILL REFERENCED: $d" >&2
    grep -rlw "$d" "$OUT/Sources" "$OUT/Tests" 2>/dev/null | sed "s|$OUT/|    |" >&2
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
