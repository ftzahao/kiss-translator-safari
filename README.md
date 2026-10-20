# KISS Translator for Safari

**A native Safari Web Extension for macOS, packaged on top of [KISS Translator](https://github.com/fishjar/kiss-translator).**

[![CI](https://github.com/ftzahao/kiss-translator-safari/actions/workflows/ci.yml/badge.svg)](https://github.com/ftzahao/kiss-translator-safari/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/ftzahao/kiss-translator-safari?color=blue)](https://github.com/ftzahao/kiss-translator-safari/releases)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B%20%C2%B7%20Safari%2017%2B-lightgrey)](https://github.com/ftzahao/kiss-translator-safari)

English | [简体中文](README.zh-CN.md)

> **Unofficial.** This is a community packaging of KISS Translator for Safari, not an official
> product of the upstream author. See [License & attribution](#license--attribution).

---

## Screenshot

<!-- docs/images/hero.png is added by the maintainers; the alt text is the fallback until then. -->
<picture>
  <source srcset="docs/images/hero.png" type="image/png">
  <img src="docs/images/hero.png" alt="KISS Translator in Safari showing bilingual inline translation of a web page">
</picture>

---

## Features

Everything below comes from the upstream extension. This repository only adds the macOS
container app, the build pipeline and the packaging — it does not change translation behaviour.

- **Bilingual inline translation** — translates a page paragraph by paragraph and shows the
  result under (or above) the original text, preserving rich-text markup. Also supports a
  translation-only mode that hides the original.
- **Selection translation and word lookup** — select text to get a floating bubble with the
  translation; English words can be looked up in a dictionary and saved to a word list.
- **Hover translation** — translate the paragraph under the mouse on demand, or hold the
  mouse button to trigger it (configurable).
- **Multiple translation engines** — Google, Microsoft/Azure, DeepL and DeepLX, Baidu,
  Tencent, Volcengine, Yandex, plus AI services including OpenAI, Gemini, Claude, DeepSeek,
  Ollama, OpenRouter and others; and a fully **custom / OpenAI-compatible API** entry where
  you supply the endpoint, key, model and request template yourself.
- **Per-site rules and automatic translation** — scope translation rules per website with a
  visual element picker; automatically translate matching sites or exclude the ones you never
  want touched.
- **Text-to-speech** — read translated text aloud from the extension.
- **YouTube bilingual subtitles** — merge and translate subtitle tracks in the player.
- **Translation style presets** — underline, marker, fuzzy, blockquote and more, so bilingual
  output is legible rather than jarring.
- **Configuration sync** — sync settings across devices through a self-hosted
  [KISS-Worker](https://github.com/fishjar/kiss-worker) deployment or WebDAV.

Not every upstream surface is available on Safari. Safari's Web Extension runtime differs
from Chromium/Firefox (for example, no offscreen documents in the same form), so some
advanced surfaces such as file translation and on-device AI features may be limited or
missing depending on the upstream release and Safari version. When in doubt, check the
upstream release notes.

---

## Installation

There are three ways to get the extension. Pick one.

### (a) Download from Releases (recommended for users)

The published builds are **unsigned and not notarized** — they are only ad-hoc signed.
macOS blocks them on first launch until you clear the quarantine flag.

1. Open [Releases](https://github.com/ftzahao/kiss-translator-safari/releases) and download
   `KISSTranslator-<version>.dmg` (and `checksums.txt` if you want to verify).
2. Optionally verify the download:

   ```sh
   shasum -a 256 -c checksums.txt
   ```

3. Open the DMG and drag **KISS Translator.app** to `/Applications`.
4. Clear the quarantine attribute — either is fine:

   - Finder: right-click the app → **Open** → **Open** in the confirmation dialog.
   - Terminal:

     ```sh
     xattr -dr com.apple.quarantine "/Applications/KISS Translator.app"
     ```

5. Launch the app once. It is only a container; it explains how to enable the extension and
   then stays out of the way.
6. In Safari, open **Settings → Extensions**, tick **KISS Translator**, and grant website
   access. You can allow it per site, or choose "Always Allow on Every Website" if you prefer.

### (b) Build from source

**Prerequisites**

| Tool | Version |
| --- | --- |
| macOS | 14 (Sonoma) or later |
| Xcode | 16 or later (command line tools selected via `xcode-select`); Xcode 26+ for the Liquid Glass appearance |
| Node.js | 20 or later |
| pnpm | **9.14.4** — exactly. pnpm 10+ fails with `ERR_PNPM_LOCKFILE_CONFIG_MISMATCH` |
| XcodeGen | latest (`brew install xcodegen`) |

**Build**

```sh
git clone https://github.com/ftzahao/kiss-translator-safari.git
cd kiss-translator-safari

make deps        # fetch and verify the pinned upstream release, install its dependencies
make all         # extension -> Xcode project -> universal .app -> DMG + ZIP
```

Individual targets are available if you want to stop halfway:

| Target | What it does |
| --- | --- |
| `make deps` | Fetch the pinned upstream release into `.build/upstream` and install its dependencies |
| `make extension` | Build the MV3 web extension into `extension/` |
| `make project` | Generate `KISSTranslator.xcodeproj` with XcodeGen |
| `make build` | Build `build/App/KISSTranslator.app` (universal arm64 + x86_64) |
| `make sign` | Sign the app (requires your own signing identity) |
| `make dmg` | Produce `build/dist/KISSTranslator-<version>.dmg` and `.zip` |
| `make all` | `extension` + `project` + `build` + `dmg` |
| `make verify` | Verify the pinned upstream version/commit and the produced bundle |
| `make clean` | Remove build outputs |

`scripts/release.mjs` orchestrates the full pipeline (version bumping, release notes, and
artifact collection) and is what CI uses.

### (c) Run in Xcode (for development)

```sh
make project
open KISSTranslator.xcodeproj
```

Press **Run** in Xcode. The app launches, but Safari will refuse to load the extension
because it is not signed by a trusted developer.

To allow unsigned extensions:

1. In Safari, open **Settings → Advanced** and enable **Show features for web developers**.
   (This is the current Safari UI; older instructions to use
   `defaults write com.apple.Safari IncludeDevelopMenu -bool true` are obsolete.)
2. A **Develop** menu now appears in the menu bar. Open **Develop → Allow Unsigned Extensions**.
   You will be asked for your password. This setting is cleared every time Safari restarts,
   so you must re-apply it after each relaunch.
3. Run the app from Xcode again so Safari picks up the extension, then enable it in
   **Settings → Extensions**.

If Safari still does not list the extension, `safaridriver --enable` (with administrator
rights) also enables the automation-related developer settings and is a useful diagnostic.

---

## Requirements

| | |
| --- | --- |
| OS | macOS 14 Sonoma or later |
| Browser | Safari 17 or later |
| Architecture | Universal binary — Apple Silicon (`arm64`) and Intel (`x86_64`) |
| Build tooling | Xcode 16+, Node 20+ (matches `upstream.nodeMajor`), pnpm 9.14.4, XcodeGen |
| Appearance | Liquid Glass on macOS 26+ when built with the macOS 26 SDK (Xcode 26+); classic appearance otherwise |
| iOS / iPadOS | Not supported yet |

---

## How it works

```
  upstream release  v<version>  (pinned in config/build.config.mjs)
         │
         │  make deps -- fetch tarball at the pinned commit, verify SHA, pnpm install (9.14.4)
         ▼
  .build/upstream/                (upstream source tree, never modified in place)
         │
         │  make extension -- build MV3 web extension
         ▼
  extension/                      (manifest.json, background.js, content.js, ...)
         │
         │  make project -- XcodeGen reads project.yml (+ config/build.config.mjs)
         ▼
  KISSTranslator.xcodeproj        (generated, git-ignored)
         │
         │  make build -- xcodebuild, configuration Release, universal binary
         ▼
  build/App/KISSTranslator.app
    └── Contents/PlugIns/KISSTranslatorExtension.appex
          └── Contents/Resources/manifest.json + extension assets
         │
         │  make dmg
         ▼
  build/dist/KISSTranslator-<version>.dmg  +  .zip
         │
         │  .github/workflows/release.yml on tag push
         ▼
  GitHub Release (with checksums.txt)
```

Key points:

- The Xcode project is **generated**. Never edit it by hand; edit the XcodeGen spec and run
  `make project`.
- The web extension is **built from a pinned upstream commit**, not from a moving branch.
  `make verify` re-checks the pin.
- The SwiftUI container is deliberately minimal: it hosts the `.appex` and explains how to
  enable it. All translation logic lives in the extension.

---

## Updating the app

On launch the app queries GitHub Releases once and, when a newer version exists,
shows an "Update to x.y.z" badge next to the version label. Clicking it opens a
sheet with the release notes and a download link.

Updates are not installed automatically: releases are unsigned, so replacing the
running app would be refused by Gatekeeper. Download the DMG, drag the app into
Applications to replace the old copy, and your extension settings (translation
providers, site rules, …) are preserved.

A failed check (offline, no releases published yet) stays out of the way and only
offers a "Check for Updates" retry link.

---

## Updating upstream

The upstream pin lives in `config/build.config.mjs`:

```js
export const upstream = {
  version: "2.1.1",
  commit: "a1279f2517bd478ef1dd93b941f9177094486cd4",
  pnpmVersion: "9.14.4",
  ...
};
```

To upgrade:

1. Find the upstream release tag and its commit on
   [fishjar/kiss-translator/releases](https://github.com/fishjar/kiss-translator/releases).
2. Update `upstream.version` and `upstream.commit` (and `app.marketingVersion`, which mirrors
   it).
3. Run `make clean && make deps && make verify` — this re-verifies the commit and rebuilds.
4. Add a `CHANGELOG.md` entry, commit, tag `v<version>`, push the tag. The release workflow
   refuses to publish if the tag does not match `app.marketingVersion`.

**The version you ship is the upstream version.** There is no separate packaging version
number; `2.1.1` here means "upstream KISS Translator 2.1.1, packaged for Safari".
Packaging-only fixes are added to the same changelog section and shipped as part of the
next upstream bump rather than as a separate tag, so the version always identifies the
upstream release.

---

## License & attribution

**This project is licensed under the GNU General Public License v3.0.** See [LICENSE](LICENSE)
and [NOTICE](NOTICE).

- **Original project:** [KISS Translator](https://github.com/fishjar/kiss-translator) by
  **fishjar** (Gabe), licensed GPL-3.0.
- This repository is a **derivative work**: it redistributes a build of the upstream web
  extension and adds a native macOS wrapper (SwiftUI container app, build scripts, project
  generator spec). The wrapper code is also GPL-3.0.
- Corresponding source for every binary we publish is available in this repository and at
  the pinned upstream commit listed in [NOTICE](NOTICE).
- **No warranty.** The software is provided "as is", without warranty of any kind, as stated
  in Sections 15 and 16 of the GPL.

### Trademark and donation disclaimer

- "KISS Translator" and its logo belong to the upstream author. This repository **does not
  claim to be, nor represent, the official KISS Translator extension**, and it has no
  affiliation with fishjar beyond inheritance of the GPL-licensed code.
- If you want to support the project financially, donate to the **upstream author** via the
  links in the [upstream README](https://github.com/fishjar/kiss-translator#appreciation).
  This repository does not accept donations.

---

## FAQ

**The extension does not appear in Safari → Settings → Extensions.**
Make sure the container app has been launched at least once from `/Applications` (Safari only
discovers extensions that are registered by an installed, launched app). Then quit and reopen
Safari. If you built from source, see [Run in Xcode](#c-run-in-xcode-for-development) and
enable **Develop → Allow Unsigned Extensions**.

**Safari says "Safari 无法验证扩展" / "Safari cannot verify the extension".**
This is the expected Gatekeeper behaviour for an unsigned/ad-hoc-signed build. Clear the
quarantine attribute as described in [Installation (a)](#a-download-from-releases-recommended-for-users),
or — for the sources you trust — build it yourself. A properly signed and notarized release
requires the maintainer's Apple Developer identity and is not automated yet.

**Why are releases unsigned? Why is there no notarization?**
Notarization requires a paid Apple Developer Program membership and a Developer ID
certificate. Those are private credentials and cannot be placed in a public CI workflow. The
release workflow produces ad-hoc-signed builds only.

**Is there a way to avoid the Gatekeeper warning?**
Build from source, or install a future signed and notarized release. Until then, every build
published here triggers the "unidentified developer" warning on first launch. This is
expected and is not a bug.

**Can I use this on iOS or iPadOS?**
Not yet. The project currently targets macOS only. iOS/iPadOS support would require an
additional build target and App Store distribution, and is tracked separately.

**Does it work with Safari Technology Preview?**
Usually yes, but it is not part of the tested matrix. Report issues with your exact
Safari/STP version.

**Where do I report a translation bug?**
If the translation itself is wrong (bad output, missing service, broken page layout),
report it [upstream](https://github.com/fishjar/kiss-translator/issues). If the problem is
installation, signing, the container app, or the build, report it
[here](https://github.com/ftzahao/kiss-translator-safari/issues). See [CONTRIBUTING.md](CONTRIBUTING.md).

**Is my data sent anywhere?**
The extension sends the text it translates to whichever translation service **you**
configure — the same behaviour as upstream. This project adds no telemetry and no servers.
See [SECURITY.md](SECURITY.md).

---

## Related links

- Upstream project: <https://github.com/fishjar/kiss-translator>
- Upstream companion services: [KISS-Worker](https://github.com/fishjar/kiss-worker) (sync),
  [kiss-rules](https://github.com/fishjar/kiss-rules) (community rules)
- Build details: [docs/BUILDING.md](docs/BUILDING.md)
