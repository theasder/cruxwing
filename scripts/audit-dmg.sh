#!/usr/bin/env bash
# Диагностика свежести одного или нескольких DMG по их собственному штампу.
#
#   bash scripts/audit-dmg.sh app/dist/cruxwing-AppleSilicon.dmg
#   bash scripts/audit-dmg.sh app/dist/cruxwing-AppleSilicon.dmg \
#       app/dist/cruxwing-Intel.dmg
#
# Пути передаются явно: репозиторий не знает, где владелец публикует файлы, и
# не должен зависеть от соседнего checkout. Для каждого образа проверяются:
# подпись DMG от закреплённого издателя, Gatekeeper и приложенный билет
# нотариального сервиса; внутри — bundle id, подпись/билет .app, архитектура,
# полный SHA-256 исходников/входов упаковки и полный Git commit. У нескольких
# образов commit обязан совпадать — две архитектуры одного выпуска не могут
# ссылаться на разные ревизии.
#
# Граница проверки важна. Сравнение хеша отвечает на узкий вопрос свежести:
# «самоотчёт артефакта совпадает с лежащими рядом исходниками?». Артефакт сам
# сообщает CruxwingSourceHash/CruxwingCommit, поэтому это НЕ доказательство
# воспроизводимой сборки (reproducible-build proof) и не независимая аттестация
# происхождения. Для этого нужны сборка из проверенного commit в чистом CI,
# журнал/подпись процесса и независимое воспроизведение байт-в-байт.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
    echo "использование: bash scripts/audit-dmg.sh <файл.dmg> [ещё.dmg ...]" >&2
}

[ "$#" -gt 0 ] || { usage; exit 2; }
command -v hdiutil >/dev/null || {
    echo "нет hdiutil — DMG можно проверить только на macOS" >&2
    exit 2
}
for tool in cmp codesign lipo plutil shasum spctl xcrun; do
    command -v "$tool" >/dev/null || {
        echo "нет $tool — обязательную проверку выпуска пропускать нельзя" >&2
        exit 2
    }
done
xcrun --find stapler >/dev/null 2>&1 || {
    echo "нет xcrun stapler — нотариальный билет проверить нельзя" >&2
    exit 2
}
[ -x /usr/libexec/PlistBuddy ] || {
    echo "нет /usr/libexec/PlistBuddy — штамп Info.plist прочитать нельзя" >&2
    exit 2
}

identity="$root/config/app.json"
expected_bundle_id="$(plutil -extract app.bundleId raw -o - "$identity")"
expected_team_id="$(plutil -extract app.developerTeamId raw -o - "$identity")"
[[ "$expected_bundle_id" =~ ^[a-z0-9.]+$ ]] || {
    echo "неверный bundle id в config/app.json: $expected_bundle_id" >&2
    exit 2
}
[[ "$expected_team_id" =~ ^[A-Z0-9]{10}$ ]] || {
    echo "неверный Apple TeamIdentifier в config/app.json: $expected_team_id" >&2
    exit 2
}
app_requirement="anchor apple generic and identifier \"$expected_bundle_id\" and certificate leaf[subject.OU] = \"$expected_team_id\""
disk_requirement="anchor apple generic and certificate leaf[subject.OU] = \"$expected_team_id\""

expected_source="$(bash "$root/scripts/app-source-hash.sh")"
current_commit="$(git -C "$root" rev-parse --verify 'HEAD^{commit}' 2>/dev/null || true)"

echo ">> freshness/self-report diagnostic"
echo "   Это проверка свежести по самоотчёту DMG, не доказательство reproducible build."
echo ">> SHA-256 исходников и входов упаковки сейчас: $expected_source"
if [ -n "$current_commit" ]; then
    echo ">> commit рабочего дерева: $current_commit"
else
    echo ">> commit рабочего дерева неизвестен — сравнение commit будет пропущено"
fi

status=0
mounted=""
mount_dir=""

detach_current() {
    local detach_status=0
    if [ -n "$mounted" ]; then
        if hdiutil detach "$mounted" -quiet; then
            :
        elif hdiutil detach "$mounted" -force -quiet; then
            :
        else
            echo "  !! не удалось отключить временный том: $mounted" >&2
            detach_status=1
        fi
    fi
    mounted=""
    if [ -n "$mount_dir" ] && [ -d "$mount_dir" ]; then
        if ! rmdir "$mount_dir" 2>/dev/null; then
            echo "  !! не удалось убрать пустую точку монтирования: $mount_dir" >&2
            detach_status=1
        fi
    fi
    mount_dir=""
    return "$detach_status"
}

trap 'detach_current >/dev/null 2>&1 || true' EXIT
trap 'exit 130' HUP INT TERM

first_commit=""
first_artifact=""
seen_commits=0
seen_arm64=0
seen_x86_64=0

