#!/usr/bin/env python3
"""Живы ли ссылки на документацию вендоров.

Правило приёма (план, §7.1) требует, чтобы метод, адрес, параметр поиска и форма
ответа были найдены В ДОКУМЕНТАЦИИ ВЕНДОРА. Ссылка в манифесте — это и есть
предъявленное доказательство: по ней следующий человек проверяет, что коннектор
описывает сервис, а не догадку.

Мёртвая ссылка не ломает поиск сегодня — она ломает возможность проверить
утверждение завтра. Вендор убирает страницы старых версий молча: у Gitea адрес
версии 1.20 отвечал 404, и заметили это только этой проверкой.

Запускается руками, а не в CI: чужие сайты падают и переезжают, и красный набор
от чужого сбоя учит не верить набору.

    python3 scripts/proverka-ssylok.py
"""
import json
import pathlib
import ssl
import sys
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONNECTORS = ROOT / "mvp/Sources/OrakulCore/Resources/connectors"


def check(url: str) -> tuple[bool, str]:
    # Якорь отбрасываем: сервер о нём не знает, а «#tag/...» — это указание
    # браузеру, куда прокрутить.
    request = urllib.request.Request(url.split("#")[0], method="GET",
                                     headers={"User-Agent": "orakul/0"})
    try:
        with urllib.request.urlopen(request, timeout=20,
                                    context=ssl.create_default_context()) as response:
            return response.status == 200, str(response.status)
    except urllib.error.HTTPError as error:
        return False, f"HTTP {error.code}"
    except Exception as error:                      # сеть, TLS, имя хоста
        return False, type(error).__name__


def main() -> int:
    dead = []
    for path in sorted(CONNECTORS.glob("*.json")):
        manifest = json.loads(path.read_text())
        ok, detail = check(manifest["docs"])
        print(f"{'ok ' if ok else 'НЕТ'}  {manifest['id']:12} {detail:10} {manifest['docs']}")
        if not ok:
            dead.append((manifest["id"], manifest["docs"], detail))
    if dead:
        print()
        print("Мёртвые ссылки на документацию — утверждение о сервисе стало непроверяемым:")
        for name, url, detail in dead:
            print(f"  {name}: {url} ({detail})")
        return 1
    print(f"\nвсе {len(list(CONNECTORS.glob('*.json')))} ссылок живы")
    return 0


if __name__ == "__main__":
    sys.exit(main())
