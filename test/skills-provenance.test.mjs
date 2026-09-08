import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const root = join(repo, 'app', 'Sources', 'MeetGPT', 'Resources', 'Skills');
const manifest = JSON.parse(readFileSync(join(root, 'INGEST_MANIFEST.json'), 'utf8'));
const metadata = JSON.parse(readFileSync(join(root, 'skill-metadata.json'), 'utf8'));
const policy = JSON.parse(readFileSync(join(root, 'runtime-allowlist.json'), 'utf8'));
const records = new Map(manifest.skills.map((record) => [record.id, record]));
const reviews = new Map(policy.reviewed_skills.map((review) => [review.id, review]));
const liveIDs = readdirSync(root, { withFileTypes: true })
  .filter((entry) => entry.isDirectory()
    && existsSync(join(root, entry.name, 'SKILL.md')))
  .map((entry) => entry.name)
  .sort();
const licenseFiles = readdirSync(root)
  .filter((name) => /^LICENSE-.*\.txt$/.test(name))
  .sort();

const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');

function assertFullMITText(body, label) {
  assert.match(body, /^MIT License/m, `${label}: MIT heading missing`);
  assert.match(body, /copyright/i, `${label}: copyright notice missing`);
  assert.match(body, /Permission is hereby granted, free of charge/i,
    `${label}: MIT permission grant missing`);
  assert.match(body, /THE SOFTWARE IS PROVIDED ["“]AS IS["”]/i,
    `${label}: MIT warranty disclaimer missing`);
}

test('the shipped tree, provenance, metadata, and allowlist are one exact nine-skill set', () => {
  assert.equal(manifest.schema_version, 2);
  assert.equal(manifest.scope, 'shipped-runtime-reviewed-only');
  assert.equal(manifest.policy, 'runtime-allowlist.json');
  assert.equal(policy.default_decision, 'deny');
  assert.equal(manifest.shipped_skill_count, 9);
  assert.equal(policy.reviewed_skill_count, 9);

  const recordIDs = [...records.keys()].sort();
  const reviewIDs = [...reviews.keys()].sort();
  assert.equal(records.size, manifest.skills.length, 'duplicate provenance ids');
  assert.equal(reviews.size, policy.reviewed_skills.length, 'duplicate runtime review ids');
  assert.deepEqual(liveIDs, recordIDs);
  assert.deepEqual(liveIDs, Object.keys(metadata).sort());
  assert.deepEqual(liveIDs, reviewIDs);
  assert.deepEqual(
    readdirSync(root).filter((name) => name.endsWith('.json')).sort(),
    ['INGEST_MANIFEST.json', 'runtime-allowlist.json', 'skill-metadata.json'],
    'an ungoverned JSON prompt-data resource entered the skill bundle',
  );
});

test('every shipped skill has immutable, byte-matching source and review provenance', () => {
  const bad = [];
  for (const id of liveIDs) {
    const record = records.get(id);
    const review = reviews.get(id);
    if (!record || !review) {
      bad.push(`${id}: missing provenance or review`);
      continue;
    }
    if (!/^[^/\s]+\/[^/\s]+$/.test(record.repo ?? '')) bad.push(`${id}: invalid repo`);
    if (!/^[0-9a-f]{40}$/.test(record.source_commit ?? '')) bad.push(`${id}: invalid source commit`);
    if (!/^[0-9a-f]{64}$/.test(record.source_sha256 ?? '')) bad.push(`${id}: invalid source digest`);
    if (!record.source_path || record.source_path.startsWith('/')
        || record.source_path.split('/').includes('..')
        || record.source_path.includes('\\')) bad.push(`${id}: unsafe source path`);
    if (record.license !== 'MIT') bad.push(`${id}: unsupported license ${record.license}`);

    const actual = sha256(readFileSync(join(root, id, 'SKILL.md')));
    if (actual !== record.source_sha256) bad.push(`${id}: shipped bytes differ from provenance`);
    if (review.decision !== 'allow'
        || review.source_repo !== record.repo
        || review.source_commit !== record.source_commit
        || review.source_sha256 !== record.source_sha256
        || review.license !== record.license
        || !Array.isArray(review.prompt_ids)
        || review.prompt_ids.length === 0
        || !review.rationale?.trim()) {
      bad.push(`${id}: runtime review differs from provenance or has no scope/rationale`);
    }
    const entry = metadata[id];
    if (!entry?.domain?.trim() || !entry?.meeting_relevance?.trim() || !entry?.use_when?.trim()) {
      bad.push(`${id}: incomplete routing metadata`);
    }
  }
  assert.deepEqual(bad, [], `skills without publishable provenance:\n${bad.join('\n')}`);
});

test('every shipped skill pins an immutable, complete bundled MIT notice', () => {
  const referencedNotices = new Set();
  const sharedNoticeSources = new Map();

  for (const id of liveIDs) {
    const record = records.get(id);
    assert.equal(record.bundled_license_path, basename(record.bundled_license_path),
      `${id}: bundled notice must remain beside ATTRIBUTION.md`);
    assert.match(record.bundled_license_path, /^LICENSE-MIT-[A-Za-z0-9._-]+\.txt$/);
    assert.equal(record.license_repo, record.repo);
    assert.match(record.license_commit, /^[0-9a-f]{40}$/);
    assert.equal(record.license_path, 'LICENSE');
    assert.match(record.license_sha256, /^[0-9a-f]{64}$/);

    const noticePath = join(root, record.bundled_license_path);
    assert.ok(existsSync(noticePath), `${id}: bundled notice missing`);
    const bytes = readFileSync(noticePath);
    assert.equal(sha256(bytes), record.license_sha256, `${id}: bundled notice digest mismatch`);
    assertFullMITText(bytes.toString('utf8'), id);

    const source = JSON.stringify({
      repo: record.license_repo,
      commit: record.license_commit,
      path: record.license_path,
      sha256: record.license_sha256,
    });
    const previous = sharedNoticeSources.get(record.bundled_license_path);
    if (previous) assert.equal(source, previous, `${id}: shared notice has conflicting provenance`);
    else sharedNoticeSources.set(record.bundled_license_path, source);
    referencedNotices.add(record.bundled_license_path);
  }

  assert.deepEqual([...referencedNotices].sort(), licenseFiles,
    'license directory contains an unreferenced notice or omits a referenced one');
});
