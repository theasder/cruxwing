import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const manifest = readFileSync(
  resolve(repo, 'app', 'Support', 'PrivacyInfo.xcprivacy'), 'utf8');

function trackedSource(paths) {
  const files = execFileSync('git', [
    'ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', ...paths,
  ], {
    cwd: repo,
  }).toString('utf8').split('\0')
    .filter((file) => file.endsWith('.swift') && existsSync(resolve(repo, file)));
  return files.map((file) => readFileSync(resolve(repo, file), 'utf8')).join('\n');
}

function reasonsFor(category) {
  const escaped = category.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const entry = manifest.match(new RegExp(
    `<dict>\\s*<key>NSPrivacyAccessedAPIType</key>\\s*<string>${escaped}</string>`
      + `[\\s\\S]*?<key>NSPrivacyAccessedAPITypeReasons</key>\\s*<array>([\\s\\S]*?)</array>`
      + `[\\s\\S]*?</dict>`,
  ));
  assert.ok(entry, `privacy manifest omits ${category}`);
  return [...entry[1].matchAll(/<string>([^<]+)<\/string>/g)].map((match) => match[1]);
}

test('elapsed-time API use has the matching privacy-manifest reason', () => {
  const source = trackedSource(['app/Sources/MeetGPT', 'mvp/Sources/OrakulCore']);
  assert.match(source, /ProcessInfo\.processInfo\.systemUptime/,
    'source guard found no systemUptime use, so this test would protect nothing');
  assert.ok(reasonsFor('NSPrivacyAccessedAPICategorySystemBootTime').includes('35F9.1'),
    'systemUptime measures elapsed in-app time, which requires reason 35F9.1');
});

test('file metadata covers app-owned and explicitly selected folders', () => {
  const localNotes = readFileSync(
    resolve(repo, 'mvp', 'Sources', 'OrakulCore', 'LocalNotes.swift'), 'utf8');
  assert.match(localNotes, /contentModificationDateKey/,
    'source guard found no selected-folder metadata read');
  const reasons = reasonsFor('NSPrivacyAccessedAPICategoryFileTimestamp');
  assert.ok(reasons.includes('C617.1'), 'app-container file metadata lost reason C617.1');
  assert.ok(reasons.includes('3B52.1'),
    'metadata from a folder selected by the user requires reason 3B52.1');
});
