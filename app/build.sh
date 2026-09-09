#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_ARCH="${MEETGPT_ARCH:-native}"
SWIFT_BUILD_ARGS=(-c release)
SWIFT_SCRATCH="$ROOT/.build"
case "$BUILD_ARCH" in
    native)
        DEFAULT_APP_BASENAME="cruxwing"
        ;;
    arm64|x86_64)
        SWIFT_SCRATCH="$ROOT/.build/$BUILD_ARCH"
        SWIFT_BUILD_ARGS+=(--triple "${BUILD_ARCH}-apple-macosx13.0"
                           --scratch-path "$SWIFT_SCRATCH")
        if [ "$BUILD_ARCH" = "x86_64" ]; then
            DEFAULT_APP_BASENAME="cruxwing-Intel"
        else
            DEFAULT_APP_BASENAME="cruxwing"
        fi
        ;;
    *)
        echo "!! unsupported MEETGPT_ARCH=$BUILD_ARCH (use native, arm64, or x86_64)" >&2
        exit 2
        ;;
esac
APP_BASENAME="${MEETGPT_APP_BASENAME:-$DEFAULT_APP_BASENAME}"
STAGE="$ROOT/build/$APP_BASENAME.app"    # staging copy inside the repo
ENT="$ROOT/Support/MeetGPT.entitlements"
SANDBOX_ENT="$ROOT/Support/MeetGPT.sandbox.entitlements"
# App Sandbox is MANDATORY for distribution (the Mac App Store requires it), and
# opt-in for a dev build via MEETGPT_SANDBOX=1. A dist build (MEETGPT_DIST=1, set
# by notarize.sh / appstore.sh) ALWAYS signs with the sandboxed entitlements —
# the non-sandbox profile can never ship (M8). Screen/audio capture + the
# loopback OAuth listener still need an interactive check under the sandbox
# (M8 runtime gate — a dev build never exercises them sandboxed).
if [ "${MEETGPT_DIST:-0}" = "1" ] || [ "${MEETGPT_SANDBOX:-0}" = "1" ]; then
    # Fail-safe: a distribution build must never silently fall back to the
    # non-sandbox profile if the entitlements file is missing.
    if [ ! -f "$SANDBOX_ENT" ]; then
        echo "!! sandbox entitlements missing ($SANDBOX_ENT) — refusing to build" >&2
        exit 1
    fi
    ENT="$SANDBOX_ENT"
    if [ "${MEETGPT_DIST:-0}" = "1" ]; then
        echo ">> SANDBOXED build (mandatory for distribution)"
    else
        echo ">> SANDBOXED build (opt-in) — verify system-audio/mic capture + OAuth loopback before relying on it"
    fi
fi
# Inspection hatch: print the resolved entitlements and exit (no compile/sign).
# Lets CI/humans confirm the dist→sandbox tie without a full build.
if [ "${MEETGPT_PRINT_ENT:-0}" = "1" ]; then
    echo "ENT=$ENT"
    exit 0
fi
ICON="$ROOT/Support/AppIcon.icns"

# Install to a STABLE location so the app always runs from the same path.
# macOS TCC (Screen Recording / Microphone) is happier when the bundle path
# doesn't move between launches. Override with MEETGPT_APP_DIR, or set
# MEETGPT_NO_INSTALL=1 to run straight from the repo staging copy.
APP_DIR="${MEETGPT_APP_DIR:-/Applications}"
DEST="$APP_DIR/$APP_BASENAME.app"
LEGACY_DEST="$APP_DIR/MeetGPT.app"

cd "$ROOT"

# --- Generate optional LOCAL build configuration from .env ---
# The generated file is ignored. `Sources/MeetGPT/Secrets.swift` remains the
# immutable, safe fallback used by clones, tests and distribution builds.
echo ">> generating ignored LocalSecrets.generated.swift from .env"
ENV_FILE="$ROOT/.env"
SECRETS="$ROOT/Sources/MeetGPT/LocalSecrets.generated.swift"

# Distribution hardening: a release build (MEETGPT_DIST=1, set by notarize.sh)
# bakes NO provider/org secrets into the binary. The shipped app talks directly
# to the provider with a key the user stores in Keychain
# (LLM_GATEWAY=direct), and transcribes on-device
# (TRANSCRIPTION_ENGINE=local). Local builds may still compile explicitly
# development-only connector OAuth and non-secret transcription tuning from
# this repository's ignored .env, but every provider key is runtime BYOK.
DIST="${MEETGPT_DIST:-0}"

