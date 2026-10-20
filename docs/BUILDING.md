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
- [Troubleshooting](#troubleshooting)

## Prerequisites

| Tool | Version | Check |
| --- | --- | --- |
| macOS | 14.0+ | `sw_vers -productVersion` |
| Xcode | 16+ | `xcodebuild -version` |
| Node.js | 20+ | `node --version` |
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

`scripts/release.mjs` orchestrates the whole release flow (pin resolution,
version checks, artifact collection, release notes). The workflows call
`make all SIGNING=0` and `make dmg SIGNING=0` directly, so the two paths must
stay equivalent.

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
2. **Ad-hoc** — `codesign --force --deep --sign - build/App/KISSTranslator.app`.
   This is what the release workflow does after the unsigned build. It satisfies
   the code-signing requirement but not Gatekeeper.
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

## Troubleshooting

**`ERR_PNPM_LOCKFILE_CONFIG_MISMATCH`**
You are on pnpm 10+. Run `pnpm --version`; install 9.14.4 via corepack.

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

**Build is extremely slow on the first run**
`make deps` installs the full upstream dependency tree; subsequent runs reuse
the pnpm store.
