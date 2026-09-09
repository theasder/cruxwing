import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

// Что уезжает на сайт.
//
// `pages.yml` загружает весь public/ как неизменяемый Pages artifact. Поэтому
// чужая страница не должна лежать здесь «на всякий случай» и скрываться
// специальным исключением: такой мусор виден каждому клонирующему.

const PUBLIC = 'public';
const FLOW = '.github/workflows/pages.yml';
const OWN_DOMAIN = 'theasder.github.io';

function publishedPages() {
  const pages = [];
  const walk = (dir) => {
    for (const name of readdirSync(dir)) {
      const path = join(dir, name);
      if (statSync(path).isDirectory()) walk(path);
      else if (path.endsWith('.html')) pages.push(path);
    }
  };
  walk(PUBLIC);
  return pages;
}

const title = (html) => (html.match(/<title>([^<]*)<\/title>/) ?? [])[1] ?? '';
const canonical = (html) =>
  (html.match(/rel="canonical"\s+href="([^"]+)"/) ?? [])[1] ?? '';

test('на сайт не уезжает страница другого продукта', () => {
  const strangers = publishedPages().filter((path) => {
    const html = readFileSync(path, 'utf8');
      // The parent products, not ours: this product took the Cruxwing name on
      // 2026-09-09, so a Cruxwing title is now exactly what belongs here.
      return /meetgpt|wheespr/i.test(title(html));
  });
  assert.deepEqual(strangers, [],
    `в публикуемом наборе страницы чужого продукта: ${strangers.join(', ')}. ` +
    'Либо исключите каталог в pages.yml, либо перепишите страницу под cruxwing.');
});

test('canonical публикуемой страницы указывает на свой же адрес', () => {
  const foreign = publishedPages()
    .map((path) => [path, canonical(readFileSync(path, 'utf8'))])
    .filter(([, href]) => href && !href.includes(OWN_DOMAIN));
  assert.deepEqual(foreign, [],
    `canonical уводит на чужой домен: ${foreign.map((f) => f.join(' -> ')).join(', ')}. ` +
    'Поисковик отдаст чужую страницу вместо нашей, а если её там нет — 404.');
});

test('публикация не держится на списке скрытых каталогов', () => {
  const flow = readFileSync(FLOW, 'utf8');
  assert.doesNotMatch(flow, /^\s*EXCLUDE=/m,
    'pages.yml скрывает часть public/ вместо удаления или исправления файлов');
});

test('Pages refuses to publish from another product\'s repository', () => {
  const flow = readFileSync(FLOW, 'utf8');
  assert.match(flow, /EXPECTED_REPOSITORY:\s*theasder\/cruxwing/,
    'pages.yml no longer pins the canonical repository name');
  assert.match(flow, /\$GITHUB_REPOSITORY[^\n]*\$EXPECTED_REPOSITORY/,
    'pages.yml не сравнивает фактический репозиторий с ожидаемым');
  const guard = flow.indexOf('EXPECTED_REPOSITORY:');
  const publish = flow.indexOf('actions/upload-pages-artifact@');
  assert.ok(guard > -1 && guard < publish,
    'проверка идентичности должна остановить workflow до публикации');
});

test('Pages публикует artifact без Git credentials и записи в ветки', () => {
  const flow = readFileSync(FLOW, 'utf8');
  assert.match(flow, /^permissions:\n\s+contents:\s*read\s*$/m,
    'workflow по умолчанию получает больше, чем read-only checkout');
  assert.match(flow, /^\s+pages:\s*write\s*$/m,
    'deploy job не имеет минимального права GitHub Pages');
  assert.match(flow, /^\s+id-token:\s*write\s*$/m,
    'deploy job не может получить OIDC-токен Pages');
  assert.match(flow, /environment:\s*\n\s+name:\s*github-pages/,
    'Pages deployment не защищён штатным Environment');
  assert.match(flow, /persist-credentials:\s*false/,
    'checkout оставляет Git credentials доступными последующим шагам');
  assert.match(flow, /actions\/upload-pages-artifact@[0-9a-f]{40}/,
    'Pages artifact action не закреплён на commit SHA');
  assert.match(flow, /actions\/deploy-pages@[0-9a-f]{40}/,
    'Pages deploy action не закреплён на commit SHA');
  assert.doesNotMatch(flow, /\bgit\s+push\b|contents:\s*write/,
    'Pages workflow всё ещё может записывать или force-push ветку');
});
