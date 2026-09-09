#!/usr/bin/env bash
# Prove that a candidate comes from an existing annotated release tag on the
# reviewed base branch. This is a read-only gate; it neither creates tags nor
# publishes anything.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

usage() {
    echo "использование: bash scripts/release-gate.sh vX.Y.Z" >&2
}

tag="${1:-}"
[ "$#" -eq 1 ] || { usage; exit 2; }
[[ "$tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || {
    echo "!! тег выпуска должен иметь точный вид vX.Y.Z: ${tag:-<пусто>}" >&2
    exit 2
}

for tool in git node python3; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "!! для проверки выпуска нужен $tool" >&2
        exit 2
    }
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "!! проверка выпуска запущена не в Git checkout" >&2
    exit 1
}

# A temporary prospective index is useful for local tests, but it is not the
# reviewed index attached to the tag. Never let that testing trick become a
# release source.
if [ -n "${GIT_INDEX_FILE:-}" ]; then
    echo "!! выпуск нельзя проверять через GIT_INDEX_FILE; нужен обычный чистый checkout тега" >&2
    exit 1
fi

if [ -n "$(git status --porcelain=v1 --untracked-files=all)" ]; then
    echo "!! рабочее дерево не чистое; выпуск собирается только из неизменённого тега" >&2
    echo "   Имена и содержимое незакоммиченных файлов намеренно не печатаются." >&2
    exit 1
fi

# assume-unchanged and skip-worktree can make `git status` lie. Do not print the
# affected paths: they may be deliberately hidden local configuration.
if git ls-files -v | LC_ALL=C grep -Eq '^[a-zS]'; then
    echo "!! индекс скрывает отслеживаемые изменения (assume-unchanged/skip-worktree)" >&2
    echo "   Очистите эти флаги перед выпуском; пути намеренно не печатаются." >&2
    exit 1
fi

ref="refs/tags/$tag"
git show-ref --verify --quiet "$ref" || {
    echo "!! тега $tag нет в этом checkout" >&2
    exit 1
}

object_type="$(git cat-file -t "$ref" 2>/dev/null || true)"
if [ "$object_type" != "tag" ]; then
    echo "!! $tag — lightweight tag; для выпуска нужен аннотированный тег" >&2
    echo "   Создайте его после review: git tag -a $tag -m 'cruxwing $tag'" >&2
    exit 1
fi

tag_commit="$(git rev-parse --verify "$ref^{commit}")"
head_commit="$(git rev-parse --verify 'HEAD^{commit}')"
if [ "$tag_commit" != "$head_commit" ]; then
    echo "!! HEAD не совпадает с $tag" >&2
    echo "   checkout: $head_commit" >&2
    echo "   tag:      $tag_commit" >&2
    exit 1
fi

base_ref="origin/main"
base_commit="$(git rev-parse --verify "$base_ref^{commit}" 2>/dev/null || true)"
if [ -z "$base_commit" ]; then
    echo "!! не найден $base_ref; получите полную историю main перед выпуском" >&2
    exit 1
fi
if ! git merge-base --is-ancestor "$tag_commit" "$base_commit"; then
    echo "!! $tag не принадлежит истории $base_ref" >&2
    exit 1
fi

plist="app/Support/Info.plist"
[ -f "$plist" ] || { echo "!! нет $plist" >&2; exit 1; }
version="$(python3 - "$plist" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as handle:
    value = plistlib.load(handle).get("CFBundleShortVersionString", "")
print(value)
PY
)"
if [ "$tag" != "v$version" ]; then
    echo "!! тег $tag не совпадает с CFBundleShortVersionString=$version" >&2
    exit 1
fi

source_hash="$(bash scripts/app-source-hash.sh)"
[[ "$source_hash" =~ ^[0-9a-f]{64}$ ]] || {
    echo "!! не удалось получить полный SHA-256 входов приложения" >&2
    exit 1
}

# The clean tree check only covers the current snapshot. Public history is a
# separate input to an open-source release, so run the exact-blob reviewed scan
# here rather than assuming ordinary source tests saw every reachable object.
node scripts/scan-history-secrets.mjs

echo "release tag: $tag (annotated)"
echo "version:     $version"
echo "commit:      $tag_commit"
echo "base:        $base_ref ($base_commit)"
echo "source:      $source_hash"
echo "OK: чистый тег относится к проверенной ветке и совпадает с версией приложения"
