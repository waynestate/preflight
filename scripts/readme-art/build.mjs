#!/usr/bin/env node
/* ============================================================================
   Preflight README art kit.

   Renders the README images from this repo's own static front page (site/),
   its CI templates (each templates/<name>/template.yml) and its brand files, and writes
   them under docs/readme/. Nothing is drawn by hand: the hero and the gallery
   are screenshots of the real page, the checklist card is built from the
   page's own checklist and annunciator panel plus the job names and timeouts
   read from the templates, the cast is the marks resized (WayneUI composed on
   its green tile), and the badges read their facts from composer.json.

   Run from any folder (every path resolves from this file's own location):

     npm --prefix scripts/readme-art ci
     npx --prefix scripts/readme-art playwright install chromium
     node scripts/readme-art/build.mjs

   The page is opened as a file:// URL: no server, no network. Requests for
   anything that is not a local file are aborted, so a stray CDN link fails
   loudly instead of quietly phoning home.
   ========================================================================== */

import { chromium } from "playwright";
import { makeBadge } from "badge-maker";
import sharp from "sharp";
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

/* ------------------------------------------------------------- paths, limits */

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "..", "..");
const siteDir = path.join(repoRoot, "site");
const templatesDir = path.join(repoRoot, "templates");
const outDir = path.join(repoRoot, "docs", "readme");
const castDir = path.join(outDir, "cast");

const MAX_BYTES = 300 * 1024; // every file in docs/readme/ stays at or under this
const FORBIDDEN = /noug[a]t|snu[.]gs|citadel/i; // internal names never ship in art

// The tag every component ships in. The page's placards must agree with it.
const COMPONENT_TAG = "0.1.1";

// Preflight's own palette, as declared in site/assets/preflight.css.
const C = {
  green: "#0C5449",
  greenDeep: "#083B33",
  gold: "#FFCC33",
  cream: "#F4F1EA",
  paper: "#FFFDF7",
  blue: "#0E5A7D",
  ink: "#16211F",
  inkMuted: "#3E4A47",
  rule: "#CFC8B8",
  deck: "#26343A",
  deckEdge: "#1A2529",
  glass: "#121A1D",
  glassText: "#8E9BA0",
  lit: "#6CF2A6",
  litBg: "#0D3A2A",
  amber: "#FFC94A",
  amberBg: "#3B2C06",
};

const outputs = [];

function record(rel, buf) {
  const abs = path.join(outDir, rel);
  mkdirSync(path.dirname(abs), { recursive: true });
  writeFileSync(abs, buf);
  outputs.push({ rel, bytes: buf.length });
  console.log(`  ${rel}  ${buf.length} bytes`);
}

function fail(msg) {
  console.error(`FAIL: ${msg}`);
  process.exit(1);
}

function assertTextClean(text, what) {
  if (FORBIDDEN.test(text)) fail(`forbidden text matched ${FORBIDDEN} in ${what}`);
}

