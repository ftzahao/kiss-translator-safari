# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to the version number of the upstream KISS Translator
release it packages. Packaging-only changes are recorded here but do not get a
separate version number.

## [Unreleased]

### Changed

- **Every project regeneration now starts from a clean slate.** `make
  project` (and with it `make build` / `make all`) first deletes previous
  build outputs — DerivedData, the staged app, `dist/` and the generated
  `.xcodeproj` — so a rebuild never inherits stale files. `make dmg` and
  `make sign` still work standalone without wiping anything.
- **The app is now named 简约翻译.** The built bundle is `build/App/简约翻译.app`,
  DMG/ZIP artifacts are `简约翻译-<version>.dmg` / `.zip`, and Safari lists the
  extension as 简约翻译 (manifest name + onboarding copy). Internal names
  (bundle ids, Xcode target/scheme, executable `KISSTranslator`) are unchanged.

### Removed

- **In-app update checking is removed.** The app no longer queries GitHub
  Releases at launch or from the onboarding footer; this repository no
  longer publishes releases, so the check could never find anything. The
  footer keeps only the static version label — to update, pull the repo and
  rebuild.
- **CI and release are gone; this repository is now local-build only.** The
  GitHub Actions workflows (`ci.yml`, `release.yml`), issue/PR templates and
  the English `README.md` were deleted. The only supported flow is cloning the
  repo and building on your own Mac (`make all` signed with a free Apple
  Development certificate), which produces a package that actually works —
  ad-hoc-signed CI/Release artifacts could never enable the extension in
  Safari. Documentation is maintained in `README.zh-CN.md` only.

### Fixed

- **Fixed the background crash that showed as「简约翻译」出错 in Safari's
  Extensions settings.** Upstream's safari build bakes
  `REACT_APP_CLIENT="safari"` into the bundle but never lists `safari` in
  `CLIENT_EXTS`, so every `isExt` check compiled to false and the storage
  layer fell back to `window.localStorage` — which does not exist in an MV3
  service worker (`ReferenceError: Can't find variable: window`). The build
  now patches `CLIENT_EXTS` right after checkout so the Safari build is
  treated as the extension it is (uses `browser.storage.local`). Anchors
  fail loudly if a future pin changes that file.
- **The advertised build orchestrator `scripts/release.mjs` did not exist.** The
  README, `docs/BUILDING.md` and the `[0.1.0]` notes referred to a script that
  was never committed; the real build flow is `make all` (plus `make verify`).
  The docs now describe that path.
- **"The file can't be found" when clicking the primary button.** The Safari
  fallback launched `/System/Applications/Safari.app` by absolute path, but on
  current macOS Safari ships as a Cryptex at
  `/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app`, so
  `NSWorkspace.openApplication(at:)` failed and macOS surfaced the error. Safari
  is now resolved through Launch Services by bundle identifier
  (`com.apple.Safari`), and a failure to reach it produces an in-window message
  instead of a silent no-op.
- **The app crashed on launch.** SafariServices answers
  `getStateOfSafariExtension` / `showPreferencesForExtension` on its own XPC
  queue, never on the main thread, but Swift 6 imports those reply signatures
  as `@MainActor`, so the reply thunk asserted the main queue and trapped
  (`EXC_BREAKPOINT`, `dispatch_assert_queue_fail` in
  `SafariExtensionBridge.state(of:)`). The window therefore showed a stale
  "无法获取状态" badge and every button was dead — the process was already gone.
  `SafariExtensionBridge` now creates all reply handlers in non-isolated free
  functions and bounds each call with a 5 s timeout.
- **The primary button now always does something.** When SafariServices
  refuses the extension-scoped call (typical for an ad-hoc signed build), the
  app falls back to opening Safari's Extensions pane over Apple Events and, if
  even that is denied, shows a concrete message instead of the raw
  "SFErrorDomain 错误 1".