# A release commit must be enough to reconstruct the bytes being shipped.
# CruxwingSourceHash distinguishes two local builds, but it cannot recover files
# that were never committed; stamping HEAD alone would therefore make a dirty
# release look attributable while leaving no source revision that can rebuild
# it. Check the entire worktree (not only app/) before compiling.
#
# The override exists only for exercising the distribution build path locally.
# Such an artifact is stamped as dirty, and audit-dmg.sh rejects it, so it cannot
# pass the release audit by accident.
DIST_TREE_STATE="development"
require_clean_dist_tree() {
    [ "$DIST" = "1" ] || return 0

    local repo_root dirty_status index_entries index_entry
    local untracked_inputs ignored_inputs artifact_input
    repo_root="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null)" || {
        echo "!! DIST build is not inside a Git worktree — release provenance is unavailable" >&2
        return 1
    }
    dirty_status="$(git -C "$repo_root" status --porcelain=v1 --untracked-files=all 2>/dev/null)" || {
        echo "!! DIST build could not verify worktree cleanliness" >&2
        return 1
    }

    # `assume-unchanged` and sparse/skip-worktree index flags can hide a changed
    # tracked file from both status and diff. A release checkout must not use
    # either optimization anywhere: otherwise HEAD can again describe bytes
    # other than the ones the compiler reads.
    index_entries="$(git -C "$repo_root" ls-files -v 2>/dev/null)" || {
        echo "!! DIST build could not inspect Git index flags" >&2
        return 1
    }
    while IFS= read -r index_entry; do
        [ -n "$index_entry" ] || continue
        [ "${index_entry:0:1}" = "H" ] || {
            echo "!! DIST build found a tracked file hidden by a Git index flag" >&2
            echo "!! Clear assume-unchanged/skip-worktree state before release; the path is withheld" >&2
            return 1
        }
    done <<< "$index_entries"

    # `git status --untracked-files=all` still hides ignored files. Most ignored
    # paths are harmless build caches, but an ignored *.pem, *.key, *.log or
    # .DS_Store below a copied/source root is an artifact input: SwiftPM copies
    # the whole Skills directory, and app-source-hash walks these roots. Such a
    # file would ship under a "clean" HEAD without existing in that commit.
    #
    # LocalSecrets.generated.swift is the one deliberate exception. build.sh
    # creates it from .env for local builds, but DIST never enables
    # CRUXWING_LOCAL_CONFIG, so it is neither compiled nor copied.
    untracked_inputs="$(git -C "$repo_root" ls-files --others \
        --exclude-standard -- \
        app/Support app/Sources/MeetGPT mvp/Sources/CruxwingCore 2>/dev/null)" || {
        echo "!! DIST build could not inspect untracked artifact inputs" >&2
        return 1
    }
    [ -z "$untracked_inputs" ] || {
        echo "!! DIST build found an untracked file inside an artifact input root" >&2
        echo "!! Track or remove it before release; its path/content is withheld from logs" >&2
        return 1
    }

    ignored_inputs="$(git -C "$repo_root" ls-files --others --ignored \
        --exclude-standard -- \
        app/Support app/Sources/MeetGPT mvp/Sources/CruxwingCore 2>/dev/null)" || {
        echo "!! DIST build could not inspect ignored artifact inputs" >&2
        return 1
    }
    while IFS= read -r artifact_input; do
        [ -n "$artifact_input" ] || continue
        [ "$artifact_input" = "app/Sources/MeetGPT/LocalSecrets.generated.swift" ] && continue
        echo "!! DIST build found an ignored file inside an artifact input root" >&2
        echo "!! Move or track it before release; its path/content is withheld from logs" >&2
        return 1
    done <<< "$ignored_inputs"

    if [ -n "$dirty_status" ]; then
        if [ "${CRUXWING_ALLOW_DIRTY_DIST_FOR_LOCAL_VERIFICATION:-0}" != "1" ]; then
            echo "!! DIST build requires a clean Git worktree; commit or remove all changes first" >&2
            echo "!! For a non-release local build-path check only: CRUXWING_ALLOW_DIRTY_DIST_FOR_LOCAL_VERIFICATION=1" >&2
            return 1
        fi
        DIST_TREE_STATE="dirty-local-verification"
        echo ">> WARNING: dirty DIST build allowed for local verification only"
        echo ">> scripts/audit-dmg.sh will reject this artifact"
        return 0
    fi

    DIST_TREE_STATE="clean"
}
require_clean_dist_tree || exit 1
# Известные секреты — перечислены для читателя, а НЕ для решения: решение
# принимает разрешительный список внутри sw(). Оставлен потому, что отвечает на
# вопрос «что вообще бывает в .env», и потому что §5.2 роадмапа считает по нему
# размер дыры, которой больше нет.
SECRET_VARS="GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET GOOGLE_SIGNIN_CLIENT_ID GOOGLE_SIGNIN_CLIENT_SECRET HUBSPOT_CLIENT_ID HUBSPOT_CLIENT_SECRET ASANA_CLIENT_ID ASANA_CLIENT_SECRET AFFINITY_CLIENT_ID AFFINITY_CLIENT_SECRET ZOOM_CLIENT_ID ZOOM_CLIENT_SECRET SLACK_BOT_TOKEN SLACK_CHANNEL_IDS CONFLUENCE_SITE CONFLUENCE_EMAIL CONFLUENCE_TOKEN"

