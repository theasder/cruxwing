import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

// Run with: node --test
//
// orakul and Cruxwing must sit on one machine without touching each other. That
// is not a naming preference — macOS ties Screen Recording and Microphone
// permission to the bundle id, so two apps sharing one id share one grant, and
// a user cannot revoke it from one without losing the other. Same for the
// UserDefaults suite and the Keychain service: a shared identifier means
// installing orakul silently edits Cruxwing's settings.
//
// The comparison reads Cruxwing's REAL identity from its own files rather than
// a copy pasted here, so if somebody ever changes Cruxwing's bundle id into
// orakul's, this fails instead of quietly agreeing with itself.

const here = dirname(fileURLToPath(import.meta.url));
const identity = JSON.parse(readFileSync(resolve(here, '..', 'config', 'app.json'), 'utf8'));
const workspace = resolve(here, '..', '..');

const cruxwingPlist = resolve(workspace, 'cruxwing-app', 'Support', 'Info.plist');
const cruxwingDmg = resolve(workspace, 'cruxwing-app', 'dmg.sh');

// Cruxwing — соседний репозиторий, которого у клонирующего нет. Сравнение с
// ним осмысленно только в рабочей области автора; в клоне оно падало ENOENT и
// красило CI на каждом чужом pull request. Пропуск с причиной, не молчаливый.
const needsCruxwing = existsSync(cruxwingPlist)
  ? {}
  : { skip: 'Cruxwing лежит в соседнем репозитории — в клоне его нет' };

function cruxwingBundleId() {
  if (!existsSync(cruxwingPlist)) return null;
  const plist = readFileSync(cruxwingPlist, 'utf8');
  return plist.match(/<key>CFBundleIdentifier<\/key>\s*<string>([^<]+)<\/string>/)?.[1] ?? null;
}

function cruxwingVolumeName() {
  if (!existsSync(cruxwingDmg)) return null;
  return readFileSync(cruxwingDmg, 'utf8').match(/^VOLNAME="([^"]+)"/m)?.[1] ?? null;
}

