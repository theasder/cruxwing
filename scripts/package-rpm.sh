#!/usr/bin/env bash
# Пакет .rpm с командной строкой — для систем, где .deb не ставится.
#
# Зачем отдельно от `package-linux.sh`. Deb покрывает Debian и Ubuntu, но
# российский корпоративный парк это ещё и RPM-семейство. Проверено 2026-08-18:
# тот же двоичный файл на Fedora 40 запускается и работает, так что вопрос
# упаковочный, а не переносимости.
#
# Собирать НАДО в образе семейства RPM — `swift:6.0-rhel-ubi9`, — а не брать
# готовый двоичный файл от deb. Причина измерена 2026-08-18: программа,
# собранная на Ubuntu, тянет за собой `libcurl.so.4(CURL_OPENSSL_4)` —
# версионированный символ Ubuntu, которого в Fedora нет. Сама программа там
# работает, но `dnf` отказывается ставить пакет: «nothing provides…». Проверка
# зависимостей у rpm строже загрузчика, и это правильно.
set -euo pipefail

cd "$(dirname "$0")/.."

command -v rpmbuild >/dev/null || {
    echo "нет rpmbuild — соберите в образе семейства RPM со Swift:"
    echo "  docker run --rm -v \"\$PWD\":/repo -w /repo swift:6.0-rhel-ubi9 \\"
    echo "    bash -c 'dnf install -y rpm-build >/dev/null && bash scripts/package-rpm.sh'"
    exit 1
}
# Готовый статический файл — законный вход. С ним образ сборки перестаёт иметь
# значение: у musl-сборки нет зависимостей ни от glibc, ни от libcurl, и её
# можно собрать где угодно, а упаковать здесь.
PREBUILT="exports/static/orakul"

PLIST="app/Support/Info.plist"
VERSION="$(grep -A1 CFBundleShortVersionString "$PLIST" | sed -n 's/.*<string>\(.*\)<\/string>.*/\1/p')"
[ -n "$VERSION" ] || { echo "не нашёл версию в $PLIST"; exit 1; }
# У rpm дефис в Version запрещён, поэтому высота истории идёт в Release. Пара та
# же, что у deb и у сборки под macOS: один коммит — одно имя версии.
# Высота истории — вторая половина версии. Молча подставлять 0, когда git
# недоступен, нельзя: пакет уедет с номером, который ни на что не указывает, и
# «какая у вас версия» получит третий ответ. Внутри контейнера без git высоту
# передают переменной.
if [ -n "${ORAKUL_RELEASE:-}" ]; then
    RELEASE="$ORAKUL_RELEASE"
elif RELEASE="$(git rev-list --count HEAD 2>/dev/null)" && [ -n "$RELEASE" ]; then
    :
else
    echo "не смог узнать высоту истории: нет git или это не репозиторий."
    echo "передайте её явно: ORAKUL_RELEASE=\$(git rev-list --count HEAD) bash $0"
    exit 1
fi

case "$(uname -m)" in
    x86_64)  ARCH=x86_64;  DEB_ARCH=amd64 ;;
    aarch64) ARCH=aarch64; DEB_ARCH=arm64 ;;
    *)       echo "неизвестная архитектура $(uname -m)"; exit 1 ;;
esac

# Три пути, в порядке предпочтения: готовая статическая сборка, свой статический
# SDK, и только потом привязанная к glibc. Первые два дают пакет, который
# ставится на ALT (glibc 2.32) и Astra (2.28); третий — нет, и об этом сказано
# вслух, а не выяснится у пользователя.
# Каталог сборки — свой на каждый образ, и это не аккуратность.
#
# Репозиторий монтируется в контейнер, а `.build` лежит внутри него. Соберёшь в
# Ubuntu, потом в UBI — SwiftPM переиспользует чужие объектные файлы, и пакет
# уезжает с зависимостями от того дистрибутива, где его НЕ собирали. Именно так
# rpm дважды получил `libcurl.so.4(CURL_OPENSSL_4)` от Ubuntu и не ставился на
# Fedora. Каталог в /tmp живёт внутри контейнера и чужого туда не пускает.
SCRATCH="/tmp/orakul-build-$(. /etc/os-release 2>/dev/null && echo "${ID:-unknown}${VERSION_ID:-}")"
if [ -x "$PREBUILT" ]; then
    BIN="$PREBUILT"
    REQUIRES=""
    echo ">> берём готовую статическую сборку: $PREBUILT (зависимостей у пакета не будет)"
