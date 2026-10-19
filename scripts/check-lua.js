#!/usr/bin/env node
// CrowdCalmLab static gate (luaparse). Stand-in for luacheck, which is not
// available on every machine. Checks:
//   1. every CrowdCalmLab/**/*.lua parses as Lua 5.1
//   2. CrowdCalmLab/CrowdCalmLab.toc first line is "## Interface: 120105, 120107, 16001"
//   3. bidirectional TOC <-> file check (listed files exist, every .lua is listed)
//   4. "## IconTexture" path exists when the key is present
//   5. (G3) Media/ manifest: every expected .tga exists, is power-of-two,
//      and the total is under 1 MB
//   6. (G4) Locale: ns.L must be callable (__call present) because the
//      codebase calls L("key"); missing literal locale keys warn (fallback
//      renders the key text by design, so they are warnings not failures).
//   7. (G5) Glyphs: string literals may only contain Latin-1 (<= U+00FF)
//      plus U+2014 (em dash). The WoW client font subset renders those and
//      nothing else; e.g. U+2192 (->) draws as a tofu box in game.
// Usage: node scripts/check-lua.js [--fixture]
//   --fixture  parse scripts/fixtures/broken.lua instead; the gate must exit
//              non-zero (proves the gate can fail).
"use strict";

const fs = require("fs");
const path = require("path");

function loadLuaparse() {
  try {
    return require("luaparse");
  } catch (e) {
    /* fall through */
  }
  const tools = process.env.CCL_TOOLS;
  if (tools) {
    try {
      return require(path.join(tools, "node_modules", "luaparse"));
    } catch (e) {
      /* fall through */
    }
  }
  console.error(
    "check-lua: luaparse not found. Run `npm install luaparse` somewhere and " +
      "set CCL_TOOLS to that folder (it must contain node_modules/luaparse)."
  );
  process.exit(2);
}

const luaparse = loadLuaparse();
const repoRoot = path.resolve(__dirname, "..");
const addonDir = path.join(repoRoot, "CrowdCalmLab");
const tocPath = path.join(addonDir, "CrowdCalmLab.toc");
const expectedInterface = "## Interface: 120105, 120107, 16001";

let failures = 0;
function fail(msg) {
  failures += 1;
  console.error("FAIL " + msg);
}
function ok(msg) {
  console.log("ok   " + msg);
}

function listLua(dir, out) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      listLua(full, out);
    } else if (entry.name.toLowerCase().endsWith(".lua")) {
      out.push(full);
    }
  }
  return out;
}

// --- G3: media texture manifest ----------------------------------------
const MEDIA_MANIFEST = [
  "shadow.tga",
  "vignette.tga",
  "noise.tga",
  "glow.tga",
  "sweep.tga",
  "arc.tga",
  "emblem.tga",
  "icon.tga",
  "icon_overview.tga",
  "icon_lab.tga",
  "icon_results.tga",
  "icon_stutter.tga",
  "icon_addons.tga",
  "icon_settings.tga",
  "icon_about.tga",
  // pre.4 chrome
  "btn_dark.tga",
  "btn_gold.tga",
  "ring.tga",
  "gauge_dim.tga",
  "gauge_q.tga",
  "gauge_b.tga",
  "gauge_p.tga",
  // pre.6 visual pass
  "accent.tga",
  "spark_bar.tga",
  "bar_fill.tga",
  "bar_track.tga",
  "gauge_pip.tga",
];
const MEDIA_MAX_BYTES = 1024 * 1024; // 1 MB total budget

function isPowerOfTwo(n) {
  return n > 0 && (n & (n - 1)) === 0;
}

function checkMedia() {
  const mediaDir = path.join(addonDir, "Media");
  let total = 0;
  for (const name of MEDIA_MANIFEST) {
    const full = path.join(mediaDir, name);
    if (!fs.existsSync(full)) {
      fail("media missing: Media/" + name);
      continue;
    }
    const buf = fs.readFileSync(full);
    total += buf.length;
    if (buf.length < 18) {
      fail("media too small (not a TGA?): Media/" + name);
      continue;
    }
    const width = buf.readUInt16LE(12);
    const height = buf.readUInt16LE(14);
    if (!isPowerOfTwo(width) || !isPowerOfTwo(height)) {
      fail(
        "media not power-of-two: Media/" +
          name +
          " (" +
          width +
          "x" +
          height +
          ")"
      );
    }
  }
  if (total > MEDIA_MAX_BYTES) {
    fail(
      "media total " + total + " bytes exceeds budget " + MEDIA_MAX_BYTES
    );
  } else {
    ok(
      "media manifest (" +
        MEDIA_MANIFEST.length +
        " files, " +
        total +
        " bytes < 1 MB)"
    );
  }
}

function parseFile(file, label) {
  const src = fs.readFileSync(file, "utf8");
  try {
    const ast = luaparse.parse(src, { luaVersion: "5.1", locations: true });
    ok("parse " + label);
    return ast;
  } catch (e) {
    fail(
      "parse " +
        label +
        " line " +
        (e.line || (e.message.match(/(\d+):/) || [])[1] || "?") +
        ": " +
        e.message
    );
    return false;
  }
}

