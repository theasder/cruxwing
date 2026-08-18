import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { stripComments, bodyOf } from './swift-source.mjs';

// Всё остальное держится на том, что соединение шифровано тому, кому надо.
//
// Правило про http, запрет перенаправлений на чужой хост, секрет в заголовке
// вместо адреса — всё это стоит на проверке сертификата. Одна строка
// `completionHandler(.useCredential, URLCredential(trust: trust))` без
// SecTrustEvaluateWithError отменяет разом всё: посредник в сети становится
// сервисом, и токен уезжает к нему по «https».
//
// Просьба будет, и предсказуемая: у самостоятельных установок GitLab и Gitea
// часто свой центр сертификации, и «разрешите самоподписанные» — самая
// естественная просьба такого человека. Правильный ответ на неё — доверить
// КОНКРЕТНЫЙ сертификат (как это делает CertPinning), а не выключить проверку.
//
// Сегодня в коде выключения нет. Эта проверка о том, чтобы завтра оно не
// появилось незаметно.

const ROOTS = ['app/Sources', 'mvp/Sources'];
const HANDLER = 'didReceive challenge: URLAuthenticationChallenge';

function swiftFiles(dir) {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return swiftFiles(path);
    return path.endsWith('.swift') ? [path] : [];
  });
}

function sources() {
  return ROOTS.flatMap(swiftFiles).map((path) => ({ path, text: readFileSync(path, 'utf8') }));
}

test('доверие сертификату выдаётся только после его проверки', () => {
  const unsafe = [];
  for (const { path, text } of sources()) {
    const code = stripComments(text);
    if (!code.includes('URLCredential(trust')) continue;
    const body = bodyOf(text, HANDLER);
    assert.ok(body, `${path} создаёт доверие вне обработчика проверки подлинности — разберитесь руками`);
    if (!body.includes('SecTrustEvaluateWithError')) unsafe.push(path);
  }
  assert.deepEqual(unsafe, [],
    `доверие выдаётся без проверки цепочки: ${unsafe.join(', ')}. ` +
    'Посредник в сети станет сервисом, и токен уедет к нему по «https».');
});

test('обработчик проверки подлинности не принимает всё подряд', () => {
  for (const { path, text } of sources()) {
    const body = bodyOf(text, HANDLER);
    if (!body) continue;
    // Ветка «не наш случай» обязана возвращать системное поведение, а не
    // доверие: `performDefaultHandling` — это «пусть решает система».
    assert.ok(body.includes('performDefaultHandling') || body.includes('cancelAuthenticationChallenge'),
      `${path}: обработчик не отдаёт разбор системе и не отказывает — что он делает с чужим хостом?`);
  }
});

test('исключений App Transport Security нет', () => {
  const plists = swiftPlists();
  assert.ok(plists.length > 0, 'ни одного Info.plist не найдено — проверка смотрит в пустоту');
  for (const { path, text } of plists) {
    for (const key of ['NSAllowsArbitraryLoads', 'NSExceptionAllowsInsecureHTTPLoads',
                       'NSExceptionMinimumTLSVersion']) {
      assert.ok(!text.includes(key),
        `${path} содержит ${key} — это выключение проверки транспорта для всего приложения`);
    }
  }
});

function swiftPlists() {
  const found = [];
  const walk = (dir) => {
    for (const name of readdirSync(dir)) {
      if (name === '.build' || name === 'build' || name === 'node_modules') continue;
      const path = join(dir, name);
      if (statSync(path).isDirectory()) walk(path);
      else if (name === 'Info.plist') found.push({ path, text: readFileSync(path, 'utf8') });
    }
  };
  walk('app');
  return found;
}

// Проверка обязана ловить именно ту строку, ради которой написана.
test('подложенное «доверять чему угодно» находится', () => {
  const planted = `
  func urlSession(_ session: URLSession,
                  didReceive challenge: URLAuthenticationChallenge,
                  completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
      let trust = challenge.protectionSpace.serverTrust!
      completionHandler(.useCredential, URLCredential(trust: trust))
  }`;
  const body = bodyOf(planted, HANDLER);
  assert.ok(body, 'разбор не нашёл обработчик в образце');
  assert.ok(body.includes('URLCredential(trust'), 'образец не содержит выдачу доверия');
  assert.ok(!body.includes('SecTrustEvaluateWithError'),
    'образец обхода должен быть без проверки цепочки, иначе он ничего не изображает');
});
