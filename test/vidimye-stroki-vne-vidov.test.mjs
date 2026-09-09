import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripComments } from './swift-source.mjs';

// Текст для человека пишут не только во «Views».
//
// Потолок английских строк (§6.4) считает Views и Onboarding — и честно об этом
// говорит. Чего он сказать не мог: часть того, что человек читает, собирается в
// AppState и оттуда подставляется в вид. Так «запись уйдёт в AssemblyAI with
// your own key» прожила неизвестно сколько внутри русской фразы, а под кнопкой
// показывалось «partial merge — transcript left unchanged».
//
// Здесь считается вторая совокупность: свойства, которые вид печатает как есть.
// Список свойств — руками, потому что «строка в AppState» это ещё не текст для
// человека: там же лежат ключи, идентификаторы и записи в журнал.

const STATE = 'app/Sources/MeetGPT/AppState.swift';

/// Свойства, чьё значение вид показывает человеку без изменений.
const SHOWN = ['lastError', 'transcriptEnhanceNote', 'localDiarizationNote',
               // Добавлено 2026-08-21: строка «Saved …» нашлась не этой
               // проверкой, а соседней — про права на файлы. Список свойств
               // сторожит ровно то, что в нём перечислено, и это его предел.
               'answerActionResult'];

/// Названия сервисов — не английский текст, а имена. «Deepgram: …» это префикс
/// сообщения самого сервиса, и переводить его значило бы выдумывать за него.
const VENDOR_PREFIX = /^(Deepgram|AssemblyAI|OpenAI|Fireflies|Notion|Google|Whisper|MCP)\b/;

const CYRILLIC = /[а-яА-ЯёЁ]/;

function assignments(property) {
  const code = stripComments(readFileSync(STATE, 'utf8'));
  return [...code.matchAll(new RegExp(`${property}\\s*=\\s*"([^"]{6,})"`, 'g'))]
    .map(([, text]) => text);
}

// A ceiling that may only fall, like the one in §6.4.
const RUSSIAN_SHOWN_LEFT = 0;

test('the Russian left in shown properties only ever shrinks', () => {
  const russian = [];
  for (const property of SHOWN) {
    for (const text of assignments(property)) {
      if (VENDOR_PREFIX.test(text)) continue;
      if (!CYRILLIC.test(text.replace(/Пачка|Яндекс|Битрикс|Трекер|Вики/g, ''))) continue;
      russian.push(`${property}: «${text}»`);
    }
  }
  assert.equal(russian.length, RUSSIAN_SHOWN_LEFT,
    `shown properties still in Russian: ${russian.length}, pinned at ${RUSSIAN_SHOWN_LEFT}. `
    + russian.slice(0, 4).join('; '));
});

test('совокупность не пустая — иначе проверка сторожит пустоту', () => {
  const counted = SHOWN.flatMap(assignments).length;
  assert.ok(counted >= 20,
    `нашлось ${counted} присваиваний — разбор сломан или свойства переименовали`);
});

// Проверка обязана ловить ту строку, ради которой написана.
test('подложенная английская строка находится', () => {
  const planted = 'transcript left unchanged';
  assert.ok(!CYRILLIC.test(planted), 'образец должен быть без кириллицы');
  assert.ok(!VENDOR_PREFIX.test(planted), 'образец не должен считаться именем сервиса');
});