- **The app is no longer built without entitlements.** An ad-hoc
  `codesign --sign -` on a sandboxed bundle drops its entitlements unless they
  are passed explicitly; signing now happens inside-out
  (appex executable → appex → app) with `--entitlements` and fails loudly
  if the app sandbox or Apple Events entitlement is missing afterwards.
  `make sign` signs that way.
- **An interrupted upstream fetch no longer poisons later builds.** A network
  failure during `git fetch` left `.build/upstream-safari-raw/.git` without a
  HEAD; the next run then died at `git rev-parse HEAD` instead of refetching.
  The builder now treats a HEAD-less checkout as corrupt, wipes it and pulls
  again.
- **`make all` now really produces the DMG/ZIP.** Every doc (README, this
  changelog, `docs/BUILDING.md`) described `all` as ending in `dmg`, but the
  Makefile target stopped at `build`, so a plain `make all` left no package to
  install.

### Added

- **The onboarding window warns when the build cannot work.** Ad-hoc or
  unsigned builds are invisible to Safari — the extension never appears in
  Settings → Extensions no matter what the user does. The window now reads its
  own Team Identifier at launch and, when it is missing, shows an orange notice
  telling the user to rebuild with a developer certificate.

- `com.apple.security.automation.apple-events` (with
  `NSAppleEventsUsageDescription`) and the Safari Extensions-pane fallback.
- macOS 26 Liquid Glass: the app is built with the macOS 26 SDK (Xcode 26+,
  `DTSDKName = macosx26/27`) and no longer forces an opaque background, so the
  window picks up the system glass material. Builds made with an older SDK
  keep the classic appearance — see `docs/BUILDING.md`.
- Onboarding window layout constants (`app/Sources/Design.swift`); the
  unbounded spacer that left a large empty band above the primary button is
  gone, and the update sheet no longer grows past the screen for long notes.
- `docs/BUILDING.md` troubleshooting entries for both failure modes above.

### Changed

- The failure badge reads "Safari 未能确认扩展" and explains what to do, instead
  of the misleading "无法获取状态".

## [0.1.0] - 2026-10-20

Initial release: KISS Translator 2.1.1 packaged as a native Safari Web Extension
for macOS.

### Added

- SwiftUI container app (`KISSTranslator.app`, bundle id `com.ftzahao.kisstranslator`)
  that embeds the Safari Web Extension (`com.ftzahao.kisstranslator.extension`)
  and explains how to enable it.
- Build pipeline driven by a single pin file, `config/build.config.mjs`, which
  records the upstream version (`2.1.1`), its commit
  (`a1279f2517bd478ef1dd93b941f9177094486cd4`) and the required pnpm version
  (`9.14.4`).
- `Makefile` targets: `deps`, `extension`, `project`, `build`, `sign`, `dmg`,
  `all`, `verify`, `clean`.
- `scripts/release.mjs` orchestrator for versioning and release artifacts.
- Universal binary (Apple Silicon `arm64` + Intel `x86_64`), deployment target
  macOS 14.
- DMG and ZIP release artifacts with SHA-256 `checksums.txt`.
- GitHub Actions CI (`ci.yml`) proving a clean unsigned build, and a release
  workflow (`release.yml`) triggered by `v*` tags.
- GPL-3.0 derivative-work attribution in `NOTICE`, and community files
  (`CONTRIBUTING.md`, `SECURITY.md`, issue and PR templates).

### Notes

- Release builds are **ad-hoc signed only**; they are not signed with a
  Developer ID and are not notarized. Users must clear the quarantine attribute
  before first launch. See README "Installation".
- Requires macOS 14 Sonoma or later and Safari 17 or later.
- iOS/iPadOS is not supported in this release.
- Upstream feature availability differs by Safari; file translation and
  on-device AI features may be limited.

[Unreleased]: https://github.com/ftzahao/kiss-translator-safari/compare/v2.1.1...HEAD
[0.1.0]: https://github.com/ftzahao/kiss-translator-safari/releases/tag/v2.1.1
