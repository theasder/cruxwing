import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

// Доступ к своей сети: система спрашивает, а объяснять должны мы.
//
// Коннекторы ходят к адресам, которые вписал человек: самостоятельные GitLab и
// Gitea часто живут в LAN. Даже по HTTPS на macOS 15 первое обращение к такому
// адресу поднимает системный запрос «разрешить искать устройства в вашей сети».
//
// Измерено 2026-08-19: App Transport Security такому обращению НЕ мешает —
// пакет с этим самым Info.plist сходил на http://192.168.… и получил 200.
// Мешает другое: запрос без объяснения. Человек видит его сразу после того, как
// вписал токен от рабочего трекера, и решает в эту секунду, доверять ли
// программе вообще. Пустое место вместо причины — худший ответ.

const PLIST = 'app/Support/Info.plist';

function plist() {
  const json = execFileSync('plutil', ['-convert', 'json', '-o', '-', PLIST], { encoding: 'utf8' });
  return JSON.parse(json);
}

test('приложение объясняет, зачем ему своя сеть', () => {
  const reason = plist().NSLocalNetworkUsageDescription;
  assert.ok(reason, `${PLIST} не объявляет NSLocalNetworkUsageDescription — ` +
    'система спросит про доступ к сети без единого слова о причине');
  assert.ok(reason.length > 40, 'причина слишком короткая, чтобы что-то объяснить');
  assert.match(reason, /[а-яА-Я]/, 'причину читает человек — она на русском');
});

test('объяснение говорит о своём сервере, а не о «сетевых функциях»', () => {
  const reason = plist().NSLocalNetworkUsageDescription;
  assert.match(reason, /трекер|вики|сервер/i,
    'причина не называет, к чему именно идём: «для сетевых функций» ничего не объясняет');
  // Обещание проверяемое: наружу по этому доступу ничего не уходит.
  assert.match(reason, /вписали сами|вы вписали|наружу/i,
    'причина не говорит границу — куда именно пойдёт запрос');
});

// Ключ существует не сам по себе: он парный к возможности ходить на адреса в
// своей сети. HTTP при этом разрешён только на loopback этой же машины; LAN
// не становится безопасным транспортом только потому, что он локальный.
test('разрешение своей сети в коде и объяснение в plist — про одно и то же', () => {
  const code = readFileSync('mvp/Sources/CruxwingCore/ConnectorAddress.swift', 'utf8');
  assert.match(code, /isLoopback/, 'ConnectorAddress больше не различает loopback');
  assert.match(code, /scheme == "http" && isLoopback\(host\)/,
    'HTTP снова разрешён не только для loopback');
  assert.match(code, /if scheme == "http"[\s\S]*return forcedHTTPS\(withScheme\)/,
    'HTTP вне loopback больше не поднимается до HTTPS');
  assert.doesNotMatch(code, /192\.168\.[\s\S]*return true/,
    'частная сеть снова ошибочно приравнена к loopback');
  assert.ok(plist().NSLocalNetworkUsageDescription,
    'код ходит в свою сеть, а plist об этом молчит');
});

test('описания доступа объявлены для всего, что приложение просит', () => {
  const keys = Object.keys(plist()).filter((k) => k.endsWith('UsageDescription'));
  for (const needed of ['NSMicrophoneUsageDescription', 'NSLocalNetworkUsageDescription']) {
    assert.ok(keys.includes(needed), `нет ${needed}`);
  }
  for (const key of keys) {
    assert.ok(plist()[key].trim().length > 0, `${key} объявлен пустым — это хуже отсутствия`);
  }
});
