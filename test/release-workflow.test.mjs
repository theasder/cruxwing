import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import {
  cpSync,
  chmodSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const workflow = readFileSync(
  resolve(repo, '.github', 'workflows', 'release-candidate.yml'), 'utf8');
const ciWorkflow = readFileSync(
  resolve(repo, '.github', 'workflows', 'ci.yml'), 'utf8');
const releaseGate = readFileSync(resolve(repo, 'scripts', 'release-gate.sh'), 'utf8');

function executableYaml(source) {
  return source.split('\n').filter((line) => !line.trim().startsWith('#')).join('\n');
}

test('ordinary CI is read-only and never persists checkout credentials', () => {
  assert.match(ciWorkflow, /^permissions:\n\s+contents:\s*read\s*$/m,
    'ordinary CI lacks an explicit read-only token boundary');
  const checkouts = [...ciWorkflow.matchAll(/uses:\s*actions\/checkout@[0-9a-f]{40}/g)];
  assert.ok(checkouts.length > 0, 'ordinary CI has no checked checkout steps');
  for (const checkout of checkouts) {
    assert.match(ciWorkflow.slice(checkout.index, checkout.index + 220),
      /persist-credentials:\s*false/,
      'an ordinary CI checkout leaves repository credentials behind');
  }
});

function run(command, args, options = {}) {
  const env = { ...process.env };
  delete env.GIT_INDEX_FILE;
  Object.assign(env, options.env ?? {});
  return spawnSync(command, args, { encoding: 'utf8', ...options, env });
}

function git(root, ...args) {
  const env = { ...process.env };
  delete env.GIT_INDEX_FILE;
  return execFileSync('git', args, { cwd: root, encoding: 'utf8', env }).trim();
}

function write(root, relative, content) {
  const path = join(root, relative);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, content);
}

function releaseFixture({ tag = 'v1.2.3', version = '1.2.3', annotated = true } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'orakul-release-gate-'));
  const copies = [
    'scripts/release-gate.sh',
    'scripts/release-manifest.sh',
    'scripts/app-source-hash.sh',
    'scripts/source-hash.sh',
    'scripts/verify-swiftpm-checkouts.sh',
    'scripts/refresh-cask.sh',
    'scripts/scan-history-secrets.mjs',
    'packaging/homebrew/orakul.rb.template',
    'config/app.json',
  ];
  for (const relative of copies) {
    const target = join(root, relative);
    mkdirSync(dirname(target), { recursive: true });
    cpSync(join(repo, relative), target);
  }

  write(root, 'app/Support/Info.plist', `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleShortVersionString</key><string>${version}</string>
</dict></plist>
`);
  for (const relative of [
    'app/Package.swift',
    'app/Package.resolved',
    'app/build.sh',
    'app/Sources/MeetGPT/App.swift',
    'mvp/Package.swift',
    'mvp/Sources/OrakulCore/Core.swift',
  ]) write(root, relative, `fixture: ${relative}\n`);
  write(root, '.gitignore', 'release-candidate/\napp/dist/\n');
  write(root, 'config/history-secret-fixtures.json', '{"version":1,"fixtures":[]}\n');
  write(root, 'test-bin/node', `#!/bin/sh
exec "$ORAKUL_TEST_NODE" "$@"
`);
  chmodSync(join(root, 'test-bin', 'node'), 0o755);

  git(root, 'init', '-q', '-b', 'main');
  git(root, 'add', '-A');
  git(root, '-c', 'user.name=Orakul release test',
    '-c', 'user.email=release-test@invalid.example',
    'commit', '-qm', 'reviewed fixture');
  git(root, 'update-ref', 'refs/remotes/origin/main', 'HEAD');
  if (annotated) {
    git(root, '-c', 'user.name=Orakul release test',
      '-c', 'user.email=release-test@invalid.example',
      'tag', '-a', tag, '-m', `orakul ${tag}`);
  } else {
    git(root, 'tag', tag);
  }
  return root;
}

