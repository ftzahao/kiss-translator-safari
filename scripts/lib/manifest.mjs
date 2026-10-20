/**
 * Normalizes the upstream web extension for Safari.
 *
 * The upstream project ships one MV3 manifest refined for Chromium. Safari
 * accepts most of it, but a few keys either mean something different or are
 * rejected outright. This module applies the *minimum* set of changes needed
 * for Safari to load the extension, and records every change it makes so the
 * build log stays auditable.
 *
 * Design rules:
 *  - Never silently drop a key that affects behaviour we rely on.
 *  - Every removal must have a written justification and a runtime fallback.
 *    See docs/SAFARI-COMPATIBILITY.md for the analysis behind each entry.
 */

/**
 * Keys Safari does not support. Each entry explains why removing it is safe.
 *
 * @type {Record<string, string>}
 */
export const UNSUPPORTED_KEYS = {
  offscreen:
    "Safari has no chrome.offscreen API. Upstream's runtimeHostAdapter detects " +
    "the missing API and falls back to hosting the local-AI runtime inside the " +
    "background context, so the permission can be dropped without a crash.",
  tts:
    "Safari does not implement the chrome.tts API. Upstream uses browser TTS " +
    "only when available and otherwise delegates to the Web Speech API in the " +
    "page, which Safari supports.",
};

/** Permissions that are unknown to Safari and must be stripped. */
const UNSUPPORTED_PERMISSIONS = ["offscreen", "tts"];

/** Content-script keys Safari rejects when present. */
const UNSUPPORTED_CONTENT_SCRIPT_KEYS = [
  "match_origin_as_fallback",
  "match_about_blank",
];

/**
 * Transforms a plain manifest object into its Safari-compatible form.
 *
 * Pure function: takes a parsed manifest, returns a new manifest plus a list
 * of human-readable change descriptions. Never mutates the input.
 *
 * @param {Record<string, any>} manifest
 * @param {{ displayName?: string }} [options]
 * @returns {{ manifest: Record<string, any>, changes: string[] }}
 */
export function normalizeManifest(manifest, options = {}) {
  const out = structuredClone(manifest);
  const changes = [];

  // ---------------------------------------------------------------- permissions
  if (Array.isArray(out.permissions)) {
    const removed = out.permissions.filter((p) =>
      UNSUPPORTED_PERMISSIONS.includes(p)
    );
    if (removed.length) {
      out.permissions = out.permissions.filter(
        (p) => !UNSUPPORTED_PERMISSIONS.includes(p)
      );
      changes.push(
        `permissions: removed [${removed.join(", ")}] (unsupported by Safari)`
      );
    }
  }

  // ------------------------------------------------ declarativeNetRequest
  // Safari supports declarativeNetRequest for static rules but does not expose
  // the dynamic-rule and modifyHeaders surface upstream relies on. Upstream
  // wraps all of it in try/catch (src/background.js updateCspRules), so the
  // extension keeps working with reduced CSP-bypass behaviour instead of
  // failing to install.
  if (
    Array.isArray(out.permissions) &&
    out.permissions.includes("declarativeNetRequestWithHostAccess")
  ) {
    out.permissions = out.permissions.filter(
      (p) => p !== "declarativeNetRequestWithHostAccess"
    );
    changes.push(
      "permissions: removed [declarativeNetRequestWithHostAccess] " +
        "(dynamic modifyHeaders rules are Chromium-only; upstream degrades gracefully)"
    );
  }

  // ---------------------------------------------------------- content scripts
  if (Array.isArray(out.content_scripts)) {
    for (const [index, script] of out.content_scripts.entries()) {
      for (const key of UNSUPPORTED_CONTENT_SCRIPT_KEYS) {
        if (key in script) {
          delete script[key];
          changes.push(`content_scripts[${index}]: removed "${key}"`);
        }
      }
    }
  }

  // ------------------------------------------------------------ background
  // Safari on macOS 14+ supports MV3 service workers with `type: module`.
  // Older Safari versions only supported background pages, but our deployment
  // target (macOS 14 / Safari 17) covers the service-worker implementation.
  if (out.background && out.background.scripts && !out.background.service_worker) {
    changes.push(
      "background: persistent background page detected; Safari 17+ expects " +
        "service_worker (left untouched — upstream already ships MV3)"
    );
  }

  // ---------------------------------------------------------------- options_ui
  // Safari supports options_ui but ignores `open_in_tab`; upstream also offers
  // a full options page reachable from the popup, so this is cosmetic only.
  if (out.options_ui && "open_in_tab" in out.options_ui) {
    changes.push(
      'options_ui: dropped "open_in_tab" (Safari always opens options in a tab)'
    );
    delete out.options_ui.open_in_tab;
  }

  // --------------------------------------------------------------- branding
  // Keep upstream's localized name/description lookup but guarantee a working
  // default by pinning a concrete name for this distribution.
  if (options.displayName) {
    out.name = options.displayName;
    changes.push(`name: pinned to "${options.displayName}" for this build`);
  }

  // A stable distribution marker. Also makes it easy to tell Safari builds
  // apart from upstream Chrome zips when triaging bug reports.
  out.description = `${out.description ?? ""}`.trim() || out.name;

  return { manifest: out, changes };
}