sw() {  # sw VAR  -> value of VAR from .env (empty if absent), Swift-string-escaped
    if [ "$DIST" = "1" ]; then
        # Правило перевёрнуто 2026-08-18: в раздаваемую сборку попадает только
        # то, что названо ЯВНО. Всё остальное стирается, чем бы оно ни было.
        #
        # Почему. Сначала был список секретов — мимо него прошли четыре имени
        # (GMAIL_CLIENT_ID, GMAIL_CLIENT_SECRET, GOOGLE_ANALYTICS_CLIENT_ID,
        # GOOGLE_ANALYTICS_CLIENT_SECRET). Потом добавился класс имён
        # (*_TOKEN, *_API_KEY и подобные) — и остался зазор, записанный в §11
        # роадмапа честно: секрет с именем без узнаваемой формы по-прежнему
        # держался на списке, написанном руками. SLACK_CHANNEL_IDS,
        # CONFLUENCE_SITE, CONFLUENCE_EMAIL — как раз такие.
        #
        # Запрет по умолчанию убирает зазор целиком: чтобы значение попало в
        # бинарник, о нём надо сказать вслух здесь. Цена ошибки меняет знак — не
        # «секрет уехал молча», а «настройка не приехала», и это видно при
        # первом же запуске.
        case "$1" in
            BACKEND_URL|BACKEND_CERT_PINS|DEFAULT_TIER|LLM_GATEWAY \
                |ENSEMBLE_CHAIRMAN|ENSEMBLE_PANEL|TEAM_WATCH_AUTO_ACK \
                |TRANSCRIPTION_ENGINE|TRANSCRIPTION_CHUNK_SECONDS \
                |TRANSCRIPTION_CHUNK_OVERLAP_SECONDS \
                |TRANSCRIPTION_BOUNDARY_SLACK_SECONDS \
                |TRANSCRIPTION_LOCAL_MODEL|TRANSCRIPTION_VAD \
                |TRANSCRIPTION_LANGUAGE) : ;;   # exact non-secret settings
            # `BACKEND_URL` стоит в списке, хотя в сборку всё равно уезжает
            # пустым: его отдельно стирают ниже, и там же написано почему.
            # Убрать его отсюда — значит сделать то объяснение недостижимым
            # кодом, а вместе с ним и причину.
            *) printf ''; return ;;
        esac
        # cruxwing: прямой доступ к провайдеру, не через шлюз.
        #
        # У Cruxwing здесь стояло 'backend' — и это правильно для продукта, у
        # которого сервер есть: ключи остаются на сервере, в бинарник не
        # попадает ничего. У cruxwing сервера нет (api.cruxwing.ai не резолвится),
        # поэтому то же значение означало бы: каждый запрос уходит в никуда,
        # введённый пользователем ключ не читается вовсе, а isConfigured
        # отвечает «настроено» за все провайдеры сразу. Установщик выглядел бы
        # рабочим и не отвечал ни на один вопрос — так и было, пока не поймали.
        #
        # Гарантия «в бинарнике нет секретов» не меняется: разрешительный
        # список выше пропускает только публичные настройки. Ключ приезжает из Связки ключей в
        # рантайме, его вводит человек в настройках.
        [ "$1" = "LLM_GATEWAY" ] && { printf 'direct'; return; }
        # Расшифровка — на устройстве. 'server' означал бы managed Whisper на
        # нашем сервере, которого нет.
        [ "$1" = "TRANSCRIPTION_ENGINE" ] && { printf 'local'; return; }
        # Адрес сервера не бакается: у cruxwing сервера нет.
        #
        # У cruxwing здесь подставлялся боевой адрес, потому что без него
        # первый запуск упирался в пустоту. У cruxwing наоборот. LLM_GATEWAY
        # выше уже переключён на 'direct': запрос идёт к провайдеру с ключом
        # пользователя, и адрес в бинарнике не нужен ни для чего. Любой,
        # который сюда попадёт, будет либо мёртвым (`http://localhost:8787` —
        # из рабочей копии сборщика), либо чужим (`https://api.cruxwing.ai` —
        # сервер другого продукта). Второе хуже: этот адрес существует и
        # отвечает.
        #
        # Пустая строка — рабочее значение, а не заглушка: Config и AppState
        # проверяют её через `.isEmpty` и в этом случае не показывают вход и
        # серверные модели.
        [ "$1" = "BACKEND_URL" ] && { printf ''; return; }
    fi
    local v=""
    if [ -f "$ENV_FILE" ]; then
        v="$(grep -E "^$1=" "$ENV_FILE" | tail -n1 | cut -d= -f2- || true)"
    fi
    # This repo's own .env is the ONLY source. There used to be a fallback to a
    # repo-root .env one level up, which in the monorepo resolved to the
    # backend's env and let the Mac build inherit provider keys it had not been
    # given. The split made these repos independent, so that path now resolves
    # to whatever directory the checkouts happen to share — nothing, a sibling
    # project, or somebody else's secrets.
    #
    # Losing it costs nothing here: every build reads the user's provider key
    # from Keychain at runtime. LLM credentials are deliberately not part of
    # this generated build configuration, even for local development.
    # strip an inline comment (# at line start or after whitespace) + trim, so a
    # value like `BACKEND_URL= # fill me` bakes as empty, not the comment text.
    v="$(printf '%s' "$v" | sed -E 's/(^|[[:space:]])#.*$/\1/; s/^[[:space:]]+//; s/[[:space:]]+$//')"
    v="${v%\"}"; v="${v#\"}"                 # strip optional surrounding quotes
    v="${v//\\/\\\\}"; v="${v//\"/\\\"}"      # escape backslash and quote
    printf '%s' "$v"
}
cat > "$SECRETS" <<EOF
// GENERATED AND GITIGNORED — local build values only.
// A distribution build never enables CRUXWING_LOCAL_CONFIG.
#if CRUXWING_LOCAL_CONFIG
enum Secrets {
    // Local/test builds may use the gitignored .env Desktop OAuth client.
    // MEETGPT_DIST=1 blanks both values: sw() пропускает только публичные настройки.
    static let googleClientID  = "$(sw GOOGLE_CLIENT_ID)"
    // A native OAuth client cannot keep this credential confidential. Local and
    // tester builds may inject it from the gitignored .env; public distribution
    // builds still scrub it so they cannot accidentally reuse a private project.
    static let googleClientSecret = "$(sw GOOGLE_CLIENT_SECRET)"
    static let backendBaseURL  = "$(sw BACKEND_URL)"
    static let backendCertPins = "$(sw BACKEND_CERT_PINS)"
    static let transcriptionEngine = "$(sw TRANSCRIPTION_ENGINE)"
    static let transcriptionChunkSeconds = "$(sw TRANSCRIPTION_CHUNK_SECONDS)"
    static let transcriptionChunkOverlapSeconds = "$(sw TRANSCRIPTION_CHUNK_OVERLAP_SECONDS)"
    static let transcriptionBoundarySlackSeconds = "$(sw TRANSCRIPTION_BOUNDARY_SLACK_SECONDS)"
    static let defaultTier     = "$(sw DEFAULT_TIER)"
    // NOT read from .env: "1" only when this is a dev build (MEETGPT_DIST unset).
    // Gates the in-app Developer tools (tier preview). Dist builds bake "0".
    static let devMode         = "$([ "$DIST" = "1" ] && printf '0' || printf '1')"
    static let localWhisperModel = "$(sw TRANSCRIPTION_LOCAL_MODEL)"
    static let transcriptionVAD = "$(sw TRANSCRIPTION_VAD)"
    static let transcriptionLanguage = "$(sw TRANSCRIPTION_LANGUAGE)"
    static let llmGateway      = "$(sw LLM_GATEWAY)"
    static let ensemblePanel   = "$(sw ENSEMBLE_PANEL)"
    static let ensembleChairman = "$(sw ENSEMBLE_CHAIRMAN)"
    static let hubSpotClientID = "$(sw HUBSPOT_CLIENT_ID)"
    static let hubSpotClientSecret = "$(sw HUBSPOT_CLIENT_SECRET)"
    static let asanaClientID = "$(sw ASANA_CLIENT_ID)"
    static let asanaClientSecret = "$(sw ASANA_CLIENT_SECRET)"
    static let affinityClientID = "$(sw AFFINITY_CLIENT_ID)"
    static let affinityClientSecret = "$(sw AFFINITY_CLIENT_SECRET)"
    static let zoomClientID = "$(sw ZOOM_CLIENT_ID)"
    static let zoomClientSecret = "$(sw ZOOM_CLIENT_SECRET)"
    static let googleSignInClientID = "$(sw GOOGLE_SIGNIN_CLIENT_ID)"
    static let googleSignInClientSecret = "$(sw GOOGLE_SIGNIN_CLIENT_SECRET)"
    static let gmailClientID = "$(sw GMAIL_CLIENT_ID)"
    static let gmailClientSecret = "$(sw GMAIL_CLIENT_SECRET)"
    static let googleAnalyticsClientID = "$(sw GOOGLE_ANALYTICS_CLIENT_ID)"
    static let googleAnalyticsClientSecret = "$(sw GOOGLE_ANALYTICS_CLIENT_SECRET)"
    static let slackBotToken   = "$(sw SLACK_BOT_TOKEN)"
    static let slackChannelIDs = "$(sw SLACK_CHANNEL_IDS)"
    static let confluenceSite  = "$(sw CONFLUENCE_SITE)"
    static let confluenceEmail = "$(sw CONFLUENCE_EMAIL)"
    static let confluenceToken = "$(sw CONFLUENCE_TOKEN)"
    static let teamWatchAutoAck = "$(sw TEAM_WATCH_AUTO_ACK)"
}
#endif
EOF

