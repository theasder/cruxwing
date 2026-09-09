import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..');

function run(command, args, options = {}) {
  // Publication checks can themselves run under a temporary prospective
  // index. Fixture repositories must use their own index, not the caller's.
  const env = { ...process.env, ...(options.env ?? {}) };
  delete env.GIT_INDEX_FILE;
  return spawnSync(command, args, {
    encoding: 'utf8',
    ...options,
    env,
  });
}

function cleanTreeGuardSource() {
  const build = readFileSync(resolve(repo, 'app', 'build.sh'), 'utf8');
  const match = /(DIST_TREE_STATE="development"[\s\S]*?\nrequire_clean_dist_tree \|\| exit 1\n)/.exec(build);
  assert.ok(match, 'could not isolate the DIST clean-tree guard from build.sh');
  return match[1];
}

test('DIST refuses dirty or unversioned source and the local override stays auditable', () => {
  const root = mkdtempSync(join(tmpdir(), 'cruxwing-dist-provenance-'));
  const app = join(root, 'app');
  const sourceRoot = join(app, 'Sources', 'MeetGPT');
  mkdirSync(sourceRoot, { recursive: true });
  try {
    assert.equal(run('git', ['init', '-q'], { cwd: root }).status, 0);
    writeFileSync(join(root, 'tracked.txt'), 'committed\n');
    writeFileSync(join(root, '.gitignore'), [
      '*.pem',
      'app/Sources/MeetGPT/LocalSecrets.generated.swift',
      '',
    ].join('\n'));
    assert.equal(run('git', ['add', 'tracked.txt', '.gitignore'], { cwd: root }).status, 0);
    assert.equal(run('git', [
      '-c', 'user.name=Cruxwing release test',
      '-c', 'user.email=release-test@invalid.example',
      'commit', '-qm', 'fixture',
    ], { cwd: root }).status, 0);

    const probe = `${cleanTreeGuardSource()}\nprintf 'STATE=%s\\n' "$DIST_TREE_STATE"\n`;
    const baseEnv = { ...process.env, DIST: '1', ROOT: app };

    const clean = run('bash', ['-c', probe], { cwd: root, env: baseEnv });
    assert.equal(clean.status, 0, clean.stderr);
    assert.match(clean.stdout, /STATE=clean/);

    const sentinel = 'SECRET-VALUE-MUST-NEVER-APPEAR-IN-LOGS';
    writeFileSync(join(root, 'tracked.txt'), `${sentinel}\n`);
    const dirty = run('bash', ['-c', probe], { cwd: root, env: baseEnv });
    assert.notEqual(dirty.status, 0, 'dirty tracked source passed the DIST guard');
    assert.doesNotMatch(`${dirty.stdout}${dirty.stderr}`, new RegExp(sentinel),
      'the provenance failure printed file contents');

    const overridden = run('bash', ['-c', probe], {
      cwd: root,
      env: { ...baseEnv, CRUXWING_ALLOW_DIRTY_DIST_FOR_LOCAL_VERIFICATION: '1' },
    });
    assert.equal(overridden.status, 0, overridden.stderr);
    assert.match(overridden.stdout, /STATE=dirty-local-verification/);

    writeFileSync(join(root, 'tracked.txt'), 'committed\n');

    assert.equal(run('git', ['update-index', '--assume-unchanged', 'tracked.txt'], {
      cwd: root,
    }).status, 0);
    writeFileSync(join(root, 'tracked.txt'), sentinel);
    const hiddenTracked = run('bash', ['-c', probe], { cwd: root, env: baseEnv });
    assert.notEqual(hiddenTracked.status, 0,
      'an assume-unchanged tracked file passed the DIST guard');
    assert.doesNotMatch(`${hiddenTracked.stdout}${hiddenTracked.stderr}`, new RegExp(sentinel));
    assert.equal(run('git', ['update-index', '--no-assume-unchanged', 'tracked.txt'], {
      cwd: root,
    }).status, 0);
    writeFileSync(join(root, 'tracked.txt'), 'committed\n');

    // The generated local config is ignored but DIST does not compile it, so
    // a developer's prior local build must not make release verification
    // impossible. It is the only ignored exception inside artifact roots.
    writeFileSync(join(sourceRoot, 'LocalSecrets.generated.swift'), sentinel);
    const generated = run('bash', ['-c', probe], { cwd: root, env: baseEnv });
    assert.equal(generated.status, 0, generated.stderr);
    assert.match(generated.stdout, /STATE=clean/);

    const ignoredSecret = join(sourceRoot, 'private.pem');
    writeFileSync(ignoredSecret, sentinel);
    const ignored = run('bash', ['-c', probe], { cwd: root, env: baseEnv });
    assert.notEqual(ignored.status, 0, 'ignored file in a copied source root passed');
    assert.doesNotMatch(`${ignored.stdout}${ignored.stderr}`, new RegExp(sentinel));
    rmSync(ignoredSecret);

    const untrackedSource = join(sourceRoot, 'Untracked.swift');
    writeFileSync(untrackedSource, sentinel);
    const untrackedArtifact = run('bash', ['-c', probe], { cwd: root, env: baseEnv });
    assert.notEqual(untrackedArtifact.status, 0,
      'untracked file in a compiled source root passed');
    const overriddenArtifact = run('bash', ['-c', probe], {
      cwd: root,
      env: { ...baseEnv, CRUXWING_ALLOW_DIRTY_DIST_FOR_LOCAL_VERIFICATION: '1' },
    });
    assert.notEqual(overriddenArtifact.status, 0,
      'the local override admitted an untracked artifact input');
    rmSync(untrackedSource);

    writeFileSync(join(root, 'untracked.txt'), sentinel);
    const untracked = run('bash', ['-c', probe], { cwd: root, env: baseEnv });
    assert.notEqual(untracked.status, 0, 'untracked source passed the DIST guard');
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('a dirty local-verification artifact cannot pass the DMG audit', () => {
  const build = readFileSync(resolve(repo, 'app', 'build.sh'), 'utf8');
  const audit = readFileSync(resolve(repo, 'scripts', 'audit-dmg.sh'), 'utf8');
  assert.match(build, /CruxwingTreeState string \$DIST_TREE_STATE/,
    'build.sh no longer stamps the verified worktree state');
  assert.match(audit, /\[ "\$stamped_tree_state" = "clean" \]/,
    'audit-dmg.sh no longer requires the clean-tree stamp');
  assert.match(audit, /local-verification artifacts cannot pass the release audit/,
    'the local override is no longer visibly excluded from release');
});
