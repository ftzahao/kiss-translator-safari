/**
 * Build configuration for the KISS Translator Safari extension.
 *
 * This file is the single source of truth for the pinned upstream version and
 * the native bundle metadata. The scripts in ./scripts read it; nothing else
 * should hard-code these values.
 */

export const upstream = {
  // Canonical upstream repository.
  owner: "fishjar",
  repo: "kiss-translator",
  // Pinned upstream release. Bump this (and run `make verify`) to upgrade.
  version: "2.1.1",
  // Commit SHA resolved for the tag above (v2.1.1^{}). Verified at fetch time:
  // the build aborts if the tag does not resolve to exactly this commit.
  commit: "a1279f2517bd478ef1dd93b941f9177094486cd4",
  // The exact pnpm version upstream pins in .pnpm-version. Using a different
  // major (e.g. pnpm 10+) fails with ERR_PNPM_LOCKFILE_CONFIG_MISMATCH.
  pnpmVersion: "9.14.4",
  // Minimum Node.js major that can build upstream. Upstream declares no
  // `engines` field, so this mirrors what CI pins rather than an upstream
  // requirement; keep it in sync with NODE_VERSION in the workflows.
  nodeMajor: 20,
};

export const app = {
  // Marketing name shown in Finder / Launchpad / Safari settings.
  displayName: "KISS Translator",
  // Product name; also the .app bundle name and the Xcode target name.
  productName: "KISSTranslator",
  // Bundle identifiers.
  bundleId: "com.ftzahao.kisstranslator",
  extensionBundleId: "com.ftzahao.kisstranslator.extension",
  // Version surfaced to the user. Mirrors the upstream extension version so a
  // single number describes what this build actually contains.
  marketingVersion: "2.1.1",
};

export const targets = {
  macosDeploymentTarget: "14.0",
  architectures: ["arm64", "x86_64"],
};
