import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const semVerPattern = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$/;

export function parseSemVer(value, label = "version") {
  const match = String(value ?? "").match(semVerPattern);
  if (!match) {
    throw new Error(`${label} is not valid SemVer: ${JSON.stringify(value)}`);
  }
  return {
    raw: String(value),
    core: [BigInt(match[1]), BigInt(match[2]), BigInt(match[3])],
    prerelease: match[4] ? match[4].split(".") : [],
  };
}

export function compareSemVer(leftValue, rightValue) {
  const left = typeof leftValue === "string" ? parseSemVer(leftValue) : leftValue;
  const right = typeof rightValue === "string" ? parseSemVer(rightValue) : rightValue;
  for (let index = 0; index < left.core.length; index += 1) {
    if (left.core[index] !== right.core[index]) {
      return left.core[index] > right.core[index] ? 1 : -1;
    }
  }
  if (left.prerelease.length === 0 || right.prerelease.length === 0) {
    return left.prerelease.length === right.prerelease.length ? 0 : (left.prerelease.length === 0 ? 1 : -1);
  }
  const length = Math.max(left.prerelease.length, right.prerelease.length);
  for (let index = 0; index < length; index += 1) {
    const leftPart = left.prerelease[index];
    const rightPart = right.prerelease[index];
    if (leftPart === undefined || rightPart === undefined) {
      return leftPart === rightPart ? 0 : (leftPart === undefined ? -1 : 1);
    }
    if (leftPart === rightPart) continue;
    const leftNumeric = /^\d+$/.test(leftPart);
    const rightNumeric = /^\d+$/.test(rightPart);
    if (leftNumeric && rightNumeric) return BigInt(leftPart) > BigInt(rightPart) ? 1 : -1;
    if (leftNumeric !== rightNumeric) return leftNumeric ? -1 : 1;
    return leftPart > rightPart ? 1 : -1;
  }
  return 0;
}

export async function checkNativeHostMinimum(manifestPath, { stable = false } = {}) {
  const release = JSON.parse(await fs.readFile(manifestPath, "utf8"));
  const host = parseSemVer(release.distribution?.chromeStore?.nativeHost?.version, "nativeHost.version");
  const minimum = parseSemVer(release.components?.akuSidecar?.update?.minHostVersion, "components.akuSidecar.update.minHostVersion");
  if (stable && (host.prerelease.length > 0 || minimum.prerelease.length > 0)) {
    throw new Error("Stable packaging requires non-prerelease nativeHost.version and minHostVersion.");
  }
  if (compareSemVer(host, minimum) < 0) {
    throw new Error(`Packaged nativeHost.version ${host.raw} is below AkuSidecar minHostVersion ${minimum.raw}.`);
  }
  return { status: "ok", nativeHostVersion: host.raw, minHostVersion: minimum.raw, stable };
}

const scriptPath = fileURLToPath(import.meta.url);
if (process.argv[1] && path.resolve(process.argv[1]) === scriptPath) {
  checkNativeHostMinimum(path.resolve(process.argv[2] ?? ""), { stable: process.argv.includes("--stable") })
    .then((result) => process.stdout.write(`${JSON.stringify(result)}\n`))
    .catch((error) => {
      process.stderr.write(`${error.message}\n`);
      process.exitCode = 1;
    });
}