for supplied in "$@"; do
    echo ""
    echo ">> DMG: $supplied"
    if [ ! -f "$supplied" ]; then
        echo "  НЕТ ФАЙЛА: $supplied" >&2
        status=1
        continue
    fi
    case "$supplied" in
        *.dmg) : ;;
        *)
            echo "  это не путь к .dmg: $supplied" >&2
            status=1
            continue
            ;;
    esac

    case "$(basename "$supplied")" in
        cruxwing-AppleSilicon.dmg)
            expected_arch="arm64"
            if [ "$seen_arm64" -ne 0 ]; then
                echo "  повторный образ Apple Silicon — пара выпуска неоднозначна" >&2
                status=1
            fi
            seen_arm64=$((seen_arm64 + 1))
            ;;
        cruxwing-Intel.dmg)
            expected_arch="x86_64"
            if [ "$seen_x86_64" -ne 0 ]; then
                echo "  повторный образ Intel — пара выпуска неоднозначна" >&2
                status=1
            fi
            seen_x86_64=$((seen_x86_64 + 1))
            ;;
        *)
            echo "  неизвестное имя образа: $(basename "$supplied")" >&2
            echo "  ожидается cruxwing-AppleSilicon.dmg или cruxwing-Intel.dmg" >&2
            status=1
            continue
            ;;
    esac

    dmg="$(cd "$(dirname "$supplied")" && pwd)/$(basename "$supplied")"

    if codesign --verify --strict --verbose=2 -R="$disk_requirement" \
        "$dmg" >/dev/null 2>&1; then
        echo "  подпись DMG: издатель $expected_team_id подтверждён"
    else
        echo "  ПОДПИСЬ DMG НЕДЕЙСТВИТЕЛЬНА ИЛИ ИЗДАТЕЛЬ НЕ $expected_team_id" >&2
        status=1
    fi

    if xcrun stapler validate "$dmg" >/dev/null 2>&1; then
        echo "  нотариальный билет DMG: приложен и действителен"
    else
        echo "  НОТАРИАЛЬНЫЙ БИЛЕТ DMG НЕ ПРОШЁЛ ПРОВЕРКУ" >&2
        status=1
    fi

    if spctl --assess --type open --context context:primary-signature \
        --verbose=2 "$dmg" >/dev/null 2>&1; then
        echo "  Gatekeeper DMG: принят"
    else
        echo "  GATEKEEPER ОТКЛОНИЛ DMG" >&2
        status=1
    fi

    mount_dir="$(mktemp -d "${TMPDIR:-/tmp}/cruxwing-audit.XXXXXX")"
    if ! hdiutil attach "$dmg" -readonly -nobrowse -quiet -mountpoint "$mount_dir"; then
        echo "  НЕ УДАЛОСЬ СМОНТИРОВАТЬ DMG" >&2
        status=1
        detach_current || status=1
        continue
    fi
    mounted="$mount_dir"

    app=""
    app_count=0
    for candidate in "$mount_dir"/*.app; do
        [ -d "$candidate" ] || continue
        app="$candidate"
        app_count=$((app_count + 1))
    done
    if [ "$app_count" -ne 1 ]; then
        echo "  ожидалось одно .app в корне DMG, найдено: $app_count" >&2
        status=1
        detach_current || status=1
        continue
    fi

    if codesign --verify --deep --strict --verbose=2 -R="$app_requirement" \
        "$app" >/dev/null 2>&1; then
        echo "  подпись приложения: $expected_bundle_id / $expected_team_id"
    else
        echo "  ПОДПИСЬ ПРИЛОЖЕНИЯ, BUNDLE ID ИЛИ ИЗДАТЕЛЬ НЕВЕРНЫ" >&2
        status=1
    fi

    if xcrun stapler validate "$app" >/dev/null 2>&1; then
        echo "  нотариальный билет приложения: приложен и действителен"
    else
        echo "  НОТАРИАЛЬНЫЙ БИЛЕТ ПРИЛОЖЕНИЯ НЕ ПРОШЁЛ ПРОВЕРКУ" >&2
        status=1
    fi

    if spctl --assess --type execute --verbose=2 "$app" >/dev/null 2>&1; then
        echo "  Gatekeeper приложения: принят"
    else
        echo "  GATEKEEPER ОТКЛОНИЛ ПРИЛОЖЕНИЕ" >&2
        status=1
    fi

    plist="$app/Contents/Info.plist"
    bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || true)"
    executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist" 2>/dev/null || true)"
    if [ "$bundle_id" != "$expected_bundle_id" ]; then
        echo "  НЕВЕРНЫЙ BUNDLE ID: ${bundle_id:-<пусто>} (ожидался $expected_bundle_id)" >&2
        status=1
    fi

    # License obligations apply to the shipped object code. Verify the payload
    # from the tracked source manifest rather than trusting a manifest supplied
    # by the DMG itself: an artifact must not be able to redefine what counts as
    # complete compliance.
    source_legal="$root/app/Support/Legal"
    bundled_legal="$app/Contents/Resources/Legal"
    if [ ! -f "$bundled_legal/MANIFEST.sha256" ] \
       || ! cmp -s "$source_legal/MANIFEST.sha256" "$bundled_legal/MANIFEST.sha256"; then
        echo "  ЮРИДИЧЕСКИЙ МАНИФЕСТ ОТСУТСТВУЕТ ИЛИ НЕ СОВПАДАЕТ С ИСХОДНИКАМИ" >&2
        status=1
    fi
    legal_ok=1
    while read -r expected_legal_hash relative_legal_path; do
        [ -n "$expected_legal_hash" ] || continue
        legal_file="$bundled_legal/$relative_legal_path"
        if [ ! -s "$legal_file" ]; then
            echo "  НЕТ ЛИЦЕНЗИИ/УВЕДОМЛЕНИЯ: $relative_legal_path" >&2
            legal_ok=0
            status=1
            continue
        fi
        actual_legal_hash="$(shasum -a 256 "$legal_file" | cut -d' ' -f1)"
        if [ "$actual_legal_hash" != "$expected_legal_hash" ]; then
            echo "  ИЗМЕНЕНА ЛИЦЕНЗИЯ/УВЕДОМЛЕНИЕ: $relative_legal_path" >&2
            legal_ok=0
            status=1
        fi
    done < "$source_legal/MANIFEST.sha256"
    if [ "$legal_ok" = "1" ]; then
        echo "  лицензии и уведомления: полный отслеживаемый набор"
    fi

    binary="$app/Contents/MacOS/$executable"
    if [ -z "$executable" ] || [ ! -f "$binary" ]; then
        echo "  НЕ НАЙДЕН ИСПОЛНЯЕМЫЙ ФАЙЛ ИЗ Info.plist: ${executable:-<пусто>}" >&2
        status=1
    else
        actual_arch="$(lipo -archs "$binary" 2>/dev/null || true)"
        if [ "$actual_arch" = "$expected_arch" ]; then
            echo "  архитектура: $actual_arch"
        else
            echo "  НЕВЕРНАЯ АРХИТЕКТУРА: ${actual_arch:-<не прочитана>} (ожидалась $expected_arch)" >&2
            status=1
        fi
    fi

    stamped_source="$(/usr/libexec/PlistBuddy -c 'Print :CruxwingSourceHash' "$plist" 2>/dev/null || true)"
    stamped_commit="$(/usr/libexec/PlistBuddy -c 'Print :CruxwingCommit' "$plist" 2>/dev/null || true)"
    stamped_tree_state="$(/usr/libexec/PlistBuddy -c 'Print :CruxwingTreeState' "$plist" 2>/dev/null || true)"

    if [ "$stamped_tree_state" = "clean" ]; then
        echo "  worktree: clean at build time"
    else
        echo "  DIRTY OR UNVERIFIED WORKTREE STAMP: ${stamped_tree_state:-<missing>}" >&2
        echo "  local-verification artifacts cannot pass the release audit" >&2
        status=1
    fi

    if [[ ! "$stamped_source" =~ ^[0-9a-f]{64}$ ]]; then
        echo "  ШТАМП SHA-256 ОТСУТСТВУЕТ ИЛИ НЕПОЛОН: ${stamped_source:-<пусто>}" >&2
        status=1
    elif [ "$stamped_source" = "$expected_source" ]; then
        echo "  исходники: самоотчёт совпадает ($stamped_source)"
    else
        echo "  РАСХОЖДЕНИЕ ИСХОДНИКОВ" >&2
        echo "    DMG:    $stamped_source" >&2
        echo "    сейчас: $expected_source" >&2
        status=1
    fi

    if [[ "$stamped_commit" =~ ^[0-9a-f]{40}$ || "$stamped_commit" =~ ^[0-9a-f]{64}$ ]]; then
        echo "  commit: $stamped_commit"
        if [ -n "$current_commit" ] && [ "$stamped_commit" != "$current_commit" ]; then
            echo "  РАСХОЖДЕНИЕ COMMIT: DMG не собран из текущего HEAD ($current_commit)" >&2
            status=1
        fi
    else
        echo "  ПОЛНЫЙ COMMIT ОТСУТСТВУЕТ: ${stamped_commit:-<пусто>}" >&2
        status=1
    fi

    if [ "$seen_commits" -eq 0 ]; then
        first_commit="$stamped_commit"
        first_artifact="$supplied"
    elif [ "$stamped_commit" != "$first_commit" ]; then
        echo "  РАСХОЖДЕНИЕ КОММИТОВ МЕЖДУ DMG:" >&2
        echo "    $first_artifact: ${first_commit:-<пусто>}" >&2
        echo "    $supplied: ${stamped_commit:-<пусто>}" >&2
        status=1
    fi
    seen_commits=$((seen_commits + 1))

    detach_current || status=1
done

if [ "$#" -gt 1 ] && { [ "$seen_arm64" -ne 1 ] || [ "$seen_x86_64" -ne 1 ]; }; then
    echo "!! пара выпуска должна содержать ровно один Apple Silicon и один Intel DMG" >&2
    status=1
fi

exit "$status"
