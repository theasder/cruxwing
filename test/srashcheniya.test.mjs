import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

// Слово, в котором кириллица срослась с латиницей.
//
// Так выглядит перевод, совпавший с УСЕЧЁННЫМ началом строки: «Providers
// attempted:» после замены превратилось в «Дайтеrs attempted:». Это уже
// случалось трижды за неделю — «чтобы подfirm its destination», «Остановите и
// нtart recording» — и каждый раз ловилось тестом, который закреплял ту строку.
// У этой строки такого теста не было, и она прожила в коде день.
//
// Проверки на язык её не видят: в строке есть кириллица, значит она «русская».
const ROOTS = ['app/Sources', 'mvp/Sources'];

// Экранирование (\n, \t) и подстановка (\(…)) стоят вплотную к буквам законно:
// «\n\nПроверьте» — это перевод строки, а не сросшееся слово.
const FUSION = /(?<![\\])[а-яА-ЯёЁ][A-Za-z]|(?<![\\][a-z]?)[A-Za-z][а-яА-ЯёЁ]/;

function swiftFiles(dir) {
  return readdirSync(dir).flatMap((entry) => {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) return swiftFiles(path);
    return path.endsWith('.swift') ? [path] : [];
  });
}

function fusions() {
  const found = [];
  for (const root of ROOTS) {
    for (const file of swiftFiles(root)) {
      readFileSync(file, 'utf8').split('\n').forEach((line, index) => {
        if (line.trim().startsWith('//')) return;
        for (const match of line.matchAll(/"((?:[^"\\\n]|\\.)*)"/g)) {
          // Строки-образцы (регулярные выражения) мешают алфавиты законно:
          // «[A-Za-zА-Яа-я]» — это класс символов, а не слово.
          const literal = match[1];
          if (/\[[^\]]*[A-Za-z][^\]]*[а-яА-ЯёЁ]/.test(literal)) continue;
          // Набор символов — данные, а не речь: «aeiouyаеёиоуыэюя» перечисляет
          // гласные обоих алфавитов и намеренно слитен. Сращение от усечённого
          // перевода всегда падает в СЕРЕДИНУ фразы, поэтому проверяем только
          // литералы с пробелами.
          if (!literal.includes(' ')) continue;
          // Убираем подстановки целиком: «\(count) раз» — не сращение.
          const text = literal.replace(/\\\(.*?\)/g, ' ').replace(/\\[a-z]/g, ' ');
          if (FUSION.test(text)) found.push(`${file}:${index + 1}  ${text.slice(0, 70)}`);
        }
      });
    }
  }
  return found;
}

test('в строках нет слов, где кириллица срослась с латиницей', () => {
  assert.deepEqual(fusions(), [],
    'перевод совпал с усечённым началом строки — так рождается «Дайтеrs attempted»');
});

test('проверка ловит настоящее сращение и не трогает законное соседство', () => {
  const fused = 'Ответ оборвался. Дайтеrs attempted: ';
  assert.ok(FUSION.test(fused), 'настоящее сращение не поймано');
  // Класс символов в образце и подстановка рядом с кириллицей — законны.
  assert.ok(!FUSION.test('Проверьте соединение'.replace(/\\\(.*?\)/g, ' ')));
  assert.ok(!FUSION.test('  Проверьте соединение'), 'подстановка засчитана за сращение');
});
