import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

// Способ проверки сам должен быть проверен.
//
// Мутация здесь — основной способ отличить сторожа от украшения, и делалась она
// каждый раз заново в оболочке. Четырежды подряд она соврала: дважды замена не
// применялась (якоря в файле не было) и прогон показывал «зелёное» ни о чём,
// один раз `set -e` убил скрипт с мутацией в дереве, один раз zsh выполнил
// обратные кавычки как подстановку.
//
// scripts/mutaciya.py эти случаи закрывает, и вот это — проверка того, что
// закрывает. Инструмент проверки, которому верят на слово, ничем не лучше
// сторожа, которого никто не звал.

const RUNNER = 'scripts/mutaciya.py';

function run(args) {
  try {
    const stdout = execFileSync('python3', [RUNNER, ...args], { encoding: 'utf8' });
    return { code: 0, output: stdout };
  } catch (error) {
    return { code: error.status, output: (error.stdout ?? '') + (error.stderr ?? '') };
  }
}

function sandbox(contents) {
  const dir = mkdtempSync(join(tmpdir(), 'mutaciya-'));
  const file = join(dir, 'proba.txt');
  writeFileSync(file, contents);
  return file;
}

test('отсутствующий якорь — отказ, а не зелёное', () => {
  const file = sandbox('первая строка\n');
  const { code, output } = run(['--file', file, '--old', 'такого текста нет',
                                '--new', 'x', '--', 'true']);
  assert.equal(code, 2, 'молча согласился портить то, чего нет');
  assert.match(output, /НЕ ПРИМЕНИЛАСЬ БЫ/);
  assert.equal(readFileSync(file, 'utf8'), 'первая строка\n', 'файл всё-таки тронут');
});

test('пойманная мутация — код 0, и файл восстановлен', () => {
  const file = sandbox('значение = 1\n');
  const { code } = run(['--file', file, '--old', '1', '--new', '2', '--', 'false']);
  assert.equal(code, 0, 'упавший прогон должен считаться пойманной мутацией');
  assert.equal(readFileSync(file, 'utf8'), 'значение = 1\n', 'файл не восстановлен');
});

test('непойманная мутация — код 1 и прямая формулировка', () => {
  const file = sandbox('значение = 1\n');
  const { code, output } = run(['--file', file, '--old', '1', '--new', '2', '--', 'true']);
  assert.equal(code, 1, 'зелёный прогон с испорченным кодом должен считаться провалом');
  assert.match(output, /сторож слеп/);
  assert.equal(readFileSync(file, 'utf8'), 'значение = 1\n');
});

test('файл восстанавливается, даже когда команда падает насмерть', () => {
  const file = sandbox('значение = 1\n');
  run(['--file', file, '--old', '1', '--new', '2', '--', 'sh', '-c', 'kill -9 $$']);
  assert.equal(readFileSync(file, 'utf8'), 'значение = 1\n',
               'убитая команда оставила мутацию в дереве — так и рождается ложный эталон');
});

test('пустая команда — отказ', () => {
  const file = sandbox('значение = 1\n');
  const { code } = run(['--file', file, '--old', '1', '--new', '2', '--']);
  assert.equal(code, 2, 'без команды проверять нечего, а ответ был бы зелёным');
});
