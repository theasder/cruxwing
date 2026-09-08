import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

// Четвёртая совокупность §6.4: фразы, СОБРАННЫЕ из кусков.
//
// Счёт §6.4 берёт литералы у Text/Label/Button и потому верен ровно для них.
// Фраза, склеенная из подстановок — «\(app.name) is connected — click to skip
// it on this call» — в него не попадает: она приходит в вид аргументом
// `detail:`, `accessibilityLabel(...)` или собирается в `parts.append(...)`.
// Утверждение «английских предложений на этих поверхностях не осталось» было
// верно про измеренное и неверно про экран: в одном массиве подписей для
// VoiceOver соседствовали «сейчас на входе примерно…» и «credit balance
// loading». Незрячий человек слышал половину значка по-английски.
const ROOTS = ['app/Sources/MeetGPT/Views', 'app/Sources/MeetGPT/Onboarding'];
const CYRILLIC = /[а-яА-ЯёЁ]/;

// Не текст для человека: строки журнала, идентификаторы доступности, форматы
// дат, ключи настроек. Их перевод не только не нужен — он их сломает.
// Косая черта раньше стояла здесь как признак пути — и вычёркивала живую
// фразу «…в настройках (Deepgram / Whisper API)», потому что в ней тоже есть
// косая. Путь узнаётся иначе: он начинается с косой, содержит «://» или не
// имеет вокруг неё пробелов.
const LOOKS_LIKE_A_PATH = /^\/|:\/\/|\S\/\S/;
const NOT_FOR_A_PERSON = /event=|request_id|=\S|EEEE|HH:mm|^\.|com\.|_|^[a-z0-9.]+$/;

function swiftFiles(dir) {
  return readdirSync(dir).flatMap((entry) => {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) return swiftFiles(path);
    return path.endsWith('.swift') ? [path] : [];
  });
}

function englishPhrases() {
  const found = [];
  for (const root of ROOTS) {
    for (const file of swiftFiles(root)) {
      const lines = readFileSync(file, 'utf8').split('\n');
      lines.forEach((line, index) => {
        if (line.trim().startsWith('//')) return;
        // Идентификатор доступности — не текст, а имя, по которому его ищут
        // наборы. Перевести его значит сломать проверки и ничего не дать
        // человеку: вслух он не читается.
        //
        // Смотрим и на две строки выше: вызов часто перенесён, и сама строка с
        // именем стоит отдельно. Проверка «только эта строка» пропускала их.
        const window = lines.slice(Math.max(0, index - 2), index + 1).join('\n');
        if (window.includes('accessibilityIdentifier')) return;
        for (const match of line.matchAll(/"((?:[^"\\\n]|\\.)*)"/g)) {
          const core = match[1].replace(/\\\(.*?\)/g, '').trim();
          if (core.length < 12 || !core.includes(' ')) return;
          if (NOT_FOR_A_PERSON.test(core)) return;
          if (LOOKS_LIKE_A_PATH.test(core)) return;
          // The direction reversed: the product is moving to English, so what
          // is counted is the Russian still on screen. Vendor names are how
          // their owners spell them, and a phrase whose only Cyrillic is a
          // name like that is finished.
          const own = core.replace(/Пачка|Яндекс|Битрикс|Трекер|Вики/g, '');
          if (!CYRILLIC.test(own)) return;
          // Three words or more is a phrase, not a two-word caption.
          if (own.split(/\s+/).filter((w) => w.length > 1).length < 3) return;
          found.push(`${file}:${index + 1}  ${core.slice(0, 70)}`);
        }
      });
    }
  }
  return found;
}

// A ceiling, not a promise of zero: the migration to English runs screen by
// screen. Equality on purpose — a ceiling nobody lowers stops meaning anything,
// and a new Russian phrase has to be explained just as much as a missed one.
const RUSSIAN_PHRASES_LEFT = 252;

test('the Russian phrases left on screen only ever shrink', () => {
  const left = englishPhrases();
  assert.equal(left.length, RUSSIAN_PHRASES_LEFT,
    `Russian phrases on screen: ${left.length}, pinned at ${RUSSIAN_PHRASES_LEFT}. `
    + left.slice(0, 5).join(' | '));
});

test('the count actually catches something', () => {
  // A check that cannot find anything is green forever.
  const line = '    Text("этот запрос стоит примерно столько кредитов")';
  const core = 'этот запрос стоит примерно столько кредитов';
  assert.ok(CYRILLIC.test(core) && !NOT_FOR_A_PERSON.test(core));
  assert.ok(core.split(/\s+/).filter((w) => w.length > 1).length >= 3);
  assert.ok(line.includes(core));
});

test('строки журнала и идентификаторы переводить не просят', () => {
  for (const technical of ['event=backend_chat_start request_id=',
                           'settings.connected.provider.notion',
                           'EEEE, d MMMM · HH:mm']) {
    assert.ok(NOT_FOR_A_PERSON.test(technical), `засчитано за фразу: ${technical}`);
  }
  // Путь — да, а фраза с косой чертой между словами — нет.
  assert.ok(LOOKS_LIKE_A_PATH.test('/Users/name/Library/Application Support'));
  assert.ok(LOOKS_LIKE_A_PATH.test('https://example.com/api'));
  assert.ok(!LOOKS_LIKE_A_PATH.test('в настройках (Deepgram / Whisper API)'));
});
