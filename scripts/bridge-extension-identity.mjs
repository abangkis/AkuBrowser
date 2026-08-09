import fs from "node:fs";
import { createHash } from "node:crypto";

const [registryPath, manifestPath, profileName] = process.argv.slice(2);
if (!registryPath || !manifestPath || !profileName) {
  throw new Error("usage: bridge-extension-identity.mjs <registry> <manifest> <profile>");
}

const registry = JSON.parse(fs.readFileSync(registryPath, "utf8"));
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
const profile = registry.profiles?.[profileName];

if (registry.schemaVersion !== 1) throw new Error("unsupported Bridge identity registry schema");
if (!profile) throw new Error(`Bridge identity profile is not declared: ${profileName}`);
if (!/^[a-p]{32}$/.test(profile.extensionId ?? "")) {
  throw new Error(`Bridge identity profile has an invalid extension ID: ${profileName}`);
}

let derivedExtensionId = null;
if (profile.distribution === "unpacked") {
  if (typeof manifest.key !== "string" || manifest.key.length === 0) {
    throw new Error("unpacked Bridge identity requires manifest.key");
  }
  const publicKey = Buffer.from(manifest.key, "base64");
  if (publicKey.length === 0 || publicKey.toString("base64") !== manifest.key) {
    throw new Error("manifest.key must be canonical base64");
  }
  const digest = createHash("sha256").update(publicKey).digest();
  derivedExtensionId = [...digest.subarray(0, 16)]
    .map((byte) => String.fromCharCode(97 + (byte >> 4), 97 + (byte & 15)))
    .join("");
  if (derivedExtensionId !== profile.extensionId) {
    throw new Error(`manifest.key derives ${derivedExtensionId}, expected ${profile.extensionId}`);
  }
}

console.log(JSON.stringify({
  schemaVersion: 1,
  profile: profileName,
  distribution: profile.distribution,
  extensionId: profile.extensionId,
  extensionOrigin: `chrome-extension://${profile.extensionId}/`,
  derivedExtensionId,
  identitySource: profile.identitySource ?? null,
}, null, 2));