/**
 * Validates a built extension directory before it is embedded in the app.
 * Throws with a precise message when something is structurally wrong, so
 * failures surface at build time rather than as a blank Safari extension.
 *
 * @param {Record<string, any>} manifest
 * @param {string[]} files relative POSIX paths present in the directory
 * @param {string} [displayName]
 */
export function validateManifest(manifest, files, displayName) {
  const problems = [];
  const has = (p) => files.includes(p);

  if (manifest.manifest_version !== 3) {
    problems.push(`manifest_version must be 3, got ${manifest.manifest_version}`);
  }

  if (!manifest.version || !/^\d+(\.\d+){0,3}$/.test(manifest.version)) {
    problems.push(
      `version must be 1-4 dot-separated integers, got ${JSON.stringify(manifest.version)}`
    );
  }

  // Safari requires an icon; the extension otherwise cannot be enabled.
  if (!manifest.icons || !manifest.icons["128"]) {
    problems.push("manifest.icons must include a 128px icon for Safari");
  } else if (!has(stripLeadingSlash(manifest.icons["128"]))) {
    problems.push(`icon file missing from build: ${manifest.icons["128"]}`);
  }

  // Every referenced HTML entry point must exist.
  for (const [label, page] of [
    ["action.default_popup", manifest.action?.default_popup],
    ["options_ui.page", manifest.options_ui?.page],
  ]) {
    if (page && !has(stripLeadingSlash(page))) {
      problems.push(`${label} points at missing file: ${page}`);
    }
  }

  // Content scripts and their files.
  for (const [index, script] of (manifest.content_scripts ?? []).entries()) {
    if (!Array.isArray(script.matches) || script.matches.length === 0) {
      problems.push(`content_scripts[${index}] has no matches`);
    }
    for (const js of script.js ?? []) {
      if (!has(stripLeadingSlash(js))) {
        problems.push(`content_scripts[${index}] references missing file: ${js}`);
      }
    }
  }

  // Service worker.
  const sw = manifest.background?.service_worker;
  if (sw && !has(stripLeadingSlash(sw))) {
    problems.push(`background.service_worker references missing file: ${sw}`);
  }

  // Web accessible resources: verify the directory prefix exists in some form.
  for (const entry of manifest.web_accessible_resources ?? []) {
    for (const resource of entry.resources ?? []) {
      const prefix = stripLeadingSlash(resource).replace(/\*+$/, "");
      if (prefix && !files.some((f) => f.startsWith(prefix))) {
        problems.push(`web_accessible_resources references missing path: ${resource}`);
      }
    }
  }

  // A pinned display name should survive if we asked for it.
  if (displayName && manifest.name !== displayName) {
    problems.push(
      `manifest.name should be "${displayName}", got ${JSON.stringify(manifest.name)}`
    );
  }

  if (problems.length) {
    throw new Error(
      `Manifest validation failed:\n  - ${problems.join("\n  - ")}`
    );
  }
}

function stripLeadingSlash(path) {
  return String(path).replace(/^\/+/, "");
}
