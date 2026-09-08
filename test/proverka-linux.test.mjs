import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

// Проверка Linux до отправки должна делать РОВНО то, что делает CI.
//
// Иначе «локально сходится» перестаёт значить «сойдётся в CI», и перестанет
// молча: шаг добавят в ci.yml, скрипт останется прежним, и человек будет верить
// зелёному выводу, который проверил меньше. Ровно так расходятся любые два
// списка одного и того же — метки форм, каталоги публикации, а теперь шаги.

const CI = readFileSync('.github/workflows/ci.yml', 'utf8');
const SCRIPT = readFileSync('scripts/proverka-linux.sh', 'utf8');

const VERIFIED_IMAGE_DIGESTS = new Map([
  ['swift:6.0', 'sha256:0bdd33b44c0493bdf6a674700ce8960cff301977125cff2ced94770d13d7a921'],
  ['alt:p10', 'sha256:5edc92edf6bc866824427f05834ffff3f815974fc1cd9840e0dda2492d11ce30'],
  ['debian:12', 'sha256:6ebd97fa83deb272194a2cf015b3d26a4d538e9ad3a7a79d544c8af5b0a01443'],
  ['fedora:40', 'sha256:3c86d25fef9d2001712bc3d9b091fc40cf04be4767e48f1aa3b785bf58d300ed'],
]);

const IMAGE_REF = String.raw`(?:[a-z0-9]+(?:[._-][a-z0-9]+)*(?:\/[a-z0-9]+(?:[._-][a-z0-9]+)*)*):[A-Za-z0-9][A-Za-z0-9._-]*(?:@sha256:[a-f0-9]{64})?`;

/** Images used by a job container or executable `docker run` command. */
function dockerImageRefs(text = CI) {
  const unfolded = text.replace(/\\\r?\n\s*/g, ' ');
  const containers = [...unfolded.matchAll(/^\s*container:\s*(\S+)/gm)]
    .map((match) => match[1]);
  const runs = [...unfolded.matchAll(
    new RegExp(String.raw`\bdocker run\b[^\n]*?\s(${IMAGE_REF})\s+(?:bash|sh)\b`, 'g'),
  )].map((match) => match[1]);
  return [...containers, ...runs];
}

/** Шаги задания linux-core. */
function linuxJob() {
  const start = CI.indexOf('  linux-core:');
  assert.ok(start > 0, 'в ci.yml больше нет задания linux-core');
  const rest = CI.slice(start + 1);
  const end = rest.search(/\n  [a-zа-я][\w-]*:\n/);
  return end > 0 ? rest.slice(0, end) : rest;
}

/** Команды, которые задание действительно выполняет. */
function commands(text) {
  return text
    .split('\n')
    .map((line) => line.replace(/^\s*run:\s*/, ''))
    // Команда бывает не первой на строке: в скрипте перед ней стоит `echo …;`.
    // Разбор «строка начинается с swift» нашёл бы ноль команд и объявил бы
    // расхождение там, где его нет.
    .flatMap((line) => line.split(/;|&&/))
    .map((line) => line.trim())
    .filter((line) => /^(swift|bash) /.test(line))
    // Приведение к одному виду: CI задаёт каталог через working-directory,
    // скрипт — через --package-path. Это одно и то же действие.
    .map((line) => line.replace(/\s--package-path\s+mvp/, ''))
    .map((line) => line.split('|')[0].trim())
    .filter(Boolean);
}

test('проверка до отправки делает то же, что задание linux-core', () => {
  const wanted = new Set(commands(linuxJob()));
  const have = new Set(commands(SCRIPT));

  assert.ok(wanted.size >= 4, `в задании нашлось всего ${wanted.size} команд — разбор сломан`);

  const missing = [...wanted].filter((command) => !have.has(command));
  assert.deepEqual(missing, [],
    `scripts/proverka-linux.sh не делает того, что делает CI: ${missing.join(' | ')}. ` +
    'Локальный зелёный будет означать меньше, чем кажется.');
});

test('проверка идёт с тем же читаемым тегом образа, что задание', () => {
  const image = (linuxJob().match(/container:\s*(\S+)/) || [])[1];
  assert.ok(image, 'задание больше не задаёт образ');
  const readableTag = image.split('@')[0];
  assert.ok(SCRIPT.includes(readableTag),
    `задание идёт в ${readableTag}, а скрипт — в другом образе; проверяется не то, что ломается`);
});

test('каждый Docker-образ CI закреплён проверенным digest с читаемым тегом', () => {
  const refs = dockerImageRefs();
  assert.equal(refs.length, 9,
    `ожидалось 9 исполняемых ссылок на образы, найдено ${refs.length}: ${refs.join(', ')}`);

  for (const ref of refs) {
    assert.match(ref, /^[^@\s]+:[^@\s]+@sha256:[a-f0-9]{64}$/,
      `${ref} — изменяемый тег без sha256 digest`);
    const [tag, digest] = ref.split('@');
    assert.ok(VERIFIED_IMAGE_DIGESTS.has(tag),
      `${tag} не входит в проверенный список образов`);
    assert.equal(digest, VERIFIED_IMAGE_DIGESTS.get(tag),
      `${tag} закреплён другим digest — его нужно отдельно проверить`);
  }

  for (const tag of VERIFIED_IMAGE_DIGESTS.keys()) {
    assert.ok(refs.some((ref) => ref.startsWith(`${tag}@`)),
      `${tag} исчез из CI — проверка digest больше ничего для него не доказывает`);
  }
});

// Выборка обязана ловить расхождение, ради которого написана.
test('пропущенный шаг находится', () => {
  const wanted = new Set(commands(linuxJob()));
  const crippled = new Set([...wanted].slice(1));
  const missing = [...wanted].filter((command) => !crippled.has(command));
  assert.equal(missing.length, 1, 'сравнение не замечает выпавший шаг');
});

// Проверка предупреждений должна ловить свой дефект, а не просто существовать.
test('запрет на выброшенное значение написан так, как пишет компилятор', () => {
  const script = readFileSync('scripts/proverka-preduprezhdenij.sh', 'utf8');
  assert.match(script, /grep -nE "warning:\.\*/,
    'совпадение ищется сразу после «warning:» — компилятор так не пишет, ' +
    'и проверка пропустит «initialization of immutable value ... was never used»');
  assert.match(script, /was never used/,
    'запрет на выброшенное значение исчез — именно так пропало предупреждение о внедрении');
});
