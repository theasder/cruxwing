import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

// Run with: node --test
//
// The stated metric is stars and adoption. Before anyone reads a line of Swift
// they meet the repository furniture: the security policy, the CI badge, the
// issue form. Each is a promise, and the failure mode is always the same — the
// promise outlives the thing it describes. A CI file naming a directory that
// was renamed, a security policy pointing at a mailbox nobody owns, an issue
// form asking for a field the build stopped stamping.
//
// None of that breaks a build. It breaks the first impression of the one
// visitor who tried to help, which is the only currency this project has.
//
// The licence is deliberately not checked here — `contributing`, `readme` and
// `landing` already assert it, and a fourth copy would be a fourth thing to
// update.

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, '..');
const read = (...p) => readFileSync(resolve(repo, ...p), 'utf8');

// Keep braces in executable Swift and blank strings/comments. This is enough
// structure to isolate @Test function bodies without mistaking example code in
// documentation or a brace inside a multiline string for executable control
// flow.
function maskSwiftTrivia(source) {
  const output = [...source];
  let index = 0;
  let blockDepth = 0;
  let state = 'code';
  while (index < source.length) {
    const pair = source.slice(index, index + 2);
    const triple = source.slice(index, index + 3);
    if (state === 'code' && pair === '//') {
      state = 'line-comment'; output[index] = output[index + 1] = ' '; index += 2; continue;
    }
    if (state === 'code' && pair === '/*') {
      state = 'block-comment'; blockDepth = 1;
      output[index] = output[index + 1] = ' '; index += 2; continue;
    }
    if (state === 'code' && triple === '"""') {
      state = 'multiline-string'; output[index] = output[index + 1] = output[index + 2] = ' ';
      index += 3; continue;
    }
    if (state === 'code' && source[index] === '"') {
      state = 'string'; output[index] = ' '; index += 1; continue;
    }
    if (state === 'line-comment') {
      if (source[index] === '\n') state = 'code';
      else output[index] = ' ';
      index += 1; continue;
    }
    if (state === 'block-comment') {
      if (pair === '/*') {
        blockDepth += 1; output[index] = output[index + 1] = ' '; index += 2; continue;
      }
      if (pair === '*/') {
        blockDepth -= 1; output[index] = output[index + 1] = ' '; index += 2;
        if (blockDepth === 0) state = 'code';
        continue;
      }
      if (source[index] !== '\n') output[index] = ' ';
      index += 1; continue;
    }
    if (state === 'multiline-string') {
      if (triple === '"""') {
        output[index] = output[index + 1] = output[index + 2] = ' ';
        index += 3; state = 'code'; continue;
      }
      if (source[index] !== '\n') output[index] = ' ';
      index += 1; continue;
    }
    if (state === 'string') {
      if (source[index] === '\\') {
        output[index] = ' ';
        if (index + 1 < source.length && source[index + 1] !== '\n') output[index + 1] = ' ';
        index += 2; continue;
      }
      if (source[index] === '"') state = 'code';
      if (source[index] !== '\n') output[index] = ' ';
      index += 1; continue;
    }
    index += 1;
  }
  return output.join('');
}

