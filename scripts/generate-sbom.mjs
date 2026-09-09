#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const skillsRoot = join(repo, 'app', 'Sources', 'MeetGPT', 'Resources', 'Skills');
const output = join(repo, 'app', 'Support', 'Legal', 'Cruxwing.cdx.json');
const checkOnly = process.argv.includes('--check');

const manifest = JSON.parse(readFileSync(join(skillsRoot, 'INGEST_MANIFEST.json'), 'utf8'));
const metadata = JSON.parse(readFileSync(join(skillsRoot, 'skill-metadata.json'), 'utf8'));
const runtimePolicy = JSON.parse(readFileSync(join(skillsRoot, 'runtime-allowlist.json'), 'utf8'));
const resolvedPackages = JSON.parse(readFileSync(join(repo, 'app', 'Package.resolved'), 'utf8'));
const infoPlist = readFileSync(join(repo, 'app', 'Support', 'Info.plist'), 'utf8');

const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');
const sourceRecords = new Map(manifest.skills.map((record) => [record.id, record]));
const reviews = new Map(runtimePolicy.reviewed_skills.map((review) => [review.id, review]));
const encodePath = (value) => value.split('/').map(encodeURIComponent).join('/');

function fail(message) {
  throw new Error(`SBOM generation refused: ${message}`);
}

function plistValue(key) {
  const escaped = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = new RegExp(`<key>${escaped}</key>\\s*<string>([^<]+)</string>`).exec(infoPlist);
  if (!match) fail(`${key} is missing from Info.plist`);
  return match[1];
}

function spdxLicense(value) {
  const normalized = value?.trim() ?? '';
  if (/^MIT-0$/i.test(normalized)) return 'MIT-0';
  if (/^BSD-2-Clause(?:\s+license)?$/i.test(normalized)) return 'BSD-2-Clause';
  if (/^BSD-3-Clause(?:\s+license)?$/i.test(normalized)) return 'BSD-3-Clause';
  if (/Apache-2\.0/i.test(normalized)) return 'Apache-2.0';
  if (/\bMIT(?:\s+License)?\b/i.test(normalized)) return 'MIT';
  fail(`unsupported skill license expression: ${normalized}`);
}

function noticeFor(record, licenseID) {
  const notice = record.bundled_license_path;
  if (!notice || notice !== notice.split('/').at(-1)
      || !/^LICENSE-[A-Za-z0-9._-]+\.txt$/.test(notice)
      || !existsSync(join(skillsRoot, notice))) {
    fail(`${record.id} has no concrete bundled license evidence`);
  }
  const bytes = readFileSync(join(skillsRoot, notice));
  if (!/^[0-9a-f]{64}$/.test(record.license_sha256 ?? '')
      || sha256(bytes) !== record.license_sha256) {
    fail(`${record.id} bundled license differs from immutable provenance`);
  }
  if (record.license_repo !== record.repo
      || !/^[0-9a-f]{40}$/.test(record.license_commit ?? '')
      || record.license_path !== 'LICENSE') {
    fail(`${record.id} license source is incomplete`);
  }
  return `MeetGPT_MeetGPT.bundle/Skills/${notice}`;
}

