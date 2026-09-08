import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

// Строки, которые человек читает на экране, должны быть на русском (план, §6.4).
//
// Считается не «сколько осталось перевести», а верхняя граница: сколько строк
// не содержат ни одной кириллической буквы. В остатке имена (`GitHub`,
// `orakul`), голые подстановки (`"\($0)"`) и кавычки вокруг цитаты — их
// переводить нечего. Граница считает КЛАСС, а не дефект, и растёт она только
// вместе с объяснением.
//
// Проверка читает файл целиком, а не построчно. Документированный однострочник
// на grep построчный, и вызов, разнесённый на две строки, для него не
// существует:
//
//     Label(
//         "Определить самому · \(detected.displayLabel)",
//
// Это настоящая строка из BrainstormPanel.swift. Английская строка в такой же
// форме выросла бы в границе, а команда показала бы, что ничего не изменилось.

const ROOT = 'app/Sources/MeetGPT';
const SURFACES = ['Views', 'Onboarding'];
const PLAN = 'docs/ROADMAP.md';

/// Вызовы SwiftUI, чей первый аргумент — строка длиннее трёх знаков.
const CALL = /(?:Text|Label|Button|Toggle|\.help|\.navigationTitle|Section)\(\s*"[^"]{4,}"/g;
const CYRILLIC = /[а-яА-ЯёЁ]/;

function swiftFiles(dir) {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return swiftFiles(path);
    return path.endsWith('.swift') ? [path] : [];
  });
}

function literals() {
  const found = new Set();
  for (const surface of SURFACES) {
    for (const file of swiftFiles(join(ROOT, surface))) {
      for (const call of readFileSync(file, 'utf8').match(CALL) ?? []) {
        found.add(call.match(/"[^"]+"/)[0]);
      }
    }
  }
  return [...found];
}

/// Числа берутся из плана: он их называет, проверка их держит. Второе место,
/// где написано число, — это второе место, где оно разойдётся с правдой.
function stated() {
  const plan = readFileSync(PLAN, 'utf8');
  const line = plan.match(/of (\d+) string literals in `Views\/` and `Onboarding\/`, (\d+)\s*\ncarry no Cyrillic letter/);
  assert.ok(line, '§6.4 больше не называет числа — проверке нечего держать');
  return { total: Number(line[1]), without: Number(line[2]) };
}

test('английских строк на экранах не становится больше', () => {
  const without = literals().filter((s) => !CYRILLIC.test(s));
  const { without: promised } = stated();

  assert.equal(without.length, promised,
    without.length > promised
      ? `строк без кириллицы стало ${without.length} вместо ${promised}. ` +
        `Новые: ${without.join(', ')}. Либо переведите, либо объясните в §6.4, ` +
        'почему эта строка не переводится.'
      : `строк без кириллицы осталось ${without.length}, а §6.4 обещает ${promised}. ` +
        'Опустите число в плане: потолок, который никто не опускает, ' +
        'перестаёт что-либо значить.');
});

test('число строк на этих экранах — настоящее', () => {
  assert.equal(literals().length, stated().total,
    'знаменатель в §6.4 разошёлся с деревом');
});

// Проверка обязана видеть то, чего не видит документированная команда.
test('английская строка, разнесённая на две строки, находится', () => {
  const split = 'Label(\n    "Refining the answer…",\n    systemImage: "wand"\n)';
  const hit = split.match(CALL);
  assert.ok(hit, 'выборка построчная — она пропустит ровно тот случай, ради которого написана');
  assert.ok(!CYRILLIC.test(hit[0]), 'образец должен быть без кириллицы');
});

// План (§6.4) утверждает, что задача названа новичку в CONTRIBUTING. Утверждение
// было неправдой полдня: там про это не было ни строки. Теперь есть — и
// проверяется, иначе это снова станет неправдой молча.
test('CONTRIBUTING называет задачу и то же самое число', () => {
  const doc = readFileSync('CONTRIBUTING.md', 'utf8');
  const { total, without } = stated();
  assert.match(doc, /Russian strings on screen/,
    'CONTRIBUTING no longer names the task, and §6.4 promises that it does');
  assert.ok(doc.includes(String(total)) && doc.includes(String(without)),
    `CONTRIBUTING не повторяет числа ${total}/${without} из §6.4 — ` +
    'человек прочтёт устаревшее и не поймёт, куда двигать');
  assert.match(doc, /test\/russkie-stroki\.test\.mjs/,
    'CONTRIBUTING не говорит, чем число держится');
});
