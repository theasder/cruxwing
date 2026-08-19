import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripComments } from './swift-source.mjs';

// Ошибка движка не должна тихо становиться другой ошибкой.
//
// Движок различает случаи не для красоты: «токен не принят» отправляет человека
// выпускать новый, «нет права» — выдавать право, «сервис отказал» несёт слова
// самого сервиса. Обёртка семьи переводит эти случаи в свои, и если две разные
// ошибки сходятся в одну, человек получает совет, который заведомо не сработает.
//
// Так уже было дважды за два дня: `.vendor` заворачивался в `.unreadable`
// (нашлось на живом Wiki.js), `.forbidden` — в `.unauthorised` в трёх семьях.
// Оба раза наборы были зелёными: они проверяли движок, а человек видит обёртку.
//
// Слияние не запрещено — оно должно быть названо. Пометка
// «СЛИЯНИЕ НАМЕРЕННОЕ» рядом с веткой снимает запрет и оставляет след.

const FAMILIES = ['TeamNotes', 'WorkMessengers', 'SelfHostedTrackers',
                  'WesternTrackers', 'RussianTrackers'];
const MARK = 'СЛИЯНИЕ НАМЕРЕННОЕ';
const ENGINE = engineErrors();

/** Имена случаев ошибки движка — из самого движка, а не списком здесь.
 *
 * Первая версия брала все `case .что-то:` подряд и приняла за ошибки названия
 * СЕРВИСОВ (`.slack`, `.plane`), объявив слиянием то, что им не является.
 * Проверка, у которой два ложных срабатывания из трёх, перестаёт читаться. */
function engineErrors() {
  const code = stripComments(readFileSync('mvp/Sources/OrakulCore/ManifestConnector.swift', 'utf8'));
  const start = code.indexOf('public enum ConnectorError');
  assert.ok(start > 0, 'у движка больше нет ConnectorError — проверка смотрит в пустоту');
  const body = code.slice(start, code.indexOf('\n    }', start));
  const names = [...body.matchAll(/^\s*case (\w+)/gm)].map((m) => m[1]);
  assert.ok(names.length >= 8, `у движка нашлось ${names.length} случаев — разбор сломан`);
  return new Set(names);
}

/** Пары «случай движка -> случай семьи» из веток перевода. */
function mapping(name) {
  const raw = readFileSync(`mvp/Sources/OrakulCore/${name}.swift`, 'utf8');
  const code = stripComments(raw);
  const pairs = [];
  const re = /case ((?:\.\w+(?:\([^)]*\))?,?\s*)+):\s*(?:\n\s*)?(?:if [^\n]*\n\s*)?throw \w+Error\.(\w+)/g;
  for (const m of code.matchAll(re)) {
    const engine = [...m[1].matchAll(/\.(\w+)/g)].map((x) => x[1]);
    for (const one of engine) {
      if (ENGINE.has(one)) pairs.push({ engine: one, family: m[2] });
    }
  }
  return { pairs, raw };
}

test('разные ошибки движка не сходятся в одну ошибку семьи', () => {
  const collapsed = [];
  for (const name of FAMILIES) {
    const { pairs, raw } = mapping(name);
    assert.ok(pairs.length >= 5, `${name}: разбор нашёл ${pairs.length} веток — он сломан`);

    const byFamily = new Map();
    for (const { engine, family } of pairs) {
      if (!byFamily.has(family)) byFamily.set(family, new Set());
      byFamily.get(family).add(engine);
    }
    for (const [family, engines] of byFamily) {
      if (engines.size > 1 && !raw.includes(MARK)) {
        collapsed.push(`${name}: ${[...engines].join(' и ')} -> ${family}`);
      }
    }
  }
  assert.deepEqual(collapsed, [],
    `разные случаи движка сведены в один: ${collapsed.join('; ')}. ` +
    `Человек получит совет, который не сработает. Если слияние осознанное — ` +
    `напишите рядом «${MARK}» и причину.`);
});

test('403 и 401 различаются в каждой семье', () => {
  for (const name of FAMILIES) {
    const { pairs } = mapping(name);
    const forbidden = pairs.filter((p) => p.engine === 'forbidden').map((p) => p.family);
    const unauthorised = pairs.filter((p) => p.engine === 'unauthorised').map((p) => p.family);
    assert.ok(forbidden.length > 0, `${name} не переводит .forbidden вовсе`);
    for (const f of forbidden) {
      assert.ok(!unauthorised.includes(f),
        `${name}: 403 и 401 приводят к одному ответу «${f}» — ` +
        'на 403 совет «перевыпустите токен» бесполезен, право выдают отдельно');
    }
  }
});

// Выборка обязана ловить то слияние, ради которого написана.
test('подложенное слияние находится', () => {
  const planted = `
    case .unauthorised: throw ConnectorError.unauthorised
    case .forbidden:    throw ConnectorError.unauthorised`;
  const pairs = [];
  const re = /case ((?:\.\w+(?:\([^)]*\))?,?\s*)+):\s*(?:\n\s*)?throw \w+Error\.(\w+)/g;
  for (const m of planted.matchAll(re)) {
    for (const one of [...m[1].matchAll(/\.(\w+)/g)].map((x) => x[1])) {
      pairs.push({ engine: one, family: m[2] });
    }
  }
  const families = new Set(pairs.map((p) => p.family));
  assert.equal(pairs.length, 2, 'разбор не увидел обе ветки образца');
  assert.equal(families.size, 1, 'образец слияния не выглядит слиянием — проверка ничего не значит');
});
