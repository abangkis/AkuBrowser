import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read = (path) => fs.readFileSync(new URL(path, import.meta.url), "utf8");
test("Windows tuple includes only the isolated reader host and immutable sibling executable", () => {
  const builder = read("./build-windows-installed-app.ps1");
  assert.match(builder, /cmd\\aku-reader-broker/);
  assert.match(builder, /path = "aku-reader-broker\.exe"/);
  assert.match(builder, /allowed_origins = @\("chrome-extension:\/\/dlibmmlopdahibfniinemhnghlifiple\/"\)/);
  assert.ok(builder.indexOf('$readerHostManifest =') < builder.indexOf('$payloadEntries ='));
  assert.match(builder, /@\("manifest.json", "content.js", "service-worker.js"\)/);
});
test("installer fences registry ownership and checks readback before active pointer", () => {
  const installer = read("../installer/windows/installed-app.nsi");
  assert.doesNotMatch(installer, /com\.akubrowser\.runtime/);
  assert.match(installer, /!define READER_HOST "com\.akubrowser\.reader_activation"/);
  assert.ok(installer.indexOf('registration must not be overwritten') < installer.indexOf('File /oname=AkuBrowserLauncher.exe'));
  assert.ok(installer.indexOf('registration could not be verified') < installer.indexOf('File /oname=current.json'));
  const uninstall = installer.slice(installer.indexOf('Section "Uninstall"'));
  assert.equal((uninstall.match(/\$\{If\} \$0 == "\$INSTDIR\\runtime\\versions\\\$\{APP_VERSION\}\\\$\{READER_HOST\}\.json"/g) ?? []).length, 2);
  assert.equal((uninstall.match(/DeleteRegKey HKCU "Software\\(?:Google\\Chrome|Chromium)\\NativeMessagingHosts/g) ?? []).length, 2);
});
