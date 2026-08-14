#!/usr/bin/env node

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import path from "node:path";

const [repositoryRootInput, releaseSourceSha, toolingSha, dirtyOption] = process.argv.slice(2);
const allowDirty = dirtyOption === "--allow-dirty";

const fail = (message) => {
  throw new Error(message);
};
const git = (args, options = {}) => execFileSync(
  "git",
  ["-C", repositoryRootInput, ...args],
  { encoding: "utf8", ...options },
).trim();

if (!repositoryRootInput || !/^[a-f0-9]{40}$/.test(releaseSourceSha ?? "") || !/^[a-f0-9]{40}$/.test(toolingSha ?? "") || (dirtyOption && !allowDirty)) {
  fail("usage: verify-release-tooling-drift.mjs <AkuBrowser-root> <release-source-sha> <tooling-sha> [--allow-dirty]");
}

const repositoryRoot = path.resolve(repositoryRootInput);
const currentHead = git(["rev-parse", "HEAD"]);
if (currentHead !== toolingSha) fail(`AkuBrowser tooling HEAD differs: expected ${toolingSha}, got ${currentHead}`);
const workingTreeDirty = Boolean(git(["status", "--porcelain"]));
if (workingTreeDirty && !allowDirty) fail("AkuBrowser tooling checkout is dirty");

for (const sha of [releaseSourceSha, toolingSha]) {
  const resolved = git(["rev-parse", "--verify", `${sha}^{commit}`]);
  if (resolved !== sha) fail(`release/tooling SHA is not an exact commit: ${sha}`);
}
try {
  execFileSync("git", ["-C", repositoryRoot, "merge-base", "--is-ancestor", releaseSourceSha, toolingSha], { stdio: "ignore" });
} catch {
  fail("release source SHA must be an ancestor of the selected tooling SHA");
}

const exactToolingFiles = new Set([
  ".github/workflows/windows-runtime-installer.yml",
  "scripts/build-macos-preview.sh",
  "scripts/build-macos-runtime-installer.sh",
  "scripts/finalize-macos-signing-request.ps1",
  "scripts/finalize-macos-signing.sh",
  "scripts/run-macos-signing-request.sh",
  "scripts/run-macos-stable-gate.sh",
  "scripts/test-macos-preview.sh",
  "scripts/test-macos-runtime-installer.sh",
  "scripts/test-macos-signing-request.sh",
  "scripts/test-windows-runtime-updater.ps1",
  "scripts/verify-release-tooling-drift.mjs",
]);
const isAllowed = (file) => file === "README.md" || file.startsWith("docs/") ||
  file.startsWith("installer/windows/cmd/sign-update-manifest/") || exactToolingFiles.has(file);

const changedFiles = releaseSourceSha === toolingSha
  ? []
  : git(["diff", "--no-renames", "--name-only", "--diff-filter=ACDMRTUXB", `${releaseSourceSha}..${toolingSha}`])
    .split(/\r?\n/)
    .filter(Boolean)
    .sort();
const rejectedFiles = changedFiles.filter((file) => !isAllowed(file));
if (rejectedFiles.length > 0) {
  fail(`post-freeze drift includes packaged or unapproved source files:\n${rejectedFiles.join("\n")}`);
}

const changedFilesSha256 = createHash("sha256").update(`${changedFiles.join("\n")}\n`).digest("hex");
process.stdout.write(`${JSON.stringify({
  schemaVersion: 1,
  status: "ok",
  kind: changedFiles.length === 0 ? "none" : "release-tooling-only",
  releaseSourceSha,
  toolingSha,
  workingTreeDirty,
  changedFiles,
  changedFilesSha256,
}, null, 2)}\n`);
