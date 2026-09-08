// Учётных данных нет ни в репозитории, ни в собранном приложении.
//
// `Secrets.swift` — отслеживаемая неизменяемая конфигурация безопасного клона.
// Локальная сборка пишет `.env` только в игнорируемый
// `LocalSecrets.generated.swift` и включает его отдельным compile flag. Так
// обычная сборка не превращает живой ключ в готовую к коммиту правку.
//
// Повод не выдуманный. В унаследованном файле лежали два живых секрета клиента
// Google проекта Cruxwing — и они уехали в опубликованные DMG: `LC_ALL=C grep -a`
// находил обе строки прямо в бинарнике по адресу загрузки. orakul при этом
// аккаунтов не имеет вовсе, README обещает «аккаунт не нужен», а общий с
// Cruxwing идентификатор — ровно то, что запрещают проверки в identity.test.mjs
// про bundle id и Связку ключей.

import { test, describe } from 'node:test';
import assert from 'node:assert';
import {
  readFileSync, existsSync, readdirSync, writeFileSync, rmSync, mkdtempSync,
  mkdirSync, chmodSync,
} from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join } from 'node:path';
import { resolve, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, '..');
const secretsPath = resolve(repo, 'app', 'Sources', 'MeetGPT', 'Secrets.swift');
const localSecretsPath = resolve(
  repo, 'app', 'Sources', 'MeetGPT', 'LocalSecrets.generated.swift');

/// Формы, по которым учётные данные узнаются независимо от имени поля.
/// Именно формы, а не список известных строк: список защищает только от
/// того, что уже утекло.
const CREDENTIAL_SHAPES = [
  [/GOCSPX-[A-Za-z0-9_-]{10,}/, 'секрет клиента Google (GOCSPX-…)'],
  [/\d{11,}-[a-z0-9]{20,}\.apps\.googleusercontent\.com/, 'идентификатор клиента Google'],
  [/sk-[A-Za-z0-9]{20,}/, 'ключ OpenAI (sk-…)'],
  [/sk-ant-[A-Za-z0-9-]{20,}/, 'ключ Anthropic'],
  [/ghp_[A-Za-z0-9]{30,}/, 'токен GitHub'],
  [/AKIA[0-9A-Z]{16}/, 'ключ AWS'],
  [/xox[baprs]-[A-Za-z0-9-]{10,}/, 'токен Slack'],
  [/-----BEGIN [A-Z ]*PRIVATE KEY-----/, 'закрытый ключ'],
];

function builtBinary() {
  return resolve(repo, 'app', 'build', 'orakul.app', 'Contents', 'MacOS', 'MeetGPT');
}

function skipUnbuilt() {
  return existsSync(builtBinary())
    ? false
    : 'приложение ещё не собрано — проверка бинарника запускается после build.sh';
}

function fakeAppBundle({ resource = 'clean', executable = 'clean' } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'orakul-artifact-scan-'));
  const app = join(root, 'orakul.app');
  const macOS = join(app, 'Contents', 'MacOS');
  const resources = join(app, 'Contents', 'Resources');
  mkdirSync(macOS, { recursive: true });
  mkdirSync(resources, { recursive: true });
  const binary = join(macOS, 'MeetGPT');
  writeFileSync(binary, `${executable}\n`);
  chmodSync(binary, 0o755);
  writeFileSync(join(resources, 'settings.json'), `${resource}\n`);
  return { root, app };
}

function exitStatus(command, args, options = {}) {
  try {
    execFileSync(command, args, { stdio: 'pipe', ...options });
    return 0;
  } catch (error) {
    return error.status ?? 1;
  }
}

