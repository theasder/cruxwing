import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import {
  mkdtempSync, rmSync, writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const scanner = resolve(repo, 'scripts', 'scan-history-secrets.mjs');

function isolatedGitEnvironment() {
  const environment = { ...process.env };
  // Root publication tests may use a prospective index. A nested fixture must
  // use the index in its own .git directory.
  delete environment.GIT_INDEX_FILE;
  return environment;
}

function git(cwd, args, options = {}) {
  return execFileSync('git', args, {
    cwd,
    env: isolatedGitEnvironment(),
    encoding: 'utf8',
    ...options,
  });
}

test('all reachable history and current publication inputs pass the exact secret review', () => {
  const result = spawnSync(process.execPath, [scanner], {
    cwd: repo,
    encoding: 'utf8',
  });
  assert.equal(result.status, 0, `${result.stdout}${result.stderr}`);
  assert.match(result.stdout, /history secret scan clean: \d+ objects, \d+ current files/);
  assert.match(result.stdout, /exact synthetic fixture blobs reviewed/,
    'the scan silently ignored its deliberate redaction fixtures');
});

test('an unknown historical key fails redacted, and only its exact reviewed blob can pass', () => {
  const root = mkdtempSync(join(tmpdir(), 'orakul-history-secret-'));
  const allowlist = join(root, 'reviewed.json');
  const secretPath = join(root, 'redaction-fixture.txt');
  // Assemble the sentinel so the Orakul repository never contains the same
  // credential-shaped value that this negative fixture is meant to catch.
  const sentinel = ['sk-', 'history-fixture-', 'X'.repeat(24)].join('');
  try {
    git(root, ['init', '-q']);
    writeFileSync(secretPath, `${sentinel}\n`);
    git(root, ['add', 'redaction-fixture.txt']);
    git(root, [
      '-c', 'user.name=Orakul history scan test',
      '-c', 'user.email=history-scan@invalid.example',
      'commit', '-qm', 'synthetic fixture',
    ]);
    writeFileSync(allowlist, '{"version":1,"fixtures":[]}\n');

    const rejected = spawnSync(process.execPath, [
      scanner, '--repo', root, '--allowlist', allowlist,
    ], { encoding: 'utf8', env: isolatedGitEnvironment() });
    const rejectedOutput = `${rejected.stdout}${rejected.stderr}`;
    assert.equal(rejected.status, 1, rejectedOutput);
    assert.match(rejectedOutput, /redaction-fixture\.txt \[sk-provider\]/);
    assert.doesNotMatch(rejectedOutput, new RegExp(sentinel),
      'the security gate printed the credential it found');

    const oid = git(root, ['hash-object', 'redaction-fixture.txt']).trim();
    writeFileSync(allowlist, `${JSON.stringify({
      version: 1,
      fixtures: [{
        oid,
        path: 'redaction-fixture.txt',
        categories: ['sk-provider'],
        reason: 'Synthetic value created solely for the scanner test.',
      }],
    })}\n`);
    const reviewed = spawnSync(process.execPath, [
      scanner, '--repo', root, '--allowlist', allowlist,
    ], { encoding: 'utf8', env: isolatedGitEnvironment() });
    assert.equal(reviewed.status, 0, `${reviewed.stdout}${reviewed.stderr}`);
    assert.match(reviewed.stdout, /1 exact synthetic fixture blobs reviewed/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
