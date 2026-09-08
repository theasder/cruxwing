import { test, describe, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, copyFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const guard = resolve(here, '..', 'scripts', 'build-running.sh');

/// Поддельный репозиторий: тот же сторож, свой каталог `app`.
function fakeRepo() {
  const root = mkdtempSync(resolve(tmpdir(), 'orakul-guard-'));
  mkdirSync(resolve(root, 'scripts'));
  mkdirSync(resolve(root, 'app'));
  copyFileSync(guard, resolve(root, 'scripts', 'build-running.sh'));
  // Keep bash alive while `sleep` runs. If sleep is the final command, bash is
  // allowed to exec it, so there is no `dist-all.sh` process for the guard to
  // identify even though the fixture claims to model a real build script.
  writeFileSync(resolve(root, 'app', 'dist-all.sh'), '#!/bin/bash\nsleep 30\n:\n');
  return root;
}

const running = (root, env = process.env) =>
  spawnSync('bash', [resolve(root, 'scripts', 'build-running.sh')], {
    encoding: 'utf8', env,
  }).status === 0;

function buildDiagnostic(build) {
  const psResult = spawnSync('ps', ['-p', String(build.pid), '-o', 'pid=,ppid=,command='], {
    encoding: 'utf8',
  });
  const cwdResult = spawnSync('lsof', ['-a', '-p', String(build.pid), '-d', 'cwd', '-Fn'], {
    encoding: 'utf8',
  });
  const candidatesResult = spawnSync('pgrep', ['-fl', 'dist-all\\.sh'], {
    encoding: 'utf8',
  });
  const ps = (psResult.stdout ?? psResult.error?.message ?? '').trim();
  const cwd = (cwdResult.stdout ?? cwdResult.error?.message ?? '').trim();
  const candidates = (candidatesResult.stdout ?? candidatesResult.error?.message ?? '').trim();
  return `child=${ps || 'gone'}; cwd=${cwd || 'unknown'}; candidates=${candidates || 'none'}`;
}

describe('сторож «идёт ли сборка»', () => {
  const repos = [fakeRepo(), fakeRepo()];
  // Запуск ровно такой, как настоящий: `cd app && bash dist-all.sh`. Именно
  // из-за него в командной строке процесса нет пути, и прежний шаблон
  // `pgrep -f "orakul/app.*dist-all\.sh"` не совпадал ни разу.
  let build;
  before(async () => {
    build = spawn('bash', ['dist-all.sh'], {
      cwd: resolve(repos[0], 'app'), detached: true, stdio: 'ignore',
    });
    await new Promise((ready, failed) => {
      build.once('spawn', ready);
      build.once('error', failed);
    });

    // `spawn` means the child exists, not that bash has opened the script and
    // acquired its final cwd. Wait for the exact condition under test instead
    // of racing the scheduler on a busy test runner.
    for (let attempt = 0; attempt < 40 && !running(repos[0]); attempt += 1) {
      await new Promise((ready) => setTimeout(ready, 25));
    }
  });
  after(() => {
    try { process.kill(-build?.pid); } catch { /* уже умер */ }
    for (const root of repos) rmSync(root, { recursive: true, force: true });
  });

  test('замечает сборку своего репозитория', () => {
    assert.ok(running(repos[0]),
      `сборка идёт, а сторож молчит — мутация посреди сборки её уронит; ${buildDiagnostic(build)}`);
  });

  test('чужую сборку за свою не принимает', () => {
    // Тот же сторож, тот же процесс в системе, другой каталог. Без этого
    // сторож кричал бы всегда, к нему бы привыкли и перестали читать.
    assert.ok(!running(repos[1]),
      'чужая сборка принята за свою — ложная тревога');
  });

  test('на macOS находит lsof и без /usr/sbin в PATH', () => {
    const stripped = { ...process.env, PATH: '/opt/homebrew/bin:/usr/bin:/bin' };
    assert.ok(running(repos[0], stripped),
      'сторож зависит от интерактивного PATH и пропускает настоящую сборку');
  });

  test('личность процесса берётся из каталога, а не из командной строки', () => {
    const source = spawnSync('cat', [guard], { encoding: 'utf8' }).stdout;
    assert.match(source, /"\$lsof_bin" -a -p "\$pid" -d cwd/,
      'проверка каталога исчезла — остаётся сравнение строк запуска');
  });
});
