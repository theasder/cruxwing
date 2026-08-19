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

test('проверка идёт в том же образе, что задание', () => {
  const image = (linuxJob().match(/container:\s*(\S+)/) || [])[1];
  assert.ok(image, 'задание больше не задаёт образ');
  assert.ok(SCRIPT.includes(image),
    `задание идёт в ${image}, а скрипт — в другом образе; проверяется не то, что ломается`);
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