if [ "$DIST" != "1" ]; then
    SWIFT_BUILD_ARGS+=(-Xswiftc -DCRUXWING_LOCAL_CONFIG)
fi

if [ "$DIST" = "1" ]; then
    echo ">> DIST build: ключи не бакаются — их вводит человек, расшифровка на устройстве"
    # Читается файл, который DIST действительно компилирует. Локальный
    # `LocalSecrets.generated.swift` в этом режиме остаётся под выключенным
    # `#if CRUXWING_LOCAL_CONFIG`; проверять его означало бы доказывать свойства
    # файла, которого в отгружаемом бинарнике нет.
    #
    # Раньше здесь стояло `sw BACKEND_URL` — и это была мёртвая проверка: тот
    # же `sw` двадцатью строками выше стирает BACKEND_URL в dist-ветке, так что
    # переменная была пуста ВСЕГДА, останов не мог сработать ни при каких
    # обстоятельствах, а «сервер не задан — так и задумано» печаталось как
    # доказательство. Правило репозитория ровно об этом: проверять отгружаемое,
    # а не то, что его кормит.
    #
    # Ровно одно строковое объявление: отсутствие/динамическое выражение не
    # трактуется как пустота. Иначе переименование поля убрало бы саму проверку,
    # а сборка продолжила бы докладывать «сервер не задан».
    DIST_CONFIG="$ROOT/Sources/MeetGPT/Secrets.swift"
    DIST_BACKEND_COUNT="$(grep -Ec '^[[:space:]]*static let backendBaseURL[[:space:]]*=[[:space:]]*"[^"]*"[[:space:]]*$' "$DIST_CONFIG" || true)"
    if [ "$DIST_BACKEND_COUNT" != "1" ]; then
        echo "!! В $DIST_CONFIG ожидалось ровно одно строковое объявление backendBaseURL" >&2
        exit 1
    fi
    DIST_BACKEND="$(sed -n 's/.*backendBaseURL[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$DIST_CONFIG")"
    # Проверка перевёрнута против cruxwing. Там запрещался адрес рабочей копии
    # (`localhost`) при обязательном боевом; здесь запрещён любой непустой:
    # cruxwing ходит к провайдеру напрямую, сервера у него нет, и адрес в
    # бинарнике может только увести данные не туда. Останов жёсткий, потому что
    # на машине сборщика такая ошибка не видна.
    if [ -n "$DIST_BACKEND" ]; then
        echo "!! В DIST-сборку попал адрес сервера ($DIST_BACKEND) — отказ." >&2
        echo "!! У cruxwing нет сервера: LLM_GATEWAY=direct, ключ пользователя, запрос к провайдеру." >&2
        echo "!! Адрес попал в отгружаемый Secrets.swift — уберите его источник, а не эту проверку." >&2
        exit 1
    fi
    echo ">> сервер не задан — так и задумано"
