import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

// Работа читает описания мягко, сборка — строго.
//
// `bundled()` бросает на первом негодном файле, а звали его в работе через
// `try?` — значит ОДИН негодный манифест молча убирал ВСЕ, и каждый сервис
// возвращался на рукописный путь: без отделения 403 от 401, без узнавания
// страницы входа вместо данных, с угадыванием чужого конверта. Это случилось
// при добавлении Rocket.Chat, а упала проверка Zulip — за два сервиса от
// причины.
//
// Поведение проверить набором нельзя: разница видна лишь тогда, когда негодный
// файл уже в сборке, а этого не допускает bundledManifestsPass. Поэтому здесь
// проверяется форма — что в работе нет строгого чтения.
const DIR = 'mvp/Sources/OrakulCore';

test('в рабочем коде нет строгого чтения манифестов', () => {
  const offenders = [];
  for (const file of readdirSync(DIR).filter((f) => f.endsWith('.swift'))) {
    if (file === 'ConnectorManifest.swift') continue;   // сам источник обоих чтений
    const text = readFileSync(join(DIR, file), 'utf8')
      .split('\n')
      .filter((line) => !line.trim().startsWith('//'))
      .join('\n');
    if (text.includes('ConnectorManifest.bundled()')) offenders.push(file);
  }
  assert.deepEqual(offenders, [],
    `строгое чтение в работе: ${offenders.join(', ')} — один негодный файл уберёт все описания`);
});

test('мягкое чтение вообще используется', () => {
  // Проверка «нет строгого» зелена и в мире, где манифесты не читают вовсе.
  const users = readdirSync(DIR)
    .filter((f) => f.endsWith('.swift') && f !== 'ConnectorManifest.swift')
    .filter((f) => readFileSync(join(DIR, f), 'utf8').includes('ConnectorManifest.usable()'));
  assert.ok(users.length >= 4,
    `мягкое чтение зовут ${users.length} файлов — похоже, проверка смотрит не туда`);
});
