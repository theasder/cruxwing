#!/usr/bin/env node

// Scan every reachable Git object and every current publication input for
// credential-shaped values without ever printing the value itself. Redaction
// tests deliberately contain synthetic keys; those are reviewed by exact Git
// blob identity, path and detector category rather than ignored by directory.

import { execFileSync } from 'node:child_process';
import {
  existsSync, lstatSync, readFileSync, readlinkSync,
} from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');

function argumentsFrom(argv) {
  const result = {
    repo: scriptRoot,
    allowlist: resolve(scriptRoot, 'config', 'history-secret-fixtures.json'),
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--repo' || argument === '--allowlist') {
      const value = argv[index + 1];
      if (!value) throw new Error(`${argument} requires a path`);
      result[argument.slice(2)] = resolve(value);
      index += 1;
    } else {
      throw new Error(`unknown argument: ${argument}`);
    }
  }
  return result;
}

const detectors = [
  ['google-oauth', /GOCSPX-[A-Za-z0-9_-]{10,}/],
  ['anthropic', /(?<![A-Za-z0-9_-])sk-ant-[A-Za-z0-9_-]{20,}/],
  ['sk-provider', /(?<![A-Za-z0-9_-])sk-(?:live-)?[A-Za-z0-9_-]{20,}/],
  ['google-api', /AIza[A-Za-z0-9_-]{30,}/],
  ['google-client', /[0-9]{11,}-[a-z0-9]{20,}\.apps\.googleusercontent\.com/],
  ['github', /(?:gh[pousr]_[A-Za-z0-9_]{30,}|github_pat_[A-Za-z0-9_]{50,})/],
  ['gitlab', /glpat-[A-Za-z0-9_-]{20,}/],
  ['aws', /AKIA[0-9A-Z]{16}/],
  ['slack', /xox[baprs]-[A-Za-z0-9-]{10,}/],
  ['stripe', /(?:sk|rk)_live_[A-Za-z0-9]{16,}/],
  ['telegram', /(?<![0-9])\d{8,12}:[A-Za-z0-9_-]{30,}/],
  ['npm', /npm_[A-Za-z0-9]{30,}/],
  ['pypi', /pypi-AgEIcHlwaS5vcmc[A-Za-z0-9_-]{30,}/],
  ['bearer', /[Bb]earer [A-Za-z0-9._-]{24,}/],
  ['private-key', /-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----/],
];

function categoriesIn(buffer) {
  const text = buffer.toString('utf8');
  return detectors.filter(([, detector]) => detector.test(text))
    .map(([category]) => category).sort();
}

function git(repo, args, options = {}) {
  return execFileSync('git', args, {
    cwd: repo,
    maxBuffer: 512 * 1024 * 1024,
    ...options,
  });
}

function parseAllowlist(file) {
  const parsed = JSON.parse(readFileSync(file, 'utf8'));
  if (parsed.version !== 1 || !Array.isArray(parsed.fixtures)) {
    throw new Error('history-secret allowlist must have version 1 and a fixtures array');
  }
  const fixtures = new Map();
  for (const fixture of parsed.fixtures) {
    if (!/^[0-9a-f]{40}(?:[0-9a-f]{24})?$/.test(fixture.oid)
        || typeof fixture.path !== 'string' || fixture.path.length === 0
        || !Array.isArray(fixture.categories) || fixture.categories.length === 0
        || typeof fixture.reason !== 'string' || fixture.reason.trim().length < 12) {
      throw new Error('malformed history-secret fixture entry');
    }
    const categories = [...new Set(fixture.categories)].sort();
    if (categories.some((category) => !detectors.some(([known]) => known === category))) {
      throw new Error(`unknown detector category in fixture ${fixture.oid}`);
    }
    const key = `${fixture.oid}\0${fixture.path}`;
    if (fixtures.has(key)) throw new Error(`duplicate history-secret fixture ${fixture.oid}`);
    fixtures.set(key, { ...fixture, categories, used: false });
  }
  return fixtures;
}

function inspectHit({ scope, oid, path, categories }, fixtures, violations) {
  if (categories.length === 0) return;
  const fixture = fixtures.get(`${oid}\0${path}`);
  if (fixture && JSON.stringify(fixture.categories) === JSON.stringify(categories)) {
    fixture.used = true;
    return;
  }
  violations.push({ scope, oid, path, categories });
}

