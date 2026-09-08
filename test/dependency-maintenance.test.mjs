import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const dependabot = readFileSync(resolve(repo, '.github', 'dependabot.yml'), 'utf8');
const review = readFileSync(
  resolve(repo, '.github', 'workflows', 'dependency-review.yml'), 'utf8');
const codeowners = readFileSync(resolve(repo, '.github', 'CODEOWNERS'), 'utf8');
const releaseDocs = readFileSync(resolve(repo, 'docs', 'RELEASING.md'), 'utf8');

function ecosystem(name) {
  const entries = dependabot.split(/\n(?=  - package-ecosystem:)/).slice(1);
  return entries.find((entry) =>
    entry.startsWith(`  - package-ecosystem: "${name}"`)) ?? '';
}

test('Dependabot opens bounded weekly review PRs for the two real dependency surfaces', () => {
  assert.match(dependabot, /^version:\s*2\s*$/m);
  const entries = dependabot.match(/^  - package-ecosystem:/gm) ?? [];
  assert.equal(entries.length, 2, 'an unreviewed package ecosystem was added');

  const swift = ecosystem('swift');
  const actions = ecosystem('github-actions');
  assert.match(swift, /^    directory:\s*"\/app"\s*$/m);
  assert.match(actions, /^    directory:\s*"\/"\s*$/m);
  for (const entry of [swift, actions]) {
    assert.match(entry, /^      interval:\s*"weekly"\s*$/m);
    assert.match(entry, /^    open-pull-requests-limit:\s*[1-4]\s*$/m);
    assert.match(entry, /^          - "patch"\s*$/m,
      'only low-risk patch updates should be grouped');
  }

  assert.doesNotMatch(dependabot, /directory:\s*"\/mvp"/);
  assert.doesNotMatch(dependabot, /auto-merge|registries:|secrets\./i);
});

test('dependency review is read-only, public-only and commit-pinned', () => {
  assert.match(review, /^\s+pull_request:\s*$/m);
  assert.doesNotMatch(review, /^\s+(push|pull_request_target|workflow_run):/m);
  assert.match(review, /^\s+contents:\s*read\s*$/m);
  assert.doesNotMatch(review, /^\s+[a-z-]+:\s*write\s*$/m);
  assert.match(review, /if:\s*github\.event\.repository\.private == false/);
  assert.match(review, /actions\/dependency-review-action@[0-9a-f]{40}\s+# v5\.0\.0/);
  assert.match(review, /actions\/checkout@[0-9a-f]{40}\s+# v4/);
  assert.match(review, /comment-summary-in-pr:\s*never/);
  assert.match(releaseDocs,
    /после перевода репозитория в public[\s\S]{0,180}автоматически перестаёт быть пропущенным/,
    'owner docs do not explain when the public-only check activates');
});

test('dependency maintenance policy and its test require owner review', () => {
  for (const path of [
    '/.github/dependabot.yml',
    '/.github/workflows/',
    '/test/dependency-maintenance.test.mjs',
  ]) {
    const escaped = path.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    assert.match(codeowners, new RegExp(`^${escaped}\\s+@theasder\\s*$`, 'm'));
  }
});
