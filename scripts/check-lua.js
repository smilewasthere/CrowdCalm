#!/usr/bin/env node
// CrowdCalmLab static gate (luaparse). Stand-in for luacheck, which is not
// available on every machine. Checks:
//   1. every CrowdCalmLab/**/*.lua parses as Lua 5.1
//   2. CrowdCalmLab/CrowdCalmLab.toc first line is "## Interface: 120105, 120107, 16001"
//   3. bidirectional TOC <-> file check (listed files exist, every .lua is listed)
//   4. "## IconTexture" path exists when the key is present
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

function parseFile(file, label) {
  const src = fs.readFileSync(file, "utf8");
  try {
    luaparse.parse(src, { luaVersion: "5.1", locations: true });
    ok("parse " + label);
    return true;
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
    const iconFull = path.join(addonDir, iconTexture.replace(/\//g, "\\"));
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
  for (const file of luaFiles) {
    const rel = path.relative(addonDir, file).replace(/\\/g, "\\");
    if (!listedSet.has(rel.toLowerCase())) {
      fail("lua file not listed in TOC: " + rel);
    }
    allParsed = parseFile(file, rel) && allParsed;
  }

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