fi

# Установщик собирается с чистого листа.
#
# SwiftPM держит список файлов зависимости-по-пути в кеше на каждую
# архитектуру (`.build/arm64`, `.build/x86_64`) и НЕ замечает там новый файл.
# `TranscriptCleanup.swift`, добавленный в ядро, уронил сборку установщика с
# «cannot find TranscriptCleanup in scope» — при том что `swift build` в app/
# в тот же момент собирался: у отладочной сборки свой кеш, и он был свежий.
# Дата на манифесте ядра не помогает, список пересчитывается по содержимому.
#
# Для установщика чистая сборка правильна и без этой причины: DMG обязан
# отвечать исходникам, на которые ссылается его штамп, а не остаткам прошлого
# прогона. Платим двумя минутами на архитектуру.
if [ "$BUILD_ARCH" != "native" ]; then
    # A prospective-release check may provide GIT_INDEX_FILE for Cruxwing's root
    # tree. SwiftPM spawns Git while creating dependency worktrees; forwarding
    # the root index into those nested repositories leaves their own indexes
    # empty (every file appears deleted and untracked). The compiler never
    # needs Cruxwing's alternate index, so keep that boundary out of SwiftPM.
    env -u GIT_INDEX_FILE swift package "${SWIFT_BUILD_ARGS[@]}" clean 2>/dev/null || true
fi

if [ "$DIST" = "1" ]; then
    # Resolution may fetch a missing checkout, but it may not choose a newer
    # revision than the reviewed lockfile. Inspect the exact scratch path this
    # architecture will compile: app/.build is ignored, so the main clean-tree
    # gate cannot see a hand-edited dependency checkout.
    echo ">> resolving exactly Package.resolved and verifying SwiftPM checkouts"
    env -u GIT_INDEX_FILE swift package "${SWIFT_BUILD_ARGS[@]}" \
        --only-use-versions-from-resolved-file resolve
    bash "$ROOT/../scripts/verify-swiftpm-checkouts.sh" \
        "$SWIFT_SCRATCH" "$ROOT/Package.resolved"
fi

