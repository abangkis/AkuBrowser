import fs from "node:fs";
import path from "node:path";
import { createHash } from "node:crypto";

const root = path.resolve(process.argv[2] ?? "");
if (!process.argv[2] || !fs.statSync(root).isDirectory()) {
  throw new Error("usage: fingerprint-extension-directory.mjs <directory>");
}

const files = walk(root).sort().map((file) => ({
  path: file,
  sha256: createHash("sha256").update(fs.readFileSync(path.join(root, file))).digest("hex"),
}));
const fingerprint = createHash("sha256").update(JSON.stringify(files)).digest("hex");
console.log(JSON.stringify({ files, fingerprint }, null, 2));

function walk(directory, relative = "") {
  const result = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const childRelative = path.posix.join(relative, entry.name);
    const child = path.join(directory, entry.name);
    if (entry.isDirectory()) result.push(...walk(child, childRelative));
    else if (entry.isFile()) result.push(childRelative);
    else throw new Error(`unsupported extension package entry: ${childRelative}`);
  }
  return result;
}
