import assert from 'node:assert/strict';
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const verifier = resolve(repo, 'scripts', 'verify-swiftpm-checkouts.sh');

function run(command, args, options = {}) {
  // The repository's publication tests may run under a temporary prospective
  // index. A fixture repository must never inherit that root GIT_INDEX_FILE:
  // Git would then read/write the caller's index instead of its own and the
  // fixture would fail before exercising the verifier.
  const env = { ...process.env, ...(options.env ?? {}) };
  delete env.GIT_INDEX_FILE;
  return spawnSync(command, args, { encoding: 'utf8', ...options, env });
}

function writePlutilShim(bin) {
  const shim = join(bin, 'plutil');
  writeFileSync(shim, `#!/usr/bin/env node
const fs = require('node:fs');
const args = process.argv.slice(2);
if (args[0] !== '-extract' || args[2] !== 'raw' || args[3] !== '-o' || args[4] !== '-') process.exit(2);
let value = JSON.parse(fs.readFileSync(args[5], 'utf8'));
for (const part of args[1].split('.')) value = value[part !== '' && Number.isInteger(Number(part)) ? Number(part) : part];
process.stdout.write(String(Array.isArray(value) ? value.length : value) + '\\n');
`);
  chmodSync(shim, 0o755);
}

function fixture() {
  const root = mkdtempSync(join(tmpdir(), 'cruxwing-swiftpm-checkouts-'));
  const scratch = join(root, 'scratch');
  const checkout = join(scratch, 'checkouts', 'Example');
  const bin = join(root, 'bin');
  mkdirSync(checkout, { recursive: true });
  mkdirSync(bin);
  writePlutilShim(bin);

  assert.equal(run('git', ['init', '-q'], { cwd: checkout }).status, 0);
  writeFileSync(join(checkout, 'Source.swift'), 'let reviewed = true\n');
  writeFileSync(join(checkout, '.gitignore'), '*.pem\n');
  assert.equal(run('git', ['add', 'Source.swift', '.gitignore'], { cwd: checkout }).status, 0);
  assert.equal(run('git', [
    '-c', 'user.name=Cruxwing release test',
    '-c', 'user.email=release-test@invalid.example',
    'commit', '-qm', 'fixture',
  ], { cwd: checkout }).status, 0);
  const revision = run('git', ['rev-parse', 'HEAD'], { cwd: checkout }).stdout.trim();
  const resolved = join(root, 'Package.resolved');
  const state = join(scratch, 'workspace-state.json');
  writeFileSync(resolved, JSON.stringify({
    pins: [{ identity: 'example', state: { revision, version: '1.0.0' } }],
    version: 2,
  }));
  writeFileSync(state, JSON.stringify({
    object: { dependencies: [{
      packageRef: { identity: 'example', kind: 'remoteSourceControl' },
      state: { checkoutState: { revision }, name: 'sourceControlCheckout' },
      subpath: 'Example',
    }] },
  }));
  return {
    root, scratch, checkout, resolved, state, revision,
    env: { ...process.env, PATH: `${bin}:${process.env.PATH}` },
  };
}

test('SwiftPM checkout verifier rejects dirty source without exposing its contents', () => {
  const f = fixture();
  try {
    const clean = run('bash', [verifier, f.scratch, f.resolved], { env: f.env });
    assert.equal(clean.status, 0, clean.stderr);
    assert.match(clean.stdout, /1 verified/);

    const sentinel = 'SECRET-MUST-NOT-APPEAR-IN-OUTPUT';
    writeFileSync(join(f.checkout, 'Source.swift'), `${sentinel}\n`);
    const dirty = run('bash', [verifier, f.scratch, f.resolved], { env: f.env });
    assert.notEqual(dirty.status, 0, 'modified tracked dependency passed');
    assert.doesNotMatch(`${dirty.stdout}${dirty.stderr}`, new RegExp(sentinel));

    writeFileSync(join(f.checkout, 'Source.swift'), 'let reviewed = true\n');
    writeFileSync(join(f.checkout, 'Untracked.swift'), sentinel);
    const untracked = run('bash', [verifier, f.scratch, f.resolved], { env: f.env });
    assert.notEqual(untracked.status, 0, 'untracked dependency source passed');
    rmSync(join(f.checkout, 'Untracked.swift'));

    writeFileSync(join(f.checkout, 'private.pem'), sentinel);
    const ignored = run('bash', [verifier, f.scratch, f.resolved], { env: f.env });
    assert.notEqual(ignored.status, 0, 'ignored dependency input passed');
    assert.doesNotMatch(`${ignored.stdout}${ignored.stderr}`, new RegExp(sentinel));
    rmSync(join(f.checkout, 'private.pem'));

    assert.equal(run('git', ['update-index', '--assume-unchanged', 'Source.swift'], {
      cwd: f.checkout,
    }).status, 0);
    writeFileSync(join(f.checkout, 'Source.swift'), sentinel);
    const hiddenTracked = run('bash', [verifier, f.scratch, f.resolved], { env: f.env });
    assert.notEqual(hiddenTracked.status, 0,
      'assume-unchanged dependency source passed');
    assert.doesNotMatch(`${hiddenTracked.stdout}${hiddenTracked.stderr}`, new RegExp(sentinel));
  } finally {
    rmSync(f.root, { recursive: true, force: true });
  }
});

