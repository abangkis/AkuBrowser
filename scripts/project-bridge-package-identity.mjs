import fs from "node:fs";
import path from "node:path";
import { createHash } from "node:crypto";

const [registryPath, packageRoot, profileName] = process.argv.slice(2);
if (!registryPath || !packageRoot || !profileName) {
  throw new Error("usage: project-bridge-package-identity.mjs <registry> <package-root> <profile>");
}

const registry = JSON.parse(fs.readFileSync(registryPath, "utf8"));
const profile = registry.profiles?.[profileName];
if (registry.schemaVersion !== 2 || !profile) throw new Error("unsupported or missing Bridge identity profile");
if (!/^[a-p]{32}$/.test(profile.extensionId ?? "")) throw new Error("invalid Bridge extension ID");
if (!["development", "acceptance", "production"].includes(profile.environment)) throw new Error("invalid Bridge environment");
if (!["manual", "managed"].includes(profile.runtimeLifecycle)) throw new Error("invalid Bridge runtime lifecycle");

const manifestPath = path.join(packageRoot, "manifest.json");
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
if (profile.publicKey) {
  const publicKey = Buffer.from(profile.publicKey, "base64");
  if (publicKey.toString("base64") !== profile.publicKey) throw new Error("Bridge public key must be canonical base64");
  const digest = createHash("sha256").update(publicKey).digest().subarray(0, 16);
  const derivedId = [...digest].map((byte) => String.fromCharCode(97 + (byte >> 4), 97 + (byte & 15))).join("");
  if (derivedId !== profile.extensionId) throw new Error(`Bridge public key derives ${derivedId}, expected ${profile.extensionId}`);
  manifest.key = profile.publicKey;
} else {
  delete manifest.key;
}
fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

const mode = profileName === "production-store" ? "production-store"
  : profileName === "production-offline" ? "production-offline"
    : profileName === "production-app" ? "production-app"
    : profileName;
const deploymentSource = `export const BRIDGE_DEPLOYMENT = Object.freeze(${JSON.stringify({
  mode,
  identityProfile: profileName,
  distribution: profile.distribution,
  runtimeLifecycle: profile.runtimeLifecycle,
  runtimeAcquisition: profile.runtimeAcquisition,
}, null, 2)});\n`;
fs.writeFileSync(path.join(packageRoot, "bridge-deployment.js"), deploymentSource);

console.log(JSON.stringify({
  schemaVersion: 1,
  profile: profileName,
  mode,
  extensionId: profile.extensionId,
  extensionOrigin: `chrome-extension://${profile.extensionId}/`,
}, null, 2));
