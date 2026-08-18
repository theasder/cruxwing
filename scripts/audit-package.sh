#!/usr/bin/env bash
# Из какого кода собран этот пакет.
#
# То же, что `audit-dmg.sh` делает для macOS, только для .deb и .rpm: читает
# штамп из САМОГО файла и пересчитывает хеш по рабочему дереву. Вопрос один: то
# ли это, что лежит сейчас в репозитории, — и ответ берётся из артефакта, а не
# из журнала сборки.
#
# Зачем вообще. Собранное и выложенное — разные вещи, и путают их регулярно:
# сборка зелёная, файл на месте, а в публикации лежит вчерашний. Номер коммита
# этого не показывает: при незакоммиченном дереве он одинаков у всех сборок
# подряд.
#
#   bash scripts/audit-package.sh exports/linux/orakul_0.1.0-179_arm64.deb
#   bash scripts/audit-package.sh exports/linux/orakul-0.1.0-179.aarch64.rpm
set -euo pipefail

cd "$(dirname "$0")/.."

PACKAGE="${1:-}"
[ -n "$PACKAGE" ] || { echo "укажите пакет: bash scripts/audit-package.sh <файл.deb|файл.rpm>"; exit 1; }
[ -f "$PACKAGE" ] || { echo "нет файла: $PACKAGE"; exit 1; }
ABSOLUTE="$(cd "$(dirname "$PACKAGE")" && pwd)/$(basename "$PACKAGE")"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

case "$PACKAGE" in
    *.deb)
        command -v dpkg-deb >/dev/null || { echo "нет dpkg-deb — запустите в системе с ним"; exit 1; }
        dpkg-deb -x "$ABSOLUTE" "$WORK"
        ;;
    *.rpm)
        command -v rpm2cpio >/dev/null || { echo "нет rpm2cpio — запустите в системе с ним"; exit 1; }
        (cd "$WORK" && rpm2cpio "$ABSOLUTE" | cpio -idm --quiet)
        ;;
    *)
        echo "не знаю такого пакета: $PACKAGE"; exit 1 ;;
esac

INFO="$WORK/usr/share/doc/orakul/build-info"
[ -f "$INFO" ] || {
    echo "в пакете нет штампа сборки — проследить, из чего он собран, нельзя"
    exit 1
}

STAMPED_SOURCE="$(sed -n 's/^source: //p' "$INFO")"
STAMPED_PATHS="$(sed -n 's/^paths: //p' "$INFO")"
STAMPED_COMMIT="$(sed -n 's/^commit: //p' "$INFO")"
[ -n "$STAMPED_SOURCE" ] && [ -n "$STAMPED_PATHS" ] || { echo "штамп неполный:"; cat "$INFO"; exit 1; }

# Пересчитывается по тем путям, которые назвал сам штамп: если однажды в пакет
# поедет другое, проверка пойдёт следом, а не продолжит сверять старое.
ACTUAL="$(bash scripts/source-hash.sh $STAMPED_PATHS)"

echo "пакет:  $PACKAGE"
echo "коммит: $STAMPED_COMMIT"
echo "штамп:  $STAMPED_SOURCE"
echo "сейчас: $ACTUAL"

if [ "$STAMPED_SOURCE" = "$ACTUAL" ]; then
    echo "СОВПАДАЕТ: пакет собран из этих исходников"
else
    echo "РАСХОЖДЕНИЕ: пакет собран из другого кода, чем лежит сейчас в дереве."
    echo "Это не обязательно ошибка — так выглядит и старый файл рядом с новым кодом."
    exit 1
fi
