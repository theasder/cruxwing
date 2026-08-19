import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { stripComments } from './swift-source.mjs';

// Полный список того, с кем приложение вообще может заговорить.
//
// Довод продукта — «запись остаётся на вашем компьютере». Проверено, что она не
// уходит нам (§3, OffDeviceTrafficTests) и что коннекторы ходят одной дверью.
// Не проверено было главное для этого довода: НИКУДА БОЛЬШЕ. Ни счётчика
// посещений, ни отчёта о сбоях, ни проверки обновлений — сегодня их нет, и
// заметить появление первого было нечем: один литерал в одном файле.
//
// Список ниже — не украшение. Новый адрес роняет прогон, пока кто-нибудь не
// напишет рядом, что это и почему человек согласился туда ходить.

const ROOT = 'app/Sources/MeetGPT';

const KNOWN = {
  // Поставщики моделей: только с ключом человека и по его выбору.
  'api.anthropic.com': 'модель, ключ человека',
  'api.openai.com': 'модель, ключ человека',
  'api.deepseek.com': 'модель, ключ человека',
  'api.moonshot.ai': 'модель, ключ человека',
  'api.z.ai': 'модель, ключ человека',
  'dashscope-intl.aliyuncs.com': 'модель, ключ человека',
  'llm.api.cloud.yandex.net': 'модель, ключ человека',
  'generativelanguage.googleapis.com': 'модель, ключ человека',
  'api.assemblyai.com': 'облачная расшифровка, ключ человека, по кнопке',

  // MCP: адрес каталога, к которому идут только после подключения человеком.
  'mcp.notion.com': 'MCP, подключает человек',
  'mcp.linear.app': 'MCP, подключает человек',
  'mcp.atlassian.com': 'MCP, подключает человек',
  'mcp.intercom.com': 'MCP, подключает человек',
  'mcp.sentry.dev': 'MCP, подключает человек',
  'mcp.zapier.com': 'MCP, подключает человек',
  'mcp.attio.com': 'MCP, подключает человек',
  'mcp.asana.com': 'MCP, подключает человек',
  'mcp.hubspot.com': 'MCP, подключает человек',
  'mcp.affinity.co': 'MCP, подключает человек',
  'mcp.amplitude.com': 'MCP, подключает человек',
  'mcp.mixpanel.com': 'MCP, подключает человек',
  'mcp.posthog.com': 'MCP, подключает человек',
  'mcp-us.zoom.us': 'MCP, подключает человек',
  'api.fireflies.ai': 'MCP, подключает человек',
  'gmailmcp.googleapis.com': 'MCP, подключает человек',
  'analyticsdata.googleapis.com': 'MCP, подключает человек',
  'mcp.example.com': 'образец в поле ввода, никуда не идёт',

  // Google: только после согласия в браузере.
  'accounts.google.com': 'вход Google, согласие в браузере',
  'oauth2.googleapis.com': 'обмен кода на токен',
  'www.googleapis.com': 'Диск и почта после согласия',
  'docs.googleapis.com': 'Документы после согласия',
  'sheets.googleapis.com': 'Таблицы после согласия',
  'slides.googleapis.com': 'Презентации после согласия',
  'forms.googleapis.com': 'Формы после согласия',
  'docs.google.com': 'открытие созданного документа в браузере',
  'www.notion.so': 'открытие страницы в браузере',
  'slack.com': 'коннектор Slack, токен человека',

  // Не адреса, а имена пространств XML внутри .docx. Никуда не идут: файл
  // собирается на этом компьютере, и эти строки лежат в его разметке.
  'schemas.openxmlformats.org': 'пространство имён XML в .docx, не запрашивается',
  'purl.org': 'пространство имён XML в .docx, не запрашивается',
  'www.w3.org': 'пространство имён XML в .docx, не запрашивается',

  // Свой же компьютер: сюда возвращается браузер после согласия.
  '127.0.0.1': 'петля для возврата из браузера',
};

function swiftFiles(dir) {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (path.includes('/Resources/Skills/')) return [];
    if (statSync(path).isDirectory()) return swiftFiles(path);
    return path.endsWith('.swift') ? [path] : [];
  });
}

function hosts() {
  const found = new Map();
  for (const path of swiftFiles(ROOT)) {
    const code = stripComments(readFileSync(path, 'utf8'));
    for (const m of code.matchAll(/"https?:\/\/([a-zA-Z0-9.\-]+)/g)) {
      if (!found.has(m[1])) found.set(m[1], path.replace(ROOT + '/', ''));
    }
  }
  return found;
}

test('приложение не ходит никуда, кроме описанного', () => {
  const unknown = [...hosts()].filter(([host]) => !(host in KNOWN));
  assert.deepEqual(unknown, [],
    `новые адреса без объяснения: ${unknown.map(([h, f]) => `${h} (${f})`).join(', ')}. ` +
    'Допишите, что это и почему человек согласился туда ходить — ' +
    'или уберите: счётчиков, отчётов о сбоях и проверок обновлений здесь нет.');
});

test('в списке нет адресов, которых в коде уже нет', () => {
  const actual = hosts();
  const stale = Object.keys(KNOWN).filter((host) => !actual.has(host));
  assert.deepEqual(stale, [],
    `описаны адреса, которых в коде нет: ${stale.join(', ')}. ` +
    'Список, переживший код, читается как разрешение.');
});

test('счётчиков и отчётов о сбоях среди адресов нет', () => {
  // Отдельно и по именам: это то, чего не должно появиться незаметно.
  const forbidden = /sentry\.io|bugsnag|crashlytics|firebase|amplitude\.com\/|segment\.io|mixpanel\.com\/track|google-analytics\.com|appcenter\.ms/;
  for (const [host, file] of hosts()) {
    assert.ok(!forbidden.test(host), `${host} в ${file} — это счётчик или отчёт о сбоях`);
  }
});
