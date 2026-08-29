import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");

test("production shell exposes the real NextMove application", async () => {
  const [html, layout] = await Promise.all([read("public/demo.html"), read("app/layout.tsx")]);
  assert.match(html, /<title>نكست موف \| كل رياضتك في مكان واحد<\/title>/);
  assert.match(html, /rel="canonical" href="https:\/\/nextmove-fouad\.fouadmotaz25\.chatgpt\.site\/"/);
  assert.match(html, /auth\.verifyOtp\(\{email:pendingEmail,token,type:'email'\}\)/);
  assert.match(html, /auth\.verifyOtp\(\{phone:pendingPhone,token,type:'sms'\}\)/);
  assert.match(html, /بوابة الدفع التجارية لم تُربط بعد/);
  assert.match(layout, /metadataBase: new URL\("https:\/\/nextmove-fouad\.fouadmotaz25\.chatgpt\.site"\)/);
  assert.doesNotMatch(layout, /headers\(\)|h\.get\("host"\)/);
  assert.doesNotMatch(html, /service_role|SUPABASE_SERVICE_ROLE_KEY/);
});

test("PWA files use the production root and an offline fallback", async () => {
  const [manifestRaw, worker] = await Promise.all([read("public/manifest.webmanifest"), read("public/sw.js")]);
  const manifest = JSON.parse(manifestRaw);
  assert.equal(manifest.id, "/");
  assert.equal(manifest.scope, "/");
  assert.match(manifest.start_url, /^\/demo\.html/);
  assert.ok(manifest.icons.some((icon) => icon.sizes === "192x192"));
  assert.ok(manifest.icons.some((icon) => icon.sizes === "512x512"));
  assert.match(worker, /nextmove-app-v13/);
  assert.match(worker, /caches\.match\('\/demo\.html'\)/);
  assert.doesNotMatch(manifestRaw, /\/malabna\//);
});

test("booking function refuses browser cash confirmation before gateway verification", async () => {
  const fn = await read("supabase/functions/book-stadium-slot/index.ts");
  assert.match(fn, /paymentMethod === "cash"/);
  assert.match(fn, /DEPOSIT_GATEWAY_REQUIRED/);
  assert.match(fn, /authClient\.auth\.getUser\(token\)/);
  assert.equal((fn.match(/Deno\.serve/g) || []).length, 1);
});