function fixtureEnv(root, extra = {}) {
  return {
    ...extra,
    ORAKUL_TEST_NODE: process.execPath,
    PATH: `${join(root, 'test-bin')}:${process.env.PATH ?? ''}`,
  };
}

test('release workflow prepares an attested candidate but cannot publish it', () => {
  const code = executableYaml(workflow);
  assert.match(code, /^\s+workflow_dispatch:/m,
    'candidate workflow is not an explicit owner action');
  assert.doesNotMatch(code, /^\s+(push|release):/m,
    'candidate workflow can start publication from a push/release event');
  assert.match(code, /^\s+environment:\s*release\s*$/m,
    'owner review environment is not attached to the release job');
  assert.match(code, /^\s+contents:\s*read\s*$/m,
    'workflow token can mutate repository contents');
  assert.doesNotMatch(code, /^\s+contents:\s*write\s*$/m);
  assert.match(code, /^\s+id-token:\s*write\s*$/m);
  assert.match(code, /^\s+attestations:\s*write\s*$/m);
  assert.match(code, /^\s+artifact-metadata:\s*write\s*$/m);
  assert.match(code, /fetch-depth:\s*0/);
  assert.match(code, /persist-credentials:\s*false/);
  assert.doesNotMatch(code, /git fetch[^\n]*origin[^\n]*main/,
    'private checkout tries an unauthenticated fetch after removing credentials');

  for (const forbidden of [
    /\bgh\s+release\b/,
    /\bgit\s+push\b/,
    /softprops\/action-gh-release/,
    /actions\/create-release/,
  ]) assert.doesNotMatch(code, forbidden, `workflow still publishes via ${forbidden}`);

  const identityGate = code.indexOf('EXPECTED_REPOSITORY');
  const checkout = code.indexOf('actions/checkout@');
  const build = code.indexOf('bash app/dist-all.sh');
  assert.ok(identityGate >= 0 && identityGate < checkout && checkout < build,
    'repository identity does not fail before source/credentials are used');
  assert.match(code, /GITHUB_REF[^\n]+refs\/tags\/\$RELEASE_TAG/,
    'workflow definition is not bound to the same tag as the candidate input');
});

