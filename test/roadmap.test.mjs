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
/// Скрипт без комментариев: строка, упомянутая в пояснении, не считается
/// исполняемой. На этом здесь уже спотыкались шесть раз.
function stripShellComments(text) {
  return text.split('\n')
    .filter((line) => !line.trimStart().startsWith('#'))
    .join('\n');
}

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

  test('каждый подключённый сервис из кода назван в перечне', () => {
    // Перепись в плане уже сверяется с кодом. Роадмап повторяет её своими
    // словами в §2.2 — значит, повторяет и способ устареть: сервис появился
    // или выпал, а строка «подключено» осталась прежней.
    //
    // Проверка смотрела в ОДНУ семью из пяти — российские трекеры. Ровно
    // поэтому из таблицы тихо выпали Slack, Plane, GitFlic, BookStack, Wiki.js
    // и Nextcloud: их семьи не смотрел никто, а общее число рядом оставалось
    // верным и создавало впечатление, что перечень живой.
    const families = ['RussianTrackers.swift', 'WorkMessengers.swift',
                      'SelfHostedTrackers.swift', 'TeamNotes.swift',
                      'WesternTrackers.swift'];
    const inventory = section('2.2');
    let counted = 0;

    for (const file of families) {
      const src = read('mvp', 'Sources', 'OrakulCore', file);
      const block = src.slice(src.indexOf('public var title: String'));
      const shipped = [...block.slice(0, block.indexOf('}\n\n')).matchAll(/return "([^"]+)"/g)]
        .map(([, title]) => title);
      assert.ok(shipped.length >= 2,
        `${file}: нашлось ${shipped.length} названий — проверка была бы пустой`);
      counted += shipped.length;

      for (const name of shipped) {
        assert.ok(inventory.includes(name),
          `${name} (${file}) есть в коде и пропал из перечня подключённого`);
      }
    }
    assert.ok(counted >= 20, `по всем семьям нашлось ${counted} названий — разбор сломан`);
  });

  test('живая проверка в перечне названа по манифестам, а не на память', () => {
    // Жирным в §2.2 отмечено «проверено на работающем сервисе». Утверждение
    // сильное, и держится оно не словом: манифест такого коннектора несёт
    // отметку о живом прогоне.
    // Отметка — ПОЛЕ манифеста, а не слово в примечании.
    //
    // Здесь искалось слово «живом», а у GitLab в примечании стояло «на
    // поднятом у себя»: проверка молча пропускала сервис, и жирная отметка в
    // §2.2 держалась на выборе слова в прозе. Утверждение «проверено на
    // работающем сервисе» слишком сильное, чтобы зависеть от синонима.
    const live = readdirSync(resolve(here, '..', 'mvp', 'Sources', 'OrakulCore',
                                     'Resources', 'connectors'))
      .filter((f) => f.endsWith('.json'))
      .filter((f) => JSON.parse(read('mvp', 'Sources', 'OrakulCore', 'Resources',
                                     'connectors', f)).liveCheckedOn);
    assert.ok(live.length >= 4, `манифестов с живой проверкой ${live.length} — ждали хотя бы четыре`);

    const inventory = section('2.2');
    const bold = [...inventory.matchAll(/\*\*([^*]+)\*\*/g)].map(([, name]) => name);
    assert.ok(bold.length >= 4, 'в перечне не отмечено ни одной живой проверки');

    // Список названий — ручной, потому что в перечне сервис зовётся так, как
    // его зовут люди («Gitea / Forgejo»), а в манифесте — идентификатором.
    // Но пропускать НЕИЗВЕСТНОЕ имя молча нельзя: именно так GitLab и Plane
    // прошли живую проверку и остались неотмеченными — `continue` тихо
    // выбрасывал всё, чего нет в списке, и проверка сторожила ровно четыре
    // сервиса из шести. Та же ошибка, что с ручным списком свойств в §6.4.
    const titles = { gitea: 'Gitea / Forgejo', redmine: 'Redmine',
                     wikijs: 'Wiki.js', nextcloud: 'Nextcloud',
                     gitlab: 'GitLab', plane: 'Plane', bookstack: 'BookStack',
                     mattermost: 'Mattermost', rocketChat: 'Rocket.Chat',
                     matrix: 'Matrix / Element' };
    for (const id of live) {
      const key = id.replace('.json', '');
      const title = titles[key];
      assert.ok(title,
        `манифест ${key} отмечен живой проверкой, а имени для перечня нет — ` +
        'добавьте его, иначе проверка молча пропустит сервис');
      assert.ok(bold.includes(title),
        `${title} проверен на живом сервисе, а в §2.2 это не отмечено`);
    }
  });

  test('предел размера и окно памяти в §10.1 — те же, что в коде', () => {
    // Числа §10.1 были закреплены наполовину: сроки — да, а потолок ответа и
    // срок памяти жили в прозе. Ровно так же выглядели причины «остаётся
    // кодом» в §6.2 — верные на день написания и не сверяемые ни с чем; две из
    // четырёх к моменту проверки уже протухли.
    const engine = read('mvp', 'Sources', 'OrakulCore', 'ManifestConnector.swift');
    const bytes = /maximumResponseBytes = (\d+) \* 1024 \* 1024/.exec(engine);
    assert.ok(bytes, 'потолок ответа не найден в движке — разбор сломан');
    const audit = section('10.1');
    assert.ok(audit.includes(`${bytes[1]} MB`),
      `§10.1 называет не тот потолок: в коде ${bytes[1]} МБ`);

    // И «в двух местах» — это счёт, а не оборот речи: снимут одну проверку,
    // и фраза останется верной на вид.
    const places = ['ManifestConnector.swift', 'ConnectorSession.swift']
      .filter((f) => read('mvp', 'Sources', 'OrakulCore', f).includes('maximumResponseBytes'));
    assert.equal(places.length, 2,
      `потолок проверяется в ${places.length} местах, а §10.1 обещает два`);

    const cache = read('mvp', 'Sources', 'OrakulCore', 'ConnectorCache.swift');
    const window = /freshFor: TimeInterval = (\d+)/.exec(cache);
    assert.ok(window, 'окно памяти не найдено — разбор сломан');
    assert.ok(audit.includes(`${window[1]} seconds`),
      `§10.1 называет не то окно памяти: в коде ${window[1]} с`);
  });

  test('пределы по времени в §10.1 те же, что в коде', () => {
    // Раздел про недружелюбного вендора однажды уже приписал защиту не тому
    // пределу: байт в секунду держался будто бы восьмисекундным таймаутом, а
    // тот считает ПАУЗЫ и обнуляется на каждом принятом байте. Числа в тексте
    // теперь берутся из кода, а не из памяти.
    const session = read('mvp', 'Sources', 'OrakulCore', 'ConnectorSession.swift');
    const values = [...session.matchAll(/timeoutIntervalForResource = (\d+)/g)]
      .map(([, n]) => Number(n));
    assert.equal(values.length, 2,
      `в ConnectorSession нашлось ${values.length} значений предела — разбор сломан`);

    const audit = section('10.1');
    for (const value of values) {
      assert.ok(new RegExp(`\\b${value}\\b`).test(audit),
        `§10.1 не называет предел ${value} с, который стоит в коде`);
    }
  });

  test('§10.1 называет оба написания своей сессии', () => {
    // Сторож ловит и `URLSession.shared`, и `URLSession(configuration:)`.
    // Текст, называющий одно, обещает половину защиты.
    const test = read('mvp', 'Tests', 'OrakulCoreTests', 'RedirectPolicyTests.swift');
    assert.ok(test.includes('URLSession.shared') && test.includes('URLSession('),
      'проверка перестала ловить оба написания — тогда и текст менять не надо');

    const audit = section('10.1');
    assert.ok(audit.includes('URLSession.shared'), '§10.1 не называет `URLSession.shared`');
    assert.ok(audit.includes('URLSession(configuration:)'),
      '§10.1 не называет свою сессию — а сторож её ловит');
  });

  test('каждый сторож границы из §3 существует и что-то проверяет', () => {
    // §3 говорит про себя: «не разговоры о ценностях: каждая строка ломает
    // сборку или прогон». Держится это на именах в столбце «чем закреплено», и
    // проверить их было нечем: переименованный набор оставил бы в плане
    // обещание защиты, которой нет. Ровно тот класс, который §13 уже знает, —
    // сторож, которого нельзя позвать, — только на уровне самого плана.
    const borders = section('3');
    const named = [...borders.matchAll(/`([A-Za-z][A-Za-z0-9_]*Tests|[a-z-]+\.test\.mjs|LiveConnectorProbe)`/g)]
      .map(([, name]) => name);
    const unique = [...new Set(named)];
    assert.ok(unique.length >= 5,
      `в §3 нашлось ${unique.length} имён сторожей — разбор сломан`);

    const roots = ['app/Tests/MeetGPTTests', 'mvp/Tests/OrakulCoreTests', 'test'];
    for (const name of unique) {
      const isSwift = !name.endsWith('.mjs');
      const candidates = roots.flatMap((root) => {
        try {
          return readdirSync(resolve(here, '..', root))
            .filter((file) => file === name || file === `${name}.swift` || file.startsWith(name))
            .map((file) => resolve(here, '..', root, file));
        } catch { return []; }
      });
      assert.ok(candidates.length > 0,
        `§3 закрепляет границу за «${name}», а такого набора нет`);

      const body = readFileSync(candidates[0], 'utf8');
      const hasTests = isSwift ? /@Test\b/.test(body) : /\btest\(/.test(body);
      assert.ok(hasTests,
        `«${name}» существует, но не содержит ни одной проверки — граница не закреплена ничем`);
    }
  });

  test('числа из кода в плане — те же, что в коде', () => {
    // Прозу про защиты этот файл уже ловил на трёх устаревших утверждениях.
    // Числа стареют так же и заметны ещё меньше: «три манифеста» и «предел 10»
    // выглядят одинаково правдоподобно и когда верны, и когда нет.
    const engine = read('mvp', 'Sources', 'OrakulCore', 'ManifestConnector.swift');
    const limit = Number(/scanPageLimit = (\d+)/.exec(engine)[1]);
    assert.ok(limit > 0, 'предел страниц не найден в движке — разбор сломан');
    assert.ok(section('7.2').includes(`scanPageLimit\` = ${limit}`),
      `§7.2 называет не тот предел страниц: в коде ${limit}`);

    // Причины стареют так же, как числа, и заметны ещё меньше.
    //
    // §6.2 держит список «остаётся кодом, и вот почему». Две причины из четырёх
    // оказались просроченными: Zulip ждал Basic-авторизации, появившейся вместе
    // с Nextcloud, а Matrix — вложенного тела, переставшего быть преградой,
    // когда тело стало шаблоном-строкой. Обе фразы читались как верные.
    //
    // Числа здесь пересчитываются из кода на каждом прогоне; у причин такой
    // проверки не было. «Остаётся кодом» — утверждение о коде ровно в той же
    // мере, что и «четырнадцать манифестов».
    // Идентификаторы — из файлов, а не из их имён: по полю `id` ищет движок, а
    // имя файла лишь соглашение. Эта же проверка сначала сверяла имена и
    // объявила `rocketChat` необъяснённым, когда файл назывался иначе.
    const connectorsDir = resolve(here, '..', 'mvp', 'Sources', 'OrakulCore',
                                  'Resources', 'connectors');
    const described = readdirSync(connectorsDir)
      .filter((f) => f.endsWith('.json'))
      .map((f) => JSON.parse(readFileSync(resolve(connectorsDir, f), 'utf8')).id);
    const claimedAsCode = { 'Яндекс Трекер': 'yandexTracker', 'Битрикс24': 'bitrix24' };
    const stillCode = section('6.2').slice(section('6.2').indexOf('Still code'));
    for (const [name, id] of Object.entries(claimedAsCode)) {
      assert.ok(stillCode.includes(name), `§6.2 больше не называет ${name} среди остающихся кодом`);
      assert.ok(!described.map((d) => d.toLowerCase()).includes(id.toLowerCase()),
        `§6.2 зовёт ${name} кодом, а манифест для него уже написан`);
    }

    // И обратная сторона — та, которой не было и которая и подвела.
    //
    // Проверка выше следит, чтобы НАЗВАННЫЙ кодом не обзавёлся манифестом
    // втихую. Но список читается как полный, а был неполным: из пяти сервисов
    // без манифеста в нём стояло два. Rocket.Chat, Kaiten и YouGile оставались
    // кодом вообще без объяснения. Теперь молчание ловится по имени.
    const enums = readFileSync(resolve(here, '..', 'mvp', 'Sources', 'OrakulCore',
                                       'RussianTrackers.swift'), 'utf8')
      + readFileSync(resolve(here, '..', 'mvp', 'Sources', 'OrakulCore',
                             'WorkMessengers.swift'), 'utf8');
    const inCode = [...enums.matchAll(/public enum Service: String[^{]*\{\s*\n\s*case ([^\n]+)/g)]
      .flatMap((m) => m[1].split(',').map((n) => n.trim()));
    const lowered = described.map((id) => id.toLowerCase());
    const silent = inCode.filter((id) => !lowered.includes(id.toLowerCase()))
      .filter((id) => !Object.values(claimedAsCode).includes(id));
    assert.deepEqual(silent, [],
      `сервисы без манифеста и без причины в §6.2: ${silent.join(', ')}`);

    const manifests = readdirSync(resolve(here, '..', 'mvp', 'Sources', 'OrakulCore',
                                          'Resources', 'connectors'))
      .filter((f) => f.endsWith('.json')).length;
    assert.ok(manifests >= 10, `манифестов нашлось ${manifests} — разбор сломан`);
    assert.ok(section('6.2').includes(`Today there are ${manifests}`),
      `§6.2 не называет сегодняшнее число манифестов (${manifests})`);
  });

  // Сервисы, чей параметр поиска — язык, а не строка, перечислены в §7.4
  // словами. Список этот не украшение: он говорит, кому вопрос уходит
  // обезоруженным, и по нему сверяются, когда добавляют шестого. Манифест
  // переводят на {queryWords} одной строкой, а абзац остаётся прежним — и
  // читается как действующий перечень, которым он больше не является.
  // §11 говорит, сколько коннекторов проверено на живом сервисе, а сколько
  // написано только по документации. Ровно это число уже один раз отстало —
  // строка держала «четыре», когда их было шесть, — и заметили это не при
  // чтении, а когда мутация пометок в §2.2 прошла зелёной.
  test('§11 знает, сколько коннекторов проверено живьём, а сколько нет', () => {
    const dir = resolve(here, '..', 'mvp', 'Sources', 'OrakulCore',
                        'Resources', 'connectors');
    const manifests = readdirSync(dir)
      .filter((f) => f.endsWith('.json'))
      .map((f) => JSON.parse(readFileSync(resolve(dir, f), 'utf8')));
    const live = manifests.filter((m) => m.liveCheckedOn);
    const onlyDocs = manifests.filter((m) => !m.liveCheckedOn);

    assert.ok(live.length >= 2 && onlyDocs.length >= 2,
      `живых ${live.length}, бумажных ${onlyDocs.length} — разбор сломан`);

    const words = ['ноль', 'one', 'two', 'three', 'four', 'five', 'six', 'seven',
                   'eight', 'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen',
                   'fifteen', 'sixteen'];
    const risks = section('11');
    assert.ok(risks.includes(`**${words[live.length]}** carry \`liveCheckedOn\``),
      `§11 называет другое число проверенных живьём, а их ${live.length}`);
    assert.ok(risks.includes(`**${words[onlyDocs.length]}** do not`),
      `§11 называет другое число бумажных, а их ${onlyDocs.length}`);

    // И поимённо — иначе «семь» останется верным, когда живьём проверят
    // другую семёрку.
    for (const manifest of live) {
      assert.ok(risks.includes(manifest.title),
        `${manifest.title} проверен живьём, а §11 его не называет`);
    }
  });

  // Формат манифеста описан для того, кто придёт снаружи, и устаревает он
  // тише всего: движок учит новую подстановку, а CONTRIBUTING продолжает
  // рассказывать про старую. Стоит это дорого — человек по инструкции напишет
  // {query} там, где нужен {queryWords}, и привезёт ту самую дыру, которую
  // §7.4 закрывал: чужой сервис прочтёт вопрос как указание.
  test('CONTRIBUTING называет все подстановки, которые умеет движок', () => {
    const engine = read('mvp', 'Sources', 'OrakulCore', 'ConnectorManifest.swift');
    const line = /let builtin: Set<String> = \[([^\]]+)\]/.exec(engine);
    assert.ok(line, 'в движке не нашёлся список подстановок — разбор сломан');
    const placeholders = [...line[1].matchAll(/"([a-zA-Z]+)"/g)].map((m) => m[1]);
    assert.ok(placeholders.length >= 5,
      `подстановок нашлось ${placeholders.length} — разбор сломан`);

    const doc = read('CONTRIBUTING.md');
    const missing = placeholders.filter((name) => !doc.includes(`{${name}}`));
    assert.deepEqual(missing, [],
      `движок умеет подстановки, о которых CONTRIBUTING молчит: ${missing.join(', ')}`);
  });

  test('перечень языковых сервисов в §7.4 — тот же, что в манифестах', () => {
    const dir = resolve(here, '..', 'mvp', 'Sources', 'OrakulCore',
                        'Resources', 'connectors');
    const dialects = readdirSync(dir)
      .filter((f) => f.endsWith('.json'))
      .map((f) => JSON.parse(readFileSync(resolve(dir, f), 'utf8')))
      .filter((m) => {
        const templates = (m.request.query ?? []).map((q) => q.value)
          .concat(m.request.body ?? '');
        return templates.some((t) => t.includes('{queryWords}'));
      });

    assert.ok(dialects.length >= 2,
      `языковых манифестов нашлось ${dialects.length} — разбор сломан`);

    // Искать по всему §7.4 бесполезно, и это показала мутация: Slack, Trello,
    // BookStack и Mattermost стоят там в таблице подключённого независимо от
    // того, что написано про язык поиска. Переименуй их в нужном абзаце — и
    // проверка всё равно нашла бы имя строкой выше. Поэтому берётся ровно тот
    // абзац, который делает утверждение.
    const whole = section('7.4');
    const from = whole.indexOf('was the first, and a sweep');
    const to = whole.indexOf('The likely trigger');
    assert.ok(from >= 0 && to > from, '§7.4 потерял абзац про язык поиска');
    // Начало абзаца — от его первой строки, а не от середины найденной фразы.
    const start = whole.lastIndexOf('\n\n', from) + 2;
    const text = whole.slice(start, to);

    for (const manifest of dialects) {
      assert.ok(text.includes(manifest.title),
        `${manifest.title} обезоруживает вопрос, а абзац §7.4 о нём молчит`);
    }

    // Ещё и счёт словом: имя, оставшееся в абзаце от прежней редакции, сам по
    // себе перечень выше не поймает — он проверяет только одну сторону.
    const words = ['ноль', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven'];
    const others = dialects.length - 1;   // Jira названа в том же абзаце отдельно
    assert.ok(text.includes(`${words[others]} more read it as a language`),
      `§7.4 обещает другое число языковых сервисов, а их ${others} кроме Jira`);
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
    // Идентификатор берётся ИЗ ФАЙЛА, а не из его имени.
    //
    // Достижимость решает поле `id`: движок ищет манифест по `$0.id ==
    // service.rawValue`. Имя файла — соглашение, и оно однажды разошлось:
    // `rocketchat.json` с идентификатором `rocketChat` был вполне достижим, а
    // проверка объявила его брошенным. Сверять надо то, по чему ищет код.
    const dir = resolve(repo, 'mvp', 'Sources', 'OrakulCore', 'Resources', 'connectors');
    const ids = readdirSync(dir)
      .filter((name) => name.endsWith('.json'))
      .map((name) => JSON.parse(readFileSync(resolve(dir, name), 'utf8')).id);
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

  test('§8: система из таблицы не может быть названа непроверенной рядом', () => {
    // Ровно та поломка, ради которой это написано: таблица говорила «ставится
    // и работает», а абзац тремя строками ниже — «не проверено». Пережило это
    // потому, что §8 был единственным разделом без единой проверки: у всех
    // остальных числа привязаны к коду, у этого была проза.
    const text = section('8');
    const rows = [...text.matchAll(/^\| ([^|]+?) \|[^|]*\| ([^|]+?) \|$/gm)]
      .map(([, system, result]) => ({ system: system.trim(), result: result.trim() }))
      .filter(({ system }) => !/^System$|^-+$/.test(system));
    assert.ok(rows.length >= 3, `в таблице §8 строк ${rows.length} — проверка была бы пустой`);

    const working = rows.filter(({ result }) => /installs|runs|works/i.test(result))
      .map(({ system }) => system.replace(/\s*\(.*\)/, '').trim());
    assert.ok(working.length >= 3, 'ни одна система не названа работающей — таблица не о том');

    for (const system of working) {
      // Первое слово названия: «ALT p10» → «ALT», «Astra Linux 1.7» → «Astra».
      const name = system.split(/[\s,]/)[0];
      const claimsUntested = new RegExp(
        `${name}[^.]{0,80}\\b(untested|not tested|is untested)\\b`, 'i');
      assert.doesNotMatch(text.replace(/\n/g, ' '), claimsUntested,
        `§8 одновременно говорит, что ${name} работает и что он не проверен`);
    }
  });

  test('§8: обещание «пакет ни от чего не зависит» держится скриптами', () => {
    // Обещание сильное: на изолированной машине это разница между «ставится» и
    // «не ставится». Если скрипт снова начнёт объявлять зависимости, текст
    // обязан перестать это обещать.
    const text = section('8').replace(/\n/g, ' ');
    if (!/declares \*\*no dependencies at all\*\*|no `Depends`/.test(text)) return;

    for (const file of ['package-linux.sh', 'package-rpm.sh']) {
      const script = stripShellComments(read('scripts', file));
      // Зависимости допустимы только на запасном пути (без статического SDK):
      // именно поэтому они появляются внутри ветки, а не безусловно.
      const unconditional = script.split('\n').filter((line) =>
        /^(Depends|Requires):/.test(line.trim()));
      assert.deepEqual(unconditional, [],
        `${file} объявляет зависимости безусловно — обещание §8 перестало быть правдой`);
    }
  });

  test('§8: версия пакета берётся оттуда же, откуда версия macOS-сборки', () => {
    // Два артефакта одного коммита обязаны отвечать на вопрос «какая версия»
    // одинаково. Число, вписанное в скрипт руками, разъезжается на второй
    // правке.
    const text = section('8').replace(/\n/g, ' ');
    assert.match(text, /CFBundleShortVersionString/,
      '§8 больше не говорит, откуда берётся версия');
    for (const file of ['package-linux.sh', 'package-rpm.sh']) {
      const script = stripShellComments(read('scripts', file));
      assert.match(script, /CFBundleShortVersionString/,
        `${file} перестал читать версию из Info.plist`);
    }
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
    // Механизм проверяется по СВОЙСТВУ, а не по конкретной строке фильтра.
    // Прошлая версия требовала ровно `*_CLIENT_ID|*_CLIENT_SECRET|…` и упала,
    // когда защиту усилили: запрет по умолчанию строже фильтра по форме имени,
    // но не совпадает с ним текстуально. Проверка, падающая на усилении, учит
    // не усиливать.
    //
    // Свойство: в dist-ветке есть ветка «всё остальное — стереть».
    const swBody = build.slice(build.indexOf('sw() {'), build.indexOf('\n}', build.indexOf('sw() {')));
    const defaultDeny = /\*\)\s*printf ''; return ;;/.test(swBody);
    const closed = /closed 2026-\d{2}-\d{2}/.test(text);
    assert.equal(closed, defaultDeny,
      closed
        ? '§5.2 объявлен закрытым, а в sw нет запрета по умолчанию: имя, о котором не сказано, уедет в сборку'
        : 'в sw есть запрет по умолчанию, а §5.2 всё ещё описывает дыру открытой');

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
    // Reversed with the product: §6.4 now pins how much Russian is left.
    const russian = [...literals].filter((s) => /[а-яё]/i.test(s));
    assert.ok(russian.length <= promised,
      `строк с кириллицей стало ${russian.length}, а §6.4 обещает не больше ${promised}`);
  });

  test('§2.1 names the verification lanes without a volatile test counter', () => {
    // Exact totals age on every contribution and say nothing about maturity.
    // The commands are stable; their runners are the current source of truth.
    const status = section('2.1');
    assert.match(status, /npm test/);
    assert.match(status, /cd app && swift test/);
    assert.match(status, /cd mvp && swift test/);
    assert.doesNotMatch(status, /\b\d{2,5}\s+(?:tests?|провер)/i,
      '§2.1 advertises a test total that will drift on the next contribution');
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
    // где ссылка вела на github.com/theasder/cruxwing.
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

  test('§13 знает, сколько проверок у этого файла', () => {
    // Раздел, который обещает бороться с устареванием, устарел первым: он
    // называл пять проверок, когда их было семнадцать. Причина ровно одна —
    // число никто не считал.
    //
    // Считается по объявлениям в этом же файле. Проверка про себя саму:
    // добавили проверку — обновите §13, иначе набор не пройдёт.
    const source = readFileSync(fileURLToPath(import.meta.url), 'utf8');
    const declared = (source.match(/^  test\('/gm) ?? []).length;
    assert.ok(declared >= 10, `объявлений нашлось ${declared} — считается не то`);

    const text = section('13').replace(/\n/g, ' ');
    const stated = /holds \*\*(\d+) checks\*\*/.exec(text);
    assert.ok(stated, '§13 больше не называет число проверок');
    assert.equal(Number(stated[1]), declared,
      `проверок в файле ${declared}, а §13 обещает ${stated[1]}`);
  });

  test('README ведёт к плану развития', () => {
    // План, о котором знает только автор, своей работы не выполняет: он
    // существует затем, чтобы пришедший со стороны видел, во что встроится
    // его правка.
    assert.match(read('README.md'), /docs\/ROADMAP\.md/,
      'README не ссылается на план развития');
  });
});
