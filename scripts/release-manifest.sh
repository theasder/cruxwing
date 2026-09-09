#!/usr/bin/env bash
# Assemble a reviewable release-candidate directory from the two already
# audited DMGs. The output has one checksum list and a workflow-independent
# JSON record. Publication is deliberately out of scope.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

usage() {
    echo "использование: bash scripts/release-manifest.sh vX.Y.Z [app/dist] [release-candidate/vX.Y.Z]" >&2
}

tag="${1:-}"
dist="${2:-app/dist}"
output="${3:-release-candidate/${tag:-unknown}}"
[ "$#" -ge 1 ] && [ "$#" -le 3 ] || { usage; exit 2; }

for tool in git python3; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "!! для манифеста выпуска нужен $tool" >&2
        exit 2
    }
done

if command -v sha256sum >/dev/null 2>&1; then
    SHA256=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
    SHA256=(shasum -a 256)
else
    echo "!! нет sha256sum или shasum — контрольную сумму посчитать нельзя" >&2
    exit 2
fi

bash scripts/release-gate.sh "$tag"

case "$output" in
    /|.|..|"$root")
        echo "!! небезопасный каталог результата: $output" >&2
        exit 2
        ;;
esac
if [ -e "$output" ]; then
    echo "!! каталог результата уже существует: $output" >&2
    echo "   Уберите или переименуйте его вручную; старый кандидат нельзя смешивать с новым." >&2
    exit 1
fi

artifacts=(cruxwing-AppleSilicon.dmg cruxwing-Intel.dmg)
for name in "${artifacts[@]}"; do
    file="$dist/$name"
    sidecar="$file.sha256"
    [ -f "$file" ] && [ ! -L "$file" ] || {
        echo "!! нет обычного файла $file" >&2
        exit 1
    }
    [ -f "$sidecar" ] && [ ! -L "$sidecar" ] || {
        echo "!! нет контрольной суммы $sidecar" >&2
        exit 1
    }
    expected="$(awk -v file="$name" 'NF == 2 && $2 == file { print $1 }' "$sidecar")"
    actual="$("${SHA256[@]}" "$file" | awk '{print $1}')"
    if [[ ! "$expected" =~ ^[0-9a-f]{64}$ ]] || [ "$expected" != "$actual" ]; then
        echo "!! $sidecar не подтверждает байты $file" >&2
        exit 1
    fi
done

parent="$(dirname "$output")"
mkdir -p "$parent"
stage="$(mktemp -d "$parent/.cruxwing-release-${tag}.XXXXXX")"
cleanup() { [ -z "${stage:-}" ] || rm -rf "$stage"; }
trap cleanup EXIT HUP INT TERM

for name in "${artifacts[@]}"; do
    /usr/bin/env cp -p "$dist/$name" "$stage/$name"
done
bash scripts/refresh-cask.sh "$dist" "$stage/cruxwing.rb" >/dev/null

commit="$(git rev-parse --verify 'HEAD^{commit}')"
source_hash="$(bash scripts/app-source-hash.sh)"
version="${tag#v}"
generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

CRUXWING_RELEASE_STAGE="$stage" \
CRUXWING_RELEASE_TAG="$tag" \
CRUXWING_RELEASE_VERSION="$version" \
CRUXWING_RELEASE_COMMIT="$commit" \
CRUXWING_RELEASE_SOURCE_HASH="$source_hash" \
CRUXWING_RELEASE_GENERATED_AT="$generated_at" \
python3 <<'PY'
import hashlib
import json
import os
import platform
from pathlib import Path

stage = Path(os.environ["CRUXWING_RELEASE_STAGE"])
described = [
    ("cruxwing-AppleSilicon.dmg", "macos", "arm64"),
    ("cruxwing-Intel.dmg", "macos", "x86_64"),
    ("cruxwing.rb", "homebrew-cask", "multi"),
]

artifacts = []
for name, kind, architecture in described:
    path = stage / name
    content = path.read_bytes()
    artifacts.append({
        "name": name,
        "kind": kind,
        "architecture": architecture,
        "size": len(content),
        "sha256": hashlib.sha256(content).hexdigest(),
    })

workflow = None
if os.environ.get("GITHUB_ACTIONS") == "true":
    workflow = {
        "repository": os.environ.get("GITHUB_REPOSITORY"),
        "workflowRef": os.environ.get("GITHUB_WORKFLOW_REF"),
        "runId": os.environ.get("GITHUB_RUN_ID"),
        "runAttempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
        "runnerImage": os.environ.get("ImageOS"),
    }

record = {
    "schemaVersion": 1,
    "project": "cruxwing",
    "version": os.environ["CRUXWING_RELEASE_VERSION"],
    "tag": os.environ["CRUXWING_RELEASE_TAG"],
    "commit": os.environ["CRUXWING_RELEASE_COMMIT"],
    "sourceSha256": os.environ["CRUXWING_RELEASE_SOURCE_HASH"],
    "generatedAt": os.environ["CRUXWING_RELEASE_GENERATED_AT"],
    "builder": {
        "workflow": workflow,
        "platform": platform.platform(),
        "machine": platform.machine(),
    },
    "artifacts": artifacts,
    "claims": {
        "scope": "digest and build-context record",
        "notReproducibilityProof": True,
        "signedAttestationExpectedFromCI": workflow is not None,
    },
}
(stage / "provenance.json").write_text(
    json.dumps(record, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY

(
    cd "$stage"
    "${SHA256[@]}" \
        cruxwing-AppleSilicon.dmg \
        cruxwing-Intel.dmg \
        cruxwing.rb \
        provenance.json > SHA256SUMS
    "${SHA256[@]}" -c SHA256SUMS >/dev/null
)

mv "$stage" "$output"
stage=""
trap - EXIT HUP INT TERM

echo ">> кандидат выпуска: $output"
echo "   $(wc -l < "$output/SHA256SUMS" | tr -d ' ') файла связаны SHA-256"
echo "   проверить: (cd \"$output\" && shasum -a 256 -c SHA256SUMS)"
echo "   публикация не выполнена"
