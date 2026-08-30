import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");

test("Capacitor targets Android and iOS with a bundled app", async () => {
  const [config, html] = await Promise.all([
    read("capacitor.config.ts"),
    read("mobile-dist/index.html"),
  ]);
  assert.match(config, /appId: "iq\.nextmove\.app"/);
  assert.match(config, /appName: "NextMove"/);
  assert.match(config, /webDir: "mobile-dist"/);
  assert.match(html, /<body data-runtime="native">/);
  assert.match(html, /\.social-auth\{display:none!important\}/);
  assert.doesNotMatch(html, /rel="canonical"/);
  assert.doesNotMatch(html, /navigator\.serviceWorker\.register\('\/sw\.js'\)/);
});

test("native projects use secure production defaults", async () => {
  const [androidManifest, iosInfo] = await Promise.all([
    read("android/app/src/main/AndroidManifest.xml"),
    read("ios/App/App/Info.plist"),
  ]);
  assert.match(androidManifest, /android:allowBackup="false"/);
  assert.match(androidManifest, /android:usesCleartextTraffic="false"/);
  assert.match(androidManifest, /android\.permission\.INTERNET/);
  assert.match(iosInfo, /NSCameraUsageDescription/);
  assert.match(iosInfo, /NSMicrophoneUsageDescription/);
  assert.match(iosInfo, /NSPhotoLibraryUsageDescription/);
});
