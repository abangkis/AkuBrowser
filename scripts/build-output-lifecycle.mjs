import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const forbiddenNames = new Set(['.git', 'localappdata', 'browser-profile', 'credentials.local.json']);
const lower = (value) => path.resolve(value).toLowerCase();
const inside = (value, root) => lower(value).startsWith(lower(root) + path.sep);
const digest = (value) => crypto.createHash('sha256').update(value).digest('hex');

function processes() {
  if (process.platform === 'win32') {
    // Keep command lines in memory only. They may contain private arguments.
    const script = "$ErrorActionPreference='Stop'; Get-CimInstance Win32_Process -ErrorAction Stop | Select-Object ProcessId,ExecutablePath,CommandLine | ConvertTo-Json -Compress";
    let rows;
    try {
      const raw = execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script], { encoding: 'utf8', windowsHide: true, timeout: 20000, stdio: ['ignore', 'pipe', 'pipe'] });
      rows = JSON.parse(raw);
      if (!rows || (Array.isArray(rows) && !rows.length)) throw new Error('Empty process inventory');
    } catch { throw new Error('Windows process inspection unavailable; cleanup refused'); }
    return (Array.isArray(rows) ? rows : [rows]).map((p) => ({ pid: p.ProcessId, text: `${p.ExecutablePath || ''} ${p.CommandLine || ''}`.toLowerCase().replaceAll('/', '\\') }));
  }
  return execFileSync('ps', ['-axo', 'pid=,args='], { encoding: 'utf8', timeout: 20000 }).split('\n').map((line) => ({ pid: Number(line.trim().split(/\s+/)[0]), text: line.toLowerCase() }));
}

export function measure(root, { rejectSensitive = false } = {}) {
  if (!fs.existsSync(root)) return { bytes: 0, files: 0 };
  let bytes = 0, files = 0;
  const pending = [root];
  while (pending.length) {
    const current = pending.pop();
    const stat = fs.lstatSync(current);
    if (stat.isSymbolicLink()) throw new Error(`Reparse/link target refused: ${current}`);
    const name = path.basename(current).toLowerCase();
    if (rejectSensitive && (forbiddenNames.has(name) || /\.(db|sqlite|sqlite3)(-wal|-shm)?$/.test(name))) throw new Error(`Source or state target refused: ${current}`);
    if (stat.isDirectory()) pending.push(...fs.readdirSync(current).map((name) => path.join(current, name)));
    else { bytes += stat.size; files++; }
  }
  return { bytes, files };
}

export class OutputLifecycle {
  constructor(root, options = {}) {
    this.root = path.resolve(root);
    this.policy = options.policy || JSON.parse(fs.readFileSync(path.join(this.root, 'config/build-retention.json'), 'utf8'));
    this.now = options.now || (() => new Date());
    this.processes = options.processes || processes;
    this.freeSpace = options.freeSpace || (() => { const s = fs.statfsSync(this.root); return s.bavail * s.bsize; });
    this.registry = path.join(this.root, 'acceptance-state/.output-lifecycle');
    if (this.policy.schemaVersion !== 1) throw new Error('Unsupported retention policy');
    for (const [name, c] of Object.entries(this.policy.classes)) {
      if (!['build', 'artifacts'].includes(name) || c.root !== name || !Number.isSafeInteger(c.maxBytes) || c.maxBytes <= 0 || !Number.isInteger(c.maxCountPerFamily) || c.maxCountPerFamily < 1 || !(c.maxAgeDays > 0)) throw new Error('Invalid retention class');
    }
    this.noLinks(this.root);
    if (lower(fs.realpathSync(this.root)) !== lower(this.root)) throw new Error('Repository root has a reparse ancestor');
    this.noLinks(this.registry);
  }

  noLinks(target) {
    const resolved = path.resolve(target);
    if (resolved !== this.root && !inside(resolved, this.root)) throw new Error(`Path escapes repository: ${resolved}`);
    let cursor = resolved;
    while (true) {
      if (fs.existsSync(cursor) && fs.lstatSync(cursor).isSymbolicLink()) throw new Error(`Reparse ancestor refused: ${cursor}`);
      if (cursor === this.root) break;
      cursor = path.dirname(cursor);
    }
    return resolved;
  }

  output(target, className) {
    const c = this.policy.classes[className];
    if (!c) throw new Error('Unknown retention class');
    const resolved = this.noLinks(target);
    if (!inside(resolved, path.join(this.root, c.root))) throw new Error(`Output must be below ${c.root}: ${resolved}`);
    return resolved;
  }

