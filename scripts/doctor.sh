#!/usr/bin/env bash
# Read-only first-clone diagnosis. This intentionally does not resolve packages,
# write configuration, request credentials, or modify the developer's machine.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

failures=0
ok() { printf 'OK   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1" >&2; failures=$((failures + 1)); }
note() { printf 'INFO %s\n' "$1"; }

require_command() {
    local command_name="$1" purpose="$2"
    if command -v "$command_name" >/dev/null 2>&1; then
        ok "$command_name — $purpose"
    else
        bad "$command_name не найден — $purpose"
    fi
}

require_command git "получение исходников"
require_command swift "сборка Swift-пакетов"
require_command node "корневые проверки"
require_command npm "запуск корневых проверок"

if command -v swift >/dev/null 2>&1; then
    swift_version="$(swift --version 2>/dev/null | sed -nE 's/.*Swift version ([0-9]+([.][0-9]+)*).*/\1/p' | head -1)"
    swift_major="${swift_version%%.*}"
    if [[ "$swift_major" =~ ^[0-9]+$ ]] && [ "$swift_major" -ge 6 ]; then
        ok "Swift $swift_version (нужен 6.0+)"
    else
        bad "Swift ${swift_version:-неизвестной версии}; нужен Swift 6.0+ / Xcode 16+"
    fi
fi

if command -v node >/dev/null 2>&1; then
    node_major="$(node -p 'Number(process.versions.node.split(".")[0])' 2>/dev/null || true)"
    if [[ "$node_major" =~ ^[0-9]+$ ]] && [ "$node_major" -ge 20 ]; then
        ok "Node $(node --version) (нужен 20+; CI использует 22)"
    else
        bad "Node ${node_major:-неизвестной версии}; нужен Node 20+"
    fi
fi

for required in \
    README.md LICENSE package.json \
    mvp/Package.swift app/Package.swift app/Package.resolved \
    app/Sources/MeetGPT/Secrets.swift; do
    if [ -f "$required" ]; then
        :
    else
        bad "в checkout нет $required"
    fi
done

if [ "$failures" -eq 0 ]; then
    ok "обязательные файлы checkout на месте"
fi

case "$(uname -s)" in
    Darwin)
        mac_version="$(sw_vers -productVersion 2>/dev/null || true)"
        mac_major="${mac_version%%.*}"
        if [[ "$mac_major" =~ ^[0-9]+$ ]] && [ "$mac_major" -ge 14 ]; then
            ok "macOS $mac_version (приложению нужен macOS 14+)"
        else
            bad "macOS ${mac_version:-неизвестной версии}; приложению нужен macOS 14+"
        fi
        note "проверить всё: (cd app && swift test) && (cd mvp && swift test) && npm test"
        ;;
    Linux)
        note "нативное приложение macOS здесь не собирается; ядро и CLI поддержаны"
        note "проверить доступное: (cd mvp && swift test) && npm test"
        ;;
    *)
        note "эта система не является поддержанной средой приложения; mvp может собраться при наличии Swift 6"
        ;;
esac

note "ключи провайдеров для сборки и тестов не нужны; пользователь вводит их сам в Settings → AI"
note "Apple Developer ID и ключ нотаризации нужны только сопровождающему выпуска"

if [ "$failures" -ne 0 ]; then
    printf '\nНайдено проблем: %s\n' "$failures" >&2
    exit 1
fi

printf '\nГотово: окружение подходит для первого запуска.\n'