describe('orakul app identity', () => {
  test('is called orakul, in every field a user or the OS ever sees', () => {
    assert.equal(identity.app.name, 'orakul');
    assert.equal(identity.app.displayName, 'orakul');
    assert.equal(identity.app.volumeName, 'orakul');
    assert.match(identity.app.developerTeamId, /^[A-Z0-9]{10}$/,
      'published signatures need one explicit Apple TeamIdentifier');
  });

  test('shares no identifier with Cruxwing', needsCruxwing, () => {
    const theirs = cruxwingBundleId();
    assert.ok(theirs, 'could not read Cruxwing bundle id — the comparison would be fake');
    assert.notEqual(identity.app.bundleId, theirs);
    // Not merely different: not derived from Cruxwing's names either, since a
    // shared prefix is how these drift back together during a refactor.
    for (const field of ['bundleId', 'defaultsSuite', 'keychainService', 'volumeName']) {
      assert.doesNotMatch(identity.app[field], /cruxwing|meetgpt/i,
        `${field} still carries Cruxwing's identity`);
    }
    assert.notEqual(identity.app.volumeName, cruxwingVolumeName());
  });

  test('keeps settings and credentials in its own store', () => {
    // Distinct from each other as well as from Cruxwing: one string reused for
    // both defaults and Keychain lets a settings reset drop tokens.
    assert.notEqual(identity.app.defaultsSuite, identity.app.keychainService);
    assert.match(identity.app.bundleId, /^[a-z0-9.]+$/);
    for (const field of ['defaultsSuite', 'keychainService']) {
      assert.ok(identity.app[field].startsWith(identity.app.bundleId),
        `${field} should be namespaced under the bundle id`);
    }
  });

  test('runtime diagnostics and queues carry Orakul identity', () => {
    const files = [
      'app/Sources/MeetGPT/Config.swift',
      'app/Sources/MeetGPT/Log.swift',
      'app/Sources/MeetGPT/Audio/SystemAudioCapture.swift',
      'app/Sources/MeetGPT/Dev/LiveTestHooks.swift',
      'app/Sources/MeetGPT/MCP/LoopbackRedirectServer.swift',
      'app/Sources/MeetGPT/MCP/MCPTokenStorage.swift',
    ];
    for (const file of files) {
      const source = readFileSync(resolve(here, '..', file), 'utf8');
      const code = source.split('\n')
        .filter((line) => !line.trimStart().startsWith('//'))
        .join('\n');
      assert.doesNotMatch(code, /ai\.wheespr\.meetgpt|com\.cruxwing|ai\.cruxwing/i,
        `${file} still identifies runtime work as the parent product`);
      assert.match(code, /ai\.orakul\.desktop/,
        `${file} has no Orakul-owned runtime identifier`);
    }
  });

  test('developer smoke tools launch and inspect Orakul, not the parent app', () => {
    const helpers = [
      'app/edgetest.sh',
      'app/livetest.sh',
      'app/videotest.sh',
      'app/reset-permissions.sh',
      'app/distsmoke.sh',
    ];
    for (const file of helpers) {
      const source = readFileSync(resolve(here, '..', file), 'utf8');
      assert.doesNotMatch(source, /\/Applications\/Cruxwing\.app|quit app "Cruxwing"|process "Cruxwing"|ai\.wheespr\.meetgpt/,
        `${file} still drives or inspects the parent product`);
    }

    for (const file of ['app/edgetest.sh', 'app/livetest.sh', 'app/videotest.sh']) {
      const source = readFileSync(resolve(here, '..', file), 'utf8');
      assert.match(source, /APP="\/Applications\/orakul\.app"/,
        `${file} does not launch the installed Orakul bundle`);
      assert.match(source, /ai\.orakul\.desktop\.livetest/,
        `${file} does not use the Orakul live-test namespace`);
      assert.doesNotMatch(source, /ai\.cruxwing\.livetest/,
        `${file} still uses the parent product's live-test namespace`);
    }

    const coverageManifest = readFileSync(
      resolve(here, '..', 'app', 'Tests', 'E2E', 'coverage-manifest.json'), 'utf8');
    assert.match(coverageManifest, /ai\.orakul\.desktop\.livetest/);
    assert.doesNotMatch(coverageManifest, /ai\.cruxwing\.livetest/);

    const corpus = readFileSync(resolve(here, '..', 'app', 'eval-corpus.sh'), 'utf8');
    assert.match(corpus, /APP_SUPPORT="\$HOME\/Library\/Application Support"/,
      'eval-corpus.sh does not define the standard application-support root');
    assert.match(corpus, /orakul_history="\$APP_SUPPORT\/ai\.orakul\.desktop\/Sessions"/,
      'eval-corpus.sh cannot find Orakul session storage');
    assert.doesNotMatch(corpus, /Application Support\/(Cruxwing|MeetGPT)\/Sessions/,
      'eval-corpus.sh silently reads another product\'s sessions');
  });

  test('ships its own installers, named so neither product can overwrite the other', () => {
    const macos = identity.artifacts.macos.installers;
    const windows = identity.artifacts.windows.installers;
    assert.ok(macos.length >= 2, 'both Mac architectures need an installer');
    for (const file of [...macos, ...windows]) {
      assert.match(file, /^orakul-/, `installer not named for this app: ${file}`);
      assert.doesNotMatch(file, /cruxwing/i, `installer collides with Cruxwing: ${file}`);
    }
    // Downloads land in orakul's own tree, never in the Cruxwing site's.
    assert.match(identity.downloadDir, /^orakul\//);
    assert.doesNotMatch(identity.downloadDir, /cruxwing/i);
  });

  test('the Homebrew uninstall recipe deletes only Orakul data', () => {
    const cask = readFileSync(
      resolve(here, '..', 'packaging', 'homebrew', 'orakul.rb.template'), 'utf8');
    assert.match(cask, /~\/Library\/Application Support\/ai\.orakul\.desktop/,
      'the cask does not clean Orakul application data');
    assert.doesNotMatch(cask, /Application Support\/(MeetGPT|Cruxwing)/i,
      'uninstalling Orakul could delete another product\'s data');
  });

  test('alternate macOS release lanes create only fresh Orakul-named artifacts', () => {
    const appStore = readFileSync(resolve(here, '..', 'app', 'appstore.sh'), 'utf8');
    const intel = readFileSync(resolve(here, '..', 'app', 'build-intel.sh'), 'utf8');

    for (const [script, source] of [['appstore.sh', appStore], ['build-intel.sh', intel]]) {
      assert.doesNotMatch(source, /cruxwing/i,
        `${script} still carries the other product's identity or artifact path`);
      assert.match(source, /BUNDLE_ID="\$\(\/usr\/libexec\/PlistBuddy[^\n]+CFBundleIdentifier/,
        `${script} does not inspect the freshly built bundle identifier`);
      assert.match(source, /DISPLAY_NAME="\$\(\/usr\/libexec\/PlistBuddy[^\n]+CFBundleDisplayName/,
        `${script} does not inspect the freshly built display name`);
      assert.match(source, /"\$BUNDLE_ID" != "ai\.orakul\.desktop"/,
        `${script} would accept another product's bundle identifier`);
      assert.match(source, /"\$DISPLAY_NAME" != "orakul"/,
        `${script} would accept another product's display name`);
    }

    assert.match(appStore, /^APP="\$ROOT\/build\/orakul\.app"$/m);
    assert.match(appStore, /^PKG="\$DIST\/orakul\.pkg"$/m);
    assert.match(appStore, /MEETGPT_APP_BASENAME=orakul .*"\$ROOT\/build\.sh"/);
    assert.match(appStore,
      /productbuild --component "\$APP" \/Applications --sign "\$INSTALLER_IDENTITY" "\$PKG"/,
      'appstore.sh does not package the freshly validated Orakul app');
    assert.match(appStore, /xcrun altool --upload-app -f "\$PKG"/,
      'appstore.sh upload no longer uses the Orakul package');
    const appStoreClean = appStore.indexOf('rm -rf "$APP"');
    const appStoreOldPackage = appStore.indexOf('rm -f "$PKG"');
    const appStoreBuild = appStore.indexOf('MEETGPT_APP_BASENAME=orakul ');
    const appStoreIdentity = appStore.indexOf('BUNDLE_ID="$(');
    const appStorePackage = appStore.indexOf('productbuild --component');
    assert.ok(appStoreClean >= 0 && appStoreClean < appStoreBuild,
      'appstore.sh can reuse an app left by an earlier build');
    assert.ok(appStoreOldPackage >= 0 && appStoreOldPackage < appStoreBuild,
      'appstore.sh leaves an earlier package beside a failed build');
    assert.ok(appStoreBuild < appStoreIdentity && appStoreIdentity < appStorePackage,
      'appstore.sh does not validate the fresh app identity before packaging it');

    assert.match(intel, /^APP="\$ROOT\/build\/orakul-Intel\.app"$/m);
    assert.match(intel, /^ZIP="\$DIST\/orakul-Intel\.zip"$/m);
    assert.match(intel, /MEETGPT_APP_BASENAME=orakul-Intel/);
    assert.match(intel,
      /\/usr\/bin\/ditto -c -k --sequesterRsrc --keepParent "\$APP" "\$ZIP"/,
      'build-intel.sh does not archive the freshly validated Orakul app');
    const intelClean = intel.indexOf('rm -rf "$APP"');
    const intelOldArchive = intel.indexOf('rm -f "$ZIP"');
    const intelBuild = intel.indexOf('MEETGPT_ARCH=x86_64');
    const intelIdentity = intel.indexOf('BUNDLE_ID="$(');
    const intelArchive = intel.indexOf('/usr/bin/ditto -c -k');
    assert.ok(intelClean >= 0 && intelClean < intelBuild,
      'build-intel.sh can reuse an app left by an earlier build');
    assert.ok(intelOldArchive >= 0 && intelOldArchive < intelBuild,
      'build-intel.sh leaves an earlier archive beside a failed build');
    assert.ok(intelBuild < intelIdentity && intelIdentity < intelArchive,
      'build-intel.sh does not validate the fresh app identity before archiving it');
  });

  test('states platform release status honestly', () => {
    // The historical macOS build is behind a redirect to another product and
    // predates this branch. It must not be promoted as the current release.
    assert.equal(identity.artifacts.windows.status, 'planned');
    assert.equal(identity.artifacts.macos.status, 'release-blocked');
    assert.equal(identity.artifacts.macos.notarised, false,
      'a release-blocked tree must not claim a current notarised artifact');
    assert.match(identity.artifacts.macos.note, /v0\.1\.0/);
    assert.match(identity.artifacts.macos.note, /theasder\/cruxwing/);
    assert.match(identity.artifacts.macos.note, /переименовать репозиторий/);
    assert.match(identity.artifacts.macos.note, /оба новых DMG/);
  });

  test('records that Windows needs its own capture layer', () => {
    // ScreenCaptureKit is macOS-only. Writing this down stops the Windows port
    // being scoped as "recompile the Mac app", which it is not.
    const windows = identity.artifacts.windows;
    assert.match(windows.capture, /WASAPI/i);
    assert.match(windows.note, /ScreenCaptureKit/);
  });

  test('the landing page avoids hard-coded installer filenames', () => {
    // The stable link is the release page. Hard-coding filenames into the
    // landing page couples it to one version and architecture naming scheme.
    const html = readFileSync(resolve(here, '..', 'public', 'index.html'), 'utf8');
    const visible = html.replace(/<!--[\s\S]*?-->/g, '');
    for (const file of [
      ...identity.artifacts.macos.installers,
      ...identity.artifacts.windows.installers,
    ]) {
      assert.ok(!visible.includes(file),
        `page hard-codes versioned artifact name ${file}`);
    }
  });
});
