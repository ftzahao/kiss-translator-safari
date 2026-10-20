# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to the version number of the upstream KISS Translator
release it packages. Packaging-only changes are recorded here but do not get a
separate version number.

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

[0.1.0]: https://github.com/ftzahao/kiss-translator-safari/releases/tag/v2.1.1
