# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to the version number of the upstream KISS Translator
release it packages. Packaging-only changes are recorded here but do not get a
separate version number.

## [Unreleased]

### Fixed

- **The advertised build orchestrator `scripts/release.mjs` did not exist.** The
  README, `docs/BUILDING.md` and the `[0.1.0]` notes referred to a script that
  was never committed; the real release flow is `make all SIGNING=0` +
  the signing step in `.github/workflows/release.yml` + `make dmg SIGNING=0`.
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
  are passed explicitly; the release workflow now signs inside-out
  (appex executable → appex → app) with `--entitlements` and *fails* the job
  if the app sandbox or Apple Events entitlement is missing afterwards.
  `make sign` signs the same way.
- Release and CI workflows pinned Node 26 while `upstream.nodeMajor` is 20;
  both now use 20 so a clean runner cannot abort during `make extension`.
- **An interrupted upstream fetch no longer poisons later builds.** A network
  failure during `git fetch` left `.build/upstream-safari-raw/.git` without a
  HEAD; the next run then died at `git rev-parse HEAD` instead of refetching.
  The builder now treats a HEAD-less checkout as corrupt, wipes it and pulls
  again.

### Added

- **The onboarding window warns when the build cannot work.** Ad-hoc or
  unsigned builds (CI artifacts, the published DMG before a Developer ID pass)
  are invisible to Safari — the extension never appears in Settings →
  Extensions no matter what the user does. The window now reads its own
  Team Identifier at launch and, when it is missing, shows an orange notice
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

- **CI and release now build on `macos-26` instead of `macos-15`.** This is what
  actually makes the Liquid Glass entry above reach users: the appearance is
  opted into at compile time, and the `macos-15` image only ships Xcode 16
  (macOS 15 SDK), so every artifact built there kept the pre-26 look no matter
  which macOS the user runs. `macos-26` defaults to Xcode 26.x (macOS 26 SDK).
  There is no `macos-27` runner label yet (`xcode-27` is a preview image), so
  `macos-26` is the newest GA image. The release workflow now also asserts at
  build time that the macOS SDK is 26 or newer and fails instead of silently
  publishing a build without the glass treatment.
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
