#!/usr/bin/env node
/**
 * Verifies that a built .app really is a loadable Safari Web Extension.
 *
 * This is the check that catches the class of bug which is invisible in a
 * normal build: an .appex whose manifest sits one directory too deep, a
 * missing icon, a stale extension version, or a non-universal binary. Run it
 * after `make all` and in CI.
 */
import fs from "node:fs/promises";
import path from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

import { app, upstream } from "../config/build.config.mjs";
import { validateManifest } from "./lib/manifest.mjs";
import { step, info, ok, warn, fail } from "./lib/log.mjs";

const run = promisify(execFile);
const ROOT = path.resolve(fileURLToPath(new URL("..", import.meta.url)));
const APP = path.join(ROOT, "build", "App", `${app.productName}.app`);

const problems = [];
const notes = [];

function check(condition, message) {
  if (condition) ok(message);
  else problems.push(message);
}

async function exists(p) {
  try {
    await fs.access(p);
    return true;
  } catch {
    return false;
  }
}

async function listFiles(dir, prefix = "") {
  const out = [];
  for (const entry of await fs.readdir(dir, { withFileTypes: true })) {
    const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) out.push(...(await listFiles(path.join(dir, entry.name), rel)));
    else out.push(rel);
  }
  return out;
}

async function plistValue(plistPath, key) {
  try {
    const { stdout } = await run("/usr/libexec/PlistBuddy", [
      "-c", `Print :${key}`, plistPath,
    ]);
    return stdout.trim();
  } catch {
    return null;
  }
}

async function main() {
  step(`Verifying ${path.relative(ROOT, APP)}`);

  if (!(await exists(APP))) {
    throw new Error(
      `${path.relative(ROOT, APP)} does not exist — run \`make all\` first`
    );
  }

  // ------------------------------------------------------------------ app
  const appPlist = path.join(APP, "Contents", "Info.plist");
  check(await exists(appPlist), "app Info.plist exists");
  check(
    (await plistValue(appPlist, "CFBundleIdentifier")) === app.bundleId,
    `app bundle id is ${app.bundleId}`
  );
  check(
    (await plistValue(appPlist, "CFBundleShortVersionString")) === app.marketingVersion,
    `app version is ${app.marketingVersion}`
  );

  // ------------------------------------------------------------ extension
  const pluginsDir = path.join(APP, "Contents", "PlugIns");
  check(await exists(pluginsDir), "Contents/PlugIns exists");

  const plugins = (await exists(pluginsDir))
    ? (await fs.readdir(pluginsDir)).filter((n) => n.endsWith(".appex"))
    : [];
  check(plugins.length === 1, `exactly one .appex embedded (found ${plugins.length})`);

  if (plugins.length === 0) {
    throw new Error("no .appex to verify");
  }

  const appex = path.join(pluginsDir, plugins[0]);
  const extPlist = path.join(appex, "Contents", "Info.plist");
  const extId = await plistValue(extPlist, "CFBundleIdentifier");
  const point = await plistValue(extPlist, "NSExtension:NSExtensionPointIdentifier");
  const principal = await plistValue(extPlist, "NSExtension:NSExtensionPrincipalClass");

  check(extId === app.extensionBundleId, `extension bundle id is ${app.extensionBundleId}`);
  check(
    point === "com.apple.Safari.web-extension",
    "extension point is com.apple.Safari.web-extension"
  );
  check(Boolean(principal), `extension principal class is set (${principal})`);
  check(
    (await plistValue(extPlist, "CFBundleShortVersionString")) === app.marketingVersion,
    "extension version matches the app version"
  );

  // Safari requires manifest.json at the ROOT of Contents/Resources.
  const resources = path.join(appex, "Contents", "Resources");
  const manifestPath = path.join(resources, "manifest.json");
  check(await exists(manifestPath), "manifest.json is at the Resources root");
  check(
    !(await exists(path.join(resources, "extension"))),
    "no stray nested Resources/extension directory"
  );

  if (await exists(manifestPath)) {
    const manifest = JSON.parse(await fs.readFile(manifestPath, "utf8"));
    const files = await listFiles(resources);

    try {
      validateManifest(manifest, files, app.displayName);
      ok(`manifest validates (${files.length} resource files)`);
    } catch (err) {
      problems.push(err.message);
    }

    check(
      manifest.version === upstream.version,
      `manifest version matches pinned upstream ${upstream.version}`
    );

    // Confirm the Safari adaptations actually happened.
    const perms = manifest.permissions ?? [];
    check(!perms.includes("offscreen"), "unsupported 'offscreen' permission stripped");
    check(!perms.includes("tts"), "unsupported 'tts' permission stripped");

    // The build stamp proves which upstream commit this binary contains.
    const infoPath = path.join(resources, "build-info.json");
    if (await exists(infoPath)) {
      const info = JSON.parse(await fs.readFile(infoPath, "utf8"));
      check(
        info.upstream?.commit === upstream.commit,
        `build-info records upstream commit ${upstream.commit.slice(0, 7)}`
      );
    } else {
      problems.push("build-info.json missing (was the extension built by this repo?)");
    }
  }

  // --------------------------------------------------------- architecture
  const binary = path.join(APP, "Contents", "MacOS", app.productName);
  try {
    const { stdout } = await run("lipo", ["-archs", binary]);
    const archs = stdout.trim().split(/\s+/);
    check(
      archs.includes("arm64") && archs.includes("x86_64"),
      `universal binary (${archs.join(" + ")})`
    );
  } catch (err) {
    problems.push(`could not read architectures: ${err.message.split("\n")[0]}`);
  }

  // -------------------------------------------------------------- signing
  try {
    await run("codesign", ["-v", "--deep", "--strict", APP]);
    ok("code signature verifies");
  } catch {
    notes.push(
      "code signature does not verify — expected for an unsigned CI build before ad-hoc signing"
    );
  }

  // ---------------------------------------------------------------- report
  const size = await dirSize(APP);
  info(`bundle size: ${(size / 1024 / 1024).toFixed(1)} MiB`);

  for (const note of notes) warn(note);

  if (problems.length) {
    console.error("");
    for (const problem of problems) fail(problem);
    throw new Error(`${problems.length} verification check(s) failed`);
  }

  console.log(`\n${ok("all checks passed")}\n`);
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

main().catch((err) => {
  fail(err.message);
  process.exitCode = 1;
});
