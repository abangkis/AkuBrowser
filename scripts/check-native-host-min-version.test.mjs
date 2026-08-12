import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { checkNativeHostMinimum, compareSemVer, parseSemVer } from "./check-native-host-min-version.mjs";

async function fixture(host, minimum) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "aku-host-version-"));
  const file = path.join(root, "release.json");
  await fs.writeFile(file, JSON.stringify({
    distribution: { chromeStore: { nativeHost: { version: host } } },
    components: { akuSidecar: { update: { minHostVersion: minimum } } },
  }));
  return { root, file };
}

test("uses SemVer precedence including prerelease identifiers", () => {
  assert.equal(compareSemVer("1.2.3", "1.2.3-rc.9"), 1);
  assert.equal(compareSemVer("1.2.3-rc.10", "1.2.3-rc.2"), 1);
  assert.equal(compareSemVer("1.2.3-alpha", "1.2.3-beta"), -1);
  assert.throws(() => parseSemVer("1.02.3"), /not valid SemVer/);
});

test("accepts a packaged host at or above the Sidecar minimum", async (t) => {
  const { root, file } = await fixture("0.8.0", "0.7.9");
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  assert.equal((await checkNativeHostMinimum(file, { stable: true })).status, "ok");
});

test("rejects an older packaged host", async (t) => {
  const { root, file } = await fixture("0.7.9", "0.8.0");
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  await assert.rejects(checkNativeHostMinimum(file), /is below AkuSidecar minHostVersion/);
});

test("rejects prerelease host boundaries in stable packaging", async (t) => {
  const { root, file } = await fixture("0.8.0-rc.2", "0.8.0-rc.1");
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  await assert.rejects(checkNativeHostMinimum(file, { stable: true }), /requires non-prerelease/);
});
