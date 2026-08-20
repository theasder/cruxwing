import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

// Источник, видевший часть, обязан сказать это и когда ничего не нашёл.
//
// Разница между «искали везде» и «просмотрели последние 500 из 40 000» — весь
// смысл SearchCoverage (роадмап, §7.2). При пустой выдаче она пропадала: ветка
// возвращала nil, и охват не доезжал. Это единственный случай, когда «часть» и
// «всё» звучат для читателя одинаково — оба выходят как «ничего не нашлось».
//
// Чинилось это трижды и по одному: телеграмный архив, оба семейства трекеров,
// заметки на диске. Трижды по одному — признак того, что четвёртый источник
// заведут так же молча, и никто не заметит.
//
// Поэтому здесь список: каждая ветка веера либо говорит про свою границу, либо
// названа как «ищет сам». Второе — решение, а не пропуск, и его надо записать.

const FILE = 'app/Sources/MeetGPT/MCP/MCPGrounding.swift';
const code = readFileSync(FILE, 'utf8');
const lines = code.split('\n');

// Источники, чья пустая выдача честна: сервис ищет сам, по всему, что у него
// есть. Молчать там правильно — лишняя строка в запросе стоит места.
const SEARCHES_ITSELF = new Map([
  ['team:', 'Slack и Confluence ищут сами, границы у выдачи нет'],
  ['tracker:', 'российские трекеры ищут на своей стороне; у Битрикс24 постраничный предел ' +
               'относится к СОВПАДЕНИЯМ, а не к просмотренному'],
  ['notes:', 'вики (Outline, BookStack, Wiki.js, Nextcloud) ищут сами'],
  ['messenger:', 'рабочие мессенджеры ищут сами'],
  ['github', 'поиск GitHub — на их стороне'],
]);

// Как ветка может сказать про границу.
const SAYS_ITS_BOUND = ['boundedEmptySnippet', 'text: bound'];

// Источники, у которых граница ЕСТЬ, и списком выше их не извинить.
//
// Телеграм тут не для порядка: его имя начинается с `messenger:`, а рабочие
// мессенджеры ищут сами и потому в списке извинений. Прежняя редакция извиняла
// по приставке — и мутация, отнявшая у телеграмного архива его границу,
// проверку проходила. Архив начинается в день подключения; «ищет сам» про него
// неправда.
const MUST_DECLARE_ITS_BOUND = ['messenger:telegram', 'notes-local', 'selfhosted:', 'western:'];

// Разбор ограничен ВЕЕРОМ, а не всем файлом, и каждая ветка внутри него обязана
// опознаться. Первая редакция искала `sourceID` в окне и молча пропускала ветку,
// в которой его не нашла, — то есть мутация, спрятавшая источник, проверку
// проходила: ветка просто исчезала из разбора. Сторож, умеющий не заметить, и
// есть сторож, который не сработает.
function fanOut() {
  const start = lines.findIndex((l) => l.includes('withTaskGroup(of: (Int, GroundingSnippet?)'));
  assert.ok(start > 0, 'в файле не нашёлся веер источников');
  const end = lines.findIndex((l, i) => i > start && l.includes('return ordered'));
  assert.ok(end > start, 'у веера не нашёлся конец');
  return { start, end };
}


// Тело ветки `guard … else { … }` — от неё до закрывающей скобки того же
// отступа. Однострочный `guard … else { return (index, nil) }` — это она сама.
function branchBody(i) {
  const indent = lines[i].length - lines[i].trimStart().length;
  if (lines[i].trimEnd().endsWith('}')) return lines[i];
  const out = [lines[i]];
  for (let j = i + 1; j < lines.length; j += 1) {
    out.push(lines[j]);
    const trimmed = lines[j].trimStart();
    if (trimmed === '}' && lines[j].length - trimmed.length === indent) break;
  }
  return out.join('\n');
}

function branches() {
  const { start, end } = fanOut();
  const found = [];
  for (let i = start; i <= end; i += 1) {
    if (!lines[i].includes('isEmpty else')) continue;
    // ТЕЛО ветки, а не окно вокруг неё.
    //
    // Сначала здесь было окно в несколько строк, и оно дважды соврало в разные
    // стороны: сперва не увидело границу, посчитанную строкой выше, потом —
    // увидело её же, когда мутация выкинула её ИЗ ВЕТКИ. Близость к строке не
    // значит, что строка работает; это тот же промах, что «код остался в файле
    // и стал недостижим».
    const body = branchBody(i);
    const window = lines.slice(i, i + 14).join('\n');
    const source = /sourceID: "([^"\\]+)/.exec(window);
    found.push({ line: i + 1, source: source ? source[1] : null, window, body });
  }
  return found;
}

test('каждая ветка веера либо называет границу, либо объявлена ищущей сама', () => {
  const offenders = [];
  const seen = new Set();
  for (const branch of branches()) {
    const bounded = SAYS_ITS_BOUND.some((mark) => branch.body.includes(mark));
    const mustDeclare = branch.source
      && MUST_DECLARE_ITS_BOUND.some((prefix) => branch.source.startsWith(prefix));
    if (mustDeclare) {
      if (!bounded) {
        offenders.push(`${FILE}:${branch.line} — «${branch.source}» знает свою границу и молчит о ней`);
      }
      seen.add('bounded');
      continue;
    }
    if (bounded) continue;
    if (!branch.source) {
      offenders.push(`${FILE}:${branch.line} — ветка веера без источника: разобрать её нечем`);
      continue;
    }
    const excuse = [...SEARCHES_ITSELF.keys()].find((prefix) => branch.source.startsWith(prefix));
    if (excuse) { seen.add(excuse); continue; }
    offenders.push(`${FILE}:${branch.line} — источник «${branch.source}» молчит на пустой выдаче`);
  }
  assert.ok(branches().length >= 6, `веток нашлось ${branches().length} — разбор сломан`);
  assert.deepEqual(offenders, []);

  // И обратно: имя в списке, которого в коде нет, — разрешение для
  // несуществующего, а рядом молча перестаёт защищать существующее.
  assert.ok(seen.has('bounded'), 'ни одна ветка не объявила границу — разбор сломан');
  const stale = [...SEARCHES_ITSELF.keys()].filter((prefix) => !seen.has(prefix));
  assert.deepEqual(stale, [], `в списке «ищет сам» числятся отсутствующие ветки: ${stale}`);
});
