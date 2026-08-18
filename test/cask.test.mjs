import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/** Каст, собранный по подставным образам: настоящих в репозитории нет и быть не должно. */
function buildCask(images = { arm: 'образ-arm', intel: 'образ-intel' }) {
  const dir = mkdtempSync(join(tmpdir(), 'cask-'));
  try {
    if (images.arm !== null) writeFileSync(join(dir, 'orakul-AppleSilicon.dmg'), images.arm);
    if (images.intel !== null) writeFileSync(join(dir, 'orakul-Intel.dmg'), images.intel);
    return {
      text: execFileSync('bash', [join(ROOT, 'scripts/refresh-cask.sh'), dir],
                         { encoding: 'utf8' }),
      sha: (which) => createHash('sha256').update(images[which]).digest('hex'),
    };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test('суммы в касте считаются по самим образам, а не переписываются', () => {
  // Ошибка здесь читается человеком как «сборку подменили»: brew скажет
  // checksum mismatch, а не «мы опечатались».
  const cask = buildCask();
  assert.ok(cask.text.includes(cask.sha('arm')), 'нет суммы образа Apple Silicon');
  assert.ok(cask.text.includes(cask.sha('intel')), 'нет суммы образа Intel');
  assert.notEqual(cask.sha('arm'), cask.sha('intel'), 'подставные образы совпали — проверка пустая');
});

test('версия в касте — та же, что человек увидит в программе', () => {
  const plist = readFileSync(join(ROOT, 'app/Support/Info.plist'), 'utf8');
  const version = /<key>CFBundleShortVersionString<\/key>\s*<string>([^<]+)<\/string>/.exec(plist)[1];
  assert.match(buildCask().text, new RegExp(`version "${version.replace(/\./g, '\\.')}"`));
});

test('требование к macOS совпадает с тем, что собирает сборка', () => {
  const config = JSON.parse(readFileSync(join(ROOT, 'config/app.json'), 'utf8'));
  const major = config.artifacts.macos.minimumVersion.split('.')[0];
  const names = { 14: 'sonoma', 15: 'sequoia', 26: 'tahoe' };
  assert.ok(names[major], `кодовое имя macOS ${major} не описано в проверке`);
  assert.match(buildCask().text, new RegExp(`depends_on macos: ">= :${names[major]}"`));
});

test('каст ставит приложение под тем же именем, под каким его собирает dmg.sh', () => {
  // В build/ имена разные (иначе вторая сборка затрёт первую), а в образ едет
  // одно: для macOS разные имена — это разные приложения, и разрешения на
  // микрофон, выданные одному, к другому не относятся.
  const dmg = readFileSync(join(ROOT, 'app/dmg.sh'), 'utf8');
  const ship = /SHIP_NAME="([^"]+)"/.exec(dmg)[1];
  assert.match(buildCask().text, new RegExp(`app "${ship}\\.app"`));
});

test('адреса в касте ведут на те файлы, которые выпускает dmg.sh', () => {
  const dmg = readFileSync(join(ROOT, 'app/dmg.sh'), 'utf8');
  const published = [...dmg.matchAll(/PUBLISH_NAME="([^"]+)"/g)].map((m) => m[1]);
  assert.equal(published.length, 2, 'в dmg.sh не два имени образа — проверка устарела');
  const cask = buildCask().text;
  // Каст подставляет архитектуру в имя: orakul-#{arch}.dmg. Значит в нём
  // должны быть обе половины — общий префикс и оба суффикса.
  for (const name of published) {
    const suffix = name.replace('orakul-', '');
    assert.ok(cask.includes(suffix), `каст не знает про образ ${name}`);
  }
});

test('без одного из образов каст не выпускается', () => {
  // Иначе человек с другим процессором узнает об этом после установки.
  for (const missing of ['arm', 'intel']) {
    assert.throws(() => buildCask({ arm: 'a', intel: 'b', [missing]: null }),
                  /нет образа|Command failed/);
  }
});

test('незаполненная подстановка не уезжает в каст', () => {
  const template = readFileSync(join(ROOT, 'packaging/homebrew/orakul.rb.template'), 'utf8');
  const placeholders = [...template.matchAll(/\{\{(\w+)\}\}/g)].map((m) => m[1]);
  assert.ok(placeholders.length >= 4, 'в шаблоне пропали подстановки');
  const cask = buildCask().text;
  assert.ok(!cask.includes('{{'), `в касте осталась подстановка: ${cask}`);
});

test('README рассказывает про установку одной командой', () => {
  const readme = readFileSync(join(ROOT, 'README.md'), 'utf8');
  assert.match(readme, /brew install --cask/,
    'способ установки, ради которого всё это писалось, нигде не назван');
});