  records() {
    this.noLinks(this.registry);
    if (!fs.existsSync(this.registry)) return [];
    return fs.readdirSync(this.registry).filter((f) => /^[a-f0-9]{64}\.json$/.test(f)).map((f) => {
      const recordFile = this.noLinks(path.join(this.registry, f));
      const r = JSON.parse(fs.readFileSync(recordFile, 'utf8'));
      if (r.schemaVersion !== 1 || !['building', 'complete', 'failed'].includes(r.state) || !Array.isArray(r.outputs) || !r.outputs.length || !/^[a-f0-9]{64}$/.test(r.id) || f !== `${r.id}.json` || !Number.isFinite(Date.parse(r.updatedAt))) throw new Error('Invalid ownership record');
      r.outputs = r.outputs.map((p) => this.output(p, r.className));
      return r;
    });
  }

  write(record) {
    this.noLinks(this.registry);
    fs.mkdirSync(this.registry, { recursive: true });
    const target = this.noLinks(path.join(this.registry, `${record.id}.json`));
    const temporary = `${target}.${crypto.randomUUID()}.tmp`;
    fs.writeFileSync(temporary, JSON.stringify(record, null, 2) + '\n', { flag: 'wx' });
    fs.renameSync(temporary, target);
  }

  locked(fn) {
    this.noLinks(this.registry);
    fs.mkdirSync(this.registry, { recursive: true });
    const lock = path.join(this.registry, 'operation.lock');
    let handle;
    const deadline = Date.now() + 10000;
    const delay = new Int32Array(new SharedArrayBuffer(4));
    while (handle === undefined) {
      try { handle = fs.openSync(lock, 'wx'); }
      catch (e) {
        if (e.code !== 'EEXIST' || Date.now() >= deadline) throw new Error('Lifecycle operation is already locked; inspect its owner before retrying');
        Atomics.wait(delay, 0, 0, 25);
      }
    }
    fs.writeFileSync(handle, JSON.stringify({ pid: process.pid, at: this.now().toISOString() }));
    try { return fn(); }
    finally { fs.closeSync(handle); fs.unlinkSync(lock); }
  }

  protection(record, currentProcesses) {
    if (record.pinned) return 'pinned';
    if (record.state === 'building') return 'in_progress';
    for (const p of record.outputs) {
      const key = lower(p).replaceAll('/', process.platform === 'win32' ? '\\' : '/');
      if (currentProcesses.some((proc) => proc.text.includes(key))) return 'active_process';
      try { this.output(p, record.className); measure(p, { rejectSensitive: true }); }
      catch { return 'source_state_or_unreadable'; }
    }
    return null;
  }