function upstreamRisk(markdown) {
  const frontmatter = /^---\s*\n([\s\S]*?)\n---/.exec(markdown)?.[1] ?? '';
  const value = /^risk:\s*["']?([^\n"']+)/m.exec(frontmatter)?.[1]?.trim();
  return value || 'unspecified';
}

function property(name, value) {
  return { name, value: String(value) };
}

const liveSkills = Object.keys(metadata).sort();
if (manifest.schema_version !== 2
    || manifest.scope !== 'shipped-runtime-reviewed-only'
    || manifest.policy !== 'runtime-allowlist.json') {
  fail('unsupported or non-runtime provenance scope');
}
if (liveSkills.length !== manifest.shipped_skill_count
    || liveSkills.length !== sourceRecords.size) {
  fail(`provenance says ${manifest.shipped_skill_count} shipped skills; metadata has ${liveSkills.length}`);
}
if (new Set(runtimePolicy.reviewed_skills.map((review) => review.id)).size !== reviews.size
    || reviews.size !== runtimePolicy.reviewed_skill_count) {
  fail('runtime allowlist count or uniqueness is stale');
}
if (liveSkills.length !== reviews.size
    || liveSkills.some((id) => !reviews.has(id))
    || [...sourceRecords.keys()].some((id) => !metadata[id])) {
  fail('shipped skills, provenance, metadata, and runtime reviews are not the same set');
}

const skillComponents = liveSkills.map((id) => {
  const record = sourceRecords.get(id);
  if (!record) fail(`${id} is missing from INGEST_MANIFEST.json`);
  const filename = join(skillsRoot, id, 'SKILL.md');
  if (!existsSync(filename)) fail(`${id}/SKILL.md is missing`);
  const bytes = readFileSync(filename);
  if (sha256(bytes) !== record.source_sha256) fail(`${id} differs from source_sha256`);
  const licenseID = spdxLicense(record.license);
  const review = reviews.get(id);
  if (!review) fail(`${id} is shipped without runtime review`);
  if (review.source_sha256 !== record.source_sha256
      || review.source_commit !== record.source_commit
      || review.source_repo !== record.repo
      || spdxLicense(review.license) !== licenseID) {
    fail(`${id} runtime review differs from provenance`);
  }
  const upstreamURL = `https://github.com/${record.repo}/blob/${record.source_commit}/${encodePath(record.source_path)}`;
  return {
    type: 'data',
    'bom-ref': `cruxwing:agent-skill:${id}@sha256:${record.source_sha256}`,
    group: record.repo,
    name: id,
    version: record.source_commit,
    hashes: [{ alg: 'SHA-256', content: record.source_sha256 }],
    licenses: [{ license: { id: licenseID } }],
    externalReferences: [
      { type: 'vcs', url: `https://github.com/${record.repo}/tree/${record.source_commit}` },
      { type: 'distribution', url: upstreamURL },
    ],
    properties: [
      property('cruxwing:component-kind', 'agent-skill'),
      property('cruxwing:source-path', record.source_path),
      property('cruxwing:license-declaration', record.license),
      property('cruxwing:license-evidence', noticeFor(record, licenseID)),
      property('cruxwing:catalog-domain', metadata[id].domain),
      property('cruxwing:meeting-relevance', metadata[id].meeting_relevance),
      property('cruxwing:upstream-risk', upstreamRisk(bytes.toString('utf8'))),
      property('cruxwing:runtime-decision', 'allow'),
      property('cruxwing:runtime-prompts', [...review.prompt_ids].sort().join(',')),
    ],
  };
});

const shippedSwift = new Map([
  ['eventsource', { license: 'MIT', notice: 'eventsource/LICENSE.md' }],
  ['fluidaudio', { license: 'Apache-2.0 AND BSD-2-Clause', notice: 'FluidAudio/LICENSE' }],
  ['swift-atomics', { license: 'Apache-2.0', notice: 'swift-atomics/LICENSE.txt' }],
  ['swift-collections', { license: 'Apache-2.0', notice: 'swift-collections/LICENSE.txt' }],
  ['swift-log', { license: 'Apache-2.0', notice: 'swift-log/LICENSE.txt' }],
  ['swift-nio', { license: 'Apache-2.0', notice: 'swift-nio/LICENSE.txt' }],
  ['swift-sdk', { license: 'Apache-2.0 OR MIT', notice: 'swift-sdk/LICENSE' }],
  ['swift-system', { license: 'Apache-2.0', notice: 'swift-system/LICENSE.txt' }],
  ['whisperkit', { license: 'MIT AND Apache-2.0', notice: 'WhisperKit/LICENSE' }],
]);
const pins = new Map(resolvedPackages.pins.map((pin) => [pin.identity, pin]));
const swiftComponents = [...shippedSwift].map(([identity, legal]) => {
  const pin = pins.get(identity);
  if (!pin?.state?.revision || !pin?.state?.version) fail(`${identity} has no pinned version/revision`);
  if (!existsSync(join(repo, 'app', 'Support', 'Legal', legal.notice))) {
    fail(`${identity} legal evidence is missing`);
  }
  const github = /^https:\/\/github\.com\/([^/]+\/[^/]+?)(?:\.git)?$/.exec(pin.location)?.[1];
  if (!github) fail(`${identity} is not a pinned GitHub source`);
  return {
    type: 'library',
    'bom-ref': `cruxwing:swiftpm:${identity}@${pin.state.revision}`,
    name: identity,
    version: pin.state.version,
    purl: `pkg:github/${github}@${pin.state.revision}`,
    licenses: [{ expression: legal.license }],
    externalReferences: [
      { type: 'vcs', url: `https://github.com/${github}/tree/${pin.state.revision}` },
    ],
    properties: [
      property('cruxwing:component-kind', 'swiftpm-shipped-source-package'),
      property('cruxwing:source-revision', pin.state.revision),
      property('cruxwing:license-evidence', `Legal/${legal.notice}`),
    ],
  };
});

const embeddedComponents = [
  {
    type: 'library',
    'bom-ref': 'cruxwing:embedded:fluidaudio-fastcluster',
    name: 'fastcluster (embedded by FluidAudio)',
    licenses: [{ license: { id: 'BSD-2-Clause' } }],
    properties: [property('cruxwing:license-evidence', 'Legal/FluidAudio/fastcluster-LICENSE.md')],
  },
  {
    type: 'library',
    'bom-ref': 'cruxwing:embedded:fluidaudio-vbx',
    name: 'VBx (embedded by FluidAudio)',
    licenses: [{ license: { id: 'Apache-2.0' } }],
    properties: [property('cruxwing:license-evidence', 'Legal/FluidAudio/vbx-LICENSE.md')],
  },
  {
    type: 'library',
    'bom-ref': 'cruxwing:embedded:whisperkit-swift-transformers',
    name: 'swift-transformers-derived sources (embedded by WhisperKit)',
    licenses: [{ license: { id: 'Apache-2.0' } }],
    externalReferences: [{ type: 'vcs', url: 'https://github.com/huggingface/swift-transformers' }],
    properties: [property('cruxwing:license-evidence', 'Legal/WhisperKit/NOTICES')],
  },
];

const appVersion = plistValue('CFBundleShortVersionString');
const catalogHash = sha256(readFileSync(join(skillsRoot, 'INGEST_MANIFEST.json')));
const catalogRef = `cruxwing:agent-skills-bundle@sha256:${catalogHash}`;
const appRef = `cruxwing:application@${appVersion}`;
const coreRef = `cruxwing:core@${appVersion}`;
const catalogComponent = {
  type: 'data',
  'bom-ref': catalogRef,
  name: 'Cruxwing reviewed Agent Skills bundle',
  version: catalogHash,
  hashes: [{ alg: 'SHA-256', content: catalogHash }],
  properties: [
    property('cruxwing:skill-bundle-count', liveSkills.length),
    property('cruxwing:runtime-reviewed-count', reviews.size),
    property('cruxwing:runtime-default-decision', runtimePolicy.default_decision),
    property('cruxwing:provenance-source', 'MeetGPT_MeetGPT.bundle/Skills/INGEST_MANIFEST.json'),
    property('cruxwing:runtime-policy-source', 'MeetGPT_MeetGPT.bundle/Skills/runtime-allowlist.json'),
  ],
};

const bom = {
  $schema: 'https://cyclonedx.org/schema/bom-1.6.schema.json',
  bomFormat: 'CycloneDX',
  specVersion: '1.6',
  version: 1,
  metadata: {
    component: {
      type: 'application',
      'bom-ref': appRef,
      name: 'cruxwing',
      version: appVersion,
      licenses: [{ license: { id: 'Apache-2.0' } }],
      externalReferences: [{ type: 'vcs', url: 'https://github.com/theasder/cruxwing' }],
      properties: [
        property('cruxwing:bundle-id', plistValue('CFBundleIdentifier')),
        property('cruxwing:sbom-scope', 'shipped macOS application inputs'),
      ],
    },
  },
  components: [
    {
      type: 'library',
      'bom-ref': coreRef,
      name: 'CruxwingCore',
      version: appVersion,
      licenses: [{ license: { id: 'Apache-2.0' } }],
      properties: [property('cruxwing:component-kind', 'local-swift-package')],
    },
    ...swiftComponents,
    ...embeddedComponents,
    catalogComponent,
    ...skillComponents,
  ],
  dependencies: [
    {
      ref: appRef,
      dependsOn: [
        coreRef,
        catalogRef,
        ...swiftComponents.map((component) => component['bom-ref']),
      ].sort(),
    },
    { ref: coreRef, dependsOn: [] },
    {
      ref: swiftComponents.find((component) => component.name === 'fluidaudio')['bom-ref'],
      dependsOn: ['cruxwing:embedded:fluidaudio-fastcluster', 'cruxwing:embedded:fluidaudio-vbx'],
    },
    {
      ref: swiftComponents.find((component) => component.name === 'whisperkit')['bom-ref'],
      dependsOn: ['cruxwing:embedded:whisperkit-swift-transformers'],
    },
    { ref: catalogRef, dependsOn: skillComponents.map((component) => component['bom-ref']) },
  ],
};

const rendered = `${JSON.stringify(bom, null, 2)}\n`;
if (checkOnly) {
  if (!existsSync(output) || readFileSync(output, 'utf8') !== rendered) {
    fail('app/Support/Legal/Cruxwing.cdx.json is stale; run node scripts/generate-sbom.mjs');
  }
  process.stdout.write(`SBOM is current: ${skillComponents.length} skills, ${bom.components.length} components\n`);
} else {
  writeFileSync(output, rendered);
  process.stdout.write(`Wrote ${output}: ${skillComponents.length} skills, ${bom.components.length} components\n`);
}
