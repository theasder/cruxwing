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

VENDOR="${CRUXWING_HOSTILE_PORT:-4801}"
COLLECTOR="${CRUXWING_COLLECTOR_PORT:-4802}"

python3 scripts/vrazhdebnyj-server.py "$VENDOR" "$COLLECTOR" >/tmp/cruxwing-hostile.log 2>&1 &
SERVER=$!
trap 'kill "$SERVER" 2>/dev/null || true' EXIT

for _ in $(seq 1 20); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${VENDOR}/ok" || true)" = "200" ] && break
  sleep 1
done

echo ">> вендор :${VENDOR}, чужой хост :${COLLECTOR}"

# Вывод через файл, а не через трубу, и с сохранённым кодом возврата.
#
# Первая версия заканчивалась на `| grep … || true`: набор падал, три проверки
# были красными, скрипт возвращал ноль. В CI это был бы шаг, который не может
# сообщить о поломке, — ровно тот случай, который этот репозиторий и вычищает.
# Счётчик сборщика ДО прогона — им же и доказывается, что прогон был.
BEFORE=$(curl -s "http://127.0.0.1:${COLLECTOR}/caught" \
         | python3 -c 'import sys,json; print(json.load(sys.stdin)["hits"])' 2>/dev/null || echo 0)

OUT=$(mktemp)
set +e
CRUXWING_HOSTILE_PORT="$VENDOR" CRUXWING_COLLECTOR_PORT="$COLLECTOR" \
  swift test --package-path mvp --filter HostileServiceTests >"$OUT" 2>&1
STATUS=$?
set -e

grep -E '✔ Test |✘ Test |Test run with' "$OUT" || true

# Пропущенный набор — не пройденный набор, и по выводу этого не видно.
#
# Swift Testing на выключенном `.enabled(if:)` печатает «Test run with 6 tests
# passed after 0.001 seconds»: тесты посчитаны пройденными, не выполнившись.
# Проверка по этой строке была бы зелёной ровно тогда, когда не проверено
# ничего, — то есть сторожила бы саму себя.
#
# Поэтому спрашиваем не отчёт, а последствие: в наборе есть проверка, которая
# намеренно ходит на чужой хост сессией по умолчанию. Если счётчик сборщика не
# сдвинулся, до сокета никто не дошёл.
AFTER=$(curl -s "http://127.0.0.1:${COLLECTOR}/caught" \
        | python3 -c 'import sys,json; print(json.load(sys.stdin)["hits"])' 2>/dev/null || echo 0)
if [ "${AFTER:-0}" -le "${BEFORE:-0}" ]; then
  echo "!! счётчик чужого хоста не сдвинулся (${BEFORE:-0} -> ${AFTER:-0}): набор не выполнялся" >&2
  rm -f "$OUT"
  exit 1
fi
echo ">> набор действительно ходил в сеть: чужой хост посетили $((AFTER - BEFORE)) раз"

rm -f "$OUT"
exit "$STATUS"
