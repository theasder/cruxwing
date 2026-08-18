import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

// Что уезжает на сайт.
//
// `pages.yml` собирает ветку страницы из всего public/, поэтому «лежит в
// public/» и «опубликовано» — одно и то же, если каталог не исключён явно.
// В public/ru/ лежит landing другого продукта: 53 упоминания cruxwing, цены и
// canonical на cruxwing.ai, который сам отвечает 404. У orakul цен нет по
// устройству, и первый же push выложил бы страницу с ценами на сайт продукта
// без цен (план, §5.1).
//
// Список исключений читается из самого рабочего процесса. Второй список здесь
// разошёлся бы с первым, и разошёлся бы молча — а молчание тут и есть отказ.

const PUBLIC = 'public';
const FLOW = '.github/workflows/pages.yml';
const OWN_DOMAIN = 'theasder.github.io';

function excluded() {
  const flow = readFileSync(FLOW, 'utf8');
  const line = flow.match(/^\s*EXCLUDE="([^"]*)"/m);
  assert.ok(line, `${FLOW} больше не объявляет EXCLUDE — публикуется всё подряд`);
  return line[1].split(/\s+/).filter(Boolean);
}

function publishedPages() {
  const skip = new Set(excluded());
  const pages = [];
  const walk = (dir, top) => {
    for (const name of readdirSync(dir)) {
      if (top && skip.has(name)) continue;
      const path = join(dir, name);
      if (statSync(path).isDirectory()) walk(path, false);
      else if (path.endsWith('.html')) pages.push(path);
    }
  };
  walk(PUBLIC, true);
  return pages;
}

const title = (html) => (html.match(/<title>([^<]*)<\/title>/) ?? [])[1] ?? '';
const canonical = (html) =>
  (html.match(/rel="canonical"\s+href="([^"]+)"/) ?? [])[1] ?? '';

test('на сайт не уезжает страница другого продукта', () => {
  const strangers = publishedPages().filter((path) => {
    const html = readFileSync(path, 'utf8');
    return /cruxwing/i.test(title(html));
  });
  assert.deepEqual(strangers, [],
    `в публикуемом наборе страницы чужого продукта: ${strangers.join(', ')}. ` +
    'Либо исключите каталог в pages.yml, либо перепишите страницу под orakul.');
});

test('canonical публикуемой страницы указывает на свой же адрес', () => {
  const foreign = publishedPages()
    .map((path) => [path, canonical(readFileSync(path, 'utf8'))])
    .filter(([, href]) => href && !href.includes(OWN_DOMAIN));
  assert.deepEqual(foreign, [],
    `canonical уводит на чужой домен: ${foreign.map((f) => f.join(' -> ')).join(', ')}. ` +
    'Поисковик отдаст чужую страницу вместо нашей, а если её там нет — 404.');
});

// Исключение обязано быть настоящим: каталог, которого нет, — это не защита, а
// строка в файле.
test('исключённые каталоги существуют, иначе исключение ничего не значит', () => {
  for (const dir of excluded()) {
    assert.ok(statSync(join(PUBLIC, dir)).isDirectory(),
      `pages.yml исключает public/${dir}, а его нет — уберите строку или верните каталог`);
  }
});

// Проверка обязана видеть ту самую страницу, ради которой написана: если снять
// исключение, набор становится красным.
test('без исключения чужая страница находится', () => {
  const html = readFileSync(join(PUBLIC, 'ru', 'index.html'), 'utf8');
  assert.match(title(html), /Cruxwing/i,
    'public/ru больше не страница Cruxwing — проверка сторожит пустоту');
  assert.ok(!canonical(html).includes(OWN_DOMAIN),
    'canonical в public/ru стал своим — образец чужой страницы исчез');
});
