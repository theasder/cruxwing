#!/usr/bin/env bash
# Защиты коннекторов против настоящего сокета.
#
# Всё, что написано против недружелюбного сервиса, проверялось подставным
# `http` — то есть в обход URLSession. Такой тест не отличает «правило верное»
# от «правило применяется»: политика перенаправлений может быть безупречной, а
# делегат не подключённым, и оба случая зелёные.
#
#     bash scripts/vrazhdebnaya-proba.sh
#
# Поднимает сервер из vrazhdebnyj-server.py (вендор + чужой хост-сборщик) и
# прогоняет набор HostileServiceTests против него.
set -euo pipefail
cd "$(dirname "$0")/.."

VENDOR="${ORAKUL_HOSTILE_PORT:-4801}"
COLLECTOR="${ORAKUL_COLLECTOR_PORT:-4802}"

python3 scripts/vrazhdebnyj-server.py "$VENDOR" "$COLLECTOR" >/tmp/orakul-hostile.log 2>&1 &
SERVER=$!
trap 'kill "$SERVER" 2>/dev/null || true' EXIT

for _ in $(seq 1 20); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${VENDOR}/ok" || true)" = "200" ] && break
  sleep 1
done

echo ">> вендор :${VENDOR}, чужой хост :${COLLECTOR}"
ORAKUL_HOSTILE_PORT="$VENDOR" ORAKUL_COLLECTOR_PORT="$COLLECTOR" \
  swift test --package-path mvp --filter HostileServiceTests 2>&1 \
  | grep -E '✔ Test |✘ Test |Test run with' || true
