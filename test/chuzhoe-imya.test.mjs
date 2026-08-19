import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

// Имя родительского продукта не должно доезжать до человека, до модели и до
// чужого сервиса.
//
// orakul — форк Cruxwing, и следы остаются в местах, где их не ждёшь. За неделю
// нашлись: страница другого продукта в публикуемом каталоге (§5.1),
// предупреждение перед отправкой звука, имя клиента MCP, уходящее каждому
// подключённому сервису, название задачи, уезжающее в чужой трекер, и системная
// подсказка, сообщавшая МОДЕЛИ, что запись сделана другим приложением.
//
// Каждый раз это находилось поштучно. Здесь спрашивается сразу обо всех.

const ROOTS = ['app/Sources/MeetGPT', 'mvp/Sources/OrakulCore'];

// Что остаётся намеренно: ключи хранения и переменные окружения.
//
// Это НЕ текст, а адреса. Переименовать `com.cruxwing.credentials` значит
// потерять доступ к уже сохранённым токенам в связке ключей, а `cruxwing-tests/`
// — к уже сохранённым звонкам. Человек за красивое имя внутри плиста заплатил
// бы своими данными. Переменные окружения того же рода: их знают скрипты
// разработки.
const ALLOWED = [
  /^com\.cruxwing[.\w-]*$/,          // связка ключей
  /^ai\.cruxwing[.\w-]*$/,           // уведомления и живые пробы
  /^CRUXWING_[A-Z_]+$/,              // переменные окружения разработки
  /^cruxwing-tests\//,               // каталоги наборов
  /^cruxwing-doc-boundary/,          // граница multipart, видна только серверу
  /^@device\.cruxwing\.local$/,      // домен пробного устройства
  /^cruxwing\.\\\(/,                 // идентификатор запроса
  /^CruxwingLiveFixture/,            // строка в наборе живой пробы
];

function swiftFiles(dir) {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return swiftFiles(path);
    return path.endsWith('.swift') ? [path] : [];
  });
}

/** Строковые литералы файла, без комментариев. */
function literals(path) {
  const code = readFileSync(path, 'utf8')
    .split('\n')
    .filter((line) => !line.trim().startsWith('//'))
    .join('\n');
  const parts = code.split('"');
  return parts.filter((_, index) => index % 2 === 1);
}

test('чужое имя не встречается там, где его прочитают', () => {
  const offenders = [];
  for (const root of ROOTS) {
    for (const path of swiftFiles(root)) {
      for (const text of literals(path)) {
        if (!/cruxwing/i.test(text)) continue;
        if (ALLOWED.some((pattern) => pattern.test(text.trim()))) continue;
        offenders.push(`${path.replace(root + '/', '')}: «${text.slice(0, 70)}»`);
      }
    }
  }
  assert.deepEqual(offenders, [],
    `имя родительского продукта в тексте: ${offenders.join('; ')}. ` +
    'Ключи хранения и переменные окружения разрешены списком выше — ' +
    'остальное читает человек, модель или чужой сервис.');
});

test('разрешённое действительно есть — иначе список сторожит пустоту', () => {
  const all = ROOTS.flatMap(swiftFiles).flatMap(literals).filter((t) => /cruxwing/i.test(t));
  assert.ok(all.length >= 10,
    `литералов с чужим именем нашлось ${all.length} — разбор сломан`);
  for (const pattern of [/^com\.cruxwing/, /^CRUXWING_/]) {
    assert.ok(all.some((t) => pattern.test(t.trim())),
      `список разрешает ${pattern}, а таких строк нет — правило описывает несуществующее`);
  }
});

// Проверка обязана ловить именно прозу, а не адреса.
test('подложенная фраза находится, ключ — нет', () => {
  const prose = 'Transcript captured by Cruxwing';
  const key = 'com.cruxwing.credentials';
  assert.ok(!ALLOWED.some((p) => p.test(prose)), 'фраза принята за ключ');
  assert.ok(ALLOWED.some((p) => p.test(key)), 'ключ принят за фразу');
});