function reachableObjects(repo, fixtures, violations) {
  const listing = git(repo, ['rev-list', '--objects', '--all'], { encoding: 'utf8' })
    .trim().split('\n').filter(Boolean);
  const paths = new Map();
  for (const line of listing) {
    const separator = line.indexOf(' ');
    const oid = separator < 0 ? line : line.slice(0, separator);
    const path = separator < 0 ? '' : line.slice(separator + 1);
    if (!paths.has(oid)) paths.set(oid, new Set());
    if (path) paths.get(oid).add(path);
  }
  const oids = [...paths.keys()];
  const batch = git(repo, ['cat-file', '--batch'], {
    input: Buffer.from(`${oids.join('\n')}\n`),
  });
  let offset = 0;
  for (const expectedOID of oids) {
    const newline = batch.indexOf(10, offset);
    if (newline < 0) throw new Error('truncated git cat-file header');
    const header = batch.subarray(offset, newline).toString('ascii');
    const [oid, type, sizeText] = header.split(' ');
    if (oid !== expectedOID || !/^\d+$/.test(sizeText)) {
      throw new Error('unexpected git cat-file response');
    }
    const start = newline + 1;
    const end = start + Number(sizeText);
    if (end >= batch.length) throw new Error('truncated git object');
    const content = batch.subarray(start, end);
    offset = end + 1;
    if (type === 'tree') continue;
    const categories = categoriesIn(content);
    if (categories.length === 0) continue;
    const objectPaths = [...paths.get(oid)];
    if (objectPaths.length === 0) objectPaths.push(`<git-${type}>`);
    for (const path of objectPaths) {
      inspectHit({ scope: 'history', oid, path, categories }, fixtures, violations);
    }
  }
  return oids.length;
}

function currentPublicationInputs(repo, fixtures, violations) {
  const listing = git(repo, ['ls-files', '-co', '--exclude-standard', '-z']);
  const paths = listing.toString('utf8').split('\0').filter(Boolean);
  let scanned = 0;
  for (const path of paths) {
    const absolute = resolve(repo, path);
    // `git ls-files -c` also names tracked deletions in a prospective release
    // tree. There is no current content to inspect for those paths; their
    // historical blobs were already covered above.
    if (!existsSync(absolute)) continue;
    const metadata = lstatSync(absolute);
    if (!metadata.isFile() && !metadata.isSymbolicLink()) continue;
    const content = metadata.isSymbolicLink()
      ? Buffer.from(readlinkSync(absolute)) : readFileSync(absolute);
    const categories = categoriesIn(content);
    scanned += 1;
    if (categories.length === 0) continue;
    const oid = git(repo, ['hash-object', '--stdin'], { input: content, encoding: 'utf8' }).trim();
    inspectHit({ scope: 'worktree', oid, path, categories }, fixtures, violations);
  }
  return scanned;
}

function main() {
  const options = argumentsFrom(process.argv.slice(2));
  const shallow = git(options.repo, ['rev-parse', '--is-shallow-repository'], {
    encoding: 'utf8',
  }).trim();
  if (shallow !== 'false') {
    throw new Error('history secret scan requires a full clone (fetch-depth: 0)');
  }
  const fixtures = parseAllowlist(options.allowlist);
  const violations = [];
  const objectCount = reachableObjects(options.repo, fixtures, violations);
  const fileCount = currentPublicationInputs(options.repo, fixtures, violations);
  const unused = [...fixtures.values()].filter((fixture) => !fixture.used);

  if (violations.length > 0 || unused.length > 0) {
    console.error('!! credential-shaped data failed the history review');
    for (const violation of violations) {
      console.error(`   ${violation.scope}: ${violation.oid} ${violation.path} [${violation.categories.join(', ')}]`);
    }
    for (const fixture of unused) {
      console.error(`   stale fixture review: ${fixture.oid} ${fixture.path}`);
    }
    console.error('   Values are deliberately withheld. Revoke real credentials before rewriting history.');
    process.exitCode = 1;
    return;
  }
  console.log(`>> history secret scan clean: ${objectCount} objects, ${fileCount} current files, ${fixtures.size} exact synthetic fixture blobs reviewed`);
}

try {
  main();
} catch (error) {
  console.error(`!! history secret scan could not complete: ${error.message}`);
  process.exitCode = 2;
}
