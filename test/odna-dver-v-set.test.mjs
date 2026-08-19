import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { stripComments } from './swift-source.mjs';

// В сеть коннекторы ходят одной дверью.
//
// За этой дверью — всё, что написано против недружелюбного сервиса: запрет
// уводить запрос на чужой хост (на Linux он единственное, что удерживает токен:
// измерено, corelibs переносит Authorization при перенаправлении), предел
// размера ответа с обрывом на первом лишнем куске и предел по времени на весь
// обмен.
//
// Ни одна из этих защит не живёт в семьях коннекторов. Они живут в
// ConnectorSession, и семья получает их ровно потому, что ходит через неё.
// Строчка `URLSession.shared.data(for: request)` в новой семье выглядит
// безобидно, собирается, проходит все наборы этой семьи — и отменяет разом всё
// перечисленное. Заметить это глазами нельзя: отличие в том, чего в коде НЕТ.

const CORE = 'mvp/Sources/OrakulCore';
const DOOR = 'ConnectorSession.swift';

function coreSources() {
  return readdirSync(CORE)
    .filter((name) => name.endsWith('.swift') && name !== DOOR)
    .map((name) => ({ name, code: stripComments(readFileSync(join(CORE, name), 'utf8')) }));
}

// Своя сессия в ядре здесь НЕ проверяется, и это не пропуск.
//
// Это делает `RedirectPolicyTests.connectorsUseTheGuardedSession` — он обходит
// тот же каталог, стоит рядом с самим правилом и, в отличие от проверки
// отсюда, идёт и на Linux, где запрет держит токен в одиночку. Написанная
// вчера копия была вторым сторожем на одном правиле — тем самым, про который
// в этом же наборе сказано: чинить придётся в двух местах, и одно забудут.
// Копия убрана, а дыра, найденная при сличении, закрыта у оригинала: он ловил
// только `URLSession.shared` и пропускал `URLSession(configuration:)`.

test('каждая семья коннекторов ходит через эту дверь', () => {
  const families = coreSources().filter(({ code }) => code.includes('static let live'));
  assert.ok(families.length >= 6,
    `семей с транспортом нашлось ${families.length} — разбор сломан`);

  for (const { name, code } of families) {
    const start = code.indexOf('static let live');
    const body = code.slice(start, start + 400);
    const ownDoor = body.includes('ConnectorSession.send');
    // Семья вправе одолжить транспорт у соседа — это та же дверь, просто
    // названная её именем.
    const borrowed = /static let live[^=]*=\s*\w+\.live/.test(body);
    assert.ok(ownDoor || borrowed,
      `${name}: транспорт не ведёт в ConnectorSession — семья осталась без защит`);
  }
});

// Приложение подставляет транспорт само, и подставить оно может что угодно.
test('приложение подставляет коннекторам ту же дверь', () => {
  const manager = stripComments(
    readFileSync('app/Sources/MeetGPT/MCP/MCPConnectionManager.swift', 'utf8'));
  const defaults = [...manager.matchAll(/\?\?\s*(\w+)\.live/g)].map(([, family]) => family);
  assert.ok(defaults.length >= 6,
    `умолчаний транспорта нашлось ${defaults.length} — ждали шесть семей`);

  // Каждое умолчание — `<Семья>.live`, а куда ведёт `live`, проверено выше.
  // Замена одного из них на свою замыкание с URLSession отменяет защиты ровно
  // для этой семьи и ничего не сломает в наборах остальных.
  const injected = manager.match(/HTTP\s*=\s*\{[^}]*URLSession/g) || [];
  assert.deepEqual(injected, [],
    'приложение подставляет коннектору собственный транспорт с URLSession');
});

// Проверка обязана ловить именно ту строку, ради которой написана.
test('подложенный обход находится', () => {
  const planted = 'let (data, response) = try await URLSession.shared.data(for: request)';
  assert.ok(/URLSession\s*\(/.test(planted) || /URLSession\.shared/.test(planted),
    'образец обхода не распознан — проверка не значит ничего');
});
