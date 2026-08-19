import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { stripComments } from './swift-source.mjs';

// Отключённое приложение не спрашивают — и это держится одним списком.
//
// `researchableServers` — единственный список, из которого идут ВОПРОСЫ: и
// фоновая проверка, и ответ на звонке, и планировщик действий, и запись задачи.
// Он же вычитает то, что человек отключил. Рядом живёт
// `researchableServersIncludingMuted` — полный список, и он нужен показу: если
// отключённое исчезнет с полосы, включить его обратно будет нечем.
//
// Разница между ними — одно слово, и цена ошибки несимметрична. Написать в
// новом месте полный список значит снова спрашивать сервис, который человек
// отключил ИМЕННО ЗАТЕМ, чтобы не спрашивали: у конкурента это единственный
// способ не отдавать ему тему звонка по расписанию. Сборка при этом пройдёт,
// набор пройдёт, и увидеть это глазами нельзя — отличие в слове, а не в форме.
//
// Поэтому список мест, где полный перечень допустим, записан здесь целиком.

const SOURCES = 'app/Sources/MeetGPT';

// Показ — можно. Вопросы — нельзя.
const MAY_SEE_EVERYTHING = new Set([
  // Определение самого правила: полный список там и объявлен.
  'MCP/MCPGrounding.swift',
  // Полоса бюджета рисует и отключённые, иначе их нечем включить обратно.
  'Views/PromptBudgetBar.swift',
]);

function swiftFiles(dir) {
  return readdirSync(dir).flatMap((entry) => {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) return swiftFiles(path);
    return entry.endsWith('.swift') ? [path] : [];
  });
}

test('вопросы идут только из списка, вычитающего отключённое', () => {
  const offenders = [];
  let looked = 0;

  for (const path of swiftFiles(SOURCES)) {
    const relative = path.slice(SOURCES.length + 1);
    if (MAY_SEE_EVERYTHING.has(relative)) continue;
    // Экраны настроек управляют подключениями и обязаны видеть всё.
    if (relative.startsWith('Views/MCPApps')) continue;
    looked += 1;
    const code = stripComments(readFileSync(path, 'utf8'));
    if (code.includes('researchableServersIncludingMuted')) {
      offenders.push(`${relative}: полный список вне показа`);
    }
  }

  assert.ok(looked > 50, `просмотрено файлов ${looked} — обход сломан`);
  assert.deepEqual(offenders, []);
});

test('исключения — настоящие файлы, а не забытые имена', () => {
  // Список исключений, переживший переименование, разрешает несуществующее и
  // молча перестаёт защищать существующее.
  for (const relative of MAY_SEE_EVERYTHING) {
    assert.ok(statSync(join(SOURCES, relative)).isFile(),
      `в исключениях числится ${relative}, которого нет`);
  }
});