describe('учётные данные', () => {
  test('в истории коммитов нет ни одного настоящего секрета', () => {
    // Репозиторий уйдёт в открытый доступ вместе с историей. Секрет, удалённый
    // следующим коммитом, остаётся в ней навсегда и находится за минуту.
    //
    // Ищутся ЗНАЧЕНИЯ, а не формы: сами шаблоны (`GOCSPX-`, `sk-`) лежат в
    // проверках и в тексте страницы, и поиск по форме нашёл бы их же.
    const shallow = execFileSync('git', ['rev-parse', '--is-shallow-repository'],
                                 { cwd: repo, encoding: 'utf8' }).trim();
    assert.equal(shallow, 'false',
      'клон неполный — проверка истории прошла бы, не увидев её; '
      + 'в CI нужен fetch-depth: 0');

    const commits = execFileSync('git', ['rev-list', '--count', '--all'],
                                 { cwd: repo, encoding: 'utf8' }).trim();
    assert.ok(Number(commits) > 5, `в истории ${commits} коммит(ов) — проверять нечего`);

    const history = execFileSync('git', ['log', '--all', '-p'],
                                 { cwd: repo, encoding: 'utf8', maxBuffer: 512 * 1024 * 1024 });
    const values = history.match(
      /GOCSPX-[A-Za-z0-9_-]{15,}|sk-[A-Za-z0-9]{32,}|ghp_[A-Za-z0-9]{36}|AIza[0-9A-Za-z_-]{35}/g);
    assert.equal(values, null,
      'в истории найдены строки, похожие на настоящие ключи; '
      + 'не печатайте их в CI — отзовите ключи и перепишите историю до публикации');
  });

  test('никакой секрет не пишется в файл настроек', () => {
    // SECURITY.md: «Ключи лежат в Связке ключей macOS, а не в файле
    // настроек». UserDefaults — это как раз файл настроек: обычный plist в
    // ~/Library/Preferences, читаемый любым процессом пользователя.
    //
    // Проверяется только ЗАПИСЬ. Чтение и удаление разрешены: `google.tokens`
    // когда-то лежал там, и код нарочно забирает его оттуда и стирает —
    // запретить это значило бы законсервировать старый ключ на диске.
    const swift = [];
    const walk = (dir) => {
      for (const entry of readdirSync(dir, { withFileTypes: true })) {
        const full = resolve(dir, entry.name);
        if (entry.isDirectory()) {
          if (!/(^|\/)(\.build|build|node_modules)$/.test(full)) walk(full);
        } else if (entry.name.endsWith('.swift')) swift.push(full);
      }
    };
    walk(resolve(repo, 'app', 'Sources'));
    walk(resolve(repo, 'mvp', 'Sources'));
    assert.ok(swift.length > 50, `обход нашёл ${swift.length} файлов — проверка была бы фиктивной`);

    // «keywords» содержит «key», но секретом не является — отсюда границы слова.
    const secretish = /(token|secret|password|apikey|api_key|credential|session)/i;
    const offenders = [];
    for (const file of swift) {
      const text = readFileSync(file, 'utf8');
      for (const [, key] of text.matchAll(/UserDefaults\.standard\.set\([^)]*forKey:\s*"([^"]+)"/g)) {
        if (secretish.test(key.replace(/keywords?/gi, ''))) {
          offenders.push(`${file.slice(repo.length + 1)}: ${key}`);
        }
      }
    }
    assert.deepEqual(offenders, [],
      `секрет уходит в файл настроек вместо Связки ключей:\n${offenders.join('\n')}`);
  });

  test('Secrets.swift под контролем версий — иначе клон не собирается', () => {
    const tracked = execFileSync('git', ['ls-files', 'app/Sources/MeetGPT/Secrets.swift'],
                                 { cwd: repo, encoding: 'utf8' }).trim();
    assert.equal(tracked, 'app/Sources/MeetGPT/Secrets.swift',
      'Secrets.swift снова не отслеживается — `cd app && swift test` у клонирующего упадёт');
  });

  test('локальная сборка пишет только в точечно игнорируемый файл', () => {
    const build = readFileSync(resolve(repo, 'app', 'build.sh'), 'utf8');
    assert.match(build, /SECRETS="\$ROOT\/Sources\/MeetGPT\/LocalSecrets\.generated\.swift"/,
      'build.sh снова перезаписывает отслеживаемую конфигурацию');
    assert.match(build, /-DORAKUL_LOCAL_CONFIG/,
      'локальная конфигурация не включается явным compile flag');

    const tracked = execFileSync('git', ['ls-files', '--error-unmatch',
      'app/Sources/MeetGPT/Secrets.swift'], { cwd: repo, encoding: 'utf8' }).trim();
    assert.equal(tracked, 'app/Sources/MeetGPT/Secrets.swift');

    const generatedTracked = execFileSync('git', ['ls-files',
      'app/Sources/MeetGPT/LocalSecrets.generated.swift'],
    { cwd: repo, encoding: 'utf8' }).trim();
    assert.equal(generatedTracked, '',
      'локальный файл с ключами оказался под контролем версий');

    // `git check-ignore` проверяет реальное правило, даже если build.sh ещё не
    // создавал файл в этом checkout.
    const ignored = execFileSync('git', ['check-ignore',
      'app/Sources/MeetGPT/LocalSecrets.generated.swift'],
    { cwd: repo, encoding: 'utf8' }).trim();
    assert.equal(ignored, 'app/Sources/MeetGPT/LocalSecrets.generated.swift');
    assert.ok(!existsSync(localSecretsPath)
      || !execFileSync('git', ['status', '--short', '--untracked-files=all', '--',
        'app/Sources/MeetGPT/LocalSecrets.generated.swift'],
      { cwd: repo, encoding: 'utf8' }).trim(),
    'сгенерированный файл виден Git');
  });

  test('в Secrets.swift нет ничего похожего на учётные данные', () => {
    const source = readFileSync(secretsPath, 'utf8');
    for (const [shape, what] of CREDENTIAL_SHAPES) {
      const hit = shape.exec(source);
      assert.equal(hit, null,
        `в Secrets.swift лежит ${what}: ${hit?.[0]?.slice(0, 12)}…`);
    }
  });

  test('dist-сборка стирает учётные данные по форме имени, а не по списку', () => {
    // Список SECRET_VARS пишется руками, и четыре имени мимо него уже прошли:
    // GMAIL_CLIENT_ID, GMAIL_CLIENT_SECRET и оба GOOGLE_ANALYTICS_*. Поймать их
    // могло только чтение собранного бинарника — а та проверка пропускается,
    // когда приложение не собрано, то есть у всех, кроме сборщика выпуска.
    //
    // Проверяется поведение, а не текст: из build.sh берётся сама функция `sw`
    // и запускается с DIST=1 на подставном .env, где у каждого имени лежит
    // маячок. Текстовый поиск «есть ли строка с фильтром» прошёл бы и на
    // фильтре, поставленном ПОСЛЕ возврата значения.
    const build = readFileSync(resolve(repo, 'app', 'build.sh'), 'utf8');
    const secretVars = /SECRET_VARS="([^"]+)"/.exec(build)?.[1];
    assert.ok(secretVars, 'в build.sh больше нет SECRET_VARS');

    const lines = build.split('\n');
    const start = lines.findIndex((line) => /^sw\(\)/.test(line));
    assert.ok(start >= 0, 'функция sw больше не объявлена в build.sh');
    const end = lines.findIndex((line, i) => i > start && line === '}');
    assert.ok(end > start, 'у функции sw не нашлось закрывающей скобки');
    const swSource = lines.slice(start, end + 1).join('\n');

    // Имена берутся из самого build.sh: новое учётное имя попадёт под проверку
    // без правки теста. Форма та же, что у фильтра внутри sw.
    const credentials = [...new Set([...build.matchAll(/\$\(sw ([A-Z0-9_]+)\)/g)]
      .map((m) => m[1]))].filter((n) => /_(CLIENT_ID|CLIENT_SECRET|TOKEN|API_KEY)$/.test(n));
    assert.ok(credentials.length >= 5,
      `учётных имён нашлось ${credentials.length} — проверка была бы пустой`);

    const SENTINEL = 'SENTINEL-must-not-ship';
    const envFile = resolve(tmpdir(), 'orakul-sw-probe.env');
    writeFileSync(envFile, `${credentials.map((n) => `${n}=${SENTINEL}`).join('\n')}\n`);
    try {
      const script = [
        'set -u',
        'DIST=1',
        `SECRET_VARS=${JSON.stringify(secretVars)}`,
        `ENV_FILE=${JSON.stringify(envFile)}`,
        swSource,
        // Значение печатается в скобках: пустой вывод и «строка не напечаталась
        // вовсе» иначе выглядели бы одинаково.
        `for n in ${credentials.join(' ')}; do printf '%s=[%s]\\n' "$n" "$(sw "$n")"; done`,
      ].join('\n');
      const out = execFileSync('bash', ['-c', script], { cwd: repo, encoding: 'utf8' });

      const leaked = out.split('\n').filter((line) => line.includes(SENTINEL));
      assert.deepEqual(leaked, [],
        `dist-сборка вписала бы учётные данные в бинарник:\n  ${leaked.join('\n  ')}`);
      // Обратная сторона: строк должно быть по одной на имя, иначе «ничего не
      // утекло» может значить «ничего и не запускалось».
      assert.equal(out.trim().split('\n').length, credentials.length,
        `sw ответил не на все имена: ${out.trim()}`);
    } finally {
      rmSync(envFile, { force: true });
    }
  });

  test('Google Desktop OAuth берётся только из локального .env и стирается из dist', () => {
    // Локальная/tester-сборка должна уметь реально подключиться, но публичный
    // dist не может случайно унаследовать частный OAuth-проект. `sw` — единая
    // граница: при MEETGPT_DIST=1 он возвращает пустую строку для каждого имени
    // из SECRET_VARS независимо от содержимого .env.
    const build = readFileSync(resolve(repo, 'app', 'build.sh'), 'utf8');
    const fields = new Map([
      ['googleClientID', 'GOOGLE_CLIENT_ID'],
      ['googleClientSecret', 'GOOGLE_CLIENT_SECRET'],
      ['googleSignInClientID', 'GOOGLE_SIGNIN_CLIENT_ID'],
      ['googleSignInClientSecret', 'GOOGLE_SIGNIN_CLIENT_SECRET'],
    ]);
    const secretVars = /SECRET_VARS="([^"]+)"/.exec(build)?.[1]?.split(/\s+/) ?? [];
    assert.match(build,
      /sw\(\)[^{]*\{[\s\S]*?if \[ "\$DIST" = "1" \]; then/,
      'sw больше не проверяет MEETGPT_DIST=1');
    // Раньше здесь стояла точная строка из build.sh — то есть проверялся
    // СПОСОБ, а не свойство. Способ сменился (список запретов стал списком
    // разрешений), свойство осталось тем же, и проверка упала на усилении
    // защиты. Теперь спрашивается то, что важно: имена ниже в dist пусты.
    assert.match(build, /\*\) printf ''; return ;;/,
      'в sw больше нет запрета по умолчанию: значение, о котором не сказано явно, уедет в сборку');
    for (const [field, variable] of fields) {
      assert.ok(secretVars.includes(variable),
        `${variable} не входит в SECRET_VARS и попадёт в публичную сборку`);
      const line = new RegExp(
        `static let ${field}\\s*=\\s*"\\$\\(sw ${variable}\\)"`).exec(build);
      assert.ok(line,
        `build.sh должен брать ${field} только через dist-scrubbed sw ${variable}`);
    }
  });

  test('пустой идентификатор клиента убирает кнопку входа', () => {
    // Иначе «убрали ключи» означало бы «кнопка есть и не работает».
    const social = readFileSync(
      resolve(repo, 'app', 'Sources', 'MeetGPT', 'Integrations', 'SocialSignIn.swift'), 'utf8');
    assert.match(social, /static func showsGoogle\(hasClient: Bool[^)]*\)\s*->\s*Bool\s*\{\s*\n?\s*hasClient/,
      'показ кнопки Google больше не зависит от наличия клиента');
  });

  test('в собранном приложении учётных данных нет', { skip: skipUnbuilt() }, () => {
    // Единственная проверка, которая смотрит на то, что реально уехало
    // пользователю. Остальные читают исходники — а утекло именно из сборки.
    //
    // Байтовый поиск: строки в бинарнике не разделены. Ограничение метода
    // известно и здесь не мешает — строки короче 16 байт Swift хранит внутри
    // структуры, отдельным литералом их не найти, но все формы выше длиннее.
    const text = readFileSync(builtBinary()).toString('latin1');
    for (const [shape, what] of CREDENTIAL_SHAPES) {
      const hit = shape.exec(text);
      assert.equal(hit, null,
        `в собранном приложении лежит ${what}: ${hit?.[0]?.slice(0, 12)}…`);
    }
  });


  test('в dist-сборку не уезжает то, о чём не сказано явно', () => {
    // Дыра, записанная в §11 роадмапа: секрет с именем без узнаваемой формы
    // держался на списке, написанном руками. SLACK_CHANNEL_IDS и
    // CONFLUENCE_SITE — как раз такие: ни *_TOKEN, ни *_API_KEY.
    //
    // Проверяется свойство, а не список: выдуманное имя, которого нет ни в
    // одном списке, обязано быть стёрто просто потому, что о нём не сказано.
    const build = readFileSync(resolve(repo, 'app', 'build.sh'), 'utf8');
    const lines = build.split('\n');
    const start = lines.findIndex((line) => /^sw\(\)/.test(line));
    const end = lines.findIndex((line, i) => i > start && line === '}');
    const swSource = lines.slice(start, end + 1).join('\n');
    const secretVars = /SECRET_VARS="([^"]+)"/.exec(build)?.[1] ?? '';

    const SENTINEL = 'SENTINEL-must-not-ship';
    // Первое — имя без всякой формы, второе — публичная настройка, которая
    // обязана дойти: проверка без неё разрешала бы стереть вообще всё.
    const unnamed = ['PARTNER_HANDSHAKE', 'CONFLUENCE_SITE', 'SLACK_CHANNEL_IDS'];
    const envFile = resolve(tmpdir(), 'orakul-sw-default-deny.env');
    writeFileSync(envFile,
      `${unnamed.map((n) => `${n}=${SENTINEL}`).join('\n')}\nDEFAULT_TIER=team\n`);
    try {
      const script = [
        'set -u', 'DIST=1',
        `SECRET_VARS=${JSON.stringify(secretVars)}`,
        `ENV_FILE=${JSON.stringify(envFile)}`,
        swSource,
        `for n in ${unnamed.join(' ')} DEFAULT_TIER; do printf '%s=[%s]\\n' "$n" "$(sw "$n")"; done`,
      ].join('\n');
      const out = execFileSync('bash', ['-c', script], { cwd: repo, encoding: 'utf8' });

      const leaked = out.split('\n').filter((line) => line.includes(SENTINEL));
      assert.deepEqual(leaked, [],
        `в сборку уехало значение, о котором никто не говорил:\n  ${leaked.join('\n  ')}`);
      // И обратная сторона: запрет по умолчанию не должен стирать настройки,
      // без которых приложение перестанет работать. Иначе «ничего не утекло»
      // достигается тем, что не уехало ничего.
      assert.match(out, /DEFAULT_TIER=\[team\]/,
        `публичная настройка стёрта вместе с секретами: ${out.trim()}`);
    } finally {
      rmSync(envFile, { force: true });
    }
  });


  test('в собранном файле не остаётся значений из .env — проверено дословно', () => {
    // Остаток, записанный в §11: `sw` закрывает генерацию Secrets.swift, но
    // значение, попавшее в сборку другим путём (новый файл, ресурс, plist),
    // минует ту проверку целиком. Здесь путей нет: сравнивается отгружаемое с
    // тем, что лежит в .env.
    const script = resolve(repo, 'app', 'assert-no-env-values.sh');
    const dir = mkdtempSync(join(tmpdir(), 'orakul-env-scan-'));
    const env = join(dir, 'probe.env');
    // Assemble the fixture at runtime so the repository's own history scanner
    // never has to exempt a credential-shaped literal in its test source.
    const plantedSecret = 'sk-' + 'live-' + 'ASCIISECRET1234567';
    // Секрет ASCII, как настоящий, и второй — с кириллицей: `strings` его не
    // видит, и первая версия проверки докладывала «чисто» о заражённой сборке.
    writeFileSync(env, [
      `OPENAI_API_KEY=${plantedSecret}`,
      'CONFLUENCE_SITE=компания.atlassian.net',
      'DEFAULT_TIER=team',
      'TRANSCRIPTION_ENGINE=local',
    ].join('\n') + '\n');

    const run = (contents) => {
      const binary = join(dir, `bin-${Math.random().toString(36).slice(2)}`);
      writeFileSync(binary, contents);
      try {
        execFileSync('bash', [script, binary, env], { stdio: 'pipe' });
        return 0;
      } catch (error) {
        return error.status;
      }
    };

    // Публичные настройки в сборке — норма: они и должны там быть.
    assert.equal(run('код\nteam\nlocal\n'), 0, 'проверка ругается на исправную сборку');
    assert.equal(run(`код\n${plantedSecret}\n`), 1, 'ASCII-секрет не найден');
    assert.equal(run('код\nкомпания.atlassian.net\n'), 1, 'значение с кириллицей не найдено');

    // И главное свойство отчёта: имя переменной — да, значение — никогда.
    const binary = join(dir, 'leaky');
    writeFileSync(binary, `код\n${plantedSecret}\n`);
    let output = '';
    try {
      execFileSync('bash', [script, binary, env], { stdio: 'pipe' });
    } catch (error) {
      output = `${error.stdout ?? ''}${error.stderr ?? ''}`;
    }
    assert.match(output, /OPENAI_API_KEY/, 'отчёт не называет переменную — чинить нечего');
    assert.ok(!output.includes(plantedSecret),
      'проверка напечатала сам секрет в журнал сборки — то есть открыла ту дыру, которую ищет');

    rmSync(dir, { recursive: true, force: true });
  });

  test('дословная проверка читает Resources, а не только исполняемый файл', () => {
    // Deepgram keys have no prefix and look like an ordinary 40-character
    // digest. A shape scan cannot distinguish one; only the exact value from
    // the env that fed the build can.
    const deepgram = 'abcdef0123456789abcdef0123456789abcdef01';
    const fixture = fakeAppBundle({ resource: `{"key":"${deepgram}"}` });
    const env = join(fixture.root, 'build.env');
    writeFileSync(env, `DEEPGRAM_API_KEY=${deepgram}\n`);
    try {
      assert.notEqual(exitStatus('bash', [
        resolve(repo, 'app', 'assert-no-env-values.sh'), fixture.app, env,
      ]), 0, 'секрет в Contents/Resources остался незамеченным');
    } finally {
      rmSync(fixture.root, { recursive: true, force: true });
    }
  });

  test('дословная проверка не разрешает BACKEND_URL ни в одной части bundle', () => {
    // build.sh keeps BACKEND_URL in its switch only so DIST can force it to an
    // empty string. That implementation detail must not exempt an address that
    // arrived through a resource, plist, or any other packaging path.
    const backend = 'https://backend-leak-fixture.invalid/v1';
    const envContents = `BACKEND_URL=${backend}\n`;
    const fixtures = [
      fakeAppBundle({ executable: `compiled:${backend}` }),
      fakeAppBundle({ resource: `{"backend":"${backend}"}` }),
    ];
    try {
      for (const [index, fixture] of fixtures.entries()) {
        const env = join(fixture.root, 'build.env');
        writeFileSync(env, envContents);
        assert.notEqual(exitStatus('bash', [
          resolve(repo, 'app', 'assert-no-env-values.sh'), fixture.app, env,
        ]), 0, `BACKEND_URL fixture ${index + 1} in the bundle was not rejected`);
      }
    } finally {
      for (const fixture of fixtures) {
        rmSync(fixture.root, { recursive: true, force: true });
      }
    }
  });

  test('проверка форм читает весь bundle, знает основные семейства и пропускает чистый bundle', () => {
    const script = resolve(repo, 'app', 'assert-no-baked-secrets.sh');
    // Values are assembled at runtime so the repository history contains only
    // detection patterns, never strings that look like live credentials.
    const credentialFixtures = [
      'sk-' + 'a'.repeat(32),
      'sk-' + 'ant-' + 'a'.repeat(28),
      'GOC' + 'SPX-' + 'a'.repeat(20),
      '12345678901-' + 'a'.repeat(24) + '.apps.googleusercontent.com',
      'AI' + 'za' + 'a'.repeat(35),
      'gh' + 'p_' + 'a'.repeat(36),
      'AK' + 'IA' + 'A'.repeat(16),
      'xo' + 'xb-' + 'a'.repeat(24),
      '-----BEGIN ' + 'PRIVATE KEY-----',
      'Bearer ' + 'a'.repeat(32),
    ];
    const leakyBundles = credentialFixtures.map((credential) =>
      fakeAppBundle({ resource: `{"key":"${credential}"}` }));
    const clean = fakeAppBundle();
    try {
      for (const [index, leaky] of leakyBundles.entries()) {
        assert.notEqual(exitStatus('bash', [script, leaky.app]), 0,
          `семейство учётных данных ${index + 1} в Contents/Resources осталось незамеченным`);
      }
      assert.equal(exitStatus('bash', [script, clean.app]), 0,
        'чистый bundle отклонён — такой сторож просто отключат');
    } finally {
      for (const leaky of leakyBundles) {
        rmSync(leaky.root, { recursive: true, force: true });
      }
      rmSync(clean.root, { recursive: true, force: true });
    }
  });


  test('каждый путь выпуска зовёт обе проверки собранного файла', () => {
    // Проверка существует не зря: обе проверки стояли на пути в App Store и на
    // Intel-сборке, а notarize.sh — тот самый путь, которым делается
    // скачиваемый образ, — не звал ни одной. Отказать было нечему, поэтому
    // нашлось это чтением, а не падением.
    for (const script of ['notarize.sh', 'appstore.sh', 'build-intel.sh']) {
      const source = readFileSync(resolve(repo, 'app', script), 'utf8')
        .split('\n').filter((line) => !line.trimStart().startsWith('#')).join('\n');
      for (const guard of ['assert-no-baked-secrets.sh', 'assert-no-env-values.sh']) {
        assert.ok(source.includes(guard),
          `${script} не зовёт ${guard}: артефакт этого пути уедет непроверенным`);
      }
    }
  });

  test('проверка значений стоит до подписи, а не после', () => {
    // Подписанная сборка с секретом — это подписанный секрет: подпись придаёт
    // ей вид проверенной ровно в тот момент, когда проверять уже поздно.
    const source = readFileSync(resolve(repo, 'app', 'notarize.sh'), 'utf8');
    const scan = source.indexOf('assert-no-env-values.sh');
    const sign = source.indexOf('codesign --force');
    assert.ok(scan > 0 && sign > 0, 'в notarize.sh пропала проверка или подпись');
    assert.ok(scan < sign, 'проверка значений стоит после подписи');
  });


  test('останов на адресе сервера может сработать — и срабатывает', () => {
    // §3 роадмапа обещает: «каждая строка ломает сборку или запуск, когда её
    // нарушают». Для строки про сервер это было неправдой. Проверка читала
    // `sw BACKEND_URL`, а тот же `sw` двадцатью строками выше стирает эту
    // переменную в dist-ветке — значит останов не мог сработать НИКОГДА, а
    // «сервер не задан — так и задумано» печаталось как доказательство.
    //
    // Здесь проверяется главное свойство сторожа: что он умеет падать.
    const build = readFileSync(resolve(repo, 'app', 'build.sh'), 'utf8');
    // Строка берётся целиком: внутри неё есть свои скобки, и «до первой
    // закрывающей» вырезает половину команды — первая версия этой проверки так
    // и сделала и упала на исправном стороже.
    const configLine = build.split('\n').find((text) => text.includes('DIST_CONFIG='));
    assert.match(configLine ?? '', /Sources\/MeetGPT\/Secrets\.swift/,
      'останов проверяет не тот Secrets.swift, который DIST действительно компилирует');
    assert.doesNotMatch(configLine ?? '', /LocalSecrets\.generated/,
      'останов снова проверяет локальный файл, выключенный в DIST-сборке');

    const countLine = build.split('\n').find((text) => text.includes('DIST_BACKEND_COUNT='));
    assert.ok(countLine, 'останов принимает отсутствие объявления backendBaseURL за пустое значение');
    assert.match(build, /DIST_BACKEND_COUNT" != "1"/,
      'отсутствующее или неоднозначное объявление backendBaseURL больше не останавливает сборку');

    const line = build.split('\n').find((text) => text.includes('DIST_BACKEND='));
    assert.ok(line, 'останов больше не читает Secrets.swift');
    assert.ok(!/sw BACKEND_URL/.test(line),
      'останов снова читает функцию вместо сгенерированного файла');

    const dir = mkdtempSync(join(tmpdir(), 'orakul-backend-'));
    const run = (contents) => {
      const secrets = join(dir, `Secrets-${Math.random().toString(36).slice(2)}.swift`);
      writeFileSync(secrets, contents);
      const script = [
        'set -u',
        `DIST_CONFIG=${JSON.stringify(secrets)}`,
        line.trim(),
        'if [ -n "$DIST_BACKEND" ]; then echo "останов"; exit 1; fi',
        'echo "проход"',
      ].join('\n');
      try {
        return { code: 0, out: execFileSync('bash', ['-c', script], { encoding: 'utf8' }) };
      } catch (error) {
        return { code: error.status, out: `${error.stdout ?? ''}` };
      }
    };

    const empty = 'struct Secrets {\n    static let backendBaseURL  = ""\n}\n';
    const filled = 'struct Secrets {\n    static let backendBaseURL  = "https://api.orakul.ai"\n}\n';
    assert.equal(run(empty).code, 0, 'останов сработал на пустом адресе — сборка встанет всегда');
    assert.equal(run(filled).code, 1, 'адрес сервера в Secrets.swift не остановил сборку');

    rmSync(dir, { recursive: true, force: true });
  });
});

