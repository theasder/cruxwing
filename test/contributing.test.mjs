import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

// Run with: node --test
//
// CONTRIBUTING is the first file a would-be contributor opens, and the metric
// this project is judged by is adoption. A guide whose first command fails, or
// whose example file was renamed, costs exactly the contributor it was written
// for — so every concrete thing it promises is checked here against the repo.

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, '..');
const guide = readFileSync(resolve(repo, 'CONTRIBUTING.md'), 'utf8');

describe('CONTRIBUTING', () => {
  test('states the language contributions are expected in', () => {
    // The guide moved to English on 2026-09-08, and the project followed on
    // 2026-09-09: interface, prompts and contribution language are English now.
    // What must survive is that the guide STATES a policy rather than leaving a
    // newcomer to guess which language a pull request will be read in.
    assert.match(guide, /Issues, pull requests and discussion are in English/);
    // And it must not turn language into a barrier.
    assert.match(guide, /Awkward grammar\s+is no reason for rejection/,
      'the guide no longer says that imperfect English is fine');
  });

  test('every command it prints is one that exists', () => {
    assert.ok(existsSync(resolve(repo, 'app', 'Package.swift')), 'swift build has no package');
    assert.match(guide, /swift build/);
    assert.match(guide, /swift test/);
    assert.match(guide, /npm test/);
    const pkg = JSON.parse(readFileSync(resolve(repo, 'package.json'), 'utf8'));
    assert.ok(pkg.scripts?.test, 'the guide promises npm test, package.json has no test script');
  });

  test('the guide warns about the stale core file list', () => {
    // Ловушка, на которую напоролись дважды за одну ночь: файл добавлен в
    // ядро, импорт на месте, а сборка сообщает `cannot find <Тип> in scope`.
    // Обычный `swift build` в app/ и сборка установщика держат РАЗНЫЕ кеши, и
    // зелёный первый ничего не говорит про второй. Пришедший со стороны
    // потратит на это вечер, если не написать.
    assert.match(guide, /swift package clean/,
      'CONTRIBUTING no longer tells contributors how to refresh the core file list');
    assert.match(guide, /cannot find/,
      'the guide does not name the error, so nobody will find this section');

    // И то, что сборка установщика делает это сама, — обещание в тексте.
    const build = readFileSync(resolve(repo, 'app', 'build.sh'), 'utf8');
    assert.match(build, /swift package .* clean/,
      'the guide says the installer build cleans itself; build.sh no longer does');
  });

  test('the example it points a new connector at is still there', () => {
    // "Look at this file" is the most useful line in the guide and the first
    // to rot: the file gets renamed and nobody re-reads the docs.
    const referenced = guide.match(/`((?:app|mvp)\/[^`]+\.swift)`/g)?.map((m) => m.slice(1, -1)) ?? [];
    assert.ok(referenced.length > 0, 'the guide names no example file');
    for (const path of referenced) {
      assert.ok(existsSync(resolve(repo, path)), `CONTRIBUTING points at a missing file: ${path}`);
    }
  });

  test('the rules it states are the rules the tests enforce', () => {
    // A guide may only promise what something checks. Each of these lines has
    // a test behind it, and naming the test is what makes the promise real.
    assert.match(guide, /NoTariffsTests/);
    assert.ok(existsSync(resolve(repo, 'app', 'Tests', 'MeetGPTTests', 'NoTariffsTests.swift')),
      'the guide cites a test that does not exist');
    assert.match(guide, /InMemoryKeychain/);
    assert.match(guide, /Do not claim what does not exist/);
  });

  test('names the same licence as the repository, and says why', () => {
    // Relicensed to MPL 2.0; this guard still pinned Apache and had been red
    // since that commit.
    const licence = readFileSync(resolve(repo, 'LICENSE'), 'utf8');
    assert.match(licence, /Mozilla Public License/);
    assert.match(guide, /Mozilla Public License 2\.0/);
    // "Permissive" is the brief's requirement; the reason matters more than the
    // name to the person who has to get it past their employer.
    assert.match(guide, /patent/i);
  });
});