function esc(s) {
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

/* ------------------------------------------------------------- 1. cast strip */

// One 96x96 PNG per stack part (shown at 40 px in the README). The marks are
// copied and resized only, never redrawn. WayneUI is composed instead: its
// reverse mark (white frame, gold tab) set on a Wayne State green tile, so it
// reads as a sibling of the other thirteen.
const CAST = [
  "creed",
  "proctor",
  "sesame",
  "helmet",
  "sourdough",
  "squire",
  "preflight",
  "pinstripe",
  "booster",
  "rollcall",
  "drawbridge",
  "advisor",
  "weld",
];

function castSource(name) {
  // The site keeps every sibling's mark in assets/marks/, but its own lives
  // with the brand files.
  if (name === "preflight") return path.join(siteDir, "brand", "preflight-avatar-256.png");
  return path.join(siteDir, "assets", "marks", `${name}.png`);
}

// The WayneUI tile: the reverse mark, traced from WayneUI's approved artwork,
// set on a green rounded tile. The traced paths are placed unchanged: no edits
// to any d= value, fill, or the mark's own viewBox. The visible ink spans
// 1546 x 1551 of the 1980 x 1989 viewBox and is centred in it, so this scale
// makes the mark 352 px tall on the 512 tile (about 69%), matching the square
// marks WELD and SESAME.
function wayneuiTileSvg() {
  const raw = readFileSync(path.join(scriptDir, "src", "wayneui-mark-reverse.svg"), "utf8");
  const open = raw.indexOf("<svg");
  const openEnd = raw.indexOf(">", open) + 1;
  const close = raw.lastIndexOf("</svg>");
  if (open < 0 || openEnd < 2 || close < openEnd) fail("wayneui-mark-reverse.svg: no <svg> element");
  // Everything between the opening tag and the final </svg>, verbatim (the
  // file's own line endings included, so the paths stay byte-identical).
  const inner = raw.slice(openEnd, close).replace(/^\r?\n/, "");
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512" role="img" aria-label="WayneUI">
  <rect width="512" height="512" rx="80" ry="80" fill="#0C5449"/>
  <svg x="31.3" y="30.3" width="449.4" height="451.4" viewBox="0 0 1980 1989">
${inner}</svg>
</svg>
`;
}

async function buildCast() {
  console.log("cast:");
  const tile = Buffer.from(wayneuiTileSvg(), "utf8");
  const tilePng = await sharp(tile, { density: 300 })
    .resize(96, 96, { fit: "contain", background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png({ palette: true, quality: 85, compressionLevel: 9 })
    .toBuffer();
  record("cast/wayneui.png", tilePng);
  for (const name of CAST) {
    const src = castSource(name);
    if (!existsSync(src)) fail(`missing cast source ${path.relative(repoRoot, src)}`);
    const png = await sharp(readFileSync(src))
      .resize(96, 96, { fit: "contain", background: { r: 0, g: 0, b: 0, alpha: 0 } })
      .png({ palette: true, quality: 85, compressionLevel: 9 })
      .toBuffer();
    record(`cast/${name}.png`, png);
  }
}

/* ---------------------------------------------------------------- 2. badges */

// Facts only, read from the repo, never typed: a badge that lies is worse
// than no badge at all.
function buildBadges(templates) {
  console.log("badges:");
  const composer = JSON.parse(readFileSync(path.join(repoRoot, "composer.json"), "utf8"));
  const defs = [
    { key: "php", label: "php", message: composer.require?.php },
    { key: "license", label: "licence", message: composer.license },
    // The third fact is the repo's own product: how many CI components it ships.
    { key: "components", label: "gitlab ci components", message: String(templates.length) },
  ];
  for (const d of defs) {
    if (!d.message) fail(`no fact to badge for "${d.key}"`);
    const svg = makeBadge({
      label: d.label,
      message: d.message,
      labelColor: C.green,
      color: C.gold,
      style: "flat-square",
    });
    record(`badges/${d.key}.svg`, Buffer.from(svg, "utf8"));
  }
}

/* -------------------------------------------------------------- 3. templates */

// A template can fix its stage two ways: a `stage` input in the spec with a
// default, or a literal `stage:` on the job itself. A `$[[ inputs.stage ]]`
// reference is not a value, so it does not count.
function templateStage(text, job) {
  const fromSpec = text.match(/^ {4}stage:\s*\r?\n(?: {6}.*\r?\n)*? {6}default:\s*"?([A-Za-z0-9_-]+)"?/m)?.[1];
  if (fromSpec) return fromSpec;
  const body = text.slice(text.indexOf(`\n${job}:`));
  return body.match(/^\s{2}stage:\s*"?([A-Za-z0-9_-]+)"?\s*$/m)?.[1] ?? null;
}

// A template without a resolvable stage still says when its job runs, in its
// own rules: a schedule source reads "scheduled", a tag reads "on tag", and
// anything else reads "per pipeline" (renovate runs on a schedule or from
// the web UI, outside the pipeline's stage list).
function ruleStage(body) {
  const rules = body.match(/^\s{2}rules:\s*\r?\n(?:[ \t]{4,}.*(?:\r?\n|$))*/m)?.[0] ?? "";
  if (rules.includes('$CI_PIPELINE_SOURCE == "schedule"')) return "scheduled";
  if (rules.includes("$CI_COMMIT_TAG")) return "on tag";
  return "per pipeline";
}

// Each component's job name, timeout and stage, read from its template. A
// template is "spec, ---, job" (sometimes behind a header comment and a
// leading ---); the job is the one top-level key that is not `spec`.
function readTemplates() {
  const dirs = readdirSync(templatesDir, { withFileTypes: true }).filter((d) => d.isDirectory());
  return dirs.map((d) => {
    const file = path.join(templatesDir, d.name, "template.yml");
    if (!existsSync(file)) fail(`templates/${d.name} has no template.yml`);
    const text = readFileSync(file, "utf8");
    const keys = [...text.matchAll(/^([A-Za-z][A-Za-z0-9_-]*):\s*$/gm)].map((m) => m[1]).filter((k) => k !== "spec");
    if (keys.length !== 1) fail(`templates/${d.name}: expected one job, found ${keys.join(", ") || "none"}`);
    const job = keys[0];
    const body = text.slice(text.indexOf(`\n${job}:`));
    const timeout = body.match(/^\s+timeout:\s*(.+?)\s*$/m)?.[1];
    if (!timeout) fail(`templates/${d.name}: job ${job} has no timeout`);
    const matrix = /^\s+parallel:\s*$/m.test(body) && /^\s+matrix:\s*$/m.test(body);
    // The stage, in the order a template can set it: the spec's `stage` input
    // default, then a literal `stage:` on the job. A template with neither
    // gets its label from its own rules, which say when the job runs.
    const stage = templateStage(text, job) ?? ruleStage(body);
    const t = { job, timeout, matrix, stage };
    assertTextClean(JSON.stringify(t), `templates/${d.name}`);
    return t;
  });
}

// "30 minutes" and "15m" both read as minutes on a checklist.
function shortTimeout(t) {
  const m = t.match(/^(\d+)\s*(m|min|mins|minute|minutes)$/i);
  return m ? `${m[1]} min` : t;
}

/* ------------------------------------------------------------- 4. the page */

async function openPage(browser) {
  const context = await browser.newContext({
    viewport: { width: 1280, height: 900 },
    deviceScaleFactor: 2,
    reducedMotion: "reduce", // the page boards with every item already ticked
  });
  await context.route(/^(?!file:|data:)/, (route) => route.abort());
  const page = await context.newPage();
  await page.goto(pathToFileURL(path.join(siteDir, "index.html")).href, { waitUntil: "load" });
  await page.evaluate(() => document.fonts.ready);
  return { context, page };
}

async function assertClean(page, selector, what) {
  assertTextClean(await page.locator(selector).innerText(), what);
}

/* ------------------------------------------------------------------ 5. hero */

async function buildHero(page) {
  console.log("hero:");
  // The sticky top bar is chrome, not hero. The definition line and the
  // heading readout name the internal deploy platform, which stays out of a
  // public README; the rest of the hero is exactly as the page draws it.
  await page.addStyleTag({
    content: ".topbar, .definition, .instrument__readout { display: none !important; }",
  });
  await assertClean(page, ".hero", "hero");
  const png = await page.locator(".hero").screenshot();
  const jpg = await sharp(png).resize({ width: 1280 }).jpeg({ quality: 82, mozjpeg: true }).toBuffer();
  record("hero.jpg", jpg);
}

/* ------------------------------------------------------- 6. checklist card */

async function readChecklist(page, templates) {
  await assertClean(page, ".card__head", "checklist head");
  const data = await page.evaluate(() => {
    const t = (el) => (el ? el.textContent.replace(/\s+/g, " ").trim() : "");
    return {
      kicker: t(document.querySelector(".card__kicker")),
      title: t(document.querySelector(".card__title")),
      titleTail: t(document.querySelector(".card__title span")),
      foot: t(document.querySelector(".card__foot")),
      panelTitle: t(document.querySelector(".panel__title")),
      // The component placards say which tag each component ships in.
      placards: [...document.querySelectorAll(".placard:not(.placard--alt)")].map((a) => ({
        name: t(a.querySelector(".placard__name")),
        tag: t(a.querySelector(".placard__tag")),
      })),
      items: [...document.querySelectorAll(".card__items .item")].map((li) => ({
        name: t(li.querySelector(".item__name")),
        resp: t(li.querySelector(".item__resp")),
        lights: (li.dataset.lights || "").split(/\s+/).filter(Boolean),
        final: li.classList.contains("item--final"),
      })),
      lamps: [...document.querySelectorAll(".annun .lamp")].map((li) => ({
        key: li.dataset.lamp || "",
        face: t(li.querySelector(".lamp__face").childNodes[0]),
        small: t(li.querySelector(".lamp__face small")),
        soon: li.classList.contains("lamp--soon"),
        wide: li.classList.contains("lamp--wide"),
      })),
    };
  });
  // Only the fields we draw are checked: the final item's "why" line names the
  // deploy platform and is never read.
  assertTextClean(
    JSON.stringify([data.kicker, data.title, data.foot, data.panelTitle, data.items, data.lamps, data.placards]),
    "checklist",
  );
  // Not every component runs on every push: package-publish waits for a tag
  // and renovate for a schedule, so the card carries fewer rows than
  // templates/. Each row still must name exactly one component, checked
  // below, and the panel footer lists the ones without a row.
  const checks = data.items.filter((i) => !i.final);
  if (checks.length === 0) fail("checklist has no component rows");
  // Pair each checklist line with the job that runs it: "Composer audit" is
  // composer-audit, "PHP tests" is php-test, "ESLint · Prettier" is eslint.
  const norm = (s) => s.toLowerCase().replace(/[^a-z0-9]/g, "");
  for (const item of checks) {
    const hit = templates.filter((tp) => norm(item.name).includes(norm(tp.job)));
    if (hit.length !== 1) fail(`checklist item "${item.name}" matches ${hit.length} template jobs`);
    item.tpl = hit[0];
    const card = data.placards.find((p) => p.name === hit[0].job);
    if (!card) fail(`no component placard on the page for ${hit[0].job}`);
    // The art labels every component from COMPONENT_TAG; the placard must agree.
    if (card.tag.toLowerCase() !== `in ${COMPONENT_TAG}`) {
      fail(`placard for ${hit[0].job} reads "${card.tag}", expected "in ${COMPONENT_TAG}"`);
    }
  }
  if (!data.items.at(-1)?.final) fail("checklist has no final clearance item");
  return data;
}

// Text widths come from the real fonts in a real browser, so the dot leaders
// stop exactly where each response begins.
async function measure(page, fontCss, runs) {
  await page.setContent(
    `<!doctype html><html><head><style>${fontCss}</style></head><body>
<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">${runs
      .map((r, i) => `<text id="m${i}" font-family="${r.family}" font-weight="${r.weight}" font-size="${r.size}" letter-spacing="${r.spacing || 0}">${esc(r.text)}</text>`)
      .join("")}</svg></body></html>`,
    { waitUntil: "load" },
  );
  await page.evaluate(() => document.fonts.ready);
  return page.evaluate((n) => Array.from({ length: n }, (_, i) => document.getElementById(`m${i}`).getBBox().width), runs.length);
}

function fontFaceCss() {
  const f = (file, family, weight) => {
    const b64 = readFileSync(path.join(siteDir, "assets", "fonts", file)).toString("base64");
    return `@font-face{font-family:"${family}";font-weight:${weight};font-style:normal;src:url(data:font/woff2;base64,${b64}) format("woff2");}`;
  };
  return [
    f("b612-latin-700-normal.woff2", "B612", 700),
    f("b612-mono-latin-400-normal.woff2", "B612 Mono", 400),
    f("b612-mono-latin-700-normal.woff2", "B612 Mono", 700),
  ].join("\n");
}

const DISPLAY = "'B612', Lato, 'Segoe UI', Helvetica, Arial, sans-serif";
const MONO = "'B612 Mono', ui-monospace, Consolas, monospace";

async function buildChecklist(page, templates) {
  console.log("checklist:");
  const d = await readChecklist(page, templates);
  const fontCss = fontFaceCss();

  // ---- geometry
  const W = 1280;
  const pad = 40;
  const cardX = pad;
  const cardW = 790;
  const headH = 118;
  const rowH = 62;
  const rows = d.items.length;
  const listTop = 40 + headH + 18;
  const footY = listTop + rows * rowH + 26;
  const cardH = footY + 30 - 40;
  const H = 40 + cardH + pad;
  const innerL = cardX + 34;
  const tickSize = 26;
  const tickX = cardX + cardW - 34 - tickSize;
  const respRight = tickX - 16;

  const panelX = cardX + cardW + 34;
  const panelW = W - pad - panelX;
  const panelY = 40;
  const panelH = cardH;

  // ---- numbered names, responses and job lines, with measured widths
  const titleMain = d.title.replace(d.titleTail, "").trim();
  const items = d.items.map((it, i) => ({
    ...it,
    label: `${i + 1}. ${it.name.toUpperCase()}`,
    respU: it.resp.toUpperCase(),
    jobLine: it.tpl
      ? `${it.tpl.job}${it.tpl.matrix ? " · parallel:matrix" : ""} · timeout ${shortTimeout(it.tpl.timeout)}`
      : "",
  }));
  const widths = await measure(
    page,
    fontCss,
    items.flatMap((it) => [
      { text: it.label, family: DISPLAY, weight: 700, size: 19, spacing: 0.8 },
      { text: it.respU, family: MONO, weight: 700, size: 15, spacing: 0.6 },
    ]),
  );
  items.forEach((it, i) => {
    it.labelW = widths[2 * i];
    it.respW = widths[2 * i + 1];
  });

  // ---- timing: one checklist run every T seconds
  const T = 13;
  const at = (i) => 6 + i * 8.5; // % of the cycle at which item i is ticked
  const lastAt = at(rows - 1);
  if (lastAt > 75) fail("checklist timing overruns the cycle");
  const holdEnd = 93;
  const keyframes = [];
  const ruleAnim = []; // the gold reading line steps down the card
  items.forEach((it, i) => {
    const p = at(i);
    keyframes.push(
      `@keyframes on${i}{0%,${(p - 0.01).toFixed(2)}%{opacity:0}${p.toFixed(2)}%,${holdEnd}%{opacity:1}97%,100%{opacity:0}}`,
      `@keyframes tk${i}{0%,${(p - 0.01).toFixed(2)}%{stroke-dashoffset:30}${(p + 2.5).toFixed(2)}%,${holdEnd}%{stroke-dashoffset:0}97%,100%{stroke-dashoffset:30}}`,
    );
    ruleAnim.push(`${Math.max(0, p - 4).toFixed(2)}%,${(p - 0.5).toFixed(2)}%{transform:translateY(${i * rowH}px)}`);
  });
  keyframes.push(
    `@keyframes rd{0%{opacity:0;transform:translateY(0)}2%{opacity:1}${ruleAnim.join("")}${(lastAt + 2).toFixed(2)}%{opacity:0;transform:translateY(${(rows - 1) * rowH}px)}100%{opacity:0;transform:translateY(${(rows - 1) * rowH}px)}}`,
    `@keyframes ft{0%,${(lastAt + 3).toFixed(2)}%{opacity:0}${(lastAt + 6).toFixed(2)}%,${holdEnd}%{opacity:1}97%,100%{opacity:0}}`,
  );

  // Which checklist step lights each lamp (the page's own data-lights wiring).
  const lampStep = new Map();
  items.forEach((it, i) => it.lights.forEach((k) => lampStep.set(k, i)));

  // ---- the card rows
  const rowSvg = items
    .map((it, i) => {
      const y = listTop + i * rowH;
      const base = y + 26; // baseline of the name line
      const dotsX1 = innerL + it.labelW + 10;
      const dotsX2 = respRight - it.respW - 10;
      const final = it.final;
      const nameFill = final ? C.green : C.ink;
      const sep = i < rows - 1 ? `<line x1="${innerL}" y1="${y + rowH - 0.5}" x2="${cardX + cardW - 34}" y2="${y + rowH - 0.5}" stroke="${C.rule}" stroke-width="1" stroke-dasharray="2 4"/>` : "";
      const finalBand = final
        ? `<rect x="${cardX + 9}" y="${y + 2}" width="${cardW - 18}" height="${rowH - 4}" fill="${C.cream}"/>`
        : "";
      return `  <g>
    ${finalBand}
    <text x="${innerL}" y="${base}" font-family="${DISPLAY}" font-weight="700" font-size="19" letter-spacing="0.8" fill="${nameFill}"><tspan fill="${C.blue}">${i + 1}.</tspan>${esc(it.label.slice(String(i + 1).length + 1))}</text>
    ${dotsX2 > dotsX1 ? `<line x1="${dotsX1.toFixed(1)}" y1="${base - 5}" x2="${dotsX2.toFixed(1)}" y2="${base - 5}" stroke="#A9A08C" stroke-width="2" stroke-dasharray="0.1 5" stroke-linecap="round"/>` : ""}
    <text x="${respRight}" y="${base}" text-anchor="end" font-family="${MONO}" font-weight="700" font-size="15" letter-spacing="0.6" fill="${C.inkMuted}">${esc(it.respU)}</text>
    <text class="on on${i}" x="${respRight}" y="${base}" text-anchor="end" font-family="${MONO}" font-weight="700" font-size="15" letter-spacing="0.6" fill="${C.green}">${esc(it.respU)}</text>
    ${it.jobLine ? `<text x="${innerL + 24}" y="${base + 22}" font-family="${MONO}" font-size="13" fill="${C.inkMuted}">${esc(it.jobLine)}</text>` : ""}
    <rect x="${tickX}" y="${base - 19}" width="${tickSize}" height="${tickSize}" rx="5" fill="#FFFFFF" stroke="${C.green}" stroke-width="2"/>
    <path class="tk tk${i}" d="M${tickX + 6} ${base - 6} l5 5.5 l10 -12" fill="none" stroke="${C.green}" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round" stroke-dasharray="30"/>
    ${sep}
  </g>`;
    })
    .join("\n");

  // ---- the annunciator panel: lamps exactly as the page lists them
  const cols = 3;
  const gap = 8;
  const lampPadX = 22;
  const lampTop = panelY + 64;
  const lampW = (panelW - 2 * lampPadX - (cols - 1) * gap) / cols;
  const lampH = 58;
  let slot = 0;
  const lampSvg = d.lamps
    .map((l) => {
      let x;
      let y;
      let w;
      if (l.wide) {
        const r = Math.ceil(slot / cols);
        x = panelX + lampPadX;
        y = lampTop + r * (lampH + gap) + 6;
        w = panelW - 2 * lampPadX;
      } else {
        x = panelX + lampPadX + (slot % cols) * (lampW + gap);
        y = lampTop + Math.floor(slot / cols) * (lampH + gap);
        w = lampW;
        slot += 1;
      }
      const h = l.wide ? 66 : lampH;
      const cx = x + w / 2;
      const size = l.wide ? 17 : 14;
      const spacing = l.wide ? 2 : 0.6;
      const faceY = l.small ? y + h / 2 - 2 : y + h / 2 + size * 0.36;
      const smallTxt = l.small
        ? `<text x="${cx}" y="${y + h / 2 + 15}" text-anchor="middle" font-family="${MONO}" font-size="11" fill="${C.amber}" fill-opacity="0.8">${esc(l.small)}</text>`
        : "";
      const face = (fill, extra = "") =>
        `<text x="${cx}" y="${faceY}" text-anchor="middle" font-family="${DISPLAY}" font-weight="700" font-size="${size}" letter-spacing="${spacing}" fill="${fill}"${extra}>${esc(l.face)}</text>`;
      if (l.soon) {
        // Deferred items: amber, never lit, on the page's striped glass.
        return `  <g><rect x="${x}" y="${y}" width="${w}" height="${h}" rx="5" fill="url(#soon)" stroke="#0A0F11"/>${face(C.amber, ' fill-opacity="0.72"')}${smallTxt}</g>`;
      }
      const step = lampStep.get(l.key);
      if (step === undefined) fail(`lamp ${l.face} is not wired to any checklist item`);
      return `  <g>
    <rect x="${x}" y="${y}" width="${w}" height="${h}" rx="5" fill="${C.glass}" stroke="#0A0F11"/>${face(C.glassText)}
    <g class="on on${step}"><rect x="${x}" y="${y}" width="${w}" height="${h}" rx="5" fill="${C.litBg}" stroke="${C.lit}" stroke-opacity="0.55" filter="url(#glow)"/>${face(C.lit)}</g>
  </g>`;
    })
    .join("\n");
  const lampsBottom = lampTop + Math.ceil(slot / cols) * (lampH + gap) + 6 + 66;

  // ---- panel footer: every component in templates/, by job name, each with
  // the tag it ships in. Checklist components come first, in the card's own
  // order; the ones without a card row follow.
  const jobsY = lampsBottom + 44;
  const paired = items.filter((it) => it.tpl);
  const unpaired = templates.filter((tp) => !paired.some((it) => it.tpl === tp));
  const listed = [
    ...paired.map((it) => ({ job: it.tpl.job, stage: it.tpl.stage })),
    ...unpaired.map((tp) => ({ job: tp.job, stage: tp.stage })),
  ];
  const stages = [...new Set(listed.map((it) => it.stage))].join(" · ");
  const rowGap = 23;
  const tagLabel = `IN ${COMPONENT_TAG}`.toUpperCase();
  const jobsSvg = [
    `<text x="${panelX + lampPadX}" y="${jobsY}" font-family="${MONO}" font-weight="700" font-size="12" letter-spacing="1.2" fill="${C.glassText}">INCLUDE: ${listed.length} COMPONENTS · STAGE ${esc(stages.toUpperCase())}</text>`,
    ...listed.map((it, i) => {
      const y = jobsY + 30 + i * rowGap;
      return (
        `<text x="${panelX + lampPadX}" y="${y}" font-family="${MONO}" font-size="14" fill="${C.cream}"><tspan fill="${C.gold}">- </tspan>${esc(it.job)}</text>` +
        `<text x="${panelX + panelW - lampPadX}" y="${y}" text-anchor="end" font-family="${MONO}" font-size="12" letter-spacing="0.6" fill="${C.lit}">${esc(tagLabel)}</text>`
      );
    }),
  ].join("\n  ");
  const jobsBottom = jobsY + 30 + (listed.length - 1) * rowGap;

  // ---- screws (simple geometry: the page's placards and instrument have them)
  const screw = (x, y) =>
    `<circle cx="${x}" cy="${y}" r="4.5" fill="#8F8A7E"/><circle cx="${x - 0.8}" cy="${y - 0.8}" r="2.6" fill="#E6E1D4"/><line x1="${x - 3}" y1="${y + 1.5}" x2="${x + 3}" y2="${y - 1.5}" stroke="#5E5A50" stroke-width="1.2"/>`;
  const screws = [
    [panelX + 12, panelY + 12],
    [panelX + panelW - 12, panelY + 12],
    [panelX + 12, panelY + panelH - 12],
    [panelX + panelW - 12, panelY + panelH - 12],
  ]
    .map(([x, y]) => screw(x, y))
    .join("");

  const jobSummary = items
    .filter((it) => it.tpl)
    .map((it) => `${it.name} (${it.tpl.job}): ${it.resp}`)
    .join("; ");
  const desc = `PREFLIGHT's checklist card, "${d.title}". ${jobSummary}; then ${items.at(-1).name}: ${items.at(-1).resp}. Each item is ticked in turn and its lamp on the annunciator panel goes green; ${d.lamps
    .filter((l) => l.soon)
    .map((l) => l.face)
    .join(", ")} are marked coming soon. ${d.foot}`;
  assertTextClean(desc, "checklist description");

  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" role="img" aria-labelledby="pf-title pf-desc">
  <title id="pf-title">PREFLIGHT's before-takeoff checklist, run on every push</title>
  <desc id="pf-desc">${esc(desc)}</desc>
  <style>
${fontCss}
${keyframes.join("\n")}
${items.map((_, i) => `.on${i}{animation:on${i} ${T}s linear infinite}.tk${i}{animation:tk${i} ${T}s linear infinite}`).join("\n")}
.reading{animation:rd ${T}s ease-in-out infinite}
.foot{animation:ft ${T}s linear infinite}
@media (prefers-reduced-motion: reduce){
  .on,.tk,.foot{animation:none;opacity:1;stroke-dashoffset:0}
  .reading{animation:none;opacity:0}
}
  </style>
  <defs>
    <pattern id="soon" width="12" height="12" patternUnits="userSpaceOnUse" patternTransform="rotate(135)">
      <rect width="12" height="12" fill="#11181B"/><rect width="6" height="12" fill="#151E21"/>
    </pattern>
    <filter id="glow" x="-30%" y="-30%" width="160%" height="160%">
      <feGaussianBlur in="SourceAlpha" stdDeviation="5" result="blur"/>
      <feFlood flood-color="${C.lit}" flood-opacity="0.45" result="tint"/>
      <feComposite in="tint" in2="blur" operator="in" result="halo"/>
      <feMerge><feMergeNode in="halo"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
    <clipPath id="card"><rect x="${cardX + 9}" y="${40 + 9}" width="${cardW - 18}" height="${cardH - 18}" rx="14"/></clipPath>
  </defs>

  <!-- the cockpit deck: opaque, so the card reads on white and on near-black -->
  <rect width="${W}" height="${H}" rx="24" fill="${C.deck}"/>
  <rect x="1" y="1" width="${W - 2}" height="${H - 2}" rx="23" fill="none" stroke="${C.deckEdge}" stroke-width="2"/>

  <!-- the laminated checklist -->
  <rect x="${cardX}" y="40" width="${cardW}" height="${cardH}" rx="22" fill="#FFFFFF" fill-opacity="0.6"/>
  <g clip-path="url(#card)">
    <rect x="${cardX}" y="40" width="${cardW}" height="${cardH}" fill="${C.paper}"/>
    <rect x="${cardX}" y="40" width="${cardW}" height="${headH}" fill="${C.green}"/>
    <rect class="reading" x="${cardX + 9}" y="${listTop + 2}" width="${cardW - 18}" height="${rowH - 4}" fill="${C.gold}" fill-opacity="0.22"/>
${rowSvg}
    <text class="foot" x="${cardX + cardW / 2}" y="${footY}" text-anchor="middle" font-family="${MONO}" font-weight="700" font-size="14" letter-spacing="1.2" fill="${C.green}">${esc(d.foot.toUpperCase())}</text>
  </g>
  <circle cx="${cardX + cardW / 2}" cy="${40 + 23}" r="11" fill="#ECE8DE" stroke="#FFFFFF" stroke-opacity="0.5" stroke-width="5"/>
  <circle cx="${cardX + cardW / 2}" cy="${40 + 24}" r="9" fill="none" stroke="#000" stroke-opacity="0.12" stroke-width="2"/>
  <text x="${cardX + cardW / 2}" y="${40 + 66}" text-anchor="middle" font-family="${MONO}" font-size="13" letter-spacing="1.8" fill="#CFE3DD">${esc(d.kicker.toUpperCase())}</text>
  <text x="${cardX + cardW / 2}" y="${40 + 100}" text-anchor="middle" font-family="${DISPLAY}" font-weight="700" font-size="28" fill="${C.cream}">${esc(titleMain)} <tspan font-family="${MONO}" font-weight="400" font-size="17" fill="#CFE3DD">${esc(d.titleTail)}</tspan></text>

  <!-- the annunciator panel -->
  <rect x="${panelX}" y="${panelY}" width="${panelW}" height="${panelH}" rx="16" fill="#1E2A2F" stroke="${C.deckEdge}" stroke-width="2"/>
  ${screws}
  <text x="${panelX + panelW / 2}" y="${panelY + 42}" text-anchor="middle" font-family="${MONO}" font-weight="700" font-size="13" letter-spacing="3" fill="${C.glassText}">${esc(d.panelTitle.toUpperCase())}</text>
${lampSvg}
  <line x1="${panelX + lampPadX}" y1="${jobsY - 22}" x2="${panelX + panelW - lampPadX}" y2="${jobsY - 22}" stroke="${C.gold}" stroke-opacity="0.5" stroke-width="1.5"/>
  ${jobsSvg}
</svg>
`;
  if (jobsBottom > panelY + panelH - 24) {
    fail("annunciator panel content overflows the panel");
  }
  record("checklist.svg", Buffer.from(svg, "utf8"));
}