test('сборка для распространения печёт devMode = 0', () => {
  // Один переключатель держит несколько дверей.
  //
  // `Config.isDevBuild` читает `Secrets.devMode`, и от него зависят 25 мест:
  // содержательная диагностика звонка, включаемая переменной окружения;
  // предпросмотр тарифов; и — резче всего — `usesDataProtectionKeychain`. То
  // есть свойство «токены остаются на этом компьютере», закреплённое отдельным
  // набором, молча стоит на этом же переключателе.
  //
  // В build.sh он верный. Держало его ничто: инверсия тернарного оператора
  // осталась бы незамеченной, а в собранном приложении появилась бы выгрузка
  // содержимого звонка по переменной окружения.
  const build = readFileSync(resolve(repo, 'app', 'build.sh'), 'utf8');
  const line = build.split('\n').find((l) => l.includes('static let devMode'));
  assert.ok(line, 'build.sh больше не печёт devMode — проверять нечего');
  assert.match(line, /DIST"?\s*=\s*"?1"?\s*\]\s*&&\s*printf\s*'0'/,
    `при DIST=1 обязан печься 0, а строка такая: ${line.trim()}`);
  assert.match(line, /\|\|\s*printf\s*'1'/,
    'вне DIST обязан печься 1, иначе разработчик лишится своих же инструментов');
});

test('DEV_MODE нельзя внести через .env в сборку для распространения', () => {
  // Список разрешённых имён в build.sh — это то, что вообще попадает в
  // Secrets.swift при DIST. DEV_MODE там быть не должно: иначе переключатель
  // включается снаружи, минуя строку выше.
  const build = readFileSync(resolve(repo, 'app', 'build.sh'), 'utf8');
  const allowlist = build.split('\n').find((l) => l.includes('BACKEND_CERT_PINS'));
  assert.ok(allowlist, 'список разрешённых имён не найден — разбор сломан');
  assert.ok(!/DEV_MODE/.test(allowlist),
    `DEV_MODE попал в список разрешённых: ${allowlist.trim()}`);
});