echo ">> swift build (release, $BUILD_ARCH)"
env -u GIT_INDEX_FILE swift build "${SWIFT_BUILD_ARGS[@]}"
if [ "$DIST" = "1" ]; then
    # Catch a checkout changed while compilation was running as well as one
    # already dirty before it. A releasable dependency cannot generate files
    # into its own source tree.
    bash "$ROOT/../scripts/verify-swiftpm-checkouts.sh" \
        "$SWIFT_SCRATCH" "$ROOT/Package.resolved"
fi
BIN_DIR="$(env -u GIT_INDEX_FILE swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)"
BIN="$BIN_DIR/MeetGPT"
[ -x "$BIN" ] || { echo "!! built executable missing: $BIN" >&2; exit 1; }

echo ">> packaging $STAGE"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"

cp "$BIN" "$STAGE/Contents/MacOS/MeetGPT"
cp "$ROOT/Support/Info.plist" "$STAGE/Contents/Info.plist"
# MAS requires a strictly increasing CFBundleVersion — derive from git height.
BUILD_NUM="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUM" "$STAGE/Contents/Info.plist" 2>/dev/null || true
# The full commit this bundle reports it was built from. A short prefix is
# convenient in a UI but ambiguous as release provenance; the plist is the
# machine-readable record and therefore keeps the complete object id.
GIT_SHA="$(git -C "$ROOT" rev-parse --verify 'HEAD^{commit}' 2>/dev/null || true)"
if [ -z "$GIT_SHA" ]; then
    if [ "$DIST" = "1" ]; then
        echo "!! DIST build has no Git commit to stamp — refusing an untraceable release" >&2
        exit 1
    fi
    GIT_SHA="unknown"
fi
/usr/libexec/PlistBuddy -c "Add :CruxwingCommit string $GIT_SHA" "$STAGE/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :CruxwingCommit $GIT_SHA" "$STAGE/Contents/Info.plist" 2>/dev/null || true
if ! /usr/libexec/PlistBuddy -c "Add :CruxwingTreeState string $DIST_TREE_STATE" \
        "$STAGE/Contents/Info.plist" 2>/dev/null \
   && ! /usr/libexec/PlistBuddy -c "Set :CruxwingTreeState $DIST_TREE_STATE" \
        "$STAGE/Contents/Info.plist" 2>/dev/null; then
    echo "!! could not stamp worktree provenance in Info.plist" >&2
    exit 1
fi
# Полный SHA-256 исходников и входов упаковки — потому что одного коммита мало.
#
# Коммит отвечает на вопрос «какой ref был выписан», а не «что внутри». При
# незакоммиченном дереве он врёт молча: 12 августа подряд собрано девять разных
# DMG, и все девять несли один и тот же `CruxwingCommit`, при 149 изменённых
# файлах. Отличить сборку с десятью коннекторами от вчерашней по штампу было
# нельзя.
#
# `LocalSecrets.generated.swift` исключается общей реализацией source-hash.sh: он
# генерируется из .env, и его содержимое зависит от режима, а не от исходников.
# Безопасный, отслеживаемый `Secrets.swift` при этом входит в штамп.
# Ядро входит в хеш наравне с приложением. Раньше считалось только по
# `Sources/MeetGPT`, а с тех пор приложение линкует CruxwingCore: коннекторы,
# словарь и поиск ушли туда и физически лежат в этом же бинарнике. Проверено:
# три файла ядра поменялись, бинарник пересобрался — штамп остался прежним.
# Штамп, который не замечает половину того, что отгружает, хуже отсутствующего:
# на него ссылается форма отчёта об ошибке. Сборка и аудит вызывают один скрипт,
# чтобы не расходиться из-за платформы, формы пути или алгоритма.
SOURCE_HASH="$(bash "$ROOT/../scripts/app-source-hash.sh")"
/usr/libexec/PlistBuddy -c "Add :CruxwingSourceHash string $SOURCE_HASH" "$STAGE/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :CruxwingSourceHash $SOURCE_HASH" "$STAGE/Contents/Info.plist" 2>/dev/null || true
echo ">> исходники: $SOURCE_HASH (коммит $GIT_SHA)"
# App-level privacy manifest (App Review requirement).
cp "$ROOT/Support/PrivacyInfo.xcprivacy" "$STAGE/Contents/Resources/PrivacyInfo.xcprivacy"

# The executable statically links permissively licensed dependencies. Their
# redistribution terms must travel with the binary, not merely remain available
# in a source checkout that most DMG users will never see. Keep tracked snapshots
# so a clean release does not depend on SwiftPM's generated checkout layout.
LEGAL="$ROOT/Support/Legal"
LEGAL_MANIFEST="$LEGAL/MANIFEST.sha256"
if [ ! -s "$LEGAL_MANIFEST" ]; then
    echo "!! legal payload manifest missing ($LEGAL_MANIFEST) — refusing to package" >&2
    exit 1
fi
if ! cmp -s "$ROOT/../LICENSE" "$LEGAL/Cruxwing/LICENSE"; then
    echo "!! bundled Cruxwing license is stale — sync Support/Legal/Cruxwing/LICENSE" >&2
    exit 1