/* -------------------------------------------------------------- 7. gallery */

// A contact sheet of three existing mobile crops, composed as a tiny HTML
// page and screenshotted. The three are the placards, the flight plan and the
// flight manual: the crops of the other sections show the internal deploy
// platform's name, so they stay out. Their source sections are text-checked.
async function buildGallery(page) {
  console.log("gallery:");
  const crops = [
    { file: "mobile-04-components-1.png", section: "#components" },
    { file: "mobile-05-flight-plan-1.png", section: "#flight-plan" },
    { file: "mobile-06-manual-1.png", section: "#manual" },
  ];
  for (const c of crops) {
    if (!existsSync(path.join(siteDir, "screenshots", "sections", c.file))) fail(`missing crop ${c.file}`);
    await assertClean(page, c.section, `section ${c.section}`);
  }
  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<style>
  html, body { margin: 0; padding: 0; }
  .sheet { width: fit-content; background: ${C.deck}; padding: 40px; display: flex; gap: 32px; }
  img {
    box-sizing: border-box;
    display: block;
    width: 360px;
    height: 640px;
    object-fit: cover;
    object-position: top;
    border-radius: 14px;
    border: 1px solid rgba(255, 204, 51, .35);
  }
</style>
</head>
<body>
<div class="sheet">
${crops.map((c) => `  <img src="${pathToFileURL(path.join(siteDir, "screenshots", "sections", c.file)).href}" alt="">`).join("\n")}
</div>
</body>
</html>`;
  await page.setContent(html, { waitUntil: "load" });
  const png = await page.locator(".sheet").screenshot();
  const jpg = await sharp(png).resize({ width: 1280 }).jpeg({ quality: 82, mozjpeg: true }).toBuffer();
  record("gallery.jpg", jpg);
}

/* ---------------------------------------------------------------- 8. board */

async function buildBoard() {
  console.log("board:");
  const src = path.join(siteDir, "brand", "preflight-board.png");
  if (!existsSync(src)) fail("missing site/brand/preflight-board.png");
  // Step the quality down until the board fits the size gate.
  for (const q of [84, 80, 76, 72, 68]) {
    const jpg = await sharp(readFileSync(src)).resize({ width: 1280, withoutEnlargement: true }).jpeg({ quality: q, mozjpeg: true }).toBuffer();
    if (jpg.length <= MAX_BYTES || q === 68) {
      record("board.jpg", jpg);
      return;
    }
  }
}

/* -------------------------------------------------------------------- main */

async function main() {
  const templates = readTemplates();
  await buildCast();
  buildBadges(templates);
  await buildBoard();

  const browser = await chromium.launch();
  try {
    const { context, page } = await openPage(browser);
    await buildHero(page);
    // The checklist reads the page's DOM first, then measures its text on
    // the same tab, so the page is reloaded for the gallery's text checks.
    await buildChecklist(page, templates);
    await page.goto(pathToFileURL(path.join(siteDir, "index.html")).href, { waitUntil: "load" });
    await buildGallery(page);
    await context.close();
  } finally {
    await browser.close();
  }

  let over = false;
  for (const { rel, bytes } of outputs) {
    if (bytes > MAX_BYTES) {
      console.error(`FAIL: ${rel} is ${bytes} bytes (limit ${MAX_BYTES})`);
      over = true;
    }
  }
  if (over) process.exit(1);
  console.log(`done: ${outputs.length} files, all at or under ${MAX_BYTES} bytes`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
