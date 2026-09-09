import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const skillsRoot = join(repo, 'app', 'Sources', 'MeetGPT', 'Resources', 'Skills');
const sbomPath = join(repo, 'app', 'Support', 'Legal', 'Cruxwing.cdx.json');
const sbom = JSON.parse(readFileSync(sbomPath, 'utf8'));
const manifest = JSON.parse(readFileSync(join(skillsRoot, 'INGEST_MANIFEST.json'), 'utf8'));
const metadata = JSON.parse(readFileSync(join(skillsRoot, 'skill-metadata.json'), 'utf8'));
const policy = JSON.parse(readFileSync(join(skillsRoot, 'runtime-allowlist.json'), 'utf8'));
const records = new Map(manifest.skills.map((record) => [record.id, record]));
const reviews = new Map(policy.reviewed_skills.map((review) => [review.id, review]));

function properties(component) {
  return new Map((component.properties ?? []).map((property) => [property.name, property.value]));
}

function licenseID(value) {
  if (/^MIT-0$/i.test(value)) return 'MIT-0';
  if (/^BSD-2-Clause(?:\s+license)?$/i.test(value)) return 'BSD-2-Clause';
  if (/^BSD-3-Clause(?:\s+license)?$/i.test(value)) return 'BSD-3-Clause';
  if (/Apache-2\.0/i.test(value)) return 'Apache-2.0';
  if (/\bMIT(?:\s+License)?\b/i.test(value)) return 'MIT';
  return undefined;
}

test('CycloneDX SBOM is deterministic, current and covered by the legal manifest', () => {
  const generated = spawnSync(process.execPath, ['scripts/generate-sbom.mjs', '--check'], {
    cwd: repo,
    encoding: 'utf8',
  });
  assert.equal(generated.status, 0, generated.stderr || generated.stdout);
  assert.equal(sbom.bomFormat, 'CycloneDX');
  assert.equal(sbom.specVersion, '1.6');
  assert.equal(sbom.metadata.component.name, 'cruxwing');
  assert.equal(sbom.metadata.component.type, 'application');

  const digest = createHash('sha256').update(readFileSync(sbomPath)).digest('hex');
  const legalManifest = readFileSync(join(repo, 'app', 'Support', 'Legal', 'MANIFEST.sha256'), 'utf8');
  assert.match(legalManifest, new RegExp(`^${digest}  Cruxwing\\.cdx\\.json$`, 'm'));
});

test('SBOM has unique components and a closed dependency graph', () => {
  const components = new Map(sbom.components.map((component) => [component['bom-ref'], component]));
  assert.equal(components.size, sbom.components.length, 'duplicate component bom-ref');
  assert.equal(sbom.components.length, 23);
  const refs = new Set([sbom.metadata.component['bom-ref'], ...components.keys()]);
  for (const edge of sbom.dependencies) {
    assert.ok(refs.has(edge.ref), `dependency source is absent: ${edge.ref}`);
    for (const target of edge.dependsOn) {
      assert.ok(refs.has(target), `dependency target is absent: ${target}`);
    }
  }
});

test('all nine shipped skills are provenance-pinned data components and runtime-approved', () => {
  const skillComponents = sbom.components.filter(
    (component) => properties(component).get('cruxwing:component-kind') === 'agent-skill',
  );
  assert.equal(skillComponents.length, manifest.shipped_skill_count);
  assert.equal(skillComponents.length, Object.keys(metadata).length);

  const seen = new Set();
  let allowed = 0;
  for (const component of skillComponents) {
    const id = component.name;
    const record = records.get(id);
    assert.ok(record, `${id}: no provenance record`);
    assert.ok(!seen.has(id), `${id}: duplicate skill component`);
    seen.add(id);
    assert.equal(component.type, 'data');
    assert.equal(component.group, record.repo);
    assert.equal(component.version, record.source_commit);
    assert.equal(component.hashes?.[0]?.alg, 'SHA-256');
    assert.equal(component.hashes?.[0]?.content, record.source_sha256);
    assert.equal(component.licenses?.[0]?.license?.id, licenseID(record.license));

    const props = properties(component);
    assert.equal(props.get('cruxwing:source-path'), record.source_path);
    assert.equal(props.get('cruxwing:catalog-domain'), metadata[id].domain);
    assert.equal(props.get('cruxwing:meeting-relevance'), metadata[id].meeting_relevance);
    const evidence = props.get('cruxwing:license-evidence');
    assert.match(evidence, /^MeetGPT_MeetGPT\.bundle\/Skills\/LICENSE-[A-Za-z0-9._-]+\.txt$/);
    assert.ok(existsSync(join(skillsRoot, evidence.split('/').at(-1))), `${id}: missing license evidence`);

    const review = reviews.get(id);
    assert.ok(review, `${id}: shipped without runtime review`);
    allowed += 1;
    assert.equal(props.get('cruxwing:runtime-decision'), 'allow');
    assert.equal(props.get('cruxwing:runtime-prompts'), [...review.prompt_ids].sort().join(','));
    assert.equal(review.source_sha256, record.source_sha256);
    assert.equal(review.source_commit, record.source_commit);
    assert.equal(review.source_repo, record.repo);
  }
  assert.equal(allowed, 9);
  assert.equal(allowed, policy.reviewed_skill_count);
});

test('SBOM distinguishes shipped Swift packages from resolved-only packages', () => {
  const shipped = sbom.components
    .filter((component) => properties(component).get('cruxwing:component-kind')
      === 'swiftpm-shipped-source-package')
    .map((component) => component.name)
    .sort();
  assert.deepEqual(shipped, [
    'eventsource',
    'fluidaudio',
    'swift-atomics',
    'swift-collections',
    'swift-log',
    'swift-nio',
    'swift-sdk',
    'swift-system',
    'whisperkit',
  ]);
  assert.ok(!sbom.components.some((component) => component.name === 'viewinspector'));
  assert.ok(sbom.components.some((component) => component.name.includes('fastcluster')));
  assert.ok(sbom.components.some((component) => component.name.includes('swift-transformers')));
});
