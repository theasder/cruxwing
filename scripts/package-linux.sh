#!/usr/bin/env bash
# Пакет .deb с командной строкой для Linux.
#
# Зачем. Ядро и командная строка собираются вне Apple с 2026-08-17 (роадмап,
# §6.1), но «собирается» и «человек может поставить» — разные вещи. Здесь второе.
#
# Версия НЕ придумывается: она берётся оттуда же, откуда её берёт сборка под
# macOS — `CFBundleShortVersionString` из `app/Support/Info.plist` плюс высота
# истории git. Два артефакта одного коммита обязаны называться одинаково, иначе
# на вопрос «какая у вас версия» появляется два разных правильных ответа.
#
# Запускать на Linux или в контейнере `swift:6.0`: нужен `dpkg-deb`.
set -euo pipefail

cd "$(dirname "$0")/.."

command -v dpkg-deb >/dev/null || {
    echo "нет dpkg-deb — соберите в контейнере:"
    echo "  docker run --rm -v \"\$PWD\":/repo -w /repo swift:6.0 bash scripts/package-linux.sh"
    exit 1
}

PLIST="app/Support/Info.plist"
VERSION="$(grep -A1 CFBundleShortVersionString "$PLIST" | sed -n 's/.*<string>\(.*\)<\/string>.*/\1/p')"
[ -n "$VERSION" ] || { echo "не нашёл версию в $PLIST"; exit 1; }
# Высота истории — вторая половина версии. Молча подставлять 0, когда git
# недоступен, нельзя: пакет уедет с номером, который ни на что не указывает, и
# «какая у вас версия» получит третий ответ. Внутри контейнера без git высоту
# передают переменной.
if [ -n "${ORAKUL_HEIGHT:-}" ]; then
    HEIGHT="$ORAKUL_HEIGHT"
elif HEIGHT="$(git rev-list --count HEAD 2>/dev/null)" && [ -n "$HEIGHT" ]; then
    :
else
    echo "не смог узнать высоту истории: нет git или это не репозиторий."
    echo "передайте её явно: ORAKUL_HEIGHT=\$(git rev-list --count HEAD) bash $0"
    exit 1
fi
DEB_VERSION="${VERSION}-${HEIGHT}"

case "$(uname -m)" in
    x86_64)  ARCH=amd64 ;;
    aarch64) ARCH=arm64 ;;
    *)       echo "неизвестная архитектура $(uname -m)"; exit 1 ;;
esac

# Статическая стандартная библиотека Swift — не оптимизация, а условие
# работоспособности. Без неё на машине пользователя программа не запускается
# вовсе: «error while loading shared libraries: libswiftCore.so». Проверено
# 2026-08-18 установкой в чистый debian:12 — первый пакет туда ставился и не
# работал, потому что проверяли его в контейнере swift:6.0, где рантайм есть.
# Каталог сборки — свой на каждый образ, и это не аккуратность.
#
# Репозиторий монтируется в контейнер, а `.build` лежит внутри него. Соберёшь в
# Ubuntu, потом в UBI — SwiftPM переиспользует чужие объектные файлы, и пакет
# уезжает с зависимостями от того дистрибутива, где его НЕ собирали. Именно так
# rpm дважды получил `libcurl.so.4(CURL_OPENSSL_4)` от Ubuntu и не ставился на
# Fedora. Каталог в /tmp живёт внутри контейнера и чужого туда не пускает.
SCRATCH="/tmp/orakul-build-$(. /etc/os-release 2>/dev/null && echo "${ID:-unknown}${VERSION_ID:-}")"
# Полностью статическая сборка, если установлен Static Linux SDK.
#
# Зачем. Обычная сборка привязывает пакет к версии glibc того образа, где его
# собрали: пакет с glibc 2.35 не ставится ни на ALT p10 (2.32), ни на Astra 1.7
# (2.28) — а это ровно те системы, ради которых Linux вообще делается. Измерено
# 2026-08-18 установкой в контейнеры обеих.
#
# Со статическим SDK у программы нет зависимостей вовсе: тот же файл работает на
# ALT, Debian и Fedora. Проверено запуском на всех трёх.
TARGET_SDK=""
if swift sdk list 2>/dev/null | grep -q static-linux; then
    case "$(uname -m)" in
        x86_64)  TARGET_SDK="x86_64-swift-linux-musl" ;;
        aarch64) TARGET_SDK="aarch64-swift-linux-musl" ;;
    esac
fi

