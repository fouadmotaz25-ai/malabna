import { cp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const publicDir = path.join(projectRoot, "public");
const outputDir = path.join(projectRoot, "mobile-dist");

await rm(outputDir, { recursive: true, force: true });
await mkdir(outputDir, { recursive: true });
await cp(publicDir, outputDir, { recursive: true });

const source = await readFile(path.join(publicDir, "demo.html"), "utf8");
const mobileHtml = source
  .replace('<link rel="canonical" href="https://nextmove-fouad.fouadmotaz25.chatgpt.site/">', "")
  .replace("</head>", '<style>body[data-runtime="native"]{padding-top:env(safe-area-inset-top);padding-left:env(safe-area-inset-left);padding-right:env(safe-area-inset-right)}body[data-runtime="native"] .auth-divider,body[data-runtime="native"] .social-auth{display:none!important}</style></head>')
  .replace("<body><main>", '<body data-runtime="native"><main>')
  .replace("navigator.serviceWorker.register('/sw.js').catch(()=>{})", "Promise.resolve()");

await writeFile(path.join(outputDir, "index.html"), mobileHtml, "utf8");

console.log("NextMove mobile web bundle is ready.");