else
    command -v swift >/dev/null || {
        echo "нет ни готовой сборки ($PREBUILT), ни swift, чтобы её сделать."
        echo "Соберите статически и положите файл туда:"
        echo "  docker run --rm -v \"\$PWD\":/repo -w /repo swift:6.0 bash -c '"
        echo "    swift sdk install <static-linux-sdk> && \\"
        echo "    swift build --package-path mvp -c release --swift-sdk \$(uname -m)-swift-linux-musl'"
        exit 1
    }
    if swift sdk list 2>/dev/null | grep -q static-linux; then
        SWIFT_FLAGS=(-c release --swift-sdk "$(uname -m)-swift-linux-musl")
        REQUIRES=""
        echo ">> статическая сборка своим SDK (зависимостей у пакета не будет)"
    else
        SWIFT_FLAGS=(-c release -Xswiftc -static-stdlib)
        REQUIRES="libcurl"
        echo ">> сборка с системными библиотеками: пакет потребует $REQUIRES"
        echo "   на ALT и Astra он не поставится — нужен Static Linux SDK"
    fi
fi
SWIFT_FLAGS+=(--scratch-path "$SCRATCH")
if [ -z "${BIN:-}" ]; then
    echo ">> сборка релиза"
    swift build --package-path mvp "${SWIFT_FLAGS[@]}"
    BIN="$(swift build --package-path mvp "${SWIFT_FLAGS[@]}" --show-bin-path)/orakul"
fi
[ -x "$BIN" ] || { echo "нет собранной программы: $BIN"; exit 1; }
# Абсолютный путь: rpmbuild выполняет %install из своего каталога, и
# относительный «exports/static/orakul» там не разрешается.
BIN="$(cd "$(dirname "$BIN")" && pwd)/$(basename "$BIN")"


# Штамп прослеживаемости: по какому коду собран этот файл.
#
# Коммита мало — при незакоммиченном дереве он одинаков у всех сборок подряд.
# Хеш считается по тому, что РЕАЛЬНО едет в пакет: ядро и командная строка.
# Приложение сюда не входит, и штамповать пакет его хешем значило бы обещать
# прослеживаемость, которой нет.
SOURCE_HASH="$(bash scripts/source-hash.sh mvp/Sources/OrakulCore mvp/Sources/orakul)"
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo "${ORAKUL_COMMIT:-неизвестен}")"
BUILT_ON="$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-неизвестно}")"

TOP="$PWD/exports/rpmbuild"
rm -rf "$TOP"
mkdir -p "$TOP"/{BUILD,RPMS,SOURCES,SPECS,BUILDROOT}

cat > "$TOP/SPECS/orakul.spec" <<SPEC
Name:           orakul
Version:        ${VERSION}
Release:        ${RELEASE}
Summary:        Поиск по своим рабочим звонкам, на своём компьютере
License:        Apache-2.0
URL:            https://github.com/theasder/orakul
${REQUIRES:+Requires:       ${REQUIRES}}
# Двоичный файл уже собран и просто переупаковывается: rpmbuild здесь не
# компилятор, а укладчик. Отладочный пакет из-за этого не нужен.
%global debug_package %{nil}

%description
Отвечает на вопрос «что мы решили?» строкой из той расшифровки, где это
прозвучало, и отказывается отвечать, если такого разговора не было.

В пакете только командная строка: добавить расшифровку, найти по ней, удалить
звонок. Записи с микрофона здесь нет — она сделана на AVFoundation и работает
только на macOS; звук пишется чем угодно в WAV 16 кГц и отдаётся командой
«расшифровать» с указанным движком.

Всё считается на этом компьютере: сети программа не требует.

%install
mkdir -p %{buildroot}/usr/bin
install -m 0755 ${BIN} %{buildroot}/usr/bin/orakul
mkdir -p %{buildroot}/usr/share/licenses/orakul
install -m 0644 ${PWD}/LICENSE %{buildroot}/usr/share/licenses/orakul/LICENSE
mkdir -p %{buildroot}/usr/share/doc/orakul
cat > %{buildroot}/usr/share/doc/orakul/build-info <<INFO
version: ${VERSION}-${RELEASE}
commit: ${COMMIT}
source: ${SOURCE_HASH}
paths: mvp/Sources/OrakulCore mvp/Sources/orakul
built-on: ${BUILT_ON}
INFO

%files
/usr/bin/orakul
/usr/share/doc/orakul/build-info
%license /usr/share/licenses/orakul/LICENSE

%changelog
SPEC

echo ">> сборка пакета"
rpmbuild --define "_topdir $TOP" -bb "$TOP/SPECS/orakul.spec" >/dev/null

PACKAGE="$(find "$TOP/RPMS" -name 'orakul-*.rpm' | head -1)"
[ -n "$PACKAGE" ] || { echo "пакет не собрался"; exit 1; }
mkdir -p exports/linux
cp "$PACKAGE" exports/linux/
FINAL="exports/linux/$(basename "$PACKAGE")"

echo ">> что внутри"
rpm -qip "$FINAL" | sed -n '1,8p'
rpm -qlp "$FINAL" | sed 's/^/  /'

echo "готов: $FINAL"
