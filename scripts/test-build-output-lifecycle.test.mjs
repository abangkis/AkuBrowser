import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import { OutputLifecycle } from './build-output-lifecycle.mjs';

const repository = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const fixtures = path.join(repository, 'build/lifecycle-tests');
function fixture(t, options = {}) {
  fs.mkdirSync(fixtures, { recursive: true });
  const root = fs.mkdtempSync(path.join(fixtures, 'case-'));
  fs.mkdirSync(path.join(root, 'build'), { recursive: true });
  fs.mkdirSync(path.join(root, 'artifacts'));
  const policy = { schemaVersion: 1, classes: { build: { root: 'build', maxCountPerFamily: 3, maxAgeDays: 7, maxBytes: 10000 }, artifacts: { root: 'artifacts', maxCountPerFamily: 2, maxAgeDays: 30, maxBytes: 10000 } } };
  t.after(() => { assert.ok(root.startsWith(fixtures + path.sep)); fs.rmSync(root, { recursive: true, force: true }); });
  let time = new Date('2026-10-07T00:00:00Z');
  const manager = new OutputLifecycle(root, { policy, now: () => time, processes: () => [], freeSpace: () => 1234, ...options });
  return { root, manager, advance: (days) => { time = new Date(time.getTime() + days * 86400000); } };
}
function output(f, name, content = 'candidate', family = 'package') {
  const p = path.join(f.root, 'build', name);
  const admission = f.manager.begin({ family, className: 'build', outputs: [p], reserveBytes: content.length });
  fs.mkdirSync(p); fs.writeFileSync(path.join(p, 'generated.bin'), content);
  f.manager.finish(admission.id, 'complete');
  return { p, id: admission.id };
}

test('dry-run creates no registry and cannot adopt unregistered source/state', (t) => {
  const f = fixture(t);
  const legacy = path.join(f.root, 'build/legacy'); fs.mkdirSync(legacy); fs.writeFileSync(path.join(legacy, 'note.md'), 'unique evidence');
  const report = f.manager.cleanup();
  assert.equal(report.targets.length, 0); assert.equal(report.capacities[0].totalBytes, 15);
  assert.equal(fs.existsSync(f.manager.registry), false);
  assert.throws(() => f.manager.begin({ family: 'test', className: 'build', outputs: [legacy], reserveBytes: 0 }), /Unregistered/);
  assert.equal(fs.readFileSync(path.join(legacy, 'note.md'), 'utf8'), 'unique evidence');
  assert.throws(() => f.manager.begin({ family: 'test', className: 'build', outputs: [path.join(f.root, 'acceptance-state/test')], reserveBytes: 0 }), /below build/);
});

test('count retention bounds repeated builds and is idempotent', (t) => {
  const f = fixture(t);
  const built = [];
  for (let i = 0; i < 8; i++) { built.push(output(f, `build-${i}`)); f.advance(0.1); }
  assert.equal(built.filter((r) => fs.existsSync(r.p)).length, 3);
  assert.equal(f.manager.records().length, 3);
  const report = f.manager.cleanup({ apply: true });
  assert.equal(report.logicalBytesRemoved, 0); assert.equal(report.observedVolumeFreeBytesDelta, 0);
});

test('age planning protects latest success; apply reports measured removals separately', (t) => {
  const f = fixture(t);
  const first = output(f, 'first'); f.advance(1);
  const second = output(f, 'second'); f.advance(9);
  const before = fs.readFileSync(path.join(f.manager.registry, `${first.id}.json`));
  const preview = f.manager.cleanup();
  assert.deepEqual(preview.targets.map((r) => r.id), [first.id]);
  assert.ok(preview.protected.some((r) => r.id === second.id && r.reason === 'latest_success'));
  assert.deepEqual(fs.readFileSync(path.join(f.manager.registry, `${first.id}.json`)), before);
  const result = f.manager.cleanup({ apply: true });
  assert.equal(result.logicalBytesRemoved, 9); assert.equal(result.observedVolumeFreeBytesDelta, 0);
  assert.equal(fs.existsSync(first.p), false); assert.equal(fs.existsSync(second.p), true);
});

test('process references, state sentinels, and in-progress output stay protected', (t) => {
  let active = [];
  const f = fixture(t, { processes: () => active });
  const first = output(f, 'active'); f.advance(1);
  const second = output(f, 'state'); f.advance(1);
  output(f, 'latest'); f.advance(9);
  active = [{ pid: 123, text: first.p.toLowerCase() }];
  fs.writeFileSync(path.join(second.p, 'aku-sidecar.db'), 'preserve');
  const pendingPath = path.join(f.root, 'build/in-progress');
  f.manager.begin({ family: 'another', className: 'build', outputs: [pendingPath], reserveBytes: 0 });
  fs.mkdirSync(pendingPath); fs.writeFileSync(path.join(pendingPath, 'progress.bin'), 'pending');
  const result = f.manager.cleanup({ apply: true });
  assert.equal(result.targets.length, 0);
  assert.deepEqual(new Set(result.protected.map((r) => r.reason)), new Set(['active_process', 'source_state_or_unreadable', 'latest_success', 'in_progress']));
  assert.equal(fs.readFileSync(path.join(second.p, 'aku-sidecar.db'), 'utf8'), 'preserve');
});

