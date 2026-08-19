import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

// Находки коннекторов уезжают модели, и по ним же проверяется предложение
// записи: в тикете или в вики может лежать обращение к модели. Проверка
// смотрит на `lastConnectorContext`, а он заполнялся в ОДНОМ месте из шести —
// пять путей, включая оба главных, клали чужой текст в запрос молча.
//
// Правило простое: `renderGrounding` в AppState зовётся только из
// `groundingBlock`, который и ведёт запись. Тогда новый путь не может забыть.
const source = readFileSync('app/Sources/MeetGPT/AppState.swift', 'utf8');

// Строки комментариев выбрасываем: собственное объяснение правила, где
// упомянуто имя функции, иначе засчитывается за нарушение — так уже было.
const code = source
  .split('\n')
  .filter((line) => !line.trim().startsWith('///') && !line.trim().startsWith('//'))
  .join('\n');

test('находки рендерятся только через дверь, которая ведёт запись', () => {
  const direct = [...code.matchAll(/PromptWorkflows\.renderGrounding\(/g)];
  const insideTheDoor = code.includes(
    'func groundingBlock(_ snippets: [GroundingSnippet]) -> String {\n' +
    '        let block = PromptWorkflows.renderGrounding(snippets)\n' +
    '        lastConnectorContext = block'
  );
  assert.ok(insideTheDoor, 'сама дверь пропала или изменилась — правило проверять нечем');
  assert.equal(direct.length, 1,
    `renderGrounding зовётся ${direct.length} раз(а) — мимо двери, значит запись потеряется`);
});

test('дверь ведёт запись именно тем, что вернула', () => {
  // Запомнить одно, а вернуть другое — тот же слепой сторож, только тише.
  const door = code.slice(code.indexOf('func groundingBlock('));
  const body = door.slice(0, door.indexOf('\n    }'));
  assert.match(body, /lastConnectorContext = block/);
  assert.match(body, /return block/);
});
