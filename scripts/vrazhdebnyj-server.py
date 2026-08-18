#!/usr/bin/env python3
"""Сервис, который ведёт себя недружелюбно, — чтобы защиты проверялись через
настоящий сокет, а не через подставку.

Каждая защита коннекторов написана против конкретного приёма, и до сих пор все
они проверялись подставным `http`, то есть в обход URLSession. Между «правило
верное» и «правило применяется» разницы в таком тесте не видно: политика
перенаправлений может быть безупречной, а делегат — не подключённым.

Поднимаются ДВА сервера:
  * «вендор» — тот, к которому обращается коннектор;
  * «сборщик» — чужой хост, куда вендор пытается увести запрос вместе с токеном.

`localhost` и `127.0.0.1` — разные имена хоста при текстовом сравнении, и это
ровно то, что должна ловить политика: сменой хоста считается любая смена имени.

Сборщик запоминает, приехал ли к нему заголовок с токеном, и отдаёт это на
/pойманное. Если приехал — защита не работает, как бы ни выглядели её тесты.
"""
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VENDOR_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 4801
COLLECT_PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 4802

stolen = {"authorization": None, "hits": 0}


class Collector(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/caught"):
            body = json.dumps(stolen).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        stolen["hits"] += 1
        auth = self.headers.get("Authorization")
        if auth:
            stolen["authorization"] = auth
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        body = b'{"data":[]}'
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


class Vendor(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send(self, code, body=b"", ctype="application/json", extra=None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for name, value in (extra or {}).items():
            self.send_header(name, value)
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_POST(self):
        self.do_GET()

    def do_GET(self):
        path = self.path.split("?")[0]

        # Увести запрос вместе с заголовком Authorization на чужой хост.
        if path == "/redirect-foreign":
            self._send(302, b"", extra={
                "Location": f"http://127.0.0.1:{COLLECT_PORT}/collect"})
            return

        # То же, но обратно на себя: разрешённый случай, иначе проверка
        # доказывала бы только «ничего не работает».
        if path == "/redirect-self":
            self._send(302, b"", extra={
                "Location": f"http://localhost:{VENDOR_PORT}/ok"})
            return

        # Понижение https → http на том же хосте.
        if path == "/redirect-downgrade":
            self._send(302, b"", extra={
                "Location": f"http://localhost:{VENDOR_PORT}/ok"})
            return

        if path == "/ok":
            self._send(200, b'{"data":[{"id":1,"title":"\\u0442\\u0430\\u0440\\u0438\\u0444\\u044b"}]}')
            return

        # Ответ, который никогда не кончается: по мегабайту, пока не оборвут.
        if path == "/endless":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            chunk = b"a" * 65536
            try:
                while True:
                    self.wfile.write(b"%X\r\n" % len(chunk) + chunk + b"\r\n")
                    self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                pass
            return

        # Молчание в сокет: соединение открыто, данных нет.
        if path == "/slow":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", "1024")
            self.end_headers()
            try:
                for _ in range(120):
                    self.wfile.write(b" ")
                    self.wfile.flush()
                    time.sleep(5)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return

        # Форма входа вместо данных, кодом 200.
        if path == "/login-page":
            self._send(200, b"<!DOCTYPE html><html><head><title>\xd0\x92\xd1\x85\xd0\xbe\xd0\xb4</title></head><body></body></html>",
                       ctype="text/html")
            return

        # GraphQL: пустой список и жалоба рядом, код 200.
        if path == "/graphql-refusal":
            self._send(200, json.dumps({
                "data": {"pages": {"search": {"results": [], "totalHits": 0}}},
                "errors": [{"message": "Превышен предел обращений",
                            "extensions": {"code": "RATE_LIMITED"}}],
            }, ensure_ascii=False).encode())
            return

        self._send(404, b'{"error":"no such path"}')

    def log_message(self, *args):
        pass


def serve(handler, port):
    ThreadingHTTPServer(("127.0.0.1", port), handler).serve_forever()


if __name__ == "__main__":
    threading.Thread(target=serve, args=(Collector, COLLECT_PORT), daemon=True).start()
    print(f"вендор :{VENDOR_PORT}  сборщик :{COLLECT_PORT}", flush=True)
    serve(Vendor, VENDOR_PORT)
