#!/usr/bin/env node
/**
 * Packages build/App/<Product>.app into a distributable DMG and ZIP.
 *
 * Output:
 *   build/dist/KISSTranslator-<version>.dmg
 *   build/dist/KISSTranslator-<version>.zip
 *
 * Both are produced from the same .app so their contents always match.
 */
import fs from "node:fs/promises";
import path from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

import { app } from "../config/build.config.mjs";
import { step, info, ok, fail } from "./lib/log.mjs";

const run = promisify(execFile);
const ROOT = path.resolve(fileURLToPath(new URL("..", import.meta.url)));

const APP = path.join(ROOT, "build", "App", `${app.displayName}.app`);
const DIST = path.join(ROOT, "build", "dist");
const STAGE = path.join(ROOT, "build", "dmg-stage");
const BASENAME = `${app.displayName}-${app.marketingVersion}`;

async function exists(p) {
  try {
    await fs.access(p);
    return true;
  } catch {
    return false;
  }
}

async function main() {
  if (!(await exists(APP))) {
    throw new Error(
      `missing ${path.relative(ROOT, APP)} — run \`make all\` first`
    );
  }

  await fs.rm(DIST, { recursive: true, force: true });
  await fs.rm(STAGE, { recursive: true, force: true });
  await fs.mkdir(DIST, { recursive: true });

  // ---------------------------------------------------------------- staging
  step("Staging disk image contents");
  await fs.mkdir(STAGE, { recursive: true });
  // ditto preserves resource forks, extended attributes and symlinks, which a
  // plain `cp -R` can mangle for signed bundles.
  await run("ditto", [APP, path.join(STAGE, `${app.displayName}.app`)]);
  await fs.symlink("/Applications", path.join(STAGE, "Applications"));
  ok("staged app + Applications symlink");

  // -------------------------------------------------------------------- dmg
  step("Creating disk image");
  const dmgPath = path.join(DIST, `${BASENAME}.dmg`);
  await run("hdiutil", [
    "create",
    "-volname", app.displayName,
    "-srcfolder", STAGE,
    "-ov",
    "-format", "UDZO",
    "-quiet",
    dmgPath,
  ]);
  ok(`${path.relative(ROOT, dmgPath)} (${await humanSize(dmgPath)})`);

  // -------------------------------------------------------------------- zip
  step("Creating ZIP");
  const zipPath = path.join(DIST, `${BASENAME}.zip`);
  // `ditto -c -k --sequesterRsrc --keepParent` is the App-Store-safe archive
  // form: it preserves the bundle structure and xattrs.
  await run("ditto", [
    "-c", "-k", "--sequesterRsrc", "--keepParent",
    APP,
    zipPath,
  ]);
  ok(`${path.relative(ROOT, zipPath)} (${await humanSize(zipPath)})`);

  // -------------------------------------------------------------- checksums
  step("Checksums");
  const sums = [];
  for (const file of [dmgPath, zipPath]) {
    // Hash from inside build/dist so checksums.txt carries bare filenames —
    // it is published verbatim in the GitHub release.
    const { stdout } = await run("shasum", ["-a", "256", path.basename(file)], {
      cwd: DIST,
    });
    const line = stdout.trim();
    sums.push(line);
    info(line);
  }
  await fs.writeFile(
    path.join(DIST, "checksums.txt"),
    `${sums.join("\n")}\n`
  );
  ok("build/dist/checksums.txt");

  await fs.rm(STAGE, { recursive: true, force: true });
  console.log(`\n${ok("packaged")} — build/dist/${BASENAME}.{dmg,zip}\n`);
}

async function humanSize(p) {
  const { size } = await fs.stat(p);
  const mb = size / 1024 / 1024;
  return `${mb.toFixed(1)} MiB`;
}

main().catch((err) => {
  fail(err.message);
  process.exitCode = 1;
});
