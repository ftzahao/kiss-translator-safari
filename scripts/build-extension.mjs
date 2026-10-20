#!/usr/bin/env node
/**
 * Fetches the pinned upstream release and builds its `safari` web-extension
 * output into build/extension.
 *
 * Why a script instead of a git subtree: this repository is a *packaging*
 * wrapper, not a fork. Pinning an immutable upstream commit keeps the
 * repository small, makes every shipped build reproducible, and lets the
 * upstream web-extension source stay a single `git clone` away for auditing.
 *
 * Usage:
 *   node scripts/build-extension.mjs            # fetch (cached) + build
 *   node scripts/build-extension.mjs --force    # ignore caches, full rebuild
 *   node scripts/build-extension.mjs --offline  # require an existing checkout
 */
import fs from "node:fs/promises";
import path from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

import { upstream, app } from "../config/build.config.mjs";
import { normalizeManifest, validateManifest } from "./lib/manifest.mjs";
import { step, info, ok, warn, fail, dim } from "./lib/log.mjs";

const run = promisify(execFile);
const ROOT = path.resolve(fileURLToPath(new URL("..", import.meta.url)));

const UPSTREAM_DIR = path.join(ROOT, ".build", "upstream");
const EXTENSION_DIR = path.join(ROOT, "build", "extension");
const RAW_DIR = path.join(ROOT, ".build", "upstream-safari-raw");

const args = new Set(process.argv.slice(2));
const FORCE = args.has("--force");
const OFFLINE = args.has("--offline");
const REMOTE = process.env.UPSTREAM_REMOTE ?? `https://github.com/${upstream.owner}/${upstream.repo}.git`;

/** Runs a command, streaming nothing but throwing a readable error on failure. */
async function sh(cmd, argv, opts = {}) {
  try {
    return await run(cmd, argv, { cwd: ROOT, maxBuffer: 64 * 1024 * 1024, ...opts });
  } catch (err) {
    const detail = [err.stdout, err.stderr].filter(Boolean).join("\n").trim();
    throw new Error(
      `Command failed: ${cmd} ${argv.join(" ")}\n${detail || err.message}`
    );
  }
}

/** Recursively lists files as POSIX relative paths. */
async function listFiles(dir, prefix = "") {
  const out = [];
  for (const entry of await fs.readdir(dir, { withFileTypes: true })) {
    const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) out.push(...(await listFiles(path.join(dir, entry.name), rel)));
    else out.push(rel);
  }
  return out;
}

