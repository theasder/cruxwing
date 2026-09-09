#!/usr/bin/env bash
# Хеш исходников, из которых собран артефакт.
#
# Одна реализация на всех, кто его считает: упаковка ставит штамп, проверка
# пересчитывает. Две разные реализации — это готовая ложная тревога: у DMG так и
# вышло, когда одна сторона писала путь `mvp/…`, а другая `app/../mvp/…`, и хеши
# разошлись при одинаковом коде.
#
# Коммита для этого мало. При незакоммиченном дереве он одинаков у всех сборок
# подряд: девять установщиков за день выходили с одним номером коммита и разным
# содержимым.
#
#   bash scripts/source-hash.sh mvp/Package.swift mvp/Sources/CruxwingCore
#
# Пути передаются явно и относительно корня репозитория: в пакет для Linux едет
# не то же, что в macOS-приложение, и штамповать пакет хешем исходников, которых
# в нём нет, значит обещать прослеживаемость, которой нет.
set -euo pipefail

cd "$(dirname "$0")/.."

[ "$#" -gt 0 ] || { echo "укажите каталоги с исходниками" >&2; exit 1; }

for path in "$@"; do
    [ -e "$path" ] || { echo "нет пути: $path" >&2; exit 1; }
    [ -d "$path" ] || [ -f "$path" ] || {
        echo "путь не файл и не каталог: $path" >&2
        exit 1
    }
    case "$path" in
        /*|.|..|./*|../*|*/./*|*/../*|*/.|*/..|*//*)
            echo "путь должен быть нормализован и относителен корню: $path" >&2
            exit 1
            ;;
        */)
            echo "уберите завершающий / из пути: $path" >&2
            exit 1
            ;;
    esac
done

# Полный SHA-256, а не короткий идентификатор. Короткий SHA-1 годился как
# подпись для человека, но не как контрольная сумма опубликованного файла.
# `sha256sum` есть в Linux-образах, системный `shasum` — на macOS.
if command -v sha256sum >/dev/null; then
    SUM=(sha256sum)
elif command -v shasum >/dev/null; then
    SUM=(shasum -a 256)
else
    echo "нет sha256sum или shasum — SHA-256 посчитать нельзя" >&2
    exit 1
fi

# В поток входят и относительный путь, и SHA-256 содержимого каждого файла.
# Нулевые разделители не ломаются на пробелах и переводах строк в именах.
# Порядок задаётся LC_ALL=C, иначе локаль делает штамп зависимым от машины.
#
# LocalSecrets.generated.swift — единственное исключение: build.sh создаёт его
# из локального .env. Безопасный Sources/MeetGPT/Secrets.swift, манифесты,
# lockfile, plist/entitlements and the build recipe are passed explicitly by
# each packager and therefore affect the artifact stamp.
find "$@" -type f ! -name LocalSecrets.generated.swift -print0 \
    | LC_ALL=C sort -z \
    | while IFS= read -r -d '' file; do
        file_hash="$("${SUM[@]}" < "$file" | awk '{print $1}')"
        printf '%s\0%s\0' "$file" "$file_hash"
      done \
    | "${SUM[@]}" \
    | awk '{print $1}'
