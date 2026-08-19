#!/usr/bin/env python3
"""Мутация: испортить одно место и убедиться, что набор это заметил.

В этом репозитории мутация — основной способ отличить сторожа от украшения.
Делалась она каждый раз заново, наспех, в оболочке, и четыре раза подряд врала:

  * замена не применилась (якоря в файле не было) — прогон зелёный, вывод
    «сторож слеп», хотя проверять было нечего. Дважды;
  * `set -e` убил скрипт на первой же упавшей проверке, оставив мутацию в
    дереве; следующий запуск снял «эталон» с испорченного файла;
  * zsh выполнил обратные кавычки внутри команды как подстановку, и правка не
    дошла до файла вовсе.

Отсюда правила, которые здесь нельзя обойти: замена обязана найтись и обязана
изменить файл; восстановление сверяется по контрольной сумме; код возврата
команды доходит до вызывающего целиком.

    python3 scripts/mutaciya.py --file mvp/Sources/OrakulCore/X.swift \\
        --old 'было' --new 'стало' -- swift test --package-path mvp

Возвращает 0, если набор УПАЛ (сторож работает), и 1, если набор прошёл
(сторож слеп) — то есть код возврата отвечает на вопрос «поймала ли проверка».
"""
import argparse
import hashlib
import pathlib
import subprocess
import sys


def digest(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("--file", required=True)
    parser.add_argument("--old", required=True, help="строка, которую портим")
    parser.add_argument("--new", default="", help="чем заменяем; пусто — удаляем")
    parser.add_argument("--expect", choices=["fail", "pass"], default="fail",
                        help="fail — набор должен упасть (обычный случай)")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    command = [c for c in args.command if c != "--"]
    if not command:
        print("!! нечего запускать: команда после -- пуста", file=sys.stderr)
        return 2

    path = pathlib.Path(args.file)
    if not path.exists():
        print(f"!! файла нет: {path}", file=sys.stderr)
        return 2

    original = path.read_text()
    before = digest(path)

    if args.old not in original:
        print(f"!! в {path} нет строки для замены — мутация НЕ ПРИМЕНИЛАСЬ БЫ, "
              f"а прогон показал бы зелёное ни о чём", file=sys.stderr)
        return 2

    mutated = original.replace(args.old, args.new, 1)
    if mutated == original:
        print("!! замена ничего не изменила", file=sys.stderr)
        return 2

    path.write_text(mutated)
    try:
        finished = subprocess.run(command, capture_output=True, text=True)
    finally:
        # Восстановление в finally, а вывод из него — нет: `return` внутри
        # finally проглатывает исключение, и упавший прогон выглядел бы как
        # обычный ответ.
        path.write_text(original)
    if digest(path) != before:
        print("!! ВОССТАНОВЛЕНИЕ СЛОМАНО: файл отличается от исходного", file=sys.stderr)
        return 2

    failed = finished.returncode != 0
    output = (finished.stdout + finished.stderr)
    lines = [l for l in output.split("\n") if "✘" in l or "AssertionError" in l]
    caught = failed or bool(lines)

    if caught:
        print("поймано:", (lines[0].strip()[:150] if lines else f"код возврата {finished.returncode}"))
    else:
        print("НЕ ПОЙМАНО: набор прошёл с испорченным кодом — сторож слеп")

    return 0 if caught == (args.expect == "fail") else 1


if __name__ == "__main__":
    sys.exit(main())