function swiftTestCredibilityOffenders(source, file = 'fixture.swift') {
  const masked = maskSwiftTrivia(source);
  const offenders = [];
  const annotation = /@Test\b/g;
  for (let match = annotation.exec(masked); match; match = annotation.exec(masked)) {
    const functionIndex = masked.indexOf('func ', match.index);
    const nextTest = masked.indexOf('@Test', match.index + match[0].length);
    if (functionIndex < 0 || (nextTest >= 0 && nextTest < functionIndex)) continue;
    const open = masked.indexOf('{', functionIndex);
    if (open < 0) continue;
    let depth = 1;
    let close = open + 1;
    for (; close < masked.length && depth > 0; close += 1) {
      if (masked[close] === '{') depth += 1;
      else if (masked[close] === '}') depth -= 1;
    }
    const body = masked.slice(open + 1, close - 1);
    const bodyOffset = open + 1;
    const patterns = [
      ['silent return', /\bguard\b[\s\S]{0,1000}?\belse\s*\{\s*return\s*(?:skipNotice\s*\(\s*\)\s*)?\}/g],
      ['literal tautology', /#expect\s*\(\s*(?:Bool\s*\(\s*)?true\s*\)?\s*\)/g],
    ];
    for (const [kind, pattern] of patterns) {
      for (let problem = pattern.exec(body); problem; problem = pattern.exec(body)) {
        const absolute = bodyOffset + problem.index;
        const line = source.slice(0, absolute).split('\n').length;
        const snippet = source.slice(absolute, absolute + problem[0].length)
          .replace(/\s+/g, ' ').trim();
        offenders.push({ file, line, kind, snippet });
      }
    }
    annotation.lastIndex = close;
  }
  return offenders;
}

describe('open-source furniture', () => {
  describe('CI', () => {
    const ci = read('.github', 'workflows', 'ci.yml');

    test('runs on pull requests, not only on the maintainer push', () => {
      // CI that fires only on main tells the contributor nothing at the moment
      // it would still matter — before the merge.
      //
      // Anchored to the `on:` block, not to the word anywhere in the file.
      // A bare /pull_request:/ passed with the trigger COMMENTED OUT, because
      // `# pull_request:` still contains it — and the concurrency block below
      // mentions `github.event_name == 'pull_request'` besides.
      const triggers = ci.split('\n')
        .filter((line) => !line.trim().startsWith('#'))
        .join('\n')
        .match(/^on:\n((?:[ \t]+.*\n|\n)*)/m)?.[1];
      assert.ok(triggers, 'CI declares no `on:` block at all');
      assert.match(triggers, /^\s+pull_request:/m,
        'CI does not run on pull requests, so a contributor learns nothing');
    });

    test('is structurally valid YAML in the ways YAML usually breaks', () => {
      // No YAML parser is available here and adding a dependency to a
      // zero-dependency test suite to lint one file is a bad trade. These are
      // the two failures that actually happen, and both are cheap to see:
      // a tab in the indentation (YAML forbids it outright) and a missing
      // top-level key (GitHub then ignores the workflow silently).
      //
      // Neither can be caught locally any other way — the first real run of
      // this file happens on someone else's pull request.
      for (const [file, required] of [
        ['.github/workflows/ci.yml', ['name', 'on', 'jobs']],
        ['.github/ISSUE_TEMPLATE/oshibka.yml', ['name', 'description', 'body']],
        ['.github/ISSUE_TEMPLATE/konnektor.yml', ['name', 'description', 'body']],
      ]) {
        const text = readFileSync(resolve(repo, file), 'utf8');
        const tab = text.split('\n').findIndex((line) => /^\s*\t/.test(line));
        assert.equal(tab, -1, `${file} line ${tab + 1} indents with a tab; YAML forbids it`);
        for (const key of required) {
          assert.match(text, new RegExp(`^${key}:`, 'm'),
            `${file} has no top-level "${key}:" — GitHub ignores the file`);
        }
      }
    });

    test('every working directory it names exists', () => {
      // A renamed directory turns into a red X on a stranger's first pull
      // request, with an error about a missing path rather than their change.
      const dirs = [...ci.matchAll(/working-directory:\s*(\S+)/g)].map(([, d]) => d);
      assert.ok(dirs.length > 0, 'no working directories declared — check the parse');
      for (const dir of dirs) {
        assert.ok(existsSync(resolve(repo, dir)),
          `CI runs in "${dir}", which does not exist`);
      }
    });

    test('it runs the suites this repo actually has', () => {
      // Per package, not "swift test appears somewhere". There are two Swift
      // packages, so a single match let the app suite be swapped for `echo`
      // while the mvp one kept the assertion green — the app is the 2668 of
      // the 2788 tests, and it was the half that could go silently missing.
      for (const pkg of ['app', 'mvp']) {
        assert.match(ci, new RegExp(`working-directory:\\s*${pkg}\\s*\\n\\s*run:\\s*swift test`),
          `CI no longer runs the Swift tests in ${pkg}/`);
      }
      assert.match(ci, /run:\s*npm test/, 'CI no longer runs the node tests');

      // And `npm test` has to be a real script, or the step is decoration.
      const pkg = JSON.parse(read('package.json'));
      assert.ok(pkg.scripts?.test, 'package.json has no test script for CI to run');
    });

    test('the cached path is one SwiftPM actually builds into', () => {
      // A cache key pointing at the wrong directory is the worst kind of green:
      // every run is a cold build, and nobody notices because it still passes.
      const cached = ci.match(/path:\s*(\S*\.build)/)?.[1];
      assert.ok(cached, 'the SwiftPM cache step no longer names a .build path');
      const manifest = cached.replace(/\.build$/, 'Package.swift');
      assert.ok(existsSync(resolve(repo, manifest)),
        `CI caches "${cached}", but there is no Swift package at that level`);
    });

    test('the build output it caches is not something the repo commits', () => {
      // `.build` was committed once and left 114 MB of stale compiler cache in
      // the history. Caching it in CI is right; tracking it is not, and the
      // ignore rule is what keeps those two apart.
      // Checked per file, not on the two joined together. Joined, deleting the
      // ROOT rule still passed on the copy in `app/.gitignore` — and the root
      // one is the whole point: `build/orakul.app` at the top level is what
      // actually got committed, home path and all.
      assert.match(read('.gitignore'), /^build\/$/m,
        'root build/ is not ignored — the built app returns to the repository');
      assert.match(read('app', '.gitignore'), /^build\/$/m,
        'app/build/ is not ignored');
      assert.match(read('app', '.gitignore'), /^\.build\/$/m,
        'app/.build/ is not ignored — the 114 MB compiler cache comes back');
    });
  });

  test('the build script stops at a local artifact boundary', () => {
    // Public contributors can build and inspect an artifact, but packaging must
    // not mutate a private sibling checkout merely because it happens to exist
    // on the maintainer's machine. Publication is a separately authorized step.
    const dist = readFileSync(resolve(repo, 'app', 'dist-all.sh'), 'utf8');
    const code = dist.split('\n')
      .filter((line) => !line.trim().startsWith('#')).join('\n');
    assert.doesNotMatch(code, /cruxwing-marketing|\bPUBLISH=|cp .*\.dmg/,
      'dist-all.sh still writes outside this repository');
    assert.match(code, /ROOT="\$\(cd "\$\(dirname "\$0"\)" && pwd\)"/,
      'the audit paths are no longer anchored to dist-all.sh itself');
    const displayed = code.replaceAll('\\"', '"');
    assert.match(displayed,
      /bash "\$ROOT\/\.\.\/scripts\/audit-dmg\.sh" "\$ROOT\/dist\/orakul-AppleSilicon\.dmg" "\$ROOT\/dist\/orakul-Intel\.dmg"/,
      'the local build no longer prints the explicit ROOT-anchored artifact audit command');
  });

  test('the credibility detector catches multiline skips and literal passes', () => {
    const broken = `
      @Test("fixture")
      func fixture() {
        guard let path = environment["ORAKUL_FIXTURE"],
              !path.isEmpty else {
          return
        }
        #expect(Bool(true))
      }
    `;
    assert.deepEqual(swiftTestCredibilityOffenders(broken).map(({ kind }) => kind).sort(),
      ['literal tautology', 'silent return']);

    const credible = `
      @Test("fixture", .enabled(if: hasFixture, "Set ORAKUL_FIXTURE."))
      func fixture() throws {
        let path = try #require(environment["ORAKUL_FIXTURE"])
        #expect(!path.isEmpty)
      }
    `;
    assert.deepEqual(swiftTestCredibilityOffenders(credible), []);
  });

  test('opt-in Swift harnesses never report PASS while doing nothing', () => {
    // `guard enabled else { return }` в теле теста печатает «passed». Шесть
    // проверок производительности так и молчали — во всех прогонах и в CI, —
    // а «250 сессий укладываются в бюджет» не значило ничего.
    //
    // Пропуск обязан быть виден: трейт `.enabled(if:)` печатает «skipped».
    // Разница между «проверено» и «не запускалось» — это вся ценность отчёта.
    const roots = ['app/Tests/MeetGPTTests', 'mvp/Tests/OrakulCoreTests'];
    // These are the corpus/live-boundary harnesses where absence is expected
    // on a public contributor machine and therefore must be a visible skip.
    // Literal `true` assertions remain forbidden in every Swift test file.
    const optInHarnesses = new Set([
      'ReflectionEvalHarness.swift',
      'RealCallTranscriptionHarness.swift',
      'LocalSpeakerLabelsTests.swift',
      'ConnectedAppMuteTests.swift',
      'NoBackendPromisesTests.swift',
    ]);
    const offenders = [];
    for (const root of roots) {
      const dir = resolve(repo, root);
      if (!existsSync(dir)) continue;
      for (const file of readdirSync(dir).filter((f) => f.endsWith('.swift'))) {
        const source = readFileSync(resolve(dir, file), 'utf8');
        offenders.push(...swiftTestCredibilityOffenders(source, file).filter((item) =>
          item.kind === 'literal tautology' || optInHarnesses.has(file)));
      }
    }
    assert.deepEqual(offenders, [],
      `these tests report PASS without checking anything:\n${offenders
        .map((item) => `${item.file}:${item.line}: ${item.kind}: ${item.snippet}`)
        .join('\n')}`);
  });

  test('the Russian dictionary exists once, not once per package', () => {
    // Копий было две — в приложении и в ядре, — и каждая правка вносилась в
    // обе руками: кросс-алфавитный поиск, падежи терминов, кэш таблиц. Три
    // раза подряд это сработало только потому, что я помнил. Следующий не
    // вспомнит, и словарь тихо разъедется: приложение станет искать иначе,
    // чем командная строка, на том же архиве.
    const copies = [];
    for (const root of ['app/Sources', 'mvp/Sources']) {
      const dir = resolve(repo, root);
      if (!existsSync(dir)) continue;
      const walk = (d) => {
        for (const entry of readdirSync(d, { withFileTypes: true })) {
          const full = resolve(d, entry.name);
          if (entry.isDirectory()) walk(full);
          else if (entry.name === 'RussianLexicon.swift') copies.push(full.slice(repo.length + 1));
        }
      };
      walk(dir);
    }
    assert.deepEqual(copies, ['mvp/Sources/OrakulCore/RussianLexicon.swift'],
      `the Russian dictionary is duplicated again:\n${copies.join('\n')}`);
  });

  test('the canonical lookup is written once, not once per search path', () => {
    // Разбор слов у приложения и командной строки разный — разные стоп-слова,
    // разная обрезка, — но шаг «термин → его канон → его падеж» был одинаковый
    // и написан дважды. Кросс-алфавитный поиск и падежи чинились в обеих
    // копиях руками; на третий раз это перестало быть случайностью.
    const paths = [
      ['CLI', 'mvp/Sources/OrakulCore/RecallIndex.swift'],
      ['app', 'app/Sources/MeetGPT/AI/DecisionRecallService.swift'],
    ];
    for (const [name, file] of paths) {
      const code = readFileSync(resolve(repo, file), 'utf8')
        .split('\n').filter((l) => !l.trim().startsWith('//')).join('\n');
      // Приложение зовёт общий разбор через `RecallIndex.searchToken`, а он
      // уже идёт в словарь. Прямой вызов `canonicalToken` из приложения был
      // как раз половиной разбора: словарь без обрезки окончаний.
      assert.match(code, /RussianLexicon\.canonicalToken\(for:|RecallIndex\.searchToken\(for:/,
        `${name} no longer uses the shared canonical lookup`);
      assert.doesNotMatch(code, /canonicalForms\(\)\[|inflections\(\)\[/,
        `${name} reimplemented the canonical lookup inline again`);
    }
  });

  test('the app links the portable core instead of copying it', () => {
    const manifest = readFileSync(resolve(repo, 'app', 'Package.swift'), 'utf8');
    assert.match(manifest, /\.package\(path: "\.\.\/mvp"\)/,
      'the app no longer depends on OrakulCore — the copy is on its way back');
    assert.match(manifest, /product\(name: "OrakulCore", package: "mvp"\)/,
      'OrakulCore is declared as a dependency but never linked');
  });

  describe('публикация страницы', () => {
    const flow = resolve(here, '..', '.github', 'workflows', 'pages.yml');

    test('страница выкладывается сама, а не один раз руками', () => {
      assert.ok(existsSync(flow), 'нет рабочего процесса публикации');
      const text = readFileSync(flow, 'utf8');
      assert.match(text, /paths: \['public\/\*\*'/,
        'публикация не привязана к правкам страницы — она устареет молча');
      assert.match(text, /actions\/upload-pages-artifact@[0-9a-f]{40}[\s\S]*?path:\s*public/,
        'Pages artifact собирается не из public/');
      assert.match(text, /actions\/deploy-pages@[0-9a-f]{40}/,
        'artifact страницы не передаётся штатному Pages deployment');
      assert.doesNotMatch(text, /git push|contents:\s*write/,
        'публикация страницы всё ещё переписывает Git-ветку');
    });

    test('после выкладки проверяется, что отдаётся именно она', () => {
      const text = readFileSync(flow, 'utf8');
      assert.match(text, /curl[\s\S]{0,120}\$DEPLOYED_PAGE_URL/,
        'никто не смотрит, что страница действительно обновилась');
      assert.match(text, /exit 1/,
        'шаг не умеет падать — «выложено» ничего не значит');
    });

    test('адрес на странице — тот же, куда её выкладывают', () => {
      const page = readFileSync(resolve(here, '..', 'public', 'index.html'), 'utf8');
      const canonical = /<link rel="canonical" href="([^"]+)"/.exec(page);
      assert.ok(canonical, 'на странице нет канонического адреса');
      const text = readFileSync(flow, 'utf8');
      const host = new URL(canonical[1]).host;
      assert.ok(text.includes(host),
        `страница называет себя ${host}, а выкладывается не туда`);
      const og = /<meta property="og:url" content="([^"]+)"/.exec(page);
      assert.equal(og?.[1], canonical[1], 'og:url и canonical разошлись');
    });
  });

  describe('правила поведения', () => {
    const coc = resolve(here, '..', 'CODE_OF_CONDUCT.md');

    test('файл есть — иначе GitHub считает проект не готовым к людям', () => {
      assert.ok(existsSync(coc), 'CODE_OF_CONDUCT.md нет');
    });

    // Смысл файла — не в списке недопустимого (его даёт Contributor Covenant),
    // а в двух обязательствах мейнтейнера. Без них останется шаблон, который
    // защищает площадку от человека, — ровно то, из-за чего уходят с форумов.
    test('promises to explain decisions and allows them to be appealed', () => {
      const text = readFileSync(coc, 'utf8');
      assert.match(text, /explained|explain/i,
        'the obligation to explain every closure is gone');
      assert.match(text, /appeal|review/i,
        'the right to demand a review is gone');
      assert.match(text, /duplicate/i,
        'closing as a duplicate is the commonest case; it has to be named');
      assert.match(text, /[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}/i,
        'nowhere to write — rules without an address do not work');
    });

    test('README leads to it rather than leaving it for GitHub alone', () => {
      const readme = readFileSync(resolve(here, '..', 'README.md'), 'utf8');
      assert.match(readme, /\(CODE_OF_CONDUCT\.md\)/,
        'README does not link to the code of conduct');
    });
  });

  describe('security policy', () => {
    const security = read('SECURITY.md');

    test('names a reporting channel that exists', () => {
      // The tempting line is "email security@orakul.ai". That domain does not
      // resolve, so it would be a channel that silently drops vulnerability
      // reports — strictly worse than offering none at all.
      assert.doesNotMatch(security, /[\w.-]+@orakul\.ai/,
        'the policy prints an address at a domain that does not resolve');
      assert.match(security, /Report a vulnerability/,
        'no working private-reporting channel is named');
    });

    test('the self-check commands it prints are real', () => {
      const script = security.match(/bash (scripts\/[\w.-]+\.sh)/)?.[1];
      assert.ok(script, 'the policy no longer offers a way to verify the build');
      assert.ok(existsSync(resolve(repo, script)),
        `the policy prints "${script}", which does not exist`);

      const filter = security.match(/--filter\s+(\w+)/)?.[1];
      assert.ok(filter, 'the policy no longer offers a live connector check');
      const suites = readdirSync(resolve(repo, 'app', 'Tests', 'MeetGPTTests'));
      assert.ok(suites.some((f) => f.startsWith(filter)),
        `the policy names --filter ${filter}, but no such suite exists`);
    });

    test('its "no server" claim matches what the build enforces', () => {
      // The policy says the build HALTS on a baked backend address. That is a
      // checkable claim about build.sh and the strongest sentence in the file.
      // Comments are stripped first: they quote the removed address on purpose,
      // so a plain substring search would pass on the wrong evidence.
      assert.match(security, /build\.sh/);
      const code = read('app', 'build.sh').split('\n')
        .filter((line) => !line.trim().startsWith('#')).join('\n');
      assert.match(code, /exit 1/, 'the policy promises the build halts; nothing halts it');
      assert.doesNotMatch(code, /api\.cruxwing\.ai/,
        'a foreign backend is back in build.sh, and the policy says it cannot be');
    });
  });

  describe('linux package', () => {
    // Пакет — это то, что человек ставит. Здесь проверяется не он сам (для
    // сборки нужен dpkg-deb, которого на macOS нет), а то, что ломается молча:
    // версия, разъехавшаяся с приложением, и потерянная лицензия.
    const script = read('scripts', 'package-linux.sh');
    // Без комментариев: закомментированная строка `# cp LICENSE` содержит
    // «cp LICENSE» и проходила проверку на подстроку. Мутация это показала —
    // сторож смотрел на текст, а не на то, что выполняется.
    const code = script.split('\n').filter((line) => !line.trim().startsWith('#')).join('\n');

    test('версия берётся из того же места, что и у сборки под macOS', () => {
      // Прописанная в скрипте версия расходится с приложением на второй же
      // правке, и на вопрос «какая у вас версия» появляются два разных
      // правильных ответа. Поэтому она читается из Info.plist, как и там.
      // По коду, а не по всему файлу: имя ключа стоит и в комментарии выше,
      // поэтому проверка на подстройку проходила даже когда скрипт читал из
      // Info.plist совсем другой ключ. Третий раз за вечер один и тот же
      // промах — сторож, смотрящий на текст вместо исполняемого.
      assert.match(code, /grep[^\n]*CFBundleShortVersionString/,
        'скрипт больше не читает версию из Info.plist');
      assert.match(code, /rev-list --count HEAD/,
        'номер сборки больше не берётся из высоты истории, как в app/build.sh');

      const plist = read('app', 'Support', 'Info.plist');
      const version = /CFBundleShortVersionString<\/key>\s*<string>([^<]+)</.exec(plist)?.[1];
      assert.ok(version, 'в Info.plist пропала CFBundleShortVersionString');
      assert.doesNotMatch(script, new RegExp(`Version:\\s*${version.replace(/\./g, '\\.')}`),
        'версия вписана в скрипт прямо — она разойдётся с приложением');
    });

    test('пакет несёт лицензию и обязательные поля', () => {
      // Политика Debian требует copyright в /usr/share/doc; без него пакет
      // раздаёт код Apache 2.0 без текста лицензии.
      assert.match(code, /usr\/share\/doc\/orakul/,
        'пакет больше не кладёт документацию туда, где её ищут');
      assert.match(code, /cp LICENSE/, 'лицензия не едет с пакетом');
      for (const field of ['Package:', 'Version:', 'Architecture:', 'Maintainer:', 'Description:']) {
        assert.ok(code.includes(field), `в control нет поля ${field}`);
      }
    });

    test('описание не обещает записи с микрофона', () => {
      // На Linux её нет, и пакет обязан говорить это прямо: человек, который
      // поставил пакет ради записи звонка, узнает об этом позже и хуже.
      // Срез от Description до КОНЦА heredoc, а не до первого «CONTROL»:
      // открывающий `<<CONTROL` стоит выше описания, и поиск с начала файла
      // давал пустую строку — проверка «не нашла упоминания» на пустоте.
      const start = script.indexOf('Description:');
      const description = script.slice(start, script.indexOf('\nCONTROL', start));
      // Оба утверждения, а не любое из них: «в пакете только командная строка»
      // и «записи с микрофона здесь нет» отвечают на разные вопросы, и раньше
      // одно подменяло другое — мутация убрала половину, а проверка прошла.
      assert.match(description, /только командная строка/,
        'описание не говорит, что в пакете лишь командная строка');
      assert.match(description, /Записи с микрофона здесь нет/,
        'описание умалчивает, что записи с микрофона в пакете нет');
      assert.match(description, /только на macOS/,
        'описание не говорит, где запись всё-таки работает');
    });

    test('пакет работает там, где Swift никогда не стоял', () => {
      // Первый .deb ставился и не запускался: «error while loading shared
      // libraries: libswiftCore.so». Проверка этого не увидела, потому что шла
      // внутри swift:6.0 — образа, где рантайм есть по определению. Артефакт
      // проверяли в среде, которая ему льстит.
      //
      // Две строки закрывают этот класс: рантайм Swift едет внутри двоичного
      // файла, а системные библиотеки объявлены зависимостями пакета, чтобы их
      // ставил менеджер пакетов, а не человек по сообщению об ошибке.
      // Свойство одно: программа запускается там, где Swift не стоял. Способов
      // два, и оба годятся — либо всё внутри файла (статический SDK), либо
      // системные библиотеки объявлены зависимостями пакета.
      //
      // Раньше здесь требовался `Depends: libcurl`. Требование устарело в тот
      // день, когда сборка стала статической: у такого пакета зависимостей нет
      // вовсе, и это лучше, а не хуже. Проверка ловила способ, а не свойство.
      // Проверяются ОБА пути, а не «хотя бы один». С «или» удаление статической
      // сборки проходило незаметно: оставался запасной путь с зависимостями, и
      // формально условие выполнялось. Но именно статический путь снимает
      // привязку к glibc, то есть даёт ALT и Astra — терять его молча нельзя.
      // Две строки, а не одна: имя цели присваивается выше, а флаг подставляется
      // ниже, и требование «musl в той же строке, что --swift-sdk» падало на
      // верном скрипте.
      assert.match(code, /swift-linux-musl/,
        'статическая цель пропала — пакет снова привязан к glibc образа сборки');
      assert.match(code, /--swift-sdk/,
        'статический SDK больше не используется при сборке');
      assert.match(code, /DEPENDS=.*libcurl/,
        'запасной путь не объявляет системные библиотеки');
      assert.match(code, /-static-stdlib/,
        'запасной путь потерял рантайм Swift');
    });

    test('установку проверяют в чистой системе, а не в образе сборки', () => {
      // Самая дорогая часть урока. Проверка установки внутри контейнера Swift
      // зелёная всегда и не значит ничего.
      const ci = read('.github', 'workflows', 'ci.yml');
      // Комментарии срезаются: в объяснении задания слово «debian:12» стоит
      // само по себе, и проверка на подстроку проходила даже когда установка
      // шла обратно в образ Swift. Четвёртый раз за вечер один и тот же промах
      // — сторож смотрел на текст вместо исполняемого.
      const job = ci.slice(ci.indexOf('linux-package:'))
        .split('\n').filter((line) => !line.trim().startsWith('#')).join('\n');
      assert.ok(job.length > 200, 'задания сборки пакета больше нет');

      // Шаг установки берётся целиком и смотрится отдельно: собирают в образе
      // Swift намеренно, а ставят обязательно в чистой системе.
      const install = job.slice(job.indexOf('Установка'));
      assert.match(install, /docker run[^\n]*(debian|ubuntu):/,
        'установка больше не проверяется в системе без Swift');
      assert.doesNotMatch(install, /docker run[^\n]*swift:/,
        'установку снова проверяют в образе Swift — там рантайм есть, и проверка пуста');
    });

    test('rpm собирают в своём семействе, а не переупаковкой чужого файла', () => {
      // Программа, собранная на Ubuntu, требует `libcurl.so.4(CURL_OPENSSL_4)`
      // — символ с версией от Ubuntu. На Fedora она запускается, но dnf пакет
      // не ставит: «nothing provides…». Поэтому rpm собирается в образе
      // семейства RPM, и это условие, а не предпочтение.
      const rpm = read('scripts', 'package-rpm.sh').split('\n')
        .filter((line) => !line.trim().startsWith('#')).join('\n');
      // Свойство то же, что у deb: пакет запускается там, где Swift не стоял.
      // Требовать `Requires: libcurl` больше нельзя — у статического пакета
      // зависимостей нет вовсе, и это лучше: именно поэтому он ставится на ALT,
      // где обычная сборка отказывалась (glibc 2.32 против нужных 2.34).
      assert.match(rpm, /swift-linux-musl/,
        'rpm потерял статическую цель — снова не поставится на ALT и Astra');
      assert.match(rpm, /REQUIRES="libcurl"/,
        'запасной путь не объявляет системные библиотеки');
      assert.match(rpm, /-static-stdlib/, 'запасной путь потерял рантайм Swift');
      assert.match(rpm, /swift build|PREBUILT/,
        'скрипт не берёт ни готовую сборку, ни собирает сам');

      // Продолжения строк разворачиваются: в YAML команда переносится обратным
      // слэшем, и образ оказывается на следующей строке. Проверка «в одной
      // строке» падала бы на верной команде — то есть заставляла бы писать
      // хуже ради сторожа.
      const ci = read('.github', 'workflows', 'ci.yml').split('\n')
        .filter((line) => !line.trim().startsWith('#')).join('\n')
        .replace(/\\\n\s*/g, ' ');
      // Требование «собирать в образе семейства RPM» устарело 2026-08-18: оно
      // существовало ради правильных зависимостей, а у статической сборки их
      // нет. Осталось то, что и было целью: пакет ставится там, где Swift не
      // стоял, — и в первую очередь на ALT, который обычную сборку отвергал.
      const install = ci.slice(ci.indexOf('Установка .rpm'));
      assert.match(install, /docker run[^\n]*alt:/,
        'rpm не проверяют на ALT — системе, ради которой статическая сборка и делалась');
      assert.match(install, /docker run[^\n]*fedora:/,
        'rpm не ставят в чистую fedora — проверка станет пустой');
      assert.doesNotMatch(install, /docker run[^\n]*swift:/,
        'установку проверяют в образе Swift — там рантайм есть, и проверка пуста');
    });

    test('каталог сборки свой у каждого образа', () => {
      // Репозиторий монтируется в контейнер, `.build` лежит внутри него, и
      // сборка в одном образе переиспользует объектные файлы другого. Так rpm
      // дважды получил зависимости Ubuntu и не ставился на Fedora.
      for (const name of ['package-linux.sh', 'package-rpm.sh']) {
        const code = read('scripts', name).split('\n')
          .filter((line) => !line.trim().startsWith('#')).join('\n');
        assert.match(code, /--scratch-path/,
          `${name} собирает в общий .build — чужие объектные файлы попадут в пакет`);
      }
    });

    test('пакет говорит, из какого кода собран, и это проверяют', () => {
      // У DMG прослеживаемость есть с самого начала: штамп в файле и
      // `audit-dmg.sh`, который его пересчитывает. Пакеты для Linux приехали
      // без неё вовсе — по .deb нельзя было сказать, из чего он собран.
      for (const name of ['package-linux.sh', 'package-rpm.sh']) {
        const code = read('scripts', name).split('\n')
          .filter((line) => !line.trim().startsWith('#')).join('\n');
        assert.match(code, /source-hash\.sh/, `${name} не считает хеш исходников`);
        assert.match(code, /build-info/, `${name} не кладёт штамп в пакет`);
      }
      // Обе стороны считают ОДНОЙ реализацией: у DMG расхождение двух
      // конвейеров однажды дало ложную тревогу на одинаковом коде.
      const audit = read('scripts', 'audit-package.sh');
      assert.match(audit, /source-hash\.sh/,
        'проверка считает хеш по-своему — она разойдётся со сборкой');
      assert.match(audit, /dpkg-deb -x|rpm2cpio/, 'проверка не читает сам пакет');

      const ci = read('.github', 'workflows', 'ci.yml').split('\n')
        .filter((line) => !line.trim().startsWith('#')).join('\n')
        .replace(/\\\n\s*/g, ' ');
      assert.match(ci, /audit-package\.sh/,
        'прослеживаемость никто не проверяет — штамп станет украшением');
    });

    test('CI собирает пакет, а не только рассказывает о нём', () => {
      const ci = read('.github', 'workflows', 'ci.yml');
      assert.match(ci, /package-linux\.sh/,
        'скрипт упаковки не запускается ни на одном прогоне — он сломается незаметно');
    });
  });

  describe('issue form', () => {
    const form = read('.github', 'ISSUE_TEMPLATE', 'oshibka.yml');

    test('asks for the version field the build actually stamps', () => {
      // It asks for OrakulSourceHash because the commit alone cannot tell two
      // builds of the same dirty tree apart — nine installers went out in one
      // day under one commit. If build.sh stops stamping it, the form starts
      // asking for something nobody can supply.
      assert.match(form, /OrakulSourceHash/);
      assert.match(read('app', 'build.sh'), /OrakulSourceHash/,
        'the form asks for a stamp the build no longer writes');
    });

    test('steers vulnerabilities away from the public tracker', () => {
      assert.match(form, /Security|SECURITY\.md/,
        'nothing steers a security report out of the public tracker');
    });

    test('is written in the language of the people it is for', () => {
      // The audience is Russian-speaking developers; an English form filters
      // out exactly the contributors this is meant to attract.
      const labels = [...form.matchAll(/label:\s*(.+)/g)].map(([, l]) => l.trim());
      assert.ok(labels.length >= 4, `only ${labels.length} fields — check the parse`);
      for (const label of labels) {
        assert.match(label, /[А-Яа-яЁё]/, `the field "${label}" is not in Russian`);
      }
    });
  });

  describe('connector form', () => {
    const form = read('.github', 'ISSUE_TEMPLATE', 'konnektor.yml');

    test('asks the four questions the project actually gates on, and requires them', () => {
      // Правило «не заявляйте того, чего нет» проверяет ровно четыре вещи:
      // метод, адрес, параметр поиска и форму ответа. Пока их спрашивал только
      // CONTRIBUTING — то есть уже после того, как человек написал код. Форма
      // задаёт их до, и обязательность здесь и есть весь смысл: необязательное
      // поле про поиск не отличается от его отсутствия.
      //
      // Проверяются идентификаторы полей, а не подписи: подпись перепишут при
      // первой же правке текста, и проверка на неё превратится в проверку
      // редактуры.
      const required = [...form.matchAll(
        /- type: \w+\s*\n\s*id: ([\w-]+)[\s\S]*?validations:\s*\n\s*required: (true|false)/g)]
        .reduce((map, [, id, flag]) => map.set(id, flag === 'true'), new Map());

      for (const field of ['dokumentatsiya', 'metod', 'poisk', 'otvet']) {
        assert.equal(required.get(field), true,
          `поле «${field}» не обязательно — гейт можно пройти, не ответив на него`);
      }
    });

    test('says what a dead end is, so a negative answer still arrives', () => {
      // Половина ценности гейта — записанные тупики: Pyrus, Мегаплан, обе базы
      // знаний. Форма, которая принимает только успех, эту половину теряет:
      // человек, не нашедший метода поиска, просто закроет вкладку, и
      // следующий будет искать заново.
      assert.match(form, /Яндекс Вики|Teamly|Pyrus|Мегаплан/,
        'форма не показывает, что отрицательный ответ — тоже результат');
      assert.match(form, /LiveConnectorProbe/,
        'форма не зовёт прогнать проверку на живом сервисе');
    });

    // Метки этой формы здесь больше не проверяются.
    //
    // Стоял запрет объявлять метку вообще: `oshibka.yml` объявлял «ошибка»,
    // которой в репозитории не было, issue приезжал без метки, и заметить это
    // было нечем. Запрет был не правилом, а признанием, что проверить нечем.
    //
    // Теперь есть чем: `.github/metki.txt` — снимок живых меток, а
    // `test/metki.test.mjs` сверяет с ним каждую форму побайтово. Правило от
    // этого стало сильнее (метку нельзя объявить несуществующую) и при этом
    // перестало запрещать законное — объявить заведённую метку можно.
    //
    // Два сторожа на одном правиле — это два места, где его чинить, и одно из
    // них забудут.
  });
});
