#!/usr/bin/env bash
# Собирает каст Homebrew по РЕАЛЬНЫМ образам, а не по памяти.
#
# Зачем скриптом. Сумма sha256 в касте — единственное, что связывает его с
# файлом: ошибись в ней, и `brew install` скажет «checksum mismatch», что
# человек прочтёт как «сборку подменили». Считать её руками при каждом выпуске
# — гарантированная ошибка через раз.
#
#   bash scripts/refresh-cask.sh [каталог-с-образами] [файл-вывода]
#
# По умолчанию образы берутся из app/dist, результат печатается в stdout.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="${1:-$ROOT/app/dist}"
OUT="${2:-}"
TEMPLATE="$ROOT/packaging/homebrew/orakul.rb.template"

[ -f "$TEMPLATE" ] || { echo "!! нет шаблона $TEMPLATE" >&2; exit 2; }

ARM="$DIST/orakul-AppleSilicon.dmg"
INTEL="$DIST/orakul-Intel.dmg"
for image in "$ARM" "$INTEL"; do
    # Отсутствующий образ — не повод выпустить каст на один процессор: человек
    # с другим получит «нет такого файла» после установки, а не до.
    [ -f "$image" ] || { echo "!! нет образа $image — соберите обе архитектуры (app/dist-all.sh)" >&2; exit 1; }
done

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

# Версия — из Info.plist приложения, а не из отдельного файла: в касте она
# обязана совпадать с тем, что человек увидит в «Об этой программе».
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$ROOT/app/Support/Info.plist")"

# Минимальная macOS — из config/app.json, где её же читает страница и
# руководство. Homebrew ждёт кодовое имя, а не номер.
MINIMUM="$(python3 -c "
import json, pathlib
config = json.loads(pathlib.Path('$ROOT/config/app.json').read_text())
print(config['artifacts']['macos']['minimumVersion'])")"
case "${MINIMUM%%.*}" in
    14) MACOS="sonoma" ;;
    15) MACOS="sequoia" ;;
    26) MACOS="tahoe" ;;
    *) echo "!! неизвестная macOS $MINIMUM — добавьте её кодовое имя в $0" >&2; exit 2 ;;
esac

CASK="$(sed \
    -e "s|{{VERSION}}|$VERSION|" \
    -e "s|{{SHA_ARM}}|$(sha "$ARM")|" \
    -e "s|{{SHA_INTEL}}|$(sha "$INTEL")|" \
    -e "s|{{MACOS}}|$MACOS|" \
    "$TEMPLATE")"

# Незаполненная подстановка — сломанный каст. Лучше не выпустить, чем выпустить
# «{{SHA_ARM}}» в поле контрольной суммы.
if printf '%s' "$CASK" | grep -q '{{'; then
    echo "!! в касте осталась подстановка — шаблон и скрипт разошлись" >&2
    exit 1
fi

if [ -n "$OUT" ]; then
    printf '%s\n' "$CASK" > "$OUT"
    echo ">> каст записан: $OUT (версия $VERSION, macOS $MACOS)"
else
    printf '%s\n' "$CASK"
fi
