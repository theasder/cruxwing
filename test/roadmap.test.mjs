import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

// Run with: node --test
//
// План развития — документ, который гниёт быстрее остальных: он говорит о
// будущем, а будущее не проверишь. Проверить можно другое — его настоящее.
// Каждое утверждение здесь либо про код («подключено вот это»), либо про
// измерение («столько имён идёт мимо списка»), и каждое из них ломается молча:
// сервис доезжает до кода, число меняется, раздел плана перенумеровывают, а
// строка в роадмапе остаётся прежней и читается как действующая.
//
// Что НЕ проверяется: правильность самого плана. Порядок работ — суждение, и
// тест, закрепивший его, мешал бы менять решение. Проверяется только то, что
// план не расходится с репозиторием.

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, '..');
const read = (...p) => readFileSync(resolve(repo, ...p), 'utf8');

const roadmap = read('docs', 'ROADMAP.md');
const plan = read('docs', 'RESEARCH-AND-PLAN.md');

/// Раздел роадмапа целиком: от своего заголовка до следующего заголовка любого
/// уровня.
function section(number) {
  const start = roadmap.search(new RegExp(`^#{2,4} ${number.replace('.', '\\.')}[.\\s]`, 'm'));
  assert.ok(start >= 0, `в роадмапе нет раздела §${number}`);
  const rest = roadmap.slice(start);
  // Со следующей строки, а не со второго символа: `^` в режиме `m` совпадает и
  // с началом самой строки, поэтому поиск «от rest.slice(1)» находил тот же
  // заголовок и возвращал раздел из одного символа. Проверки при этом
  // проходили бы только в одну сторону — «не содержит», — то есть молчали.
  const afterHeading = rest.indexOf('\n') + 1;
  const next = rest.slice(afterHeading).search(/^#{2,4} /m);
  return next < 0 ? rest : rest.slice(0, afterHeading + next);
}

// Файлы, в которых живут перечисления Service. Список один на обе проверки
// ниже: когда он был написан дважды, добавление WesternTrackers обновило одну
// копию и оставило другую — и «манифест недостижим» соврал бы про Linear.
const SERVICE_FILES = ['RussianTrackers.swift', 'WorkMessengers.swift',
                       'SelfHostedTrackers.swift', 'TeamNotes.swift',
                       'WesternTrackers.swift'];

describe('ROADMAP', () => {
  test('разделы пронумерованы и идут по порядку', () => {
    // Та же проверка, что у плана, и по той же причине: документ дописывают
    // сверху вниз, разделы расползаются, и читатель перестаёт верить цифрам
    // внутри, если не сходится оглавление.
    const headings = [...roadmap.matchAll(/^(#{2,4})\s+(.*)$/gm)].map((m) => m[2].trim());
    assert.ok(headings.length >= 10, `разделов всего ${headings.length} — проверка была бы пустой`);

    const unnumbered = headings.filter((h) => !/^[0-9]+(\.[0-9]+)*[.\s]/.test(h));
    assert.deepEqual(unnumbered, [], `разделы без номера: ${unnumbered.join(' | ')}`);

    const numbers = headings.map((h) => /^([0-9]+(?:\.[0-9]+)*)/.exec(h)[1]);
    const key = (n) => n.split('.').map(Number);
    const outOfOrder = [];
    for (let i = 1; i < numbers.length; i += 1) {
      const a = key(numbers[i - 1]); const b = key(numbers[i]);
      for (let d = 0; d < Math.max(a.length, b.length); d += 1) {
        const x = a[d] ?? -1; const y = b[d] ?? -1;
        if (x === y) continue;
        if (x > y) outOfOrder.push(`§${numbers[i - 1]} стоит перед §${numbers[i]}`);
        break;
      }
    }
    assert.deepEqual(outOfOrder, [], outOfOrder.join('; '));
  });

  test('каждый российский трекер из кода назван подключённым', () => {
    // Перепись в плане уже сверяется с кодом. Роадмап повторяет её своими
    // словами в §2.2 — значит, повторяет и способ устареть: сервис появился
    // или выпал, а строка «подключено» осталась прежней.
    const src = read('mvp', 'Sources', 'OrakulCore', 'RussianTrackers.swift');
    const block = src.slice(src.indexOf('public var title: String'));
    const shipped = [...block.slice(0, block.indexOf('}\n\n')).matchAll(/return "([^"]+)"/g)]
      .map(([, title]) => title);
    assert.ok(shipped.length >= 4, `нашлось ${shipped.length} названий — проверка была бы пустой`);

    const inventory = section('2.2');
    for (const name of shipped) {
      assert.ok(inventory.includes(name),
        `${name} есть в коде и пропал из перечня подключённого`);
    }
  });

  test('число коннекторов в тексте сходится с кодом', () => {
    // Слово «шестнадцать» стареет ровно тогда, когда добавляют
    // семнадцатый, — и этого никто не замечает, потому что добавление
    // коннектора и правка роадмапа лежат в разных головах.
    const services = (file) => {
      const src = read('mvp', 'Sources', 'OrakulCore', file);
      const block = src.slice(src.indexOf('public enum Service'));
      const line = /case ([^\n]+)/.exec(block)[1];
      return line.split(',').length;
    };
    const own = SERVICE_FILES.reduce((sum, file) => sum + services(file), 0)
      // Источники, у которых нет перечисления Service: они самостоятельные типы.
      // Список руками, поэтому каждый назван и проверен на существование —
      // иначе число «+3» переживёт удаление любого из них.
      + ['GitHubConnector', 'TelegramSupergroups', 'LocalNotes']
          .filter((type) => {
            const src = read('mvp', 'Sources', 'OrakulCore', `${type}.swift`);
            return new RegExp(`public struct ${type}\\b`).test(src);
          }).length;

    const mcp = read('app', 'Sources', 'MeetGPT', 'MCP', 'MCPCatalog.swift');
    const builtIn = mcp.slice(mcp.indexOf('static let builtIn'));
    const western = (builtIn.slice(0, builtIn.indexOf('\n    ]'))
      .match(/MCPServerDescriptor\(id:/g) ?? []).length;

    const stated = /Total: (\d+) own connectors, (\d+) western via MCP/.exec(roadmap);
    assert.ok(stated, 'строка с итогом коннекторов исчезла — считать стало нечего');
    assert.equal(Number(stated[1]), own,
      `в тексте ${stated[1]} своих коннекторов, в коде ${own}`);
    assert.equal(Number(stated[2]), western,
      `в тексте ${stated[2]} западных, в MCPCatalog.builtIn ${western}`);
  });

  test('§7.2: манифест недостижим ровно тогда, когда роадмап так и говорит', () => {
    // Ошибка, ради которой это написано, уже случилась: §7.2 сказал «shipped»
    // про Plane, у которого нет case в Service, — то есть ни один вопрос
    // человека до него не доходит. Файл в ресурсах читается как работающий
    // коннектор, потому что он загружается, проверяется и покрыт набором.
    const ids = readdirSync(resolve(repo, 'mvp', 'Sources', 'OrakulCore', 'Resources', 'connectors'))
      .filter((name) => name.endsWith('.json'))
      .map((name) => name.replace(/\.json$/, ''));
    assert.ok(ids.length >= 5, `манифестов нашлось ${ids.length} — проверка была бы пустой`);

    // Достижим тот, чей id совпадает с case в Service одного из четырёх файлов.
    const cases = new Set();
    for (const file of SERVICE_FILES) {
      const src = readFileSync(resolve(repo, 'mvp', 'Sources', 'OrakulCore', file), 'utf8');
      const block = src.slice(src.indexOf('public enum Service'));
      for (const name of /case ([^\n]+)/.exec(block)[1].split(',')) cases.add(name.trim());
    }
    const unreachable = ids.filter((id) => !cases.has(id)).sort();

    const text = section('7.2').replace(/\n/g, ' ');
    const stated = /Manifests written but not yet routed to anybody: ([^.]+)\./.exec(text);
    assert.ok(stated, 'в §7.2 пропал список недостижимых манифестов');
    // «none» — это пустой список, а не манифест с таким именем. Без разбора
    // этого слова проверка требовала бы держать в тексте несуществующий id.
    const listed = stated[1].trim() === 'none' ? []
      : stated[1].split(',').map((s) => s.replace(/\*\*/g, '').trim()).sort();
    assert.deepEqual(listed, unreachable,
      `в тексте ${listed.join(', ') || '—'}, в коде ${unreachable.join(', ') || '—'}`);
  });

  test('§7.2: граница перечисления — то же число, что в движке', () => {
    // Потолок держит движок, а не манифест. Если число в тексте разойдётся с
    // кодом, читатель поверит тексту: код он открывает реже.
    const engine = read('mvp', 'Sources', 'OrakulCore', 'ManifestConnector.swift');
    const limit = /scanPageLimit = (\d+)/.exec(engine);
    assert.ok(limit, 'потолок перечисления исчез из движка');
    const text = section('7.2').replace(/\n/g, ' ');
    assert.ok(new RegExp(`scanPageLimit\\` + '` = ' + `${limit[1]}`).test(text),
      `в движке потолок ${limit[1]} — в §7.2 стоит другое число`);
  });

  test('дыра в SECRET_VARS описана теми числами, которые в build.sh сейчас', () => {
    // §5.2 — единственное место роадмапа, где названа незакрытая дыра. Её
    // починят, а абзац останется и будет пугать читателя тем, чего уже нет;
    // или список вырастет, и абзац окажется мягче правды.
    const build = read('app', 'build.sh');
    const vars = /SECRET_VARS="([^"]+)"/.exec(build)[1].split(/\s+/);
    const used = [...new Set([...build.matchAll(/\$\(sw ([A-Z0-9_]+)\)/g)].map((m) => m[1]))];
    const missing = used.filter((v) => !vars.includes(v));
    const credentials = missing.filter((v) => /_(CLIENT_ID|CLIENT_SECRET|TOKEN|API_KEY)$/.test(v));

    const text = section('5.2');
    // Строкой с заменой переводов строк: текст перенесён по ширине, и число с
    // существительным разъезжается по двум строкам — проверка «в одну строку»
    // молчала бы на любом числе.
    assert.ok(new RegExp(`${used.length} names pass through`).test(text.replace(/\n/g, ' ')),
      `через sw проходит ${used.length} имён — в §5.2 стоит другое число`);
    assert.ok(new RegExp(`${vars.length} sit in the list`).test(text.replace(/\n/g, ' ')),
      `в SECRET_VARS ${vars.length} имён — в §5.2 стоит другое число`);

    for (const name of credentials) {
      assert.ok(text.includes(name),
        `${name} идёт мимо SECRET_VARS, и §5.2 о нём молчит`);
    }

    // Раздел объявлен закрытым — значит, механизм обязан быть на месте. Иначе
    // документ сообщает о починке, которой нет: худший вид устаревания, потому
    // что закрытый раздел больше никто не перечитывает.
    const shapeGuard = /case "\$1" in\s*\n\s*\*_CLIENT_ID\|\*_CLIENT_SECRET\|\*_TOKEN\|\*_API_KEY\)/;
    const closed = /closed 2026-\d{2}-\d{2}/.test(text);
    assert.equal(closed, shapeGuard.test(build),
      closed
        ? '§5.2 объявлен закрытым, а фильтра по форме имени в build.sh нет'
        : 'фильтр по форме имени в build.sh есть, а §5.2 всё ещё описывает дыру открытой');

    // Поведение доказывает не этот набор, а secrets.test.mjs: он запускает сам
    // `sw`. Здесь проверяется только, что документ на него ссылается — иначе
    // читатель не знает, чем подкреплено слово «closed».
    assert.match(text, /test\/secrets\.test\.mjs/,
      '§5.2 не называет проверку, которая держит это закрытым');
  });

  test('английских строк в интерфейсе не больше, чем обещано', () => {
    // Число из §6.4 — верхняя граница, и весь смысл в том, чтобы она не
    // росла. Замер повторяет команду из документа: та же выборка литералов и
    // тот же признак «ни одной кириллической буквы».
    const stated = /of (\d+) string literals in `Views\/` and `Onboarding\/`, (\d+)/
      .exec(roadmap.replace(/\n/g, ' '));
    assert.ok(stated, 'в §6.4 пропал замер английских строк');
    const promised = Number(stated[2]);

    const walk = (dir) => readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
      const full = resolve(dir, entry.name);
      if (entry.isDirectory()) return walk(full);
      return entry.name.endsWith('.swift') ? [full] : [];
    });

    const base = resolve(repo, 'app', 'Sources', 'MeetGPT');
    const literals = new Set();
    for (const dir of ['Views', 'Onboarding']) {
      for (const file of walk(resolve(base, dir))) {
        for (const [, literal] of readFileSync(file, 'utf8').matchAll(
          /(?:Text|Label|Button|Toggle|\.help|\.navigationTitle|Section)\(\s*("[^"]{4,}")/g)) {
          literals.add(literal);
        }
      }
    }
    assert.ok(literals.size > 100, `выборка вышла в ${literals.size} строк — замер не тот`);
    const english = [...literals].filter((s) => !/[а-яё]/i.test(s));
    assert.ok(english.length <= promised,
      `строк без кириллицы стало ${english.length}, а §6.4 обещает не больше ${promised}`);
  });

  test('число проверок страницы и документов в §2.1 — настоящее', () => {
    // Число устарело в ту же минуту, когда появился этот файл: добавление
    // набора меняет ровно ту величину, которую §2.1 называет измеренной.
    // Считается так же, как в readme.test.mjs, и по той же причине — иначе
    // «посчитано 2026-08-17» значит «посчитано когда-то».
    const suites = readdirSync(here).filter((n) => n.endsWith('.test.mjs'));
    const counted = suites
      .flatMap((name) => readFileSync(resolve(here, name), 'utf8').split('\n'))
      .filter((line) => /^\s*test\(/.test(line)).length;

    const stated = Number(/\| (\d{2,4}) tests?, all green \|/.exec(roadmap)?.[1] ?? NaN);
    assert.equal(stated, counted,
      `§2.1 называет ${stated} проверок, наборы объявляют ${counted}`);
  });

  test('закрытое с причиной не обещано как работа', () => {
    // Самая дорогая форма устаревания: сервис, про который в плане написано
    // «невозможно», всплывает в очереди. Кто-нибудь потратит на него день —
    // на то, что уже проверено и закрыто.
    const queue = section('7.3') + section('7.4') + section('8');
    for (const closed of ['Pyrus', 'Мегаплан', 'Яндекс Вики', 'Teamly', 'GigaChat', 'SaluteJazz']) {
      assert.ok(!queue.includes(closed),
        `${closed} закрыт в плане с причиной, а роадмап ставит его в очередь`);
    }
    // И наоборот: перечень закрытого не должен опустеть — без него причина
    // забывается, и сервис возвращается «на всякий случай».
    const closedSection = section('7.5');
    for (const closed of ['Pyrus', 'Мегаплан', 'GigaChat', 'SaluteJazz']) {
      assert.ok(closedSection.includes(closed),
        `${closed} пропал из перечня закрытого — причина потеряется`);
    }
  });

  test('каждая ссылка на раздел плана ведёт в существующий раздел', () => {
    // Роадмап опирается на план десятки раз. Раздел перенумеруют — и ссылка
    // станет отсылкой в пустоту, выглядя при этом так же авторитетно.
    const numbers = new Set([...plan.matchAll(/^#{2,4}\s+([0-9]+(?:\.[0-9]+)*)[.\s]/gm)]
      .map((m) => m[1]));
    assert.ok(numbers.size >= 20, `в плане ${numbers.size} нумерованных разделов — проверка пустая`);

    const cited = [...roadmap.matchAll(/plan §([0-9]+(?:\.[0-9]+)*)/g)].map((m) => m[1]);
    assert.ok(cited.length >= 10, `ссылок на план всего ${cited.length} — проверка была бы пустой`);
    const broken = [...new Set(cited)].filter((n) => !numbers.has(n));
    assert.deepEqual(broken, [], `ссылки в никуда: ${broken.map((n) => `§${n}`).join(', ')}`);
  });

  test('каждая сноска определена, использована, с адресом и датой чтения', () => {
    // Сноска без определения печатается как «[^tag]»: утверждение остаётся
    // голым, а выглядит подкреплённым. Определение без адреса — это «мы
    // что-то читали», а не источник. Дата нужна потому, что «проверено»
    // стареет, и читатель вправе знать, насколько.
    const refs = new Set([...roadmap.matchAll(/\[\^([a-z0-9-]+)\](?!:)/g)].map((m) => m[1]));
    const defs = new Set([...roadmap.matchAll(/^\[\^([a-z0-9-]+)\]: /gm)].map((m) => m[1]));
    assert.ok(refs.size >= 4, `сносок всего ${refs.size} — проверка была бы пустой`);

    const undefinedTags = [...refs].filter((tag) => !defs.has(tag));
    assert.deepEqual(undefinedTags, [], `упомянуты, но не определены: ${undefinedTags.join(', ')}`);
    const unused = [...defs].filter((tag) => !refs.has(tag));
    assert.deepEqual(unused, [], `определены, но не упомянуты: ${unused.join(', ')}`);

    const bodies = [...roadmap.matchAll(/^\[\^([a-z0-9-]+)\]: (.*)$/gm)];
    const addressless = bodies.filter(([, , body]) => !/https?:\/\//.test(body)).map(([, tag]) => tag);
    assert.deepEqual(addressless, [], `источники без адреса: ${addressless.join(', ')}`);
    const undated = bodies
      .filter(([, , body]) => !/read \d{4}-\d{2}-\d{2}/.test(body)).map(([, tag]) => tag);
    assert.deepEqual(undated, [], `источники без даты чтения: ${undated.join(', ')}`);
  });

  test('в очереди у каждой строки видно, на чём она держится', () => {
    // Прежняя версия требовала слова ASSUMPTION в §7.3 — и упала, когда
    // предположение ПРОВЕРИЛИ и убрали. Проверка ловила слово, а не свойство.
    //
    // Свойство такое: строка очереди опирается либо на документацию вендора
    // (сноска с адресом), либо честно говорит, что источника нет. Молчаливая
    // строка без того и другого через месяц читается как факт.
    // Правило берётся из CONTRIBUTING, а не придумывается здесь: метод, адрес и
    // параметр указываются СО ССЫЛКОЙ на справку вендора. Значит, строка,
    // называющая конкретный запрос или адрес, обязана нести сноску.
    //
    // Строки, которые ничего не утверждают, а спрашивают («есть ли поиск?»),
    // под правило не попадают: у них и нет источника, потому что нет
    // утверждения. Первая версия проверки этого не различала и объявила
    // нарушителями пять честных строк.
    // Утверждение — это адрес или запрос В КОДЕ (в обратных кавычках). Ссылка
    // markdown-ом на наш же issue утверждением не является: первая версия
    // считала её адресом сервиса и объявила нарушителями две честные строки,
    // где ссылка вела на github.com/theasder/orakul.
    // Метод плюс что угодно — и путь, и полный адрес. Первая версия требовала
    // слэша сразу после метода и не видела `GET https://…`, то есть ровно ту
    // форму, которой записана строка про Slack. Мутация это и показала.
    const claimsEndpoint = /`(GET|POST|PUT|PATCH)\s|`https?:\/\//i;
    const offenders = [];
    for (const number of ['7.3', '7.4']) {
      for (const raw of section(number).split('\n')) {
        const line = raw.replace(/\[[^\]]*\]\([^)]*\)/g, '');   // без markdown-ссылок
        if (!/^\| \*\*/.test(line)) continue;          // только строки таблицы
        if (!claimsEndpoint.test(line)) continue;        // ничего конкретного не утверждает
        if (/\[\^[a-z0-9-]+\]/.test(line)) continue;    // источник назван
        offenders.push(line.split('|')[1].trim());
      }
    }
    assert.deepEqual(offenders, [],
      `в очереди назван запрос без ссылки на документацию вендора: ${offenders.join(', ')}`);
  });

  test('русские названия сервисов написаны так же, как в коде', () => {
    // Документ на английском, и русское имя в нём — иностранное слово, которое
    // легко «поправить»: «Яндекс.Трекер», «Битрикс 24». Человек потом ищет это
    // написание в настройках приложения и не находит.
    //
    // Проверка на «созвон» здесь стояла раньше и стала пустой вместе с
    // переводом текста: в английской прозе этого слова не бывает по построению,
    // а зелёная проверка, которая не может упасть, закрывает вопрос вместо того,
    // чтобы его стеречь.
    const titles = ['RussianTrackers', 'WorkMessengers', 'SelfHostedTrackers', 'TeamNotes']
      .flatMap((file) => {
        const src = read('mvp', 'Sources', 'OrakulCore', `${file}.swift`);
        const block = src.slice(src.indexOf('public var title: String'));
        return [...block.slice(0, block.indexOf('}\n\n')).matchAll(/return "([^"]+)"/g)]
          .map(([, title]) => title);
      })
      .filter((title) => /[а-яё]/i.test(title));
    assert.ok(titles.length >= 3, `русских названий в коде ${titles.length} — проверка пустая`);

    for (const title of titles) {
      assert.ok(roadmap.includes(title), `${title} есть в коде и пропал из роадмапа`);

      // Разъезжается написание всегда в одном месте: там, где в названии стык —
      // пробел или цифра. Эти варианты и запрещаются.
      const variants = new Set();
      if (title.includes(' ')) {
        for (const separator of ['.', '-', '']) variants.add(title.replace(/ /g, separator));
      }
      const digits = /^(.*?[^\d\s])(\d+)$/.exec(title);
      if (digits) for (const separator of [' ', '-']) variants.add(`${digits[1]}${separator}${digits[2]}`);
      variants.delete(title);

      for (const wrong of variants) {
        assert.ok(!roadmap.includes(wrong),
          `в роадмапе «${wrong}», а в коде «${title}» — человек будет искать не то`);
      }
    }
  });

  test('README ведёт к плану развития', () => {
    // План, о котором знает только автор, своей работы не выполняет: он
    // существует затем, чтобы пришедший со стороны видел, во что встроится
    // его правка.
    assert.match(read('README.md'), /docs\/ROADMAP\.md/,
      'README не ссылается на план развития');
  });
});
