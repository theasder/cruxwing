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

// Что остаётся намеренно: точечные ключи совместимости и тестовая фикстура.
//
// Это НЕ публичное имя продукта. Переименовать `com.cruxwing.credentials`
// значит потерять миграцию токенов из первых сборок Orakul; домен пробного
// устройства нужен только для распознавания унаследованной локальной сессии.
// Человек за красивую строку внутри ключа заплатил бы своими данными.
const ALLOWED = [
  /^com\.cruxwing[.\w-]*$/,          // связка ключей
  /^@device\.cruxwing\.local$/,      // домен пробного устройства
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
    'Точечные ключи совместимости разрешены списком выше — ' +
    'остальное читает человек, модель или чужой сервис.');
});

test('разрешённое действительно есть — иначе список сторожит пустоту', () => {
  const all = ROOTS.flatMap(swiftFiles).flatMap(literals).filter((t) => /cruxwing/i.test(t));
  assert.ok(all.length >= 3,
    `литералов совместимости с чужим именем нашлось ${all.length} — разбор сломан`);
  for (const pattern of [/^com\.cruxwing/, /^@device\.cruxwing\.local$/, /^CruxwingLiveFixture/]) {
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

// Три базовые поверхности, где продукт представляется наружу, используют
// публичное имя. Полный обход HTTP-клиентов держит OwnNameOutwardTests.
//
// Заголовок User-Agent без явной установки система собирает из имени
// исполняемого файла: у собранного приложения это «MeetGPT» — внутреннее имя
// цели, которого нет ни на странице, ни в интерфейсе. Измерено 2026-08-21 на
// своём сервере, записавшем настоящий запрос коннектора.
//
// Пути на диске проверяет отдельный StorageIdentityTests: публичный форк не
// читает общий Application Support/MeetGPT автоматически, потому что эти данные
// могут принадлежать родительскому продукту. Здесь остаются только исходящие
// идентификаторы протокола и документа.
test('наружу продукт представляется публичным именем', () => {
  const session = readFileSync('mvp/Sources/OrakulCore/ConnectorSession.swift', 'utf8');
  assert.match(session, /return "orakul\/\\\(version \?\? "0"\)"/,
    'User-Agent коннекторов не собран из публичного имени');
  assert.match(session, /httpAdditionalHeaders = \["User-Agent": userAgent\]/,
    'заголовок не поставлен на общую сессию — часть коннекторов представится сама');

  const mcp = readFileSync('app/Sources/MeetGPT/MCP/MCPConnectionManager.swift', 'utf8');
  assert.match(mcp, /mcpClientName\s*=\s*"orakul"/,
    'серверу MCP мы называемся не публичным именем');

  const docx = readFileSync('app/Sources/MeetGPT/Export/AssistantDOCXExporter.swift', 'utf8');
  assert.ok(docx.includes('<Application>orakul</Application>'),
    'документ Word говорит, что его сделал кто-то другой');
  assert.ok(docx.includes('<dc:creator>orakul</dc:creator>'),
    'у документа Word чужой автор');
});
