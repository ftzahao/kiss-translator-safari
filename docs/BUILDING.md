# Building

Detailed build reference. For the short version, see the README
([English](https://github.com/ftzahao/kiss-translator-safari#b-build-from-source) /
[中文](https://github.com/ftzahao/kiss-translator-safari/blob/main/README.zh-CN.md)).

- [Prerequisites](#prerequisites)
- [Targets](#targets)
- [Artifacts](#artifacts)
- [Configuration](#configuration)
- [Signing](#signing)
- [Running in Safari](#running-in-safari)
- [CI and releases](#ci-and-releases)
- [Releasing](#releasing)
- [Troubleshooting](#troubleshooting)

## Prerequisites

| Tool | Version | Check |
| --- | --- | --- |
| macOS | 14.0+ | `sw_vers -productVersion` |
| Xcode | 16+ (26+ for the Liquid Glass appearance) | `xcodebuild -version` |
| Node.js | 20 (matches `upstream.nodeMajor`) | `node --version` |
| pnpm | **9.14.4 exactly** | `pnpm --version` |
| XcodeGen | latest | `xcodegen --version` |

```sh
xcode-select -p                 # must point at Xcode, not CommandLineTools
brew install xcodegen           # if missing
corepack enable && corepack prepare pnpm@9.14.4 --activate
```

> **pnpm version is load-bearing.** Upstream pins 9.14.4 in `.pnpm-version`. A
> newer major (10+) rewrites the lockfile format and aborts with
> `ERR_PNPM_LOCKFILE_CONFIG_MISMATCH`. CI enforces 9.14.4 for the same reason.

## Targets

| Target | Depends on | Produces |
| --- | --- | --- |
| `make deps` | — | `.build/upstream/` (verified upstream tree, dependencies installed) |
| `make extension` | `deps` | `extension/` (MV3 web extension) |
| `make project` | `extension` | `KISSTranslator.xcodeproj` (generated) |
| `make build` | `project` | `build/App/KISSTranslator.app` |
| `make sign` | `build` | signed `build/App/KISSTranslator.app` |
| `make dmg` | `build` | `build/dist/KISSTranslator-<version>.dmg`, `.zip` |
| `make all` | — | runs extension → project → build → dmg |
| `make verify` | `deps` | verifies the upstream pin, the extension manifest and the app bundle |
| `make clean` | — | removes `build/`, `.build/`, generated project file |

Pass `SIGNING=0` to build without any signing identity, which is what CI does:

```sh
make all SIGNING=0
```

There is **no** release script: the workflows call `make all SIGNING=0`,
sign inside-out (see [Releasing](#releasing)), then `make dmg SIGNING=0`. Both
paths must stay equivalent, and `make verify` is the gate between them.

## Artifacts

```
build/
├── App/
│   └── KISSTranslator.app
│       └── Contents/
│           ├── Info.plist
│           ├── MacOS/KISSTranslator
│           └── PlugIns/
│               └── KISSTranslatorExtension.appex
│                   └── Contents/
│                       ├── Info.plist
│                       └── Resources/
│                           └── manifest.json      # MV3 manifest
├── dist/
│   ├── KISSTranslator-<version>.dmg
│   ├── KISSTranslator-<version>.zip
│   └── checksums.txt
├── DerivedData/                                   # xcodebuild output (CI)
└── logs/                                          # build logs (CI)
```

Everything under `build/` is git-ignored. The same applies to the generated
`KISSTranslator.xcodeproj` and the `.build/` work tree.

Quick sanity check after a build:

```sh
lipo -info build/App/KISSTranslator.app/Contents/MacOS/KISSTranslator   # arm64 x86_64
plutil -p build/App/KISSTranslator.app/Contents/PlugIns/KISSTranslatorExtension.appex/Contents/Resources/manifest.json | head
```

## Configuration

`config/build.config.mjs` is the single source of truth:

- `upstream.version` / `upstream.commit` — the pinned upstream release
- `upstream.pnpmVersion` — must be 9.14.4
- `app.productName` — `KISSTranslator` (bundle name and Xcode target)
- `app.displayName` — `KISS Translator` (what users see)
- `app.bundleId` / `app.extensionBundleId` — `com.ftzahao.kisstranslator[.extension]`
- `app.marketingVersion` — mirrors the upstream version
- `targets.macosDeploymentTarget` — `14.0`
- `targets.architectures` — `["arm64", "x86_64"]`

Do not hard-code any of these values elsewhere; adjust the config and regenerate.

## Signing

Three modes:

1. **Unsigned** — `SIGNING=0` (CI). Produces a runnable app only after the user
   clears quarantine.
2. **Ad-hoc** — sign inside-out (appex executable → appex → app), always with
   `--entitlements`, e.g.
   `codesign --force --sign - --entitlements app/KISSTranslator.entitlements build/App/KISSTranslator.app`.
   This is what the release workflow does after the unsigned build. Two traps:
   an ad-hoc `codesign --sign -` on a sandboxed bundle **drops its entitlements**
   unless they are passed again, and `--deep` on the outer bundle alone leaves
   the nested `.appex` inconsistently signed. It satisfies the code-signing
   requirement but not Gatekeeper.
3. **Real signing** — `make sign` with your own identity, e.g.
   `DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" make sign`.
   Developer ID signing plus notarization needs a paid Apple Developer Program
   membership. That material is private and is **not** part of CI.

The `make sign` target and the identity variable name above are the intended
contract; confirm against the final `Makefile`.

For App Store Connect, the `store-zip` job in
`.github/workflows/release.yml` produces an unsigned `ditto`-based ZIP. Sign it
locally with an "Apple Distribution" certificate and an App Store provisioning
profile, then upload it with Xcode Organizer or `xcrun altool`. That step is
deliberately manual.

## Running in Safari

```sh
make project
open KISSTranslator.xcodeproj      # then Run in Xcode
```

1. Safari → **Settings → Advanced** → enable **Show features for web developers**.
2. **Develop → Allow Unsigned Extensions** (asks for an administrator password).
   This resets every time Safari restarts.
3. Run the app, then enable the extension in **Settings → Extensions**.

## CI and releases

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| `.github/workflows/ci.yml` | PRs, pushes to `main` | Unsigned build + assertions; log upload on failure; 30-minute cap |
| `.github/workflows/release.yml` | Tags matching `v*`, manual dispatch | Unsigned DMG + ZIP + checksums, GitHub Release |

CI asserts:

- `build/App/KISSTranslator.app` exists
- an `.appex` exists inside `Contents/PlugIns/`
- `manifest.json` exists inside the `.appex` and has `manifest_version: 3`

For a release, the tag must equal `v` + `app.marketingVersion`, e.g.
`app.marketingVersion = "2.1.1"` → tag `v2.1.1`. The workflow fails fast on a
mismatch rather than publishing a mislabelled build.

## Releasing

There is no release script and no version-bump command: a release is a commit,
a tag, and the tag-triggered workflow. Do the steps in this order.

### 1. Decide what the version means

`app.marketingVersion` mirrors the **upstream** release the wrapper packages.
Packaging-only fixes (native app, build, signing, docs) do **not** change it,
otherwise the number stops describing what the extension contains:

| Change | Action |
| --- | --- |
| Packaging fix only (app crash, entitlements, CI) | Same `marketingVersion`; re-cut the existing tag with a new build number (step 2b) |
| New upstream release (e.g. 2.1.1 → 2.2.0) | Bump `upstream.version` / `upstream.commit` / `app.marketingVersion` (step 3) and tag the new version |

### 2. Cut the release

**2a. Upstream bump** (skip when only packaging changed):

```sh
# Resolve the immutable commit the tag points at (do not guess it):
git ls-remote https://github.com/fishjar/kiss-translator refs/tags/v2.2.0^{}
# edit config/build.config.mjs: upstream.version, upstream.commit, app.marketingVersion
make extension          # fetches the pinned commit and verifies tag <-> commit
make verify
```

**2b. Always bump the build number** so an already-installed DMG shows the new
build (the onboarding footer renders `<version> (<build>)`). If you bump
`app.marketingVersion`, bump `CURRENT_PROJECT_VERSION` in `config/project.yml`
in the same commit; the tag must then match the new version. For a
packaging-only re-cut keep the version and only raise the build:

```sh
# config/project.yml: CURRENT_PROJECT_VERSION: "2"
make build SIGNING=0 && make verify
```

### 3. Verify locally before tagging

```sh
make all SIGNING=0          # extension -> project -> app
make verify
make dmg SIGNING=0          # DMG + ZIP + checksums, signed like a release
```

The release workflow signs inside-out with explicit entitlements; replicate it
by hand only if you are debugging that step (copy the `run:` block out of
`.github/workflows/release.yml`).

Smoke-test the artefact, not just the build output. Two checks caught real
release bugs that a green CI did not:

```sh
# the app must survive >10 s: a crash-on-launch means every button is dead
open build/App/KISSTranslator.app
ls -lt ~/Library/Logs/DiagnosticReports/ | head    # no new KISSTranslator-*.ips
# entitlements must survive ad-hoc signing (note: no `| grep -q`, which dies
# of SIGPIPE under `set -o pipefail`)
codesign -d --entitlements - build/App/KISSTranslator.app 2>&1 | grep -c app-sandbox
```

### 4. Commit, tag, push

```sh
git add -A && git commit -m "release: v2.1.1 (build 2)"
git tag -a v2.1.1 -m "KISS Translator for Safari 2.1.1"
git push origin main
git push origin v2.1.1     # this is what triggers release.yml
```

Re-tagging an already-published version (step 2b) needs a force push. Delete
the old asset first: `action-gh-release` matches files by the same names, so a
re-run with a different asset set leaves the previous DMG attached next to the
new one.

```sh
gh release delete-asset v2.1.1 KISSTranslator-2.1.1.dmg -y
git tag -fa v2.1.1 -m "KISS Translator for Safari 2.1.1 (build 2)"
git push origin v2.1.1 --force
```

A manual `workflow_dispatch` run is **not** a release: it only uploads workflow
artifacts. Ticking `publish` makes it publish too, targeting the tag that
matches `app.marketingVersion` — useful for rebuilding without touching tags,
but that tag must already exist, otherwise the release is created on a tag
nothing points at. Prefer the tag push.

### 5. Check the published result

Do not trust the green check mark — download what users get:

```sh
hdiutil attach -nobrowse ~/Downloads/KISSTranslator-2.1.1.dmg
codesign --verify --deep --strict "/Volumes/KISS Translator/KISS Translator.app"
plutil -p "/Volumes/KISS Translator/KISS Translator.app/Contents/Info.plist" | grep -E "DTSDKName|CFBundleVersion"
```

`DTSDKName` tells you which Xcode built it, i.e. whether the Liquid Glass
appearance (macOS 26 SDK / Xcode 26+) is in that binary at all.

### 6. Record it

Add a `CHANGELOG.md` entry under `[Unreleased]`, then rename that heading to the
version and date when you tag. The release body is generated from git by
`generate_release_notes: true`, so write commit subjects for humans.

### Things that silently break a release

| Symptom | Cause |
| --- | --- |
| Every button dead, "无法获取状态" | The app crashed (check DiagnosticReports) — see Troubleshooting |
| Safari never lists the extension | Ad-hoc/unsigned build (expected), or the appex lost its signature/entitlements |
| Not Liquid Glass on macOS 26+ | Built with an older Xcode. The workflows run on `macos-26` (Xcode 26.x / macOS 26 SDK); `macos-15` ships Xcode 16 and never gets it |
| `Tag vX.Y.Z does not match app.marketingVersion` | `config/build.config.mjs` and the tag disagree |
| `Node.js 20+ required` on CI | `NODE_VERSION` in the workflows drifted from `upstream.nodeMajor` |

## Troubleshooting

**`xcodegen: command not found`**
`brew install xcodegen`. CI does this conditionally with
`command -v xcodegen || brew install xcodegen`.

**`xcodebuild: error: The project 'KISSTranslator.xcodeproj' does not contain a scheme named 'KISSTranslator'`**
The project was not regenerated after a spec change. `make clean && make project`.

**`Signing for "KISSTranslator" requires a development team`**
Build with `SIGNING=0`, or select a team in Xcode → target → Signing &
Capabilities.

**Safari does not list the extension after `make build`**
Launch the app from `build/App` (or `/Applications`) at least once, then restart
Safari. Safari only enumerates extensions registered by an app that has run.

**"Safari cannot verify the extension" / `Safari 无法验证扩展`**
Unsigned or ad-hoc build. Enable **Develop → Allow Unsigned Extensions**, or use
a properly signed build.

**App is "damaged" or cannot be opened after downloading**
Quarantine attribute. Either right-click → Open, or
`xattr -dr com.apple.quarantine "/Applications/KISS Translator.app"`.

**Onboarding window: badge shows "无法获取状态" / the primary button does nothing**

Two independent causes, both fixed in this repository after the 2.1.1
download — check which one you have before rebuilding:

1. *The app crashes on launch.* SafariServices replies on its own XPC queue
   (`com.apple.NSXPCConnection.user.com.apple.SafariServices.ExtensionHelper`),
   never on the main thread. The Swift 6 importer presents those reply
   signatures as `@MainActor`, so a reply handler written in actor context
   traps with `EXC_BREAKPOINT` / `dispatch_assert_queue_fail` in
   `SafariExtensionBridge.state(of:)`. Check
   `~/Library/Logs/DiagnosticReports/KISSTranslator-*.ips`: if it exists, the
   process died and there is nothing left to click. `SafariExtensionBridge`
   now creates every reply handler in a non-isolated free function and bounds
   each call with a 5 s timeout; never write a reply closure inside
   `@MainActor` code.
2. *The extension is not registered with Safari.* `showPreferencesForExtension`
   answers `SFErrorDomain` error 1 when Safari does not know the extension —
   typical for ad-hoc signed builds. Safari never lists ad-hoc extensions, and
   the window now falls back to Safari's Extensions pane and says so.

**The UI is not Liquid Glass on macOS 26+**

The appearance is baked in at compile time: the app opts in by being built
with the macOS 26 SDK (Xcode 26+). A build produced with an older SDK keeps the
pre-26 look regardless of the runtime macOS version. Verify what a download
contains with
`plutil -p "/Applications/KISS Translator.app/Contents/Info.plist" | grep -i DTSDKName`.

**`ERR_PNPM_LOCKFILE_CONFIG_MISMATCH`**
You are on pnpm 10+. Run `pnpm --version`; install 9.14.4 via corepack.

**Build is extremely slow on the first run**
`make deps` installs the full upstream dependency tree; subsequent runs reuse
the pnpm store.
