import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { stripComments } from './swift-source.mjs';

// К своему серверу ходят сессией с привязкой к сертификату.
//
// `BackendPinning` сверяет отпечаток листового сертификата нашего хоста. Без
// него «https» защищает от подслушивания в кафе, но не от того, у кого есть
// сертификат на наш адрес: посредник отвечает за нас, а приложение верит.
//
// Что стоит на этом ответе: тариф человека («у вас Pro», «пробный кончился»),
// профиль вместе с токеном в заголовке — и АДРЕС ОПЛАТЫ. Последний приложение
// открывает в браузере, то есть подменивший ответ выбирает, на чьей странице
// человек введёт карту.
//
// Причины ставить общую сессию нет вовсе, и это не мнение: делегат привязки
// смотрит на ХОСТ и для всех остальных адресов молча отдаёт обычную проверку.
// То есть `BackendPinning.shared` годится и для чужих сервисов, а
// `URLSession.shared` рядом со своим сервером — просто пропущенная привязка.
//
// Найдено 2026-08-20: пять обращений в оплате и отправка отзыва шли общей
// сессией. Привязка была написана, настроена ключом BACKEND_CERT_PINS и
// названа в плане — и мимо неё ходила самая денежная часть приложения.
//
// Проверять «файлы, где написан адрес нашего сервера» оказалось мало, и это
// тоже показала мутация, а не рассуждение: половина служб получает адрес
// ПАРАМЕТРОМ (`base: String`) и слова backendBaseURL не содержит вовсе.
// Поэтому список перевёрнут: обычной сессией пользуются только названные
// здесь, и каждый в списке — чужой вендор со своим хостом.

const ROOT = 'app/Sources/MeetGPT';

// Три написания одной дыры. Первая редакция знала одно — мутация, вернувшая
// отправку отзыва на общую сессию, её прошла: там сессия стоит значением по
// умолчанию, и строки «URLSession.shared» в файле нет вовсе.
const PLAIN = [
  [/URLSession\.shared/, 'общая сессия'],
  [/URLSession\s*=\s*\.shared/, 'общая сессия значением по умолчанию'],
  [/URLSession\(configuration:/, 'своя сессия мимо привязки'],
];

// Кому обычная сессия положена: чужие вендоры со своими хостами. Привязка к
// нашему сертификату им не нужна и не мешала бы — делегат смотрит на хост, —
// но требовать её от них значило бы делать вид, что мы отвечаем за их TLS.
const THIRD_PARTY = new Set([
  'AI/AnthropicClient.swift',
  'AI/GeminiClient.swift',
  'AI/OpenAIClient.swift',
  'Integrations/AssemblyAIService.swift',
  'Integrations/CalendarService.swift',
  'Integrations/DeepgramStreamer.swift',
  'Integrations/GoogleAccountAuth.swift',
  'Integrations/GoogleAuth.swift',
  'Integrations/GoogleDocsService.swift',
  'Integrations/GoogleDocsWriter.swift',
  'Integrations/GoogleDriveWriter.swift',
  'Integrations/GoogleFormsService.swift',
  'Integrations/GoogleSheetsService.swift',
  'Integrations/GoogleSlidesService.swift',
  'Integrations/GoogleWorkspaceSearchService.swift',
  'Integrations/TeamConnectors.swift',
  'Transcription/WhisperAPITranscription.swift',
  // Сам файл привязки строит ту самую сессию — он и есть дверь.
  'Integrations/CertPinning.swift',
]);

function swiftFiles(dir) {
  return readdirSync(dir).flatMap((entry) => {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) return swiftFiles(path);
    return entry.endsWith('.swift') ? [path] : [];
  });
}

test('обычной сессией пользуются только названные чужие сервисы', () => {
  const offenders = [];
  let looked = 0;

  for (const path of swiftFiles(ROOT)) {
    const relative = path.slice(ROOT.length + 1);
    looked += 1;
    const code = stripComments(readFileSync(path, 'utf8'));
    for (const [shape, why] of PLAIN) {
      if (!shape.test(code)) continue;
      if (THIRD_PARTY.has(relative)) continue;
      offenders.push(`${relative}: ${why}`);
    }
  }

  assert.ok(looked > 50, `просмотрено файлов ${looked} — обход сломан`);
  assert.deepEqual(offenders, []);
});

test('в списке чужих нет наших и нет исчезнувших', () => {
  for (const relative of THIRD_PARTY) {
    const path = join(ROOT, relative);
    assert.ok(statSync(path).isFile(), `в списке числится ${relative}, которого нет`);
    if (relative === 'Integrations/CertPinning.swift') continue;
    const code = stripComments(readFileSync(path, 'utf8'));
    assert.ok(!/Config\.backendBaseURL|backendRoot\(/.test(code),
      `${relative} знает адрес нашего сервера и при этом освобождён от привязки`);
  }
});

test('привязка не выключена по умолчанию мимо настройки', () => {
  // Отсутствие ключа честно означает «как раньше», и это записано в самом
  // коде. Проверяется здесь другое: что решение принимается ПО КЛЮЧУ, а не
  // строкой `return .shared`, оставшейся после отладки.
  const code = stripComments(
    readFileSync(join(ROOT, 'Integrations/CertPinning.swift'), 'utf8'));
  assert.match(code, /Secrets\.backendCertPins/);
  assert.match(code, /guard !pins\.isEmpty/);
  assert.match(code, /SecTrustEvaluateWithError/,
    'привязка перестала требовать обычной проверки цепочки');
});