if [ -n "$TARGET_SDK" ]; then
    SWIFT_FLAGS=(-c release --swift-sdk "$TARGET_SDK")
    DEPENDS=""
    echo ">> статическая сборка: $TARGET_SDK (зависимостей у пакета не будет)"
else
    SWIFT_FLAGS=(-c release -Xswiftc -static-stdlib)
    DEPENDS="libcurl4, libstdc++6"
    echo ">> сборка с системными библиотеками: пакет потребует $DEPENDS"
    echo "   (для ALT и Astra нужен Static Linux SDK — см. шапку скрипта)"
fi
SWIFT_FLAGS+=(--scratch-path "$SCRATCH")

echo ">> сборка релиза"
swift build --package-path mvp "${SWIFT_FLAGS[@]}"
BIN="$(swift build --package-path mvp "${SWIFT_FLAGS[@]}" --show-bin-path)/orakul"
[ -x "$BIN" ] || { echo "нет собранной программы: $BIN"; exit 1; }

STAGE="exports/linux/orakul_${DEB_VERSION}_${ARCH}"
rm -rf "$STAGE"
mkdir -p "$STAGE/DEBIAN" "$STAGE/usr/bin" "$STAGE/usr/share/doc/orakul"

install -m 0755 "$BIN" "$STAGE/usr/bin/orakul"

# Штамп прослеживаемости: по какому коду собран этот файл.
#
# Коммита мало — при незакоммиченном дереве он одинаков у всех сборок подряд.
# Хеш считается по тому, что РЕАЛЬНО едет в пакет: ядро и командная строка.
# Приложение сюда не входит, и штамповать пакет его хешем значило бы обещать
# прослеживаемость, которой нет.
SOURCE_HASH="$(bash scripts/source-hash.sh mvp/Sources/OrakulCore mvp/Sources/orakul)"
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo "${ORAKUL_COMMIT:-неизвестен}")"
BUILT_ON="$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-неизвестно}")"

DOCDIR="$STAGE/usr/share/doc/orakul"
RELEASE_OR_HEIGHT="$HEIGHT"
cat > "$DOCDIR/build-info" <<INFO
version: ${VERSION}-${RELEASE_OR_HEIGHT}
commit: ${COMMIT}
source: ${SOURCE_HASH}
paths: mvp/Sources/OrakulCore mvp/Sources/orakul
built-on: ${BUILT_ON}
INFO


# Размер установленного в килобайтах — требование политики Debian.
SIZE_KB="$(du -ks "$STAGE/usr" | cut -f1)"

cat > "$STAGE/DEBIAN/control" <<CONTROL
Package: orakul
Version: ${DEB_VERSION}
Section: utils
Priority: optional
Architecture: ${ARCH}
Installed-Size: ${SIZE_KB}
Maintainer: orakul <https://github.com/theasder/cruxwing>
Homepage: https://github.com/theasder/cruxwing
Description: Поиск по своим рабочим звонкам, на своём компьютере
 Отвечает на вопрос «что мы решили?» строкой из той расшифровки, где это
 прозвучало, и отказывается отвечать, если такого разговора не было.
 .
 В пакете только командная строка: добавить расшифровку, найти по ней, удалить
 звонок. Записи с микрофона здесь нет — она сделана на AVFoundation и работает
 только на macOS; звук пишется чем угодно в WAV 16 кГц и отдаётся командой
 «расшифровать» с указанным движком.
 .
 Всё считается на этом компьютере: сети программа не требует.
CONTROL

# Лицензия едет с пакетом: требование политики, а не вежливость.
# Depends дописывается ОТДЕЛЬНОЙ строкой и только когда он есть. Пустая
# подстановка внутри heredoc оставляла пустую строку, а в control это разделитель
# записей: dpkg-deb отвечал «several package info entries found» — сообщение, по
# которому причину не угадать.
[ -n "$DEPENDS" ] && printf 'Depends: %s\n' "$DEPENDS" >> "$STAGE/DEBIAN/control"

cp LICENSE "$STAGE/usr/share/doc/orakul/copyright"

echo ">> сборка пакета"
dpkg-deb --build --root-owner-group "$STAGE" >/dev/null
PACKAGE="${STAGE}.deb"
[ -f "$PACKAGE" ] || { echo "пакет не собрался"; exit 1; }

echo ">> что внутри"
dpkg-deb --info "$PACKAGE" | sed -n '2,10p'
dpkg-deb --contents "$PACKAGE" | awk '{print "  " $6}'

echo "готов: $PACKAGE"
