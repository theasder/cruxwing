import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { resolve, join } from 'node:path';

// Ссылка на документацию — предъявленное доказательство, а не украшение.
//
// Правило приёма (§7.1) требует найти метод, адрес, параметр поиска и форму
// ответа В ДОКУМЕНТАЦИИ ВЕНДОРА. По ссылке в манифесте это проверяет следующий
// человек. Мёртвая ссылка не ломает поиск сегодня — она делает утверждение
// непроверяемым завтра.
//
// Живость ссылок проверяет scripts/proverka-ssylok.py, и НЕ здесь: чужие сайты
// переезжают и падают, а красный набор от чужого сбоя учит не верить набору.
// Здесь проверяется то, что от чужой сети не зависит.
const DIR = 'mvp/Sources/CruxwingCore/Resources/connectors';

const manifests = readdirSync(DIR)
  .filter((f) => f.endsWith('.json'))
  .map((f) => JSON.parse(readFileSync(join(DIR, f), 'utf8')));

test('у каждого манифеста есть ссылка на документацию вендора', () => {
  assert.ok(manifests.length >= 20, `манифестов ${manifests.length} — разбор сломан`);
  const without = manifests.filter((m) => !m.docs || !/^https:\/\//.test(m.docs));
  assert.deepEqual(without.map((m) => m.id), [],
    'манифест без ссылки на документацию — это догадка, а не описание сервиса');
});

test('ссылка ведёт на страницу метода, а не на корень сайта', () => {
  // «https://vendor.com/» подтверждает существование вендора, а не метода.
  // Правило §7.1 — про метод, параметр поиска и форму ответа.
  //
  // Метод опознаётся путём ИЛИ якорем: у Kaiten и Mattermost вся справка —
  // одна страница, и «#tag/cards/operation/getCards» указывает на метод точнее,
  // чем любой путь. Первая редакция этой проверки требовала пути и объявила обе
  // ссылки негодными — правило было о форме адреса вместо того, о чём §7.1.
  const tooBroad = manifests.filter((m) => {
    const path = m.docs.replace(/^https:\/\/[^/]+/, '').replace(/[#?].*$/, '');
    const anchor = (m.docs.split('#')[1] ?? '');
    const namesAMethod = path.replace(/\/$/, '').length > 0 || anchor.length > 0;
    return !namesAMethod;
  });
  assert.deepEqual(tooBroad.map((m) => m.id), [],
    'ссылка на корень сайта не подтверждает метод');
});

test('проверка живости ссылок существует и запускается руками', () => {
  // Сама проверка сети живёт скриптом. Если он исчезнет, останется правило без
  // способа его применить — то же, что сторож, которого никто не зовёт.
  assert.ok(existsSync(resolve('scripts/proverka-ssylok.py')),
    'скрипт проверки ссылок пропал — правило §7.1 больше нечем применить');
  const source = readFileSync('scripts/proverka-ssylok.py', 'utf8');
  assert.match(source, /CONNECTORS\.glob\("\*\.json"\)/,
    'скрипт больше не читает манифесты');
  assert.match(source, /return 1/, 'скрипт не сообщает о мёртвой ссылке кодом возврата');
});
