#!/usr/bin/env bash
# Verify the resolved source-control checkouts an active SwiftPM build uses.
#
# Usage: bash scripts/verify-swiftpm-checkouts.sh <scratch-path> <Package.resolved>
#
# The project worktree can be clean while an ignored .build/checkouts package is
# modified. SwiftPM compiles that working copy, not an abstract revision from
# Package.resolved, so release provenance must inspect both its HEAD and status.
set -euo pipefail

scratch="${1:?usage: verify-swiftpm-checkouts.sh <scratch-path> <Package.resolved>}"
resolved="${2:?usage: verify-swiftpm-checkouts.sh <scratch-path> <Package.resolved>}"
state="$scratch/workspace-state.json"

for tool in git plutil; do
    command -v "$tool" >/dev/null || {
        echo "!! $tool is required to verify SwiftPM release inputs" >&2
        exit 2
    }
done
[ -s "$resolved" ] || { echo "!! missing Package.resolved: $resolved" >&2; exit 1; }
[ -s "$state" ] || { echo "!! missing SwiftPM workspace state: $state" >&2; exit 1; }

checkout_git() {
    local checkout_root="$1"
    shift
    # A caller may use GIT_INDEX_FILE to verify a prospective release tree.
    # That index belongs to the Orakul repository, never to SwiftPM's nested
    # checkout repositories.
    env -u GIT_INDEX_FILE git -C "$checkout_root" "$@"
}

dependency_count="$(plutil -extract object.dependencies raw -o - "$state" 2>/dev/null)" || {
    echo "!! cannot read dependencies from $state" >&2
    exit 1
}
pin_count="$(plutil -extract pins raw -o - "$resolved" 2>/dev/null)" || {
    echo "!! cannot read pins from $resolved" >&2
    exit 1
}
[[ "$dependency_count" =~ ^[0-9]+$ && "$pin_count" =~ ^[0-9]+$ ]] || {
    echo "!! malformed SwiftPM dependency metadata" >&2
    exit 1
}

pinned_revision() {
    local wanted="$1" found="" i identity revision
    for ((i = 0; i < pin_count; i++)); do
        identity="$(plutil -extract "pins.$i.identity" raw -o - "$resolved" 2>/dev/null || true)"
        [ "$identity" = "$wanted" ] || continue
        [ -z "$found" ] || {
            echo "!! duplicate Package.resolved identity: $wanted" >&2
            return 1
        }
        revision="$(plutil -extract "pins.$i.state.revision" raw -o - "$resolved" 2>/dev/null || true)"
        found="$revision"
    done
    [ -n "$found" ] || {
        echo "!! active SwiftPM checkout is not pinned: $wanted" >&2
        return 1
    }
    printf '%s' "$found"
}

verified=0
for ((i = 0; i < dependency_count; i++)); do
    kind="$(plutil -extract "object.dependencies.$i.packageRef.kind" raw -o - "$state" 2>/dev/null || true)"
    [ "$kind" = "remoteSourceControl" ] || continue

    identity="$(plutil -extract "object.dependencies.$i.packageRef.identity" raw -o - "$state" 2>/dev/null || true)"
    subpath="$(plutil -extract "object.dependencies.$i.subpath" raw -o - "$state" 2>/dev/null || true)"
    workspace_revision="$(plutil -extract "object.dependencies.$i.state.checkoutState.revision" raw -o - "$state" 2>/dev/null || true)"
    [[ "$identity" =~ ^[A-Za-z0-9._-]+$ ]] || {
        echo "!! unsafe or empty SwiftPM identity in workspace state" >&2
        exit 1
    }
    case "$subpath" in
        ""|.|..|*/*|*\\*)
            echo "!! unsafe SwiftPM checkout subpath for $identity" >&2
            exit 1
            ;;
    esac

    expected_revision="$(pinned_revision "$identity")" || exit 1
    [[ "$expected_revision" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]] || {
        echo "!! invalid pinned revision for $identity" >&2
        exit 1
    }
    [ "$workspace_revision" = "$expected_revision" ] || {
        echo "!! SwiftPM workspace revision differs from Package.resolved for $identity" >&2
        exit 1
    }

    checkout="$scratch/checkouts/$subpath"
    [ -d "$checkout" ] && [ ! -L "$checkout" ] || {
        echo "!! missing or symlinked SwiftPM checkout for $identity" >&2
        exit 1
    }
    checkout_git "$checkout" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
        echo "!! SwiftPM checkout is not a Git worktree: $identity" >&2
        exit 1
    }
    actual_revision="$(checkout_git "$checkout" rev-parse --verify 'HEAD^{commit}' 2>/dev/null || true)"
    [ "$actual_revision" = "$expected_revision" ] || {
        echo "!! SwiftPM checkout HEAD differs from Package.resolved for $identity" >&2
        exit 1
    }
    checkout_status="$(checkout_git "$checkout" status --porcelain=v1 --untracked-files=all 2>/dev/null)" || {
        echo "!! cannot inspect SwiftPM checkout status for $identity" >&2
        exit 1
    }
    [ -z "$checkout_status" ] || {
        # Do not print paths or contents: a dependency checkout may contain a
        # locally tested credential or private patch.
        echo "!! modified SwiftPM checkout cannot be used for DIST: $identity" >&2
        exit 1
    }
    ignored_checkout_files="$(checkout_git "$checkout" ls-files --others --ignored --exclude-standard 2>/dev/null)" || {
        echo "!! cannot inspect ignored SwiftPM checkout files for $identity" >&2
        exit 1
    }
    [ -z "$ignored_checkout_files" ] || {
        # `git status` intentionally hides ignored paths, but SwiftPM can still
        # compile or copy one when it lies below a target/resource root.
        echo "!! ignored file in SwiftPM checkout cannot be used for DIST: $identity" >&2
        exit 1
    }
    checkout_index="$(checkout_git "$checkout" ls-files -v 2>/dev/null)" || {
        echo "!! cannot inspect SwiftPM checkout index flags for $identity" >&2
        exit 1
    }
    while IFS= read -r checkout_index_entry; do
        [ -n "$checkout_index_entry" ] || continue
        [ "${checkout_index_entry:0:1}" = "H" ] || {
            echo "!! SwiftPM checkout uses a hidden Git index flag: $identity" >&2
            exit 1
        }
    done <<< "$checkout_index"
    verified=$((verified + 1))
done

[ "$verified" -gt 0 ] || {
    echo "!! active SwiftPM build exposed no pinned source-control checkouts" >&2
    exit 1
}
echo ">> SwiftPM checkouts clean and pinned ($verified verified)"
