import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { stripComments } from './swift-source.mjs';

// Что мы кладём на диск, лежит закрытым.
//
// Три находки подряд, и каждая по отдельности: журнал наблюдения с чужой
// перепиской, сами расшифровки в двух хранилищах и архив Telegram, звук созвона
// во временном файле. Все создавались с обычными правами — то есть их читал
// любой процесс под тем же пользователем, а на Linux во временном каталоге и
// любой пользователь машины.
//
// «Запись остаётся на вашем компьютере» — довод продукта, и он про это тоже.
// Дальше правило спрашивается у каждого, кто пишет на диск, а не вспоминается.

const ROOTS = ['app/Sources/MeetGPT', 'mvp/Sources/CruxwingCore'];

// Пишущие, которым права задавать НЕ надо, и почему.
const EXEMPT = {
  // Человек сам выбирает, куда сохранить документ, и права там его.
  'Views/AIStudioView.swift': 'файл выбирает человек в диалоге сохранения',
  'Views/ContentView.swift': 'файл выбирает человек в диалоге сохранения',
  'AppState.swift': 'выгрузка в Word: путь выбирает человек в диалоге сохранения',
  // Пишет во временный каталог самого прогона, содержимого созвона там нет.
  'Dev/LiveTestHooks.swift': 'артефакты живой пробы, каталог задаёт прогон',
  // DevCallDiagnostics в списке НЕ значится: он открывает файл через
  // Darwin.open с правами сразу, то есть под выборку «пишущих» не попадает.
  // Проверка ниже это и показала — исключение было выписано зря.
};

function swiftFiles(dir) {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return swiftFiles(path);
    return path.endsWith('.swift') ? [path] : [];
  });
}

/** Файлы, которые пишут на диск. */
function writers() {
  const found = [];
  for (const root of ROOTS) {
    for (const path of swiftFiles(root)) {
      const code = stripComments(readFileSync(path, 'utf8'));
      if (!/\.write\(to:|createFile\(atPath:/.test(code)) continue;
      found.push({ path, relative: path.replace(root + '/', ''), code });
    }
  }
  return found;
}

test('каждый, кто пишет содержимое на диск, задаёт права', () => {
  const open = [];
  for (const { relative, code } of writers()) {
    if (EXEMPT[relative]) continue;
    if (/posixPermissions/.test(code)) continue;
    open.push(relative);
  }
  assert.deepEqual(open, [],
    `эти файлы кладут содержимое на диск с обычными правами: ${open.join(', ')}. ` +
    'Под теми же правами его читает любой процесс пользователя.');
});

test('список исключений не прикрывает пишущих, которых уже нет', () => {
  const actual = new Set(writers().map((w) => w.relative));
  const stale = Object.keys(EXEMPT).filter((name) => !actual.has(name));
  assert.deepEqual(stale, [],
    `исключения выписаны тем, кто больше не пишет на диск: ${stale.join(', ')}. ` +
    'Список исключений живёт дольше причин, если его не проверять.');
});

test('пишущих нашлось столько, чтобы проверка что-то значила', () => {
  assert.ok(writers().length >= 5,
    `пишущих найдено ${writers().length} — разбор сломан`);
});
