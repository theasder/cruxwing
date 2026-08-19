import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

// Третья поверхность, которую план назвал, но не считал.
//
// §6.4 считает две: строки в `Views/` и `Onboarding/` и свойства AppState,
// которые вид печатает дословно. Там же записано ограничение: «четвёртая
// поверхность, печатаемая оттуда, куда не смотрит ни один список, была бы
// невидима обоим». Она нашлась — это тексты ошибок. Человек читает их в самый
// неудачный момент, а живут они в Integrations, MCP, Audio и Transcription,
// то есть вне обоих счётов. Английских сообщений там было 65.
//
// Считаются литералы ВНУТРИ тел errorDescription / failureReason /
// recoverySuggestion, с разбором по скобкам, а не построчно: вызов, разбитый
// на две строки, для построчного счёта невидим — этим уже ошибались.
const ROOT = 'app/Sources/MeetGPT';
const DECL = /var (errorDescription|failureReason|recoverySuggestion)\s*:\s*String\?\s*\{/g;
const CYRILLIC = /[а-яА-ЯёЁ]/;

// Имя вендора перед его же сообщением — не английский текст продукта:
// переводить «Google: …» значило бы сочинять слова за сервис.
const VENDOR_PREFIX = /^[A-Za-z][A-Za-z0-9. ]{1,20}: \\\(/;

function swiftFiles(dir) {
  return readdirSync(dir).flatMap((entry) => {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) return swiftFiles(path);
    return path.endsWith('.swift') ? [path] : [];
  });
}

function blockAt(text, openIndex) {
  let depth = 0;
  for (let i = openIndex; i < text.length; i += 1) {
    if (text[i] === '{') depth += 1;
    else if (text[i] === '}') { depth -= 1; if (depth === 0) return text.slice(openIndex, i + 1); }
  }
  return text.slice(openIndex);
}

// Комментарии выбрасываются: пример «<html>…502 Bad Gateway…nginx» ОБЪЯСНЯЕТ,
// почему такой текст показывать нельзя, и попадал в счёт как нарушение.
function literals(segment) {
  const out = [];
  for (let i = 0; i < segment.length; i += 1) {
    if (segment.startsWith('//', i)) { const j = segment.indexOf('\n', i); i = j < 0 ? segment.length : j; continue; }
    if (segment.startsWith('/*', i)) { const j = segment.indexOf('*/', i); i = j < 0 ? segment.length : j + 1; continue; }
    if (segment[i] === '"') {
      if (segment.startsWith('"""', i)) {
        const j = segment.indexOf('"""', i + 3);
        out.push(segment.slice(i + 3, j < 0 ? segment.length : j)); i = j < 0 ? segment.length : j + 2; continue;
      }
      let j = i + 1; const buf = [];
      while (j < segment.length && segment[j] !== '"') {
        if (segment[j] === '\\') { buf.push(segment.slice(j, j + 2)); j += 2; continue; }
        buf.push(segment[j]); j += 1;
      }
      out.push(buf.join('')); i = j; continue;
    }
  }
  return out;
}

function englishErrorMessages() {
  const found = [];
  for (const file of swiftFiles(ROOT)) {
    const text = readFileSync(file, 'utf8');
    for (const match of text.matchAll(DECL)) {
      const open = text.indexOf('{', match.index + match[0].length - 1);
      for (const literal of literals(blockAt(text, open))) {
        const core = literal.replace(/\\\(.*?\)/g, '').trim();
        if (core.length < 6) continue;
        if (!/[A-Za-z]/.test(core)) continue;
        if (CYRILLIC.test(core)) continue;
        if (VENDOR_PREFIX.test(literal)) continue;
        found.push({ file, literal });
      }
    }
  }
  return found;
}

test('сообщения об ошибках написаны по-русски', () => {
  const left = englishErrorMessages();
  assert.deepEqual(left.map((x) => `${x.file}: ${x.literal.slice(0, 70)}`), [],
    'английское сообщение об ошибке — человек читает его в самый неудачный момент');
});

test('счёт действительно что-то считает', () => {
  // Проверка, которая ничего не находит ни при каких условиях, зелена всегда.
  // Подсовываем заведомо английское тело и требуем, чтобы его нашли.
  const fake = `var errorDescription: String? {\n    return "Could not read the folder here."\n}`;
  const open = fake.indexOf('{');
  const strings = literals(blockAt(fake, open));
  assert.ok(strings.includes('Could not read the folder here.'), 'разбор блока сломан');
  assert.ok(!CYRILLIC.test('Could not read the folder here.'));
});

test('имя вендора перед его же сообщением проходит', () => {
  assert.ok(VENDOR_PREFIX.test('Google: \\(text)'));
  assert.ok(VENDOR_PREFIX.test('AssemblyAI: \\(m)'));
  assert.ok(!VENDOR_PREFIX.test('Could not read the folder: \\(detail)'));
});
