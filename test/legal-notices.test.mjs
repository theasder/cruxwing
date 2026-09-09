import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const legalRoot = resolve(repo, 'app', 'Support', 'Legal');

const expectedFiles = [
  'FluidAudio/LICENSE',
  'FluidAudio/fastcluster-LICENSE.md',
  'FluidAudio/vbx-LICENSE.md',
  'Cruxwing/LICENSE',
  'Cruxwing.cdx.json',
  'WhisperKit/LICENSE',
  'WhisperKit/NOTICES',
  'eventsource/LICENSE.md',
  'swift-atomics/LICENSE.txt',
  'swift-collections/LICENSE.txt',
  'swift-log/LICENSE.txt',
  'swift-log/NOTICE.txt',
  'swift-nio/LICENSE.txt',
  'swift-nio/NOTICE.txt',
  'swift-sdk/LICENSE',
  'swift-system/LICENSE.txt',
];

const shippedPins = new Map([
  ['eventsource', ['1.4.1', 'a3a85a85214caf642abaa96ae664e4c772a59f6e']],
  ['fluidaudio', ['0.15.5', '19600a485baa4998812e4654b70d2bab8f2c9949']],
  ['swift-atomics', ['1.3.1', '0442cb5a3f98ab802acb777929fdb446bda11a34']],
  ['swift-collections', ['1.6.0', 'a0cb0954ecb21e4e31b0070e6ed5674e8556685a']],
  ['swift-log', ['1.14.0', 'a878e7f8f46cfc0e1125e565b5c08e7d5272dc9a']],
  ['swift-nio', ['2.101.2', 'cd3e1152083706d77b223fb29110e590efcc70c0']],
  ['swift-sdk', ['0.12.1', 'a0ae212ebf6eab5f754c3129608bc5557637e605']],
  ['swift-system', ['1.7.2', '7502b711c92a17741fa625d722b0ccbd595d8ed1']],
  ['whisperkit', ['1.0.0', '25c62997041c134b03ca82731ce2f6fd2cae1eb9']],
]);

// These resolve for disabled traits, executable/test targets, or dependencies
// of those targets, but targetDependencyMap for the shipped MeetGPT executable
// does not contain their modules. A new identity must be classified explicitly
// instead of silently shipping without a notice review.
const resolvedButNotShipped = [
  'async-http-client',
  'swift-algorithms',
  'swift-argument-parser',
  'swift-asn1',
  'swift-async-algorithms',
  'swift-certificates',
  'swift-crypto',
  'swift-distributed-tracing',
  'swift-http-structured-headers',
  'swift-http-types',
  'swift-nio-extras',
  'swift-nio-http2',
  'swift-nio-ssl',
  'swift-nio-transport-services',
  'swift-numerics',
  'swift-service-context',
  'swift-service-lifecycle',
  'viewinspector',
];

function legalManifest() {
  const lines = readFileSync(resolve(legalRoot, 'MANIFEST.sha256'), 'utf8')
    .trim().split('\n');
  return lines.map((line) => {
    const match = /^([0-9a-f]{64})  ([A-Za-z0-9._/-]+)$/.exec(line);
    assert.ok(match, `invalid legal manifest line: ${line}`);
    assert.ok(!match[2].startsWith('/') && !match[2].split('/').includes('..'),
      `unsafe legal manifest path: ${match[2]}`);
    return { hash: match[1], path: match[2] };
  });
}

test('tracked legal payload is the exact nonempty matrix for the shipped target', () => {
  const entries = legalManifest();
  assert.deepEqual(entries.map((entry) => entry.path), expectedFiles);
  for (const entry of entries) {
    const file = resolve(legalRoot, entry.path);
    assert.ok(existsSync(file), `missing legal payload: ${entry.path}`);
    assert.ok(statSync(file).size > 0, `empty legal payload: ${entry.path}`);
    const actual = createHash('sha256').update(readFileSync(file)).digest('hex');
    assert.equal(actual, entry.hash, `changed legal snapshot: ${entry.path}`);
  }
  assert.deepEqual(
    readFileSync(resolve(legalRoot, 'Cruxwing', 'LICENSE')),
    readFileSync(resolve(repo, 'LICENSE')),
    'the license inside the app no longer matches Cruxwing itself',
  );
});

test('resolved production dependencies stay pinned to the reviewed notice set', () => {
  const resolved = JSON.parse(readFileSync(resolve(repo, 'app', 'Package.resolved'), 'utf8'));
  const pins = new Map(resolved.pins.map((pin) => [pin.identity, pin.state]));
  const classified = [...shippedPins.keys(), ...resolvedButNotShipped].sort();
  assert.deepEqual([...pins.keys()].sort(), classified,
    'Package.resolved changed; classify the new/removed dependency before release');
  for (const [identity, [version, revision]] of shippedPins) {
    assert.equal(pins.get(identity)?.version, version, `${identity} version changed`);
    assert.equal(pins.get(identity)?.revision, revision,
      `${identity} revision changed; refresh its exact legal snapshots`);
  }
});

test('the executable cannot link a resolved test/trait package without notice review', () => {
  // A Package.resolved guard alone is insufficient: MeetGPT could start linking
  // AsyncHTTPClient (already resolved for EventSource's disabled trait), for
  // example, without changing a single pin. Classify the root executable's
  // direct products here; pinned revisions then make their transitive closure
  // stable until the revision guard above forces another review.
  const manifest = readFileSync(resolve(repo, 'app', 'Package.swift'), 'utf8');
  const targetStart = manifest.indexOf('.executableTarget(');
  const targetEnd = manifest.indexOf('.testTarget(', targetStart);
  assert.ok(targetStart >= 0 && targetEnd > targetStart,
    'could not isolate the shipped executable target in Package.swift');
  const target = manifest.slice(targetStart, targetEnd);
  const dependencyList = /dependencies:\s*\[([\s\S]*?)\]\s*,\s*path:/.exec(target)?.[1];
  assert.ok(dependencyList, 'could not isolate MeetGPT target dependencies');
  const code = dependencyList.replace(/\/\/.*$/gm, '');
  const products = [...code.matchAll(
    /\.product\(\s*name:\s*"([^"]+)"\s*,\s*package:\s*"([^"]+)"\s*\)/g,
  )].map((match) => `${match[1]}@${match[2]}`).sort();
  assert.deepEqual(products, [
    'CruxwingCore@mvp',
    'FluidAudio@FluidAudio',
    'MCP@swift-sdk',
    'WhisperKit@WhisperKit',
  ]);

  const unexplained = code.replace(/\.product\([\s\S]*?\)/g, '').replace(/[\s,]/g, '');
  assert.equal(unexplained, '',
    `unclassified MeetGPT target dependency: ${unexplained}`);
});

test('the app build copies the verified legal directory into the signed bundle', () => {
  const script = readFileSync(resolve(repo, 'app', 'build.sh'), 'utf8');
  const code = script.split('\n')
    .filter((line) => !line.trim().startsWith('#')).join('\n');
  assert.match(code, /shasum -a 256 -c MANIFEST\.sha256/,
    'build no longer verifies legal snapshot hashes');
  assert.match(code,
    /cp -R "\$LEGAL" "\$STAGE\/Contents\/Resources\/Legal"/,
    'build no longer puts the legal payload in the signed app');
});