fi
if ! (cd "$LEGAL" && shasum -a 256 -c MANIFEST.sha256 >/dev/null); then
    echo "!! legal payload differs from its tracked SHA-256 manifest" >&2
    exit 1
fi
rm -rf "$STAGE/Contents/Resources/Legal"
cp -R "$LEGAL" "$STAGE/Contents/Resources/Legal"

# SwiftPM emits bundled resources (the vendored Agent Skills + role matrix) as
# a sibling resource bundle next to the built binary. In the .app it belongs in
# Contents/Resources: that's where Bundle.module's packaged-app search looks
# (Bundle.main.resourceURL), and codesign rejects loose bundles inside
# Contents/MacOS ("bundle format unrecognized").
RES_BUNDLE="$(dirname "$BIN")/MeetGPT_MeetGPT.bundle"
if [ -d "$RES_BUNDLE" ]; then
    rm -rf "$STAGE/Contents/Resources/MeetGPT_MeetGPT.bundle"
    cp -R "$RES_BUNDLE" "$STAGE/Contents/Resources/"
else
    echo ">> warning: $RES_BUNDLE missing — bundled skills won't be available"
fi
if [ -f "$ICON" ]; then
    cp "$ICON" "$STAGE/Contents/Resources/AppIcon.icns"
else
    echo ">> warning: $ICON missing — app will use the generic icon"
fi

# Pick a stable signing identity if one exists — otherwise ad-hoc.
# Stable signatures let macOS remember Screen Recording / Microphone grants
# across rebuilds. Ad-hoc re-signs every build, so macOS sees "a new app"
# every time and drops TCC permissions.
SIGN_ID="${MEETGPT_SIGN_ID:-}"
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
if [ -z "$SIGN_ID" ]; then
    SIGN_ID="$(printf '%s\n' "$IDENTITIES" \
              | grep -m1 "Developer ID Application" \
              | awk -F'"' '{print $2}' || true)"
fi
if [ -z "$SIGN_ID" ]; then
    SIGN_ID="$(printf '%s\n' "$IDENTITIES" \
              | grep -Em1 'Apple Development|Mac Developer|Cruxwing|MeetGPT' \
              | awk -F'"' '{print $2}' || true)"
fi
if [ -z "$SIGN_ID" ]; then
    # Self-signed dev certs are not "valid" (-v) until trusted in the keychain,
    # but codesign can still sign with them — and TCC keys on their stable
    # identity, which is all we need. Pick up an untrusted Cruxwing cert too;
    # retain MeetGPT as a compatibility fallback for existing developer setups.
    SIGN_ID="$(security find-identity -p codesigning 2>/dev/null \
              | grep -Em1 'Cruxwing|MeetGPT' | awk -F'"' '{print $2}' || true)"
fi
if [ -z "$SIGN_ID" ]; then
    SIGN_ID="-"
    echo ">> codesign: no stable identity found, using ad-hoc ( - )"
    echo "   Screen Recording / Microphone grants will reset on every rebuild."
    echo "   Fix once:  ./create-signing-cert.sh   (then rebuild)"
else
    echo ">> codesign: using identity \"$SIGN_ID\""
fi

# Sign in with Apple is a RESTRICTED entitlement, and TWO things must line up
# before a binary may carry it:
#   1. an Apple-issued signing identity, and
#   2. an embedded provisioning profile whose App ID grants the capability.
# An Apple identity ALONE is not enough — this gate used to assume it was, and
# the resulting build was pathological to diagnose: it installed, `codesign
# --verify --deep --strict` reported "valid on disk / satisfies its Designated
# Requirement", spctl objected only to notarization, and then launchd refused to
# spawn it with "Launch failed", POSIX 153, no crash report and nothing in the
# system log. The user just sees that the application cannot be opened.
# So drop the entitlement whenever either half is missing. Sign in with Apple is
# then absent from that build; Google and email OTP sign-in still work.
PROFILE="${MEETGPT_PROVISION_PROFILE:-$ROOT/Support/embedded.provisionprofile}"
SIGN_ENT="$ENT"
KEEP_APPLESIGNIN=0
case "$SIGN_ID" in
    "Developer ID Application"*|"Apple Development"*|"Apple Distribution"*|"3rd Party Mac Developer"*)
        [ -f "$PROFILE" ] && KEEP_APPLESIGNIN=1
        ;;
esac

if [ "$KEEP_APPLESIGNIN" = "1" ]; then
    # codesign seals the profile from inside the bundle, so it has to be in
    # place before signing, not after.
    cp "$PROFILE" "$STAGE/Contents/embedded.provisionprofile"
    echo ">> Sign in with Apple: enabled via $PROFILE"
