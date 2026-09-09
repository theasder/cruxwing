import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

// Проверка, которая пропускает себя, обязана ЧИСЛИТЬСЯ пропущенной.
//
// `guard Config.isDevBuild else { return }` отчитывается как пройденная: набор
// говорит «зелено», а не выполнилось ни одного утверждения. Измерено
// 2026-08-21: в этой сборке так молчали одиннадцать проверок, одна из них с
// двадцатью утверждениями, — и все они числились пройденными.
//
// У Swift Testing для этого есть `.enabled(if:)`: пропуск виден в отчёте.
const ROOTS = ['app/Tests/MeetGPTTests', 'mvp/Tests/CruxwingCoreTests'];

// Состояние СБОРКИ ИЛИ СРЕДЫ, а не подставленное в самом тесте: именно оно
// делает проверку молчаливой на одной машине и говорящей на другой.
//
// Переменная окружения добавлена после того, как нашлись ещё шестнадцать:
// набор измерений на настоящей записи звонка выходил по guard, когда записи
// нет, — а её нет всегда, пока нет корпуса (план, §6.3). Шестнадцать «зелёных»
// измерений там, где не измерено ничего.
const BUILD_STATE = /\bConfig\.|\bSecrets\.|ProcessInfo\.processInfo\.environment/;

function offenders() {
  const found = [];
  for (const root of ROOTS) {
    for (const file of readdirSync(root).filter((f) => f.endsWith('.swift'))) {
      const lines = readFileSync(join(root, file), 'utf8').split('\n');
      lines.forEach((line, index) => {
        const text = line.trim();
        if (text.startsWith('//')) return;
        if (!/^guard\b/.test(text)) return;
        if (!BUILD_STATE.test(text)) return;
        // Пропуск — это `else { return }` на той же строке или на следующих.
        const window = lines.slice(index, index + 3).join(' ');
        if (!/else\s*\{\s*return\s*\}/.test(window)) return;
        found.push(`${root}/${file}:${index + 1}  ${text.slice(0, 62)}`);
      });
    }
  }
  return found;
}

test('проверка не пропускает себя молча по состоянию сборки', () => {
  assert.deepEqual(offenders(), [],
    'выход по guard отчитывается как ПРОЙДЕНО — используйте .enabled(if:), ' +
    'чтобы пропуск был виден в отчёте');
});

test('счёт действительно что-то ловит', () => {
  // Иначе «список пуст» значит и «всё хорошо», и «разбор сломан».
  const line = 'guard Config.isDevBuild else { return }';
  assert.ok(/^guard\b/.test(line) && BUILD_STATE.test(line)
            && /else\s*\{\s*return\s*\}/.test(line));
});