  plan({ reserveClass = null, reserveBytes = 0, excludeId = null } = {}) {
    if (!Number.isSafeInteger(reserveBytes) || reserveBytes < 0) throw new Error('Invalid space reservation');
    const rows = this.records();
    const currentProcesses = this.processes(); // Failure blocks cleanup, never assumes an idle host.
    const selected = new Set();
    const records = rows.map((r) => ({ ...r, bytes: r.outputs.reduce((n, p) => n + measure(p).bytes, 0), protection: r.id === excludeId ? 'current_output' : this.protection(r, currentProcesses) }));
    // Preserve at least the latest successful output of every producer.
    const families = new Map();
    for (const r of records.sort((a, b) => Date.parse(b.updatedAt) - Date.parse(a.updatedAt))) {
      const key = `${r.className}:${r.family}`;
      if (!families.has(key)) families.set(key, []);
      families.get(key).push(r);
    }
    for (const family of families.values()) {
      const newest = family.find((r) => r.state === 'complete');
      if (newest && !newest.protection) newest.protection = 'latest_success';
      const c = this.policy.classes[family[0].className];
      family.forEach((r, i) => {
        if (!r.protection && (i >= c.maxCountPerFamily || this.now().getTime() - Date.parse(r.updatedAt) > c.maxAgeDays * 86400000)) selected.add(r.id);
      });
    }
    const capacities = [];
    for (const [className, c] of Object.entries(this.policy.classes)) {
      const total = measure(this.noLinks(path.join(this.root, c.root))).bytes;
      const activeReservations = records.filter((r) => r.className === className && r.state === 'building').reduce((n, r) => n + Math.max(0, (r.reservedBytes || 0) - r.bytes), 0);
      const reserved = (className === reserveClass ? reserveBytes : 0) + activeReservations;
      let after = total - records.filter((r) => r.className === className && selected.has(r.id)).reduce((n, r) => n + r.bytes, 0);
      for (const r of records.filter((r) => r.className === className && !r.protection && !selected.has(r.id)).sort((a, b) => Date.parse(a.updatedAt) - Date.parse(b.updatedAt))) {
        if (after + reserved <= c.maxBytes) break;
        selected.add(r.id); after -= r.bytes;
      }
      capacities.push({ className, totalBytes: total, projectedBytes: after, reservedBytes: reserved, limitBytes: c.maxBytes, fits: after + reserved <= c.maxBytes });
    }
    const unregistered = [];
    for (const [className, c] of Object.entries(this.policy.classes)) {
      const classRoot = path.join(this.root, c.root);
      if (!fs.existsSync(classRoot)) continue;
      const owned = records.filter((r) => r.className === className).flatMap((r) => r.outputs);
      const pending = fs.readdirSync(classRoot).map((name) => path.join(classRoot, name));
      while (pending.length) {
        const p = this.noLinks(pending.pop());
        if (owned.some((v) => lower(p) === lower(v))) continue;
        if (owned.some((v) => inside(v, p))) pending.push(...fs.readdirSync(p).map((name) => path.join(p, name)));
        else unregistered.push({ className, path: p, estimatedLogicalBytes: measure(p).bytes });
      }
    }
    return { schemaVersion: 1, mode: 'dry_run', targets: records.filter((r) => selected.has(r.id)).map((r) => ({ id: r.id, family: r.family, className: r.className, outputs: r.outputs, estimatedLogicalBytes: r.bytes })), protected: records.filter((r) => r.protection).map((r) => ({ id: r.id, outputs: r.outputs, reason: r.protection })), estimatedLogicalBytes: records.filter((r) => selected.has(r.id)).reduce((n, r) => n + r.bytes, 0), capacities, unregistered, unregisteredPolicy: 'preserve; included in size ceiling' };
  }

  cleanup(options = {}) {
    if (!options.apply) return this.plan(options);
    return this.locked(() => this.applyPlan(this.plan(options)));
  }

  applyPlan(plan) {
    const beforeFree = this.safeFree();
    let logicalBytesRemoved = 0;
    const results = [];
    for (const target of plan.targets) {
      const r = this.records().find((r) => r.id === target.id);
      if (!r || this.protection(r, this.processes())) { results.push({ id: target.id, status: 'skipped_protected' }); continue; }
      const before = r.outputs.reduce((n, p) => n + measure(p).bytes, 0);
      let error = false;
      for (const p of r.outputs) {
        try {
          this.output(p, r.className);
          measure(p, { rejectSensitive: true });
          // Recheck process ownership immediately before touching each exact root.
          if (this.protection(r, this.processes())) { error = true; break; }
          fs.rmSync(p, { recursive: true, force: false, maxRetries: 0 });
        } catch (e) { if (e.code !== 'ENOENT') error = true; }
      }
      const after = r.outputs.reduce((n, p) => n + measure(p).bytes, 0);
      logicalBytesRemoved += Math.max(0, before - after);
      if (!error && !r.outputs.some((p) => fs.existsSync(p))) fs.unlinkSync(this.noLinks(path.join(this.registry, `${r.id}.json`)));
      results.push({ id: r.id, status: error ? 'skipped_or_partial_locked' : 'removed', logicalBytesRemoved: Math.max(0, before - after) });
    }
    const afterFree = this.safeFree();
    return { ...plan, mode: 'apply', results, logicalBytesRemoved, observedVolumeFreeBytesDelta: beforeFree === null || afterFree === null ? null : afterFree - beforeFree, freeSpaceAttribution: 'volume delta may include concurrent activity; logical removal is not physical reclamation' };
  }

  safeFree() { try { return this.freeSpace(); } catch { return null; } }