test('workflow binds the tag to tests, both audited DMGs, checksums and signed provenance', () => {
  for (const command of [
    'bash scripts/release-gate.sh "$RELEASE_TAG"',
    'npm test',
    '(cd mvp && swift test)',
    '(cd app && swift test)',
    'bash app/dist-all.sh',
    'scripts/audit-dmg.sh',
    'scripts/release-manifest.sh',
    'subject-checksums:',
    'steps.attest.outputs.bundle-path',
    'actions/upload-artifact@',
  ]) assert.ok(workflow.includes(command), `release workflow omits ${command}`);
  assert.match(releaseGate, /node scripts\/scan-history-secrets\.mjs/,
    'tag gate no longer scans every reachable Git object before release');
  assert.doesNotMatch(releaseGate, /npm run audit:history/,
    'release trust gate can be redirected through a package script');

  for (const name of ['orakul-AppleSilicon.dmg', 'orakul-Intel.dmg']) {
    assert.ok(workflow.includes(name), `release workflow omits ${name}`);
  }

  const actions = [...workflow.matchAll(/uses:\s*[^@\s]+@([^\s#]+)/g)].map(([, ref]) => ref);
  assert.ok(actions.length >= 4, 'too few external actions for this workflow check');
  for (const ref of actions) {
    assert.match(ref, /^[0-9a-f]{40}$/,
      `external release action is mutable instead of commit-pinned: ${ref}`);
  }
});

test('only the owner supplies Apple release credentials; provider keys never enter CI', () => {
  const appleSecrets = [
    'APPLE_DEVELOPER_ID_P12_BASE64',
    'APPLE_DEVELOPER_ID_P12_PASSWORD',
    'APPLE_NOTARY_KEY_P8_BASE64',
    'APPLE_NOTARY_KEY_ID',
    'APPLE_NOTARY_ISSUER_ID',
  ];
  for (const secret of appleSecrets) {
    assert.match(workflow, new RegExp(`secrets\\.${secret}\\b`), `${secret} is not owner-supplied`);
  }
  assert.doesNotMatch(workflow, /(?:OPENAI|ANTHROPIC|GEMINI|DEEPSEEK|YANDEX|QWEN|ZHIPU|MOONSHOT).*secrets/i,
    'an AI-provider key is being requested by release CI');
  assert.match(workflow, /Remove ephemeral Apple credentials[\s\S]*?if:\s*always\(\)/,
    'ephemeral Apple credentials are not removed on failure');
});

test('Code Owners covers the release trust roots, including its own policy', () => {
  const policy = readFileSync(resolve(repo, '.github', 'CODEOWNERS'), 'utf8');
  assert.match(policy, /^\*\s+@theasder\s*$/m,
    'unlisted source or test files can bypass the sole release owner');
  for (const path of [
    '/.github/CODEOWNERS',
    '/.github/dependabot.yml',
    '/.github/workflows/',
    '/.nvmrc',
    '/LICENSE',
    '/SECURITY.md',
    '/package.json',
    '/config/app.json',
    '/config/history-secret-fixtures.json',
    '/docs/RELEASING.md',
    '/scripts/refresh-cask.sh',
    '/scripts/generate-sbom.mjs',
    '/scripts/scan-history-secrets.mjs',
    '/scripts/verify-swiftpm-checkouts.sh',
    '/app/assert-no-baked-secrets.sh',
    '/app/assert-no-env-values.sh',
    '/app/Package.resolved',
    '/app/Support/',
    '/app/Sources/MeetGPT/AI/BundledSkillRuntimePolicy.swift',
    '/app/Sources/MeetGPT/Resources/Skills/',
    '/test/dependency-maintenance.test.mjs',
    '/test/history-secrets.test.mjs',
    '/test/release-provenance.test.mjs',
    '/test/release-workflow.test.mjs',
    '/test/sbom.test.mjs',
    '/test/secrets.test.mjs',
    '/test/skills-provenance.test.mjs',
    '/test/swiftpm-checkout-provenance.test.mjs',
  ]) {
    const escaped = path.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    assert.match(policy, new RegExp(`^${escaped}\\s+@theasder\\s*$`, 'm'),
      `CODEOWNERS does not protect ${path}`);
  }
});

test('first-clone diagnostics and CI use one declared Node line and history gate', () => {
  const nvmrc = readFileSync(resolve(repo, '.nvmrc'), 'utf8').trim();
  const pkg = JSON.parse(readFileSync(resolve(repo, 'package.json'), 'utf8'));
  const ci = readFileSync(resolve(repo, '.github', 'workflows', 'ci.yml'), 'utf8');
  const doctor = readFileSync(resolve(repo, 'scripts', 'doctor.sh'), 'utf8');

  assert.equal(nvmrc, '22');
  assert.equal(pkg.engines?.node, '>=20');
  assert.equal(pkg.scripts?.doctor, 'bash scripts/doctor.sh');
  assert.equal(pkg.scripts?.['release:check'], 'bash scripts/release-gate.sh');
  assert.equal(pkg.scripts?.['audit:history'], 'node scripts/scan-history-secrets.mjs');
  assert.match(ci, /node-version-file:\s*\.nvmrc/);
  assert.match(ci, /npm run audit:history/);
  assert.doesNotMatch(doctor,
    /\b(?:curl|wget)\b|\b(?:brew|npm|pnpm|apt-get)\s+(?:install|ci)\b|swift package resolve/,
    'first-clone diagnosis installs or downloads instead of only diagnosing');
  assert.match(doctor, /пользователь вводит их сам в Settings → AI/);
});

test('release gate accepts only a clean annotated tag matching version and main ancestry', () => {
  const root = releaseFixture();
  try {
    const gate = run('bash', ['scripts/release-gate.sh', 'v1.2.3'], {
      cwd: root, env: fixtureEnv(root),
    });
    assert.equal(gate.status, 0, `${gate.stdout}\n${gate.stderr}`);
    assert.match(gate.stdout, /OK: чистый тег/);

    const sentinel = 'PRIVATE-LOCAL-VALUE-MUST-NOT-BE-PRINTED';
    writeFileSync(join(root, 'app', 'Package.swift'), sentinel);
    const dirty = run('bash', ['scripts/release-gate.sh', 'v1.2.3'], {
      cwd: root, env: fixtureEnv(root),
    });
    assert.notEqual(dirty.status, 0, 'dirty source passed the tag gate');
    assert.doesNotMatch(`${dirty.stdout}${dirty.stderr}`, new RegExp(sentinel));
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('release gate rejects lightweight tags, version drift and prospective indexes', () => {
  const lightweight = releaseFixture({ annotated: false });
  const drift = releaseFixture({ version: '1.2.4' });
  const indexed = releaseFixture();
  try {
    const light = run('bash', ['scripts/release-gate.sh', 'v1.2.3'], {
      cwd: lightweight, env: fixtureEnv(lightweight),
    });
    assert.notEqual(light.status, 0);
    assert.match(light.stderr, /lightweight tag/);

    const wrongVersion = run('bash', ['scripts/release-gate.sh', 'v1.2.3'], {
      cwd: drift, env: fixtureEnv(drift),
    });
    assert.notEqual(wrongVersion.status, 0);
    assert.match(wrongVersion.stderr, /CFBundleShortVersionString=1\.2\.4/);

    const alternateIndex = join(indexed, 'prospective.index');
    const prospective = run('bash', ['scripts/release-gate.sh', 'v1.2.3'], {
      cwd: indexed,
      env: fixtureEnv(indexed, { GIT_INDEX_FILE: alternateIndex }),
    });
    assert.notEqual(prospective.status, 0);
    assert.match(prospective.stderr, /GIT_INDEX_FILE/);
  } finally {
    for (const root of [lightweight, drift, indexed]) {
      rmSync(root, { recursive: true, force: true });
    }
  }
});

test('release gate rejects a tagged commit outside the reviewed origin/main history', () => {
  assert.doesNotMatch(releaseGate, /ORAKUL_RELEASE_BASE_REF/,
    'an environment variable can replace the reviewed release base');
  const root = releaseFixture();
  try {
    git(root, 'tag', '-d', 'v1.2.3');
    writeFileSync(join(root, 'app', 'Package.swift'), 'unreviewed release commit\n');
    git(root, 'add', 'app/Package.swift');
    git(root, '-c', 'user.name=Orakul release test',
      '-c', 'user.email=release-test@invalid.example',
      'commit', '-qm', 'not in reviewed remote base');
    git(root, '-c', 'user.name=Orakul release test',
      '-c', 'user.email=release-test@invalid.example',
      'tag', '-a', 'v1.2.3', '-m', 'unreviewed tag');

    const outside = run('bash', ['scripts/release-gate.sh', 'v1.2.3'], {
      cwd: root, env: fixtureEnv(root),
    });
    assert.notEqual(outside.status, 0);
    assert.match(outside.stderr, /не принадлежит истории origin\/main/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('release manifest verifies sidecars and emits one self-consistent candidate', () => {
  const root = releaseFixture();
  try {
    const dist = join(root, 'app', 'dist');
    mkdirSync(dist, { recursive: true });
    for (const [name, body] of [
      ['orakul-AppleSilicon.dmg', 'arm candidate'],
      ['orakul-Intel.dmg', 'intel candidate'],
    ]) {
      const path = join(dist, name);
      writeFileSync(path, body);
      const line = execFileSync('shasum', ['-a', '256', name], {
        cwd: dist,
        encoding: 'utf8',
      });
      writeFileSync(`${path}.sha256`, line);
    }

    const output = join(root, 'release-candidate', 'v1.2.3');
    const manifest = run('bash', [
      'scripts/release-manifest.sh', 'v1.2.3', 'app/dist', output,
    ], { cwd: root, env: fixtureEnv(root) });
    assert.equal(manifest.status, 0, `${manifest.stdout}\n${manifest.stderr}`);

    const verified = run('shasum', ['-a', '256', '-c', 'SHA256SUMS'], { cwd: output });
    assert.equal(verified.status, 0, verified.stderr);
    const sums = readFileSync(join(output, 'SHA256SUMS'), 'utf8');
    for (const name of [
      'orakul-AppleSilicon.dmg', 'orakul-Intel.dmg', 'orakul.rb', 'provenance.json',
    ]) assert.match(sums, new RegExp(`  ${name.replace('.', '\\.')}$`, 'm'));

    const provenance = JSON.parse(readFileSync(join(output, 'provenance.json'), 'utf8'));
    assert.equal(provenance.tag, 'v1.2.3');
    assert.equal(provenance.version, '1.2.3');
    assert.match(provenance.commit, /^[0-9a-f]{40}$/);
    assert.match(provenance.sourceSha256, /^[0-9a-f]{64}$/);
    assert.equal(provenance.claims.notReproducibilityProof, true);
    assert.deepEqual(provenance.artifacts.map(({ name }) => name),
      ['orakul-AppleSilicon.dmg', 'orakul-Intel.dmg', 'orakul.rb']);

    const repeated = run('bash', [
      'scripts/release-manifest.sh', 'v1.2.3', 'app/dist', output,
    ], { cwd: root, env: fixtureEnv(root) });
    assert.notEqual(repeated.status, 0, 'a stale candidate directory was silently reused');
    assert.match(repeated.stderr, /уже существует/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('release manifest rejects a mismatched sidecar before creating output', () => {
  const root = releaseFixture();
  try {
    const dist = join(root, 'app', 'dist');
    mkdirSync(dist, { recursive: true });
    for (const [name, body] of [
      ['orakul-AppleSilicon.dmg', 'arm candidate'],
      ['orakul-Intel.dmg', 'intel candidate'],
    ]) writeFileSync(join(dist, name), body);
    writeFileSync(join(dist, 'orakul-AppleSilicon.dmg.sha256'),
      `${'0'.repeat(64)}  orakul-AppleSilicon.dmg\n`);
    writeFileSync(join(dist, 'orakul-Intel.dmg.sha256'),
      `${'0'.repeat(64)}  orakul-Intel.dmg\n`);

    const output = join(root, 'release-candidate', 'v1.2.3');
    const rejected = run('bash', [
      'scripts/release-manifest.sh', 'v1.2.3', 'app/dist', output,
    ], { cwd: root, env: fixtureEnv(root) });
    assert.notEqual(rejected.status, 0);
    assert.match(rejected.stderr, /не подтверждает байты/);
    assert.equal(run('test', ['!', '-e', output]).status, 0,
      'failed checksum verification left a candidate directory');
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('release documentation states every external owner action and verification limit', () => {
  const docs = readFileSync(resolve(repo, 'docs', 'RELEASING.md'), 'utf8');
  for (const phrase of [
    'does not create a GitHub Release',
    '`release` Environment',
    'a mandatory reviewer',
    'Private Vulnerability Reporting',
    'enters their own key in **Settings \u2192 AI \u2192 Provider keys**',
    'private and internal ones only on Enterprise Cloud',
    'does not prove',
    'shasum -a 256 -c SHA256SUMS',
    'gh attestation verify',
    '--source-ref refs/tags/v0.2.0',
    '--deny-self-hosted-runners',
    'gh workflow run release-candidate.yml --ref v0.2.0 -f tag=v0.2.0',
    '--verify-tag --draft',
  ]) assert.ok(docs.includes(phrase), `release docs omit: ${phrase}`);
});
