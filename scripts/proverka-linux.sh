#!/usr/bin/env bash
# То же, что делает CI на Linux, но до отправки.
#
# 2026-08-19 выяснилось, что ядро не собиралось на Linux четыре дня:
# `URLSession.bytes(for:)` и `waitsForConnectivity` есть только у Apple. Оба
# слома приехали одним коммитом, оба были не видны на macOS, и все наборы были
# зелёными. CI это ловит — но CI запускается на отправке, а неотправленных
# коммитов к тому дню накопилось сорок пять.
#
# Между «написал» и «CI сказал» не должно быть четырёх дней. Один запуск:
#
#     bash scripts/proverka-linux.sh
#
# Нужен docker. Образ тот же, что в задании linux-core, иначе проверяется не то.
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGE="swift:6.0"
echo ">> ${IMAGE}, тот же образ, что у задания linux-core"

docker run --rm --memory=2g -v "$PWD":/repo -w /repo "$IMAGE" bash -euo pipefail -c '
  apt-get update -qq >/dev/null
  apt-get install -y -qq python3 curl >/dev/null

  echo ">> версия Swift"; swift --version | head -1

  # Сборка ядра отдельно от командной строки: ядро — то, что переносимо, и
  # ломается оно первым.
  echo ">> сборка ядра";           swift build --package-path mvp --target CruxwingCore
  echo ">> сборка командной строки"; swift build --package-path mvp
  echo ">> набор ядра";            swift test --package-path mvp
  echo ">> защиты через сокет";     bash scripts/vrazhdebnaya-proba.sh
  echo ">> прогон собранной программы"
  swift build --package-path mvp -c release
  bash scripts/smoke-linux.sh
'
echo ">> на Linux сходится"