async function exists(p) {
  try {
    await fs.access(p);
    return true;
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Toolchain checks
// ---------------------------------------------------------------------------

async function checkToolchain() {
  step("Checking toolchain");

  const nodeMajor = Number(process.versions.node.split(".")[0]);
  if (nodeMajor < upstream.nodeMajor) {
    throw new Error(
      `Node.js ${upstream.nodeMajor}+ required to build upstream, found ${process.versions.node}.`
    );
  }
  ok(`node ${process.versions.node}`);

  // Upstream pins an exact pnpm in .pnpm-version. pnpm 10+ refuses the
  // lockfile ("ERR_PNPM_LOCKFILE_CONFIG_MISMATCH"), so we always invoke the
  // pinned version explicitly instead of trusting whatever `pnpm` is on PATH.
  const pnpmBin = await ensurePnpm();
  ok(`pnpm ${upstream.pnpmVersion} (${dim(pnpmBin)})`);
  return pnpmBin;
}

let cachedPnpm;
async function ensurePnpm() {
  if (cachedPnpm) return cachedPnpm;

  const toolsDir = path.join(ROOT, ".build", "tools");
  const localBin = path.join(toolsDir, "node_modules", ".bin", "pnpm");

  if (await exists(localBin)) {
    cachedPnpm = localBin;
    return cachedPnpm;
  }

  // Prefer a globally installed copy when it is already the pinned version.
  try {
    const { stdout } = await run("pnpm", ["--version"]);
    if (stdout.trim() === upstream.pnpmVersion) {
      cachedPnpm = "pnpm";
      return cachedPnpm;
    }
    warn(`global pnpm is ${stdout.trim()}, expected ${upstream.pnpmVersion}`);
  } catch {
    /* pnpm not installed globally — fall through to a local install */
  }

  info(`installing pnpm@${upstream.pnpmVersion} into .build/tools ...`);
  await fs.mkdir(toolsDir, { recursive: true });
  await fs.writeFile(
    path.join(toolsDir, "package.json"),
    JSON.stringify({ name: "build-tools", private: true, version: "0.0.0" }, null, 2)
  );
  await sh("npm", [
    "install",
    "--no-audit",
    "--no-fund",
    `pnpm@${upstream.pnpmVersion}`,
  ], { cwd: toolsDir });
  cachedPnpm = localBin;
  return cachedPnpm;
}

// ---------------------------------------------------------------------------
// Upstream checkout
// ---------------------------------------------------------------------------

async function fetchUpstream() {
  step(`Fetching ${upstream.owner}/${upstream.repo} @ ${upstream.version}`);

  const wantCommit = upstream.commit;

  if (await exists(path.join(UPSTREAM_DIR, ".git"))) {
    const { stdout } = await sh("git", ["rev-parse", "HEAD"], { cwd: UPSTREAM_DIR });
    if (stdout.trim() === wantCommit && !FORCE) {
      ok(`checkout already at ${wantCommit.slice(0, 7)}`);
      return;
    }
    info("checkout is stale, refetching ...");
    if (OFFLINE) {
      throw new Error(
        `--offline was requested but the checkout is at ${stdout.trim()}, not ${wantCommit}`
      );
    }
    await fs.rm(UPSTREAM_DIR, { recursive: true, force: true });
  }

  if (OFFLINE) {
    throw new Error(`--offline was requested but no upstream checkout exists`);
  }

  await fs.mkdir(path.dirname(UPSTREAM_DIR), { recursive: true });
  await sh("git", ["init", "--quiet", UPSTREAM_DIR]);
  await sh("git", ["remote", "add", "origin", REMOTE], { cwd: UPSTREAM_DIR });

  info(`fetching commit ${wantCommit.slice(0, 7)} ...`);
  await sh("git", ["fetch", "--depth", "1", "--quiet", "origin", wantCommit], {
    cwd: UPSTREAM_DIR,
  });
  await sh("git", ["-c", "advice.detachedHead=false", "checkout", "--quiet", wantCommit], {
    cwd: UPSTREAM_DIR,
  });

  // Verify the tag actually points at the commit we pinned. A wrong pair would
  // silently ship a different version than the one advertised.
  if (upstream.version) {
    try {
      const { stdout } = await run("git", [
        "ls-remote", "--tags", "origin", `refs/tags/v${upstream.version}^{}`, `refs/tags/v${upstream.version}`,
      ], { cwd: UPSTREAM_DIR });
      const tagged = stdout
        .split("\n")
        .filter(Boolean)
        .map((line) => line.split("\t")[0]);
      if (tagged.length && !tagged.includes(wantCommit)) {
        throw new Error(
          `v${upstream.version} points at ${tagged.join(", ")}, but config pins ${wantCommit}. ` +
            `Update config/build.config.mjs (version and commit must agree).`
        );
      }
      ok(`tag v${upstream.version} matches pinned commit`);
    } catch (err) {
      // Network may be unavailable; the commit pin is still exact, so warn only.
      if (/points at|config pins/.test(err.message)) throw err;
      warn(`could not verify tag/commit pairing: ${err.message.split("\n")[0]}`);
    }
  }

  ok(`checkout ready at ${wantCommit.slice(0, 7)}`);
}

// ---------------------------------------------------------------------------
// Upstream build
// ---------------------------------------------------------------------------

async function buildUpstream(pnpmBin) {
  step("Installing upstream dependencies");

  const stampPath = path.join(UPSTREAM_DIR, "node_modules", ".install-stamp");
  const stamp = JSON.stringify({
    commit: upstream.commit,
    pnpm: upstream.pnpmVersion,
    node: process.versions.node.split(".")[0],
  });

  const current = (await exists(stampPath))
    ? (await fs.readFile(stampPath, "utf8")).trim()
    : null;

  if (current === stamp && !FORCE) {
    ok("dependencies already installed for this commit");
  } else {
    // The upstream lockfile is authoritative: `--frozen-lockfile` also proves
    // the checkout has not been tampered with.
    await sh(pnpmBin, ["install", "--frozen-lockfile", "--reporter=append-only"], {
      cwd: UPSTREAM_DIR,
      env: {
        ...process.env,
        // Keep pnpm's global store out of the project tree and out of $HOME,
        // so builds are hermetic and never collide with the user's projects.
        npm_config_store_dir: path.join(UPSTREAM_DIR, ".pnpm-store"),
      },
    });
    await fs.writeFile(stampPath, stamp);
    ok("dependencies installed");
  }

  step("Building upstream web extension (target: safari)");
  // build-task.mjs honours BUILD_PATH and writes to <root>/build/<target>.
  await sh(pnpmBin, ["run", "build:safari-output"], {
    cwd: UPSTREAM_DIR,
    env: {
      ...process.env,
      NODE_ENV: "production",
      GENERATE_SOURCEMAP: "false",
      CI: "false",
      // react-app-rewired treats CI=true as "fail on warnings" and upstream is
      // not warning-clean; the artefact is still valid.
    },
  });

  const raw = path.join(UPSTREAM_DIR, "build", "safari");
  if (!(await exists(path.join(raw, "manifest.json")))) {
    throw new Error(`upstream build did not produce ${raw}/manifest.json`);
  }
  const files = await listFiles(raw);
  ok(`built ${files.length} files (${(await dirSize(raw) / 1024 / 1024).toFixed(1)} MiB)`);
  return raw;
}

async function dirSize(dir) {
  let total = 0;
  for (const entry of await fs.readdir(dir, { withFileTypes: true })) {
    const p = path.join(dir, entry.name);
    if (entry.isDirectory()) total += await dirSize(p);
    else total += (await fs.stat(p)).size;
  }
  return total;
}

// ---------------------------------------------------------------------------
// Safari normalization
// ---------------------------------------------------------------------------

async function normalize(rawDir) {
  step("Adapting manifest for Safari");

  await fs.rm(RAW_DIR, { recursive: true, force: true });
  await fs.cp(rawDir, RAW_DIR, { recursive: true });

  const manifestPath = path.join(RAW_DIR, "manifest.json");
  const original = JSON.parse(await fs.readFile(manifestPath, "utf8"));
  const { manifest, changes } = normalizeManifest(original, {
    displayName: app.displayName,
  });

  manifest.version = upstream.version;

  const files = await listFiles(RAW_DIR);
  validateManifest(manifest, files, app.displayName);

  await fs.writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

  if (changes.length === 0) ok("manifest already Safari-compatible");
  for (const change of changes) info(`· ${change}`);

  ok("manifest validated");
}

async function publish() {
  step("Publishing extension bundle");
  await fs.rm(EXTENSION_DIR, { recursive: true, force: true });
  await fs.mkdir(path.dirname(EXTENSION_DIR), { recursive: true });
  await fs.cp(RAW_DIR, EXTENSION_DIR, { recursive: true });

  const manifest = JSON.parse(
    await fs.readFile(path.join(EXTENSION_DIR, "manifest.json"), "utf8")
  );
  // A build fingerprint lets the native app and CI confirm what they are
  // shipping without re-parsing the extension.
  await fs.writeFile(
    path.join(EXTENSION_DIR, "build-info.json"),
    `${JSON.stringify(
      {
        upstream: {
          repository: `https://github.com/${upstream.owner}/${upstream.repo}`,
          version: upstream.version,
          commit: upstream.commit,
        },
        builtAt: new Date().toISOString(),
        builtBy: "kiss-translator-safari/scripts/build-extension.mjs",
      },
      null,
      2
    )}\n`
  );

  const files = await listFiles(EXTENSION_DIR);
  ok(`extension ready at ${path.relative(ROOT, EXTENSION_DIR)} (${files.length} files)`);
  info(`${dim("name:")} ${manifest.name} ${dim("version:")} ${manifest.version}`);
  return manifest;
}

async function main() {
  console.log(`\nKISS Translator Safari extension builder`);
  console.log(dim(`upstream ${upstream.version} @ ${upstream.commit.slice(0, 7)}`));

  try {
    const pnpmBin = await checkToolchain();
    await fetchUpstream();
    const raw = await buildUpstream(pnpmBin);
    await normalize(raw);
    const manifest = await publish();
    console.log(`\n${ok("done")} — extension ${manifest.version} ready\n`);
  } catch (err) {
    fail(err.message);
    process.exitCode = 1;
  }
}

main();