else
    rm -f "$STAGE/Contents/embedded.provisionprofile"
    SIGN_ENT="$ROOT/build/.local.entitlements"
    mkdir -p "$ROOT/build"
    cp "$ENT" "$SIGN_ENT"
    /usr/libexec/PlistBuddy -c 'Delete :com.apple.developer.applesignin' "$SIGN_ENT" >/dev/null 2>&1 || true
    if [ -f "$PROFILE" ]; then
        WHY="signing identity \"$SIGN_ID\" is not Apple-issued"
    else
        WHY="no provisioning profile at $PROFILE"
    fi
    # В cruxwing здесь был жёсткий останов: сборка без этого entitlement теряет
    # вход через Apple молча, без ошибки, у всех сразу.
    #
    # В cruxwing терять нечего. Вход вообще не показывается: `wheesprAvailable`
    # в AppState включается только при непустом адресе сервера, а DIST-сборка
    # выше его не бакает. Аккаунтов у cruxwing нет — ключ провайдера человек
    # вводит сам, и он лежит в Связке ключей. Так что останавливать сборку
    # было бы требованием профиля ради возможности, которой в продукте нет.
    #
    # Останов остаётся на один случай: если вход когда-нибудь появится
    # (адрес сервера непустой), молчаливая потеря снова станет ошибкой.
    if [ "${MEETGPT_DIST:-0}" = "1" ] && [ -n "$DIST_BACKEND" ] \
       && [ "${MEETGPT_ALLOW_NO_APPLESIGNIN:-0}" != "1" ]; then
        echo "!! сборка для распространения потеряет вход через Apple — $WHY" >&2
        echo "   Профиль Developer ID для ai.cruxwing.desktop с Sign in with Apple" >&2
        echo "   положить в $PROFILE и пересобрать." >&2
        echo "   Выпустить без этого намеренно: MEETGPT_ALLOW_NO_APPLESIGNIN=1" >&2
        exit 1
    fi
    echo ">> Вход через Apple: не собирается — $WHY (в cruxwing входа нет)"
fi

# Sign the staging bundle before installing it. Developers often launch
# the staged app directly; leaving that copy unsigned gives it a different
# TCC identity from /Applications/cruxwing.app, so an apparently granted
# Microphone or Screen Recording permission is rejected at runtime.
codesign --force --deep --sign "$SIGN_ID" --entitlements "$SIGN_ENT" "$STAGE"
codesign --verify --deep --strict "$STAGE"

# Decide the final location only after signing, then copy the exact signed
# bundle. Both supported launch paths now have the same designated requirement.
if [ "${MEETGPT_NO_INSTALL:-0}" = "1" ]; then
    APP="$STAGE"
    echo ">> install skipped (MEETGPT_NO_INSTALL=1) — using $APP"
elif mkdir -p "$APP_DIR" 2>/dev/null && [ -w "$APP_DIR" ]; then
    APP="$DEST"
    echo ">> installing to $APP"
    rm -rf "$APP"
    cp -R "$STAGE" "$APP"
    codesign --verify --deep --strict "$APP"
    if [ "$APP_BASENAME" = "Cruxwing" ] && [ -d "$LEGACY_DEST" ]; then
        echo ">> removing legacy app wrapper $LEGACY_DEST"
        rm -rf "$LEGACY_DEST"
    fi
else
    APP="$STAGE"
    echo ">> warning: $APP_DIR not writable — using signed staging copy $APP"
    echo "   (to install: sudo cp -R \"$STAGE\" \"$APP_DIR/\")"
fi

# Refresh the icon cache so Finder/Dock pick up the new icon immediately.
touch "$APP"

# TCC keys a Screen Recording / Microphone grant on the bundle id AND the
# signing requirement. Another bundle on this Mac with the SAME id but a
# DIFFERENT requirement — a copy from an older project still signed with the
# local self-signed cert, say — makes macOS treat the two as different apps:
# the permission prompt returns on every launch, and no amount of adding and
# removing entries in System Settings converges, because the record never
# matches the binary that actually runs. That cost a debugging session; a build
# is the moment to notice it, since a build is what creates the copies.
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null || true)"
if [ -n "$BUNDLE_ID" ]; then
    OUR_REQ="$(codesign -d -r- "$APP" 2>/dev/null | sed -n 's/^designated => //p')"
    CONFLICTS=""
    while IFS= read -r other; do
        [ -z "$other" ] && continue
        [ "$other" = "$APP" ] && continue
        [ "$other" = "$STAGE" ] && continue     # our own staging copy, same signature
        other_req="$(codesign -d -r- "$other" 2>/dev/null | sed -n 's/^designated => //p')"
        [ "$other_req" = "$OUR_REQ" ] && continue
        CONFLICTS="$CONFLICTS  $other\n"
    done <<< "$(mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null || true)"
    if [ -n "$CONFLICTS" ]; then
        echo ">> warning: other bundles claim $BUNDLE_ID with a DIFFERENT signature:" >&2
        printf "$CONFLICTS" >&2
        echo "   Screen Recording / Microphone prompts will keep returning until they are removed." >&2
        echo "   Fix: delete them, then  tccutil reset ScreenCapture $BUNDLE_ID && tccutil reset Microphone $BUNDLE_ID" >&2
    fi
fi

echo ">> done: $APP"
echo "launch with: open \"$APP\""
