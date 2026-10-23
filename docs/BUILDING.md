# Building

Detailed build reference. For the short version, see the
[README（中文）](../README.zh-CN.md)。

- [Prerequisites](#prerequisites)
- [Targets](#targets)
- [Artifacts](#artifacts)
- [Configuration](#configuration)
- [Signing](#signing)
- [Running in Safari](#running-in-safari)
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
> `ERR_PNPM_LOCKFILE_CONFIG_MISMATCH`.

## Targets

| Target | Depends on | Produces |
| --- | --- | --- |
| `make deps` | — | `.build/upstream/` (verified upstream tree, dependencies installed) |
| `make extension` | `deps` | `extension/` (MV3 web extension) |
| `make project` | `extension` | `KISSTranslator.xcodeproj` (generated) |
| `make build` | `project` | `build/App/简约翻译.app` |
| `make sign` | `build` | signed `build/App/简约翻译.app` |
| `make dmg` | `build` | `build/dist/简约翻译-<version>.dmg`, `.zip` |
| `make all` | — | runs extension → project → build → dmg |
| `make verify` | `deps` | verifies the upstream pin, the extension manifest and the app bundle |
| `make clean` | — | removes build outputs and the generated project file |

Every project regeneration (`make project`, and therefore `make build` and
`make all`) first deletes previous build outputs — DerivedData, the staged
`.app`, `dist/` and the generated `.xcodeproj` — so a rebuild never inherits
stale files. `build/extension` is kept (cheap to re-publish), and `make dmg`
/ `make sign` run standalone never trigger the cleanup.

Pass `SIGNING=0` to build without any signing identity (not usable with Safari —
see [Signing](#signing)):

```sh
make all SIGNING=0
```

## Artifacts

```
build/
├── App/
│   └── 简约翻译.app
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
│   ├── 简约翻译-<version>.dmg
│   ├── 简约翻译-<version>.zip
│   └── checksums.txt
└── DerivedData/                                   # xcodebuild output
```

Everything under `build/` is git-ignored. The same applies to the generated
`KISSTranslator.xcodeproj` and the `.build/` work tree.

Quick sanity check after a build:

```sh
lipo -info "build/App/简约翻译.app/Contents/MacOS/KISSTranslator"   # arm64 x86_64
plutil -p "build/App/简约翻译.app/Contents/PlugIns/KISSTranslatorExtension.appex/Contents/Resources/manifest.json" | head
```

## Configuration

`config/build.config.mjs` is the single source of truth:

- `upstream.version` / `upstream.commit` — the pinned upstream release
- `upstream.pnpmVersion` — must be 9.14.4
- `app.productName` — `KISSTranslator` (Xcode target, executable and project name; internal, ASCII)
- `app.displayName` — `简约翻译` (user-visible: the `.app` bundle name, DMG/ZIP basename, Safari extension name)
- `app.bundleId` / `app.extensionBundleId` — `com.ftzahao.kisstranslator[.extension]`
- `app.marketingVersion` — mirrors the upstream version
- `targets.macosDeploymentTarget` — `14.0`
- `targets.architectures` — `["arm64", "x86_64"]`

Do not hard-code any of these values elsewhere; adjust the config and regenerate.

## Signing

Safari only lists a web extension whose containing app carries a real **Team
Identifier** in its code signature. An ad-hoc or unsigned build is silently
omitted from **Safari → Settings → Extensions**, so for local use sign with an
Apple Development certificate (free; Xcode issues it when you sign in with an
Apple ID under **Xcode → Settings → Accounts**). `make all` auto-detects the
team from that certificate; pass it explicitly if detection is empty:

```sh
security find-certificate -c "Apple Development" -p \
  | openssl x509 -noout -subject -nameopt sep_multiline | awk -F= '/OU=/{print $2}'
make all DEVELOPMENT_TEAM=<TEAMID>
```

Such a build runs only on your own Mac: Apple Development certificates are not
redistributable.

`SIGNING=0` skips signing entirely — useful for pipeline sanity checks, never
for running the extension in Safari.

For distribution outside your own Mac you would need a paid Apple Developer
Program membership (Developer ID signing + notarization). The `make sign`
target accepts a Developer ID identity:

```sh
make sign DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
```

Two traps when signing by hand with `codesign`: an ad-hoc `codesign --sign -`
on a sandboxed bundle **drops its entitlements** unless they are passed again
with `--entitlements`, and `--deep` on the outer bundle alone leaves the nested
`.appex` inconsistently signed — sign inside-out (appex executable → appex →
app) as `make sign` does.

## Running in Safari

```sh
make project
open KISSTranslator.xcodeproj      # then Run in Xcode
```

1. Safari → **Settings → Advanced** → enable **Show features for web developers**.
2. **Develop → Allow Unsigned Extensions** (asks for an administrator password).
   This resets every time Safari restarts.
3. Run the app, then enable the extension in **Settings → Extensions**.

A properly signed build (see [Signing](#signing)) skips step 2 entirely.

## Troubleshooting

**`xcodegen: command not found`**
`brew install xcodegen`.

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
Quarantine attribute (only applies to apps copied from elsewhere — a locally
built app has no quarantine flag). Either right-click → Open, or
`xattr -dr com.apple.quarantine "/Applications/简约翻译.app"`.

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
pre-26 look regardless of the runtime macOS version. Verify what a build
contains with
`plutil -p "/Applications/简约翻译.app/Contents/Info.plist" | grep -i DTSDKName`.

**`ERR_PNPM_LOCKFILE_CONFIG_MISMATCH`**
You are on pnpm 10+. Run `pnpm --version`; install 9.14.4 via corepack.

**Build is extremely slow on the first run**
`make deps` installs the full upstream dependency tree; subsequent runs reuse
the pnpm store.
