import fs from "node:fs";
import { createHash } from "node:crypto";

const [registryPath] = process.argv.slice(2);
if (!registryPath) throw new Error("usage: validate-bridge-identity-registry.mjs <registry>");
const registry = JSON.parse(fs.readFileSync(registryPath, "utf8"));
if (registry.schemaVersion !== 2) throw new Error("unsupported Bridge identity registry schema");
const required = ["development", "acceptance", "production-store", "production-offline", "production-app"];
const ids = new Set();
for (const name of required) {
  const profile = registry.profiles?.[name];
  if (!profile) throw new Error(`missing Bridge identity profile: ${name}`);
  if (!/^[a-p]{32}$/.test(profile.extensionId ?? "")) throw new Error(`invalid extension ID: ${name}`);
  if (ids.has(profile.extensionId)) throw new Error(`duplicate extension ID: ${profile.extensionId}`);
  ids.add(profile.extensionId);
  if (profile.publicKey) {
    const key = Buffer.from(profile.publicKey, "base64");
    if (key.toString("base64") !== profile.publicKey) throw new Error(`non-canonical public key: ${name}`);
    const digest = createHash("sha256").update(key).digest().subarray(0, 16);
    const derived = [...digest].map((byte) => String.fromCharCode(97 + (byte >> 4), 97 + (byte & 15))).join("");
    if (derived !== profile.extensionId) throw new Error(`${name} key derives ${derived}, expected ${profile.extensionId}`);
  } else if (profile.distribution !== "chrome-web-store") {
    throw new Error(`non-Store profile requires a public key: ${name}`);
  }
}
console.log(JSON.stringify({ schemaVersion: 2, profiles: required, extensionIds: [...ids] }, null, 2));
