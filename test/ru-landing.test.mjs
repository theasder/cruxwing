import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '..');
const russianPath = resolve(root, 'public', 'ru', 'index.html');
const html = readFileSync(russianPath, 'utf8');
const css = readFileSync(resolve(root, 'public', 'ru', 'landing.css'), 'utf8');
const film = readFileSync(
  resolve(root, 'public', 'ru', 'demo-film', 'scene.developer-ru.js'), 'utf8');

describe('Cruxwing Russian developer landing', () => {
  test('does not change the existing Orakul landing', () => {
    // Слепок, а не список правил: страница orakul — чужой продукт для этой
    // работы, и любое её изменение обязано быть намеренным. Обновлять слепок
    // руками — это и есть «намеренно». Последний раз обновлён 2026-08-18:
    // на страницу добавились чипы Plane, GitFlic и BookStack.
    const rootLanding = readFileSync(resolve(root, 'public', 'index.html'));
    const hash = createHash('sha256').update(rootLanding).digest('hex');
    assert.equal(hash, '29636fed74d1ef73811b921aa9cc1b3bbd219011a5b298cba4c86d5ef4b8ee1b');
  });

  test('declares Russian metadata and the requested production route', () => {
    assert.match(html, /<html lang="ru">/);
    assert.match(html, /property="og:locale" content="ru_RU"/);
    assert.match(html, /rel="canonical" href="https:\/\/cruxwing\.ai\/ru\/"/);
    assert.match(html, /hreflang="en" href="https:\/\/cruxwing\.ai\/"/);
    assert.match(html, /hreflang="ru" href="https:\/\/cruxwing\.ai\/ru\/"/);
    const description = html.match(/name="description" content="([^"]+)"/)?.[1] ?? '';
    assert.match(description, /[а-яё]/i);
  });

  test('keeps one clear page title and developer-first copy', () => {
    assert.equal((html.match(/<h1\b/g) ?? []).length, 1);
    assert.match(html, /ИИ-помощник для команд разработки/);
    assert.match(html, /дизайн-ревью/);
    assert.match(html, /разбору инцидента/);
    assert.match(html, /Jira/);
    assert.match(html, /Sentry/);
  });

  test('renders one developer film and no audience tabs', () => {
    const hosts = [...html.matchAll(/data-film-embed[^>]*data-scenario="([^"]+)"/g)];
    assert.equal(hosts.length, 1);
    assert.equal(hosts[0][1], 'developer-ru');
    assert.doesNotMatch(html, /data-film-tab|role="tablist"|class="film-tabs"/);
    for (const scenario of [
      'founder-ceo', 'customer-success', 'sales-ae', 'marketing-manager',
      'recruiter-hr', 'engineering-manager', 'project-manager', 'ops-lead',
    ]) {
      assert.ok(!html.includes(`data-scenario="${scenario}"`),
        `non-developer scenario remains in the landing: ${scenario}`);
    }
  });

  test('ships a Russian engineering overlay, not the English tech-lead film', () => {
    assert.match(film, /Дизайн-ревью/);
    assert.match(film, /пайплайн/);
    assert.match(film, /Jira/);
    assert.match(film, /Sentry/);
    assert.match(film, /Постмортем/);
    assert.doesNotMatch(film, /Design review — the export pipeline rewrite/);
    assert.doesNotMatch(film, /Play the product film/);
  });

  test('shows only capture apps or native connectors before the integrations fold', () => {
    const at = html.indexOf('id="integrations"');
    const list = html.slice(html.indexOf('<ul', at), html.indexOf('</ul>', at));
    const visible = [...list.matchAll(/<li(?![^>]*strip-more)[^>]*>[\s\S]*?<span>([^<]+)<\/span>/g)]
      .map((match) => match[1].trim())
      .slice(0, 10);
    assert.deepEqual(visible, [
      'Zoom', 'Google Meet', 'Teams', 'Discord', 'Telegram',
      'Jira', 'Linear', 'Sentry', 'Notion', 'Asana',
    ]);
  });

  test('keeps every demo claim grounded in its translated transcript', () => {
    const context = vm.createContext({});
    for (const file of ['scene.js', 'scene.developer-ru.js']) {
      vm.runInContext(
        readFileSync(resolve(root, 'public', 'ru', 'demo-film', file), 'utf8'),
        context,
        { filename: file },
      );
    }
    const scene = context.CruxFilmScene;
    const transcript = scene.TRANSCRIPT.map((turn) => turn.text).join('\n');
    for (const card of scene.BLIND_SPOTS.cards) {
      assert.ok(transcript.includes(card.evidence),
        `demo evidence is not verbatim: ${card.evidence}`);
    }
    assert.equal(scene.MEETING.title, 'Дизайн-ревью — переписываем пайплайн экспорта');
    assert.ok(scene.ACTS.every((act) => /[а-яё]/i.test(act.label)),
      'every visible film chapter must be Russian');
  });

  test('all namespaced local resources exist', () => {
    const local = [...html.matchAll(/(?:href|src)="(\.\/[^"#?]+)(?:\?[^"]*)?"/g)]
      .map(([, path]) => path);
    assert.ok(local.length >= 2);
    for (const path of local) {
      assert.ok(existsSync(resolve(root, 'public', 'ru', path)),
        `missing local resource: ${path}`);
    }
  });

  test('does not use root-relative links that break on GitHub project Pages', () => {
    assert.doesNotMatch(html, /(?:href|src)="\/(?!\/)/);
    for (const target of ['download', 'privacy', 'terms', 'security', 'google-data', 'demo']) {
      assert.ok(html.includes(`https://cruxwing.ai/${target}`),
        `${target} must stay pinned to the real Cruxwing site`);
    }
  });

  test('paid plan CTAs preserve the live checkout intent', () => {
    for (const tier of ['pro', 'premium']) {
      const cta = html.match(new RegExp(`<a[^>]+data-checkout="${tier}"[^>]+>`))?.[0] ?? '';
      assert.match(cta, /href="https:\/\/cruxwing-ai\.lemonsqueezy\.com\/checkout\/custom\//);
      assert.match(cta, /target="_blank"/);
      assert.match(cta, /rel="noopener"/);
      assert.doesNotMatch(cta, /cruxwing\.ai\/download/);
    }
  });

  test('every in-page anchor has a target', () => {
    const ids = new Set([...html.matchAll(/\bid="([^"]+)"/g)].map(([, id]) => id));
    for (const [, target] of html.matchAll(/href="#([^"]+)"/g)) {
      assert.ok(ids.has(target), `missing #${target}`);
    }
  });

  test('keeps keyboard focus and reduced-motion behavior', () => {
    assert.match(css, /:focus-visible/);
    assert.match(css, /prefers-reduced-motion:\s*reduce/);
    assert.match(css, /overflow-x:\s*clip/);
    assert.match(html, /aria-label="Основная навигация"/);
    assert.match(html, /role="region" tabindex="0"/);
  });
});
