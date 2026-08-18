import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

// GitHub выбрасывает несуществующую метку молча. Форма отправляется, отчёт
// приходит, метки на нём нет — и никто не узнает, потому что ошибки не было.
// Так `oshibka.yml` объявлял метку `ошибка`, которой в репозитории не было:
// каждый отчёт об ошибке приходил без метки, а форма выглядела рабочей.
//
// Проверка сравнивает объявленное со снимком живого репозитория
// (`.github/metki.txt`, снимается scripts/snimok-metok.sh). Сравнение
// побайтовое: `ошибка` с латинской «o» — это другая метка, и выглядит она
// точно так же.

const FORMS = '.github/ISSUE_TEMPLATE';
const SNAPSHOT = '.github/metki.txt';

function realLabels() {
  return new Set(
    readFileSync(SNAPSHOT, 'utf8')
      .split('\n')
      .map((line) => line.trim())
      .filter((line) => line && !line.startsWith('#')),
  );
}

/** Метки, объявленные формой: `labels: ["a", "b"]`. */
function declaredLabels(body) {
  const line = body.split('\n').find((l) => l.startsWith('labels:'));
  if (!line) return [];
  return [...line.matchAll(/"([^"]+)"|'([^']+)'/g)].map((m) => m[1] ?? m[2]);
}

function forms() {
  return readdirSync(FORMS)
    .filter((name) => name.endsWith('.yml') && name !== 'config.yml')
    .map((name) => ({ name, body: readFileSync(join(FORMS, name), 'utf8') }));
}

test('каждая метка из формы существует в репозитории', () => {
  const real = realLabels();
  const missing = [];
  for (const { name, body } of forms()) {
    for (const label of declaredLabels(body)) {
      if (!real.has(label)) missing.push(`${name}: «${label}»`);
    }
  }
  assert.deepEqual(missing, [],
    `формы объявляют несуществующие метки: ${missing.join(', ')}. ` +
    'GitHub выбросит их молча — отчёты придут без метки. ' +
    'Создать метку (gh label create) или убрать её из формы, ' +
    'затем пересняв: bash scripts/snimok-metok.sh');
});

test('снимок снят с живого репозитория, а не написан от руки', () => {
  const head = readFileSync(SNAPSHOT, 'utf8').split('\n')[0];
  assert.match(head, /^# Снят \d{4}-\d{2}-\d{2} командой scripts\/snimok-metok\.sh/);
  // Снимок, в котором нет меток самого GitHub, снят не с репозитория.
  assert.ok(realLabels().has('bug'), 'в снимке нет стандартной метки bug');
});

// Проверка обязана ловить именно ту подмену, ради которой написана.
test('латинская «o» в «ошибка» — это другая метка, и она находится', () => {
  const real = realLabels();
  assert.ok(real.has('ошибка'), 'метка ошибка отсутствует в снимке');
  assert.ok(!real.has('oшибка'), 'снимок принял метку с латинской o как настоящую');
  // И объявление формы совпадает побайтово, а не «на вид».
  const oshibka = readFileSync(join(FORMS, 'oshibka.yml'), 'utf8');
  assert.deepEqual(declaredLabels(oshibka), ['ошибка']);
});
