import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/** Все исходники Swift продукта — без наборов: вызов из теста не считается. */
function productionSources() {
  const roots = [join(ROOT, 'app/Sources'), join(ROOT, 'mvp/Sources')];
  const files = [];
  const walk = (dir) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const full = join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.name.endsWith('.swift')) files.push(full);
    }
  };
  roots.forEach(walk);
  return files.map((path) => ({ path, text: readFileSync(path, 'utf8') }));
}

/**
 * Типы-сторожа: имя кончается на Guard/Sanitizer/Policy/Validator/Checker.
 *
 * `Gateway` исключён намеренно: он кончается на «Gate» и попадал в выборку
 * первой версией этой проверки — три ложных срабатывания подряд, после которых
 * такую проверку перестают читать.
 */
function guardTypes(sources) {
  const found = [];
  for (const { path, text } of sources) {
    const matches = text.matchAll(
      /^(?:public )?(?:final )?(?:enum|struct|class) (\w*(?:Guard|Sanitizer|Policy|Validator|Checker))\b/gm);
    for (const [, name] of matches) {
      if (name.endsWith('Gateway')) continue;
      found.push({ name, path });
    }
  }
  return found;
}

test('у каждого сторожа есть вызов из кода продукта', () => {
  // Класс поломки, ради которого написана проверка: сторож существует, покрыт
  // наборами, аккуратно объяснён — и не вызывается ниоткуда. За неделю таких
  // нашлось три: останов на адресе сервера читал переменную, которую сам же
  // обнулял; проверка ключей MCP утверждала ту ветку, в которой оказалась;
  // PromptInjectionGuard не звался из приложения ни разу.
  //
  // Ни один из трёх не был бы найден набором: они все зелёные. Их видно только
  // так — спросив, кто зовёт.
  const sources = productionSources();
  const guards = guardTypes(sources);
  assert.ok(guards.length >= 8, `сторожей нашлось ${guards.length} — выборка не та`);

  const unreachable = [];
  for (const guard of guards) {
    const used = sources.some(({ path, text }) => {
      const body = path === guard.path
        // В своём файле объявление не считается использованием: нужен вызов.
        ? text.split('\n').filter((line) => !new RegExp(
            `^(public )?(final )?(enum|struct|class) ${guard.name}\\b`).test(line)).join('\n')
        : text;
      return new RegExp(`\\b${guard.name}\\b`).test(body);
    });
    if (!used) unreachable.push(`${guard.name} (${relative(ROOT, guard.path)})`);
  }

  assert.deepEqual(unreachable, [],
    `эти сторожа не вызываются из кода продукта — они существуют и сработать не могут:\n  ${unreachable.join('\n  ')}`);
});

test('проверка ловит сторожа, которого никто не зовёт', () => {
  // Проверка проверки: без этого «список пуст» значит и «всё хорошо», и
  // «выборка пустая», а различить нельзя.
  const sources = [
    { path: '/fake/LonelyGuard.swift', text: 'enum LonelyGuard {\n    static func check() {}\n}\n' },
    { path: '/fake/User.swift', text: 'let x = 1\n' },
  ];
  const guards = guardTypes(sources);
  assert.equal(guards.length, 1);
  const used = sources.some(({ path, text }) => path !== '/fake/LonelyGuard.swift'
    && new RegExp(`\\b${guards[0].name}\\b`).test(text));
  assert.equal(used, false, 'подставной одинокий сторож должен считаться недостижимым');
});