// --- G5: glyph safety (Latin-1 + em dash only) ----------------------------
// luaparse 0.3.1 gives StringLiteral { value: null, raw: "\"hi\"" }, so the
// raw literal must be decoded here (Lua 5.1 escapes incl. \ddd) before the
// code-point scan; otherwise an escaped non-Latin char would slip through.
function luaStringValue(raw) {
  if (typeof raw !== "string" || raw.length < 2) return raw || "";
  const quote = raw[0];
  if (quote === '"' || quote === "'") {
    let out = "";
    const end = raw.length - 1; // closing quote
    let i = 1;
    while (i < end) {
      let c = raw[i];
      if (c !== "\\") {
        out += c;
        i += 1;
        continue;
      }
      i += 1;
      if (i >= end) break;
      const e = raw[i];
      if (e === "a") out += "\x07";
      else if (e === "b") out += "\x08";
      else if (e === "f") out += "\x0c";
      else if (e === "n") out += "\n";
      else if (e === "r") out += "\r";
      else if (e === "t") out += "\t";
      else if (e === "v") out += "\x0b";
      else if (e === "\n") out += "\n";
      else if (e === "\r") {
        out += "\n";
        i += 1;
      } else if (e >= "0" && e <= "9") {
        let digits = e;
        while (
          digits.length < 3 &&
          i + 1 < end &&
          raw[i + 1] >= "0" &&
          raw[i + 1] <= "9"
        ) {
          i += 1;
          digits += raw[i];
        }
        out += String.fromCharCode(parseInt(digits, 10));
      } else {
        out += e;
      }
      i += 1;
    }
    return out;
  }
  const m = raw.match(/^\[(=*)\[/);
  if (m) {
    const closer = "]" + m[1] + "]";
    return raw.slice(m[0].length, raw.length - closer.length);
  }
  return raw;
}

function walkStringLiterals(node, cb) {
  if (node === null || typeof node !== "object") return;
  if (Array.isArray(node)) {
    for (const n of node) walkStringLiterals(n, cb);
    return;
  }
  if (
    node.type === "StringLiteral" &&
    typeof node.raw === "string"
  ) {
    cb(node);
  }
  for (const key of Object.keys(node)) {
    if (key === "loc" || key === "range") continue;
    walkStringLiterals(node[key], cb);
  }
}

const GLYPH_ALLOWED_EM_DASH = 0x2014; // renders in the WoW font subset

function checkGlyphs(asts) {
  // asts: [{ label, ast }] for files that parsed successfully.
  let problems = 0;
  let strings = 0;
  for (const entry of asts) {
    walkStringLiterals(entry.ast, (node) => {
      strings += 1;
      const v = luaStringValue(node.raw);
      for (let i = 0; i < v.length; i++) {
        const cp = v.charCodeAt(i);
        if (cp > 0xff && cp !== GLYPH_ALLOWED_EM_DASH) {
          problems += 1;
          const line = node.loc && node.loc.start ? node.loc.start.line : "?";
          fail(
            "glyph " +
              entry.label +
              ":" +
              line +
              " U+" +
              cp.toString(16).toUpperCase().padStart(4, "0") +
              " (" +
              JSON.stringify(v[i]) +
              ") in string " +
              JSON.stringify(v.length > 40 ? v.slice(0, 40) + "..." : v) +
              " (allowed: ASCII/Latin-1 + em dash U+2014)"
          );
        }
      }
    });
  }
  if (problems === 0) {
    ok(
      "glyph check (" + strings + " string literals, 0 out-of-range chars)"
    );
  }
}

// --- G4: locale callability + literal key coverage -----------------------
function checkLocale(luaFiles) {
  const localePath = path.join(addonDir, "Core", "Locale.lua");
  if (!fs.existsSync(localePath)) {
    fail("locale check: Core/Locale.lua missing");
    return;
  }
  const localeSrc = fs.readFileSync(localePath, "utf8");

  // 1. L("key") is called across the codebase; L must be callable.
  const callSites = luaFiles.filter((f) => {
    if (f === localePath) return false;
    return /\bL\(\s*"/.test(fs.readFileSync(f, "utf8"));
  });
  if (callSites.length > 0 && !/__call/.test(localeSrc)) {
    fail(
      "locale: L(\"key\") used in " +
        callSites.length +
        " file(s) but Core/Locale.lua defines no __call metamethod " +
        "(L is a table: every L() call errors at runtime)"
    );
    return;
  }

  // 2. literal keys: collect defined keys from the strings table.
  const defined = new Set();
  const defRe = /^\s*([A-Za-z0-9_]+)\s*=\s*"/gm;
  let m;
  while ((m = defRe.exec(localeSrc)) !== null) defined.add(m[1]);

  // 3. literal call-site keys (L("x") and Lfmt("x")); dynamic keys
  //    ("crowd_" .. label) never close the paren right after the key, so
  //    they are not matched by design.
  const used = new Map(); // key -> first file
  const useRe = /\b(?:L|Lfmt)\(\s*"([A-Za-z0-9_]+)"\s*\)/g;
  for (const f of luaFiles) {
    const src = fs.readFileSync(f, "utf8");
    useRe.lastIndex = 0;
    let u;
    while ((u = useRe.exec(src)) !== null) {
      if (!used.has(u[1])) {
        used.set(u[1], path.relative(addonDir, f));
      }
    }
  }
  const missing = [...used.keys()].filter((k) => !defined.has(k));
  if (missing.length > 0) {
    console.warn(
      "warn locale keys used but not defined (render as key text): " +
        missing.join(", ")
    );
  }
  ok(
    "locale callable (" +
      callSites.length +
      " files call L(\"key\"), " +
      used.size +
      " literal keys, " +
      missing.length +
      " missing)"
  );
}

function main() {
  const argv = process.argv.slice(2);

  if (argv.includes("--fixture")) {
    const fixture = path.join(__dirname, "fixtures", "broken.lua");
    if (!fs.existsSync(fixture)) {
      fail("fixture missing: scripts/fixtures/broken.lua");
      process.exit(1);
    }
    const clean = parseFile(fixture, "scripts/fixtures/broken.lua");
    if (clean) {
      fail("fixture parsed cleanly but must contain a syntax error (gate cannot fail)");
      process.exit(1);
    }
    console.log("check-lua: fixture correctly rejected (gate is able to fail).");
    process.exit(1); // non-zero: the fixture IS broken; RED is proven by this exit code.
  }

  // --- TOC checks -------------------------------------------------------
  if (!fs.existsSync(tocPath)) {
    fail("TOC missing: CrowdCalmLab/CrowdCalmLab.toc");
    report();
    return;
  }
  const tocRaw = fs.readFileSync(tocPath, "utf8");
  const tocLines = tocRaw.split(/\r?\n/);
  if (tocLines[0] !== expectedInterface) {
    fail(
      "TOC first line must be exactly: " +
        expectedInterface +
        " (found: " +
        JSON.stringify(tocLines[0] || "") +
        ")"
    );
  } else {
    ok("TOC first line: " + expectedInterface);
  }

  const listed = [];
  let iconTexture = null;
  for (let i = 1; i < tocLines.length; i++) {
    const line = tocLines[i].trim();
    if (line === "" || line.startsWith("#")) {
      const m = line.match(/^##\s+IconTexture\s*:\s*(.+)$/);
      if (m) iconTexture = m[1].trim();
      continue;
    }
    listed.push(line.replace(/\//g, "\\"));
  }

  for (const rel of listed) {
    const full = path.join(addonDir, rel);
    if (!fs.existsSync(full)) fail("TOC lists missing file: " + rel);
  }
  if (listed.length > 0) ok("TOC file entries exist (" + listed.length + ")");

  if (iconTexture) {
    // IconTexture is a WoW-install-relative path
    // (Interface\AddOns\<Addon>\Media\icon.tga); resolve it against the
    // addon folder by stripping the Interface\AddOns\<name>\ prefix.
    const normalized = iconTexture.replace(/\//g, "\\");
    const prefix = "Interface\\AddOns\\CrowdCalmLab\\";
    let rel = normalized;
    if (normalized.toLowerCase().startsWith(prefix.toLowerCase())) {
      rel = normalized.slice(prefix.length);
    }
    const iconFull = path.join(addonDir, rel);
    if (!fs.existsSync(iconFull)) {
      fail("## IconTexture missing on disk: " + iconTexture);
    } else {
      ok("## IconTexture exists: " + iconTexture);
    }
  }

  // --- parse every addon lua + bidirectional TOC check ------------------
  const luaFiles = fs.existsSync(addonDir) ? listLua(addonDir, []) : [];
  const listedSet = new Set(listed.map((s) => s.toLowerCase()));
  let allParsed = true;
  const asts = [];
  for (const file of luaFiles) {
    const rel = path.relative(addonDir, file).replace(/\\/g, "\\");
    if (!listedSet.has(rel.toLowerCase())) {
      fail("lua file not listed in TOC: " + rel);
    }
    const ast = parseFile(file, rel);
    if (ast) asts.push({ label: rel, ast });
    allParsed = ast && allParsed;
  }

  // --- G3 media manifest ------------------------------------------------
  checkMedia();

  // --- G4 locale callability + key coverage -----------------------------
  checkLocale(luaFiles);

  // --- G5 glyph safety --------------------------------------------------
  checkGlyphs(asts);

  report(luaFiles.length, listed.length);
}

function report(luaCount, tocCount) {
  console.log(
    "check-lua: " +
      luaCount +
      " lua files, " +
      tocCount +
      " TOC entries, " +
      failures +
      " failure(s)"
  );
  process.exit(failures > 0 ? 1 : 0);
}

main();
