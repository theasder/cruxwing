import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripComments } from './swift-source.mjs';

// Записанный отказ должен доходить до человека.
//
// Цепочка вышла длинной, и каждое звено рвалось молча: движок различал отказ —
// обёртка семьи сводила его к «непонятному ответу»; обёртку починили — путь
// подсказок глотал ошибку в `try?`; ошибку записали — читать запись было негде.
// Хранилище, в которое никто не смотрит, ничем не лучше тишины, ради которой
// всё это писалось.

const GROUNDING = 'app/Sources/MeetGPT/MCP/MCPGrounding.swift';
const SECTIONS = ['app/Sources/MeetGPT/Views/TeamNotesSection.swift',
                  'app/Sources/MeetGPT/Views/SelfHostedTrackersSection.swift'];

test('путь подсказок записывает отказ, а не только глотает его', () => {
  const code = stripComments(readFileSync(GROUNDING, 'utf8'));
  const records = (code.match(/ConnectorHealth\.shared\.record\(/g) || []).length;
  const successes = (code.match(/ConnectorHealth\.shared\.recordSuccess\(/g) || []).length;
  assert.ok(records >= 4,
    `отказ записывается только в ${records} местах — источники, где не записывается, ` +
    'по-прежнему выглядят как «ничего не нашлось»');
  assert.equal(records, successes,
    'успех обязан стирать отказ везде, где отказ пишется: иначе висит жалоба ' +
    'про вчерашний сбой, и человек чинит то, что уже работает');
});

test('человек видит отказ там, где решает судьбу коннектора', () => {
  for (const path of SECTIONS) {
    const code = stripComments(readFileSync(path, 'utf8'));
    assert.match(code, /ConnectorHealth\.shared\.refusal\(for:/,
      `${path} не читает запись об отказе`);
    assert.match(code, /Last refusal: \\\(refusal\.words\)/,
      `${path} не показывает слова сервиса — пересказ вместо слов запрещён правилом §2.2`);
    assert.match(code, /accessibilityIdentifier\("settings\.[a-z]+\.\\\(service\.rawValue\)\.refusal"\)/,
      `${path}: у строки отказа нет опознавателя, её нельзя проверить прогоном`);
  }
});

// Проверка обязана ловить возврат к прежнему состоянию.
test('снятая запись отказа находится', () => {
  const withoutRecording = 'let hits = await withMCPDeadline(seconds: 5) { try await client.search(q) }';
  assert.ok(!/ConnectorHealth\.shared\.record\(/.test(withoutRecording),
    'образец прежнего кода не должен содержать записи — иначе проверка ничего не значит');
});
