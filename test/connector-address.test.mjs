import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { stripComments } from './swift-source.mjs';

// Адрес сервиса вписывает человек, и по этому адресу уезжает его токен. Правило
// одно и лежит в ConnectorAddress: `http` до чужого сервера поднимается до
// `https`, до своей сети — остаётся. Само правило проверено в Swift, включая
// границы частных диапазонов.
//
// Здесь проверяется другое: что правило нельзя обойти, дописав следующее
// семейство коннекторов. Сегодня дверей три (трекеры, заметки, мессенджеры), и
// все три через него ходят — но это утверждение про сегодня. Четвёртая дверь
// со своей склейкой "https://\(value)" не уронит ни один Swift-тест: он
// проверяет три известных ему сервиса, а не тот, которого ещё нет.

const CORE = 'mvp/Sources/OrakulCore';
const RULE = 'ConnectorAddress.swift';

/** Склейка схемы с чем-то, что пришло снаружи. */
const SCHEME_CONCAT = /"https?:\/\/\\\(/;

function coreSources() {
  return readdirSync(CORE)
    .filter((name) => name.endsWith('.swift') && name !== RULE)
    .map((name) => ({ name, body: stripComments(readFileSync(join(CORE, name), 'utf8')) }));
}

test('схему к пользовательскому адресу приклеивает одно место', () => {
  const offenders = coreSources()
    .filter(({ body }) => SCHEME_CONCAT.test(body))
    // RussianTrackers склеивает домен, который сам же и требует доменом, и
    // всегда через https — там нет ветки, где выбирается http.
    .filter(({ name }) => name !== 'RussianTrackers.swift')
    .map(({ name }) => name);

  assert.deepEqual(offenders, [],
    `эти файлы собирают адрес сами, мимо ${RULE}: ${offenders.join(', ')}. ` +
    'Токен по такому адресу уедет тем протоколом, который вписал человек.');
});

test('каждое семейство коннекторов зовёт правило по имени', () => {
  const families = ['SelfHostedTrackers.swift', 'TeamNotes.swift', 'WorkMessengers.swift'];
  for (const name of families) {
    const body = stripComments(readFileSync(join(CORE, name), 'utf8'));
    assert.match(body, /ConnectorAddress\.normalise\(/,
      `${name} нормализует адрес сам — правило про http перестало на него распространяться`);
  }
});

// Проверка обязана ловить подложенный обход, иначе «нарушителей нет» значит и
// «всё хорошо», и «регулярка не совпадает ни с чем».
test('обход находится, когда он есть', () => {
  const planted = 'return raw.hasPrefix("http") ? raw : "https://\\(raw)"';
  assert.match(planted, SCHEME_CONCAT,
    'выборка не видит собственный образец обхода — она не проверяет ничего');
});