  begin({ family, className, outputs, reserveBytes = 1073741824, ownerPid = process.ppid }) {
    if (!/^[a-z0-9][a-z0-9_-]{0,79}$/.test(family)) throw new Error('Invalid producer family');
    outputs = outputs.map((p) => this.output(p, className));
    if (!outputs.length || outputs.some((a, i) => outputs.some((b, j) => i !== j && (lower(a) === lower(b) || inside(a, b))))) throw new Error('Overlapping output roots');
    const id = digest(outputs.map(lower).sort().join('\n'));
    return this.locked(() => {
      const records = this.records();
      const current = this.processes().filter((p) => p.pid !== process.pid && p.pid !== ownerPid);
      const parent = records.find((r) => r.state === 'building' && r.ownerPid === ownerPid && r.className === className && outputs.every((p) => r.outputs.some((v) => inside(p, v))));
      if (parent) {
        for (const p of outputs) {
          measure(p, { rejectSensitive: true });
          if (current.some((proc) => proc.text.includes(lower(p)))) throw new Error('Output is referenced by an active process');
        }
        return { id: parent.id, outputs, className, borrowed: true };
      }
      for (const p of outputs) {
        if (records.some((r) => r.id !== id && r.outputs.some((v) => lower(v) === lower(p) || inside(v, p) || inside(p, v)))) throw new Error('Output overlaps another registered producer');
        if (fs.existsSync(p) && !records.some((r) => r.id === id)) throw new Error(`Unregistered existing output must be preserved or migrated first: ${p}`);
        measure(p, { rejectSensitive: true });
        if (current.some((proc) => proc.text.includes(lower(p)))) throw new Error('Output is referenced by an active process');
      }
      const previous = records.find((r) => r.id === id);
      if (previous?.pinned || previous?.state === 'building') throw new Error('Output is pinned or already in progress');
      this.applyPlan(this.plan({ reserveClass: className, reserveBytes, excludeId: id }));
      const c = this.policy.classes[className];
      const total = measure(path.join(this.root, c.root)).bytes;
      const activeReservations = this.records().filter((r) => r.className === className && r.state === 'building').reduce((n, r) => n + Math.max(0, (r.reservedBytes || 0) - r.outputs.reduce((v, p) => v + measure(p).bytes, 0)), 0);
      const replaced = outputs.reduce((n, p) => n + measure(p).bytes, 0);
      if (total - replaced + activeReservations + reserveBytes > c.maxBytes) throw new Error(`Retention capacity exceeded for ${className}; protected, unregistered or locked output remains. Run cleanup dry-run and resolve it before copying another runtime.`);
      const record = { schemaVersion: 1, id, family, className, outputs, state: 'building', ownerPid, reservedBytes: reserveBytes, updatedAt: this.now().toISOString(), pinned: false };
      this.write(record);
      return { id, outputs, className, reservedBytes: reserveBytes };
    });
  }

  finish(id, state, { pin = false } = {}) {
    if (!['complete', 'failed'].includes(state)) throw new Error('Invalid final state');
    return this.locked(() => {
      const record = this.records().find((r) => r.id === id);
      if (!record) throw new Error('Unknown output ownership');
      record.state = state; record.updatedAt = this.now().toISOString(); record.pinned = pin;
      for (const p of record.outputs) measure(p, { rejectSensitive: true });
      this.write(record);
      const report = this.applyPlan(this.plan({ excludeId: id }));
      const capacity = this.plan().capacities.find((c) => c.className === record.className);
      if (capacity.totalBytes + capacity.reservedBytes > capacity.limitBytes) throw new Error('Output exceeds retention capacity; preserved for explicit review');
      return { id, state, cleanup: report };
    });
  }
}

function args(values) {
  const out = {};
  for (let i = 0; i < values.length; i++) {
    const key = values[i];
    if (!key.startsWith('--')) throw new Error('Expected named argument');
    if (['--apply', '--pin'].includes(key)) out[key.slice(2)] = true;
    else out[key.slice(2)] = values[++i];
  }
  return out;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const [command, ...rest] = process.argv.slice(2);
    const options = args(rest);
    const root = options.root || path.dirname(path.dirname(fileURLToPath(import.meta.url)));
    const manager = new OutputLifecycle(root);
    let result;
    if (command === 'cleanup') result = manager.cleanup({ apply: !!options.apply });
    else if (command === 'begin') {
      const outputsJson = options['outputs-base64'] === undefined
        ? options.outputs
        : Buffer.from(options['outputs-base64'], 'base64').toString('utf8');
      result = manager.begin({ family: options.family, className: options.class, outputs: JSON.parse(outputsJson), reserveBytes: Number(options.reserve ?? 1073741824), ownerPid: Number(options['owner-pid'] || process.ppid) });
    }
    else if (command === 'finish') result = manager.finish(options.id, options.state || 'complete', { pin: !!options.pin });
    else if (command === 'measure') result = measure(options.path);
    else throw new Error('Usage: build-output-lifecycle.mjs cleanup|begin|finish|measure [named options]');
    process.stdout.write(JSON.stringify(result, null, 2) + '\n');
  } catch (e) { process.stderr.write(`Output lifecycle: ${e.message}\n`); process.exitCode = 1; }
}