test('size budget blocks a new runtime copy when unregistered output fills capacity', (t) => {
  const f = fixture(t);
  fs.writeFileSync(path.join(f.root, 'build/unique.bin'), Buffer.alloc(9950));
  const next = path.join(f.root, 'build/next');
  assert.throws(() => f.manager.begin({ family: 'package', className: 'build', outputs: [next], reserveBytes: 100 }), /capacity exceeded/);
  assert.equal(fs.existsSync(next), false);
  assert.equal(f.manager.records().length, 0);
  assert.equal(fs.statSync(path.join(f.root, 'build/unique.bin')).size, 9950);
});

test('overlapping owners, traversal, and linked roots are refused', (t) => {
  const f = fixture(t);
  const first = output(f, 'owned');
  assert.throws(() => f.manager.begin({ family: 'other', className: 'build', outputs: [path.join(first.p, 'nested')], reserveBytes: 0 }), /overlaps/);
  assert.throws(() => f.manager.begin({ family: 'other', className: 'build', outputs: [path.join(f.root, 'build/../source')], reserveBytes: 0 }), /below build/);
  const linked = path.join(f.root, 'build/linked');
  fs.symlinkSync(first.p, linked, process.platform === 'win32' ? 'junction' : 'dir');
  assert.throws(() => f.manager.begin({ family: 'other', className: 'build', outputs: [path.join(linked, 'new')], reserveBytes: 0 }), /Reparse/);
  fs.unlinkSync(linked);
});

test('failure to inspect processes fails closed before removal', (t) => {
  const f = fixture(t); const old = output(f, 'old'); f.advance(1); output(f, 'new'); f.advance(8);
  f.manager.processes = () => { throw new Error('process access unavailable'); };
  assert.throws(() => f.manager.cleanup({ apply: true }), /process access unavailable/);
  assert.ok(fs.existsSync(old.p));
});

test('a live cooperative operation lock is waited for without stealing it', (t) => {
  const f = fixture(t); fs.mkdirSync(f.manager.registry, { recursive: true });
  const lock = path.join(f.manager.registry, 'operation.lock'); fs.writeFileSync(lock, 'held by another operation');
  const child = spawn(process.execPath, ['-e', "setTimeout(() => require('node:fs').unlinkSync(process.argv[1]), 200)", lock], { windowsHide: true, stdio: 'ignore' });
  const result = f.manager.cleanup({ apply: true });
  assert.equal(result.logicalBytesRemoved, 0);
  assert.equal(fs.existsSync(lock), false);
  assert.notEqual(child.exitCode, 1);
});

test('concurrent reservations block admission before any second copy', (t) => {
  const f = fixture(t);
  f.manager.begin({ family: 'first', className: 'build', outputs: [path.join(f.root, 'build/first')], reserveBytes: 6000 });
  const second = path.join(f.root, 'build/second');
  assert.throws(() => f.manager.begin({ family: 'second', className: 'build', outputs: [second], reserveBytes: 5000 }), /capacity exceeded/);
  assert.equal(fs.existsSync(second), false);
});

test('nested release producers share only their current parent reservation', (t) => {
  const f = fixture(t); const staging = path.join(f.root, 'artifacts/kit.building'); const final = path.join(f.root, 'artifacts/kit');
  const parent = f.manager.begin({ family: 'release-kit', className: 'artifacts', outputs: [staging, final], reserveBytes: 5000, ownerPid: 55 });
  const nested = path.join(staging, 'preview');
  const child = f.manager.begin({ family: 'preview', className: 'artifacts', outputs: [nested], reserveBytes: 2000, ownerPid: 55 });
  assert.equal(child.id, parent.id); assert.equal(child.borrowed, true); assert.equal(f.manager.records().length, 1);
  assert.throws(() => f.manager.begin({ family: 'outsider', className: 'artifacts', outputs: [nested], reserveBytes: 0, ownerPid: 66 }), /overlaps/);
  fs.mkdirSync(staging); fs.writeFileSync(path.join(staging, 'receipt.json'), '{}'); fs.renameSync(staging, final);
  f.manager.finish(parent.id, 'complete', { pin: true });
  f.advance(100); assert.equal(f.manager.cleanup({ apply: true }).targets.length, 0);
  assert.ok(fs.existsSync(path.join(final, 'receipt.json')));
});

test('Windows locked files are skipped without terminating their owner', { skip: process.platform !== 'win32' }, async (t) => {
  const f = fixture(t); const old = output(f, 'locked'); f.advance(1); output(f, 'new'); f.advance(8);
  const script = "$h=[IO.File]::Open($env:AKU_LOCK_TEST_PATH,'Open','ReadWrite','None'); [Console]::WriteLine('ready'); [Console]::ReadLine() | Out-Null; $h.Dispose()";
  const child = spawn('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script], { windowsHide: true, env: { ...process.env, AKU_LOCK_TEST_PATH: path.join(old.p, 'generated.bin') }, stdio: ['pipe', 'pipe', 'pipe'] });
  const done = new Promise((resolve) => child.once('exit', resolve));
  try {
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Lock holder did not become ready')), 15000);
      child.stdout.once('data', () => { clearTimeout(timer); resolve(); });
      child.once('error', (e) => { clearTimeout(timer); reject(e); });
      child.once('exit', () => { clearTimeout(timer); reject(new Error('Lock holder exited before readiness')); });
    });
    const result = f.manager.cleanup({ apply: true });
    assert.ok(result.results.some((r) => r.id === old.id && r.status === 'skipped_or_partial_locked'));
    assert.equal(result.logicalBytesRemoved, 0);
    assert.equal(child.exitCode, null);
    assert.ok(fs.existsSync(path.join(old.p, 'generated.bin')));
  } finally { child.stdin.end('\n'); await done; }
  assert.equal(f.manager.cleanup({ apply: true }).logicalBytesRemoved, 9);
});