test('SwiftPM checkout verifier requires lockfile, workspace and HEAD to agree', () => {
  const f = fixture();
  try {
    writeFileSync(join(f.checkout, 'Source.swift'), 'let reviewed = false\n');
    assert.equal(run('git', ['add', 'Source.swift'], { cwd: f.checkout }).status, 0);
    assert.equal(run('git', [
      '-c', 'user.name=Cruxwing release test',
      '-c', 'user.email=release-test@invalid.example',
      'commit', '-qm', 'unreviewed',
    ], { cwd: f.checkout }).status, 0);
    const wrongHead = run('bash', [verifier, f.scratch, f.resolved], { env: f.env });
    assert.notEqual(wrongHead.status, 0, 'checkout at an unpinned commit passed');

    assert.equal(run('git', ['checkout', '-q', f.revision], { cwd: f.checkout }).status, 0);
    const state = JSON.parse(readFileSync(f.state, 'utf8'));
    state.object.dependencies[0].state.checkoutState.revision = '0'.repeat(40);
    writeFileSync(f.state, JSON.stringify(state));
    const wrongWorkspace = run('bash', [verifier, f.scratch, f.resolved], { env: f.env });
    assert.notEqual(wrongWorkspace.status, 0,
      'workspace state disagreeing with Package.resolved passed');
  } finally {
    rmSync(f.root, { recursive: true, force: true });
  }
});

test('DIST resolves pins and verifies the active scratch path around compilation', () => {
  const build = readFileSync(resolve(repo, 'app', 'build.sh'), 'utf8');
  assert.match(build,
    /env -u GIT_INDEX_FILE swift package "\$\{SWIFT_BUILD_ARGS\[@\]\}" \\\n+\s*--only-use-versions-from-resolved-file resolve/,
    'DIST no longer resolves strictly from Package.resolved');
  const swiftPMCommands = build.split('\n').filter(
    (line) => !line.trim().startsWith('#')
      && !line.trim().startsWith('echo ')
      && /\bswift (?:package|build)\b/.test(line),
  );
  assert.equal(swiftPMCommands.length, 4,
    'unexpected SwiftPM command entered build.sh; classify its alternate-index boundary');
  for (const command of swiftPMCommands) {
    assert.match(command, /env -u GIT_INDEX_FILE swift (?:package|build)\b/,
      'a root prospective index can corrupt a nested SwiftPM checkout index');
  }
  const firstVerify = build.indexOf('verify-swiftpm-checkouts.sh');
  const compile = build.indexOf('swift build "${SWIFT_BUILD_ARGS[@]}"');
  const secondVerify = build.indexOf('verify-swiftpm-checkouts.sh', firstVerify + 1);
  assert.ok(firstVerify >= 0 && compile > firstVerify && secondVerify > compile,
    'checkout verification must run both before and after the compiler');
  assert.match(build, /"\$SWIFT_SCRATCH" "\$ROOT\/Package\.resolved"/,
    'checkout verification no longer follows the active architecture scratch path');
  assert.doesNotMatch(build, /swift package[^\n]*\breset\b/,
    'DIST must inspect local state, not destructively reset it');
});
