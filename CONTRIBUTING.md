# Contributing

Thanks for your interest in KISS Translator for Safari. Please read this before
opening an issue or a pull request.

- [Where to report what](#where-to-report-what)
- [Reporting a bug](#reporting-a-bug)
- [Requesting a feature](#requesting-a-feature)
- [Building and testing](#building-and-testing)
- [What this repository does and does not do](#what-this-repository-does-and-does-not-do)
- [Pull request guidelines](#pull-request-guidelines)
- [Licensing of contributions](#licensing-of-contributions)

## Where to report what

This repository is a **packaging layer**, not a fork of the extension's logic.
Deciding where to report something saves everyone time:

| Problem | Report to |
| --- | --- |
| Wrong/missing translation, a service failing, API errors | [Upstream](https://github.com/fishjar/kiss-translator/issues) |
| Page layout broken by translation, rules not applying | [Upstream](https://github.com/fishjar/kiss-translator/issues) |
| Subtitle, TTS or prompt behaviour | [Upstream](https://github.com/fishjar/kiss-translator/issues) |
| App will not launch, DMG/ZIP problems, Gatekeeper/quarantine | **This repository** |
| Safari does not list the extension, "cannot verify extension" | **This repository** |
| Build failures, `make` targets, CI, Xcode project generation | **This repository** |
| Container app UI (the small window that explains how to enable) | **This repository** |

Upstream supports Chrome/Edge/Firefox; when reporting there, state clearly that
you are on **Safari (macOS)** and include the Safari version, so maintainers do
not chase browser-only differences.

## Reporting a bug

Use the [bug report template](https://github.com/ftzahao/kiss-translator-safari/issues/new?template=bug_report.yml)
and fill in every field. At minimum we need:

- macOS version (`sw_vers -productVersion`)
- Safari version (Safari → About Safari)
- App version (what the release tag says, e.g. `2.1.1`)
- Upstream version shown in the extension's About/settings page
- Exact steps to reproduce, expected result, actual result
- Whether the app was downloaded from Releases or built locally

If a crash or launch failure is involved, attach the console output if you have
it:

```sh
log show --last 5m --predicate 'process == "KISSTranslator"' --style compact
```

## Requesting a feature

Use the [feature request template](https://github.com/ftzahao/kiss-translator-safari/issues/new?template=feature_request.yml).
Be concrete about the outcome you want.

Feature requests that belong upstream (new translation service, new rule
capability, new UI in the extension) are usually closed here with a pointer to
upstream. Packing-related requests (universal binary tweaks, notarization,
alternate distribution, iOS build) are in scope here.

## Building and testing

```sh
git clone https://github.com/ftzahao/kiss-translator-safari.git
cd kiss-translator-safari

make deps         # fetch + verify the pinned upstream release, install deps
make all          # extension -> project -> app -> dmg
make verify       # confirm the upstream pin and the produced bundle
```

Requirements: macOS 14+, Xcode 16+, Node 20+, **pnpm 9.14.4** (exactly; pnpm 10+
fails with `ERR_PNPM_LOCKFILE_CONFIG_MISMATCH`), XcodeGen.

Before opening a pull request, please make sure:

1. `make clean && make all SIGNING=0` succeeds from a clean tree.
2. `make verify` passes.
3. If you changed the upstream pin, `config/build.config.mjs`, the XcodeGen spec
   and `CHANGELOG.md` are updated consistently.
4. No generated artifact is committed — `build/`, `dist/`, `*.xcodeproj`, `.build/`
   are git-ignored and must stay that way.
5. You tested the extension in Safari (`make project && open KISSTranslator.xcodeproj`,
   then enable **Develop → Allow Unsigned Extensions** after turning on
   **Settings → Advanced → Show features for web developers**).

See [docs/BUILDING.md](docs/BUILDING.md) for target-by-target details and
troubleshooting.

CI (`.github/workflows/ci.yml`) runs the same unsigned build on `macos-15` and
asserts that the built `.app` contains the `.appex` with a valid
`manifest.json`. A red CI run will not be merged.

## What this repository does and does not do

- **Does:** fetch a pinned upstream commit, build it, wrap it in a native macOS
  container, sign/pack it, and document it.
- **Does not:** modify the extension's JavaScript, add translation services, or
  maintain a separate rules database.

Prefer changes that keep the upstream sources unmodified. If a change genuinely
requires patching upstream, it must be a small, documented patch applied by the
build scripts — never an edited copy of the upstream tree — and it must be
called out in the pull request and the changelog.

## Pull request guidelines

- Keep pull requests focused; one logical change per PR.
- Describe **why**, not just what. Link the issue it closes.
- Include build evidence: CI link, or the output of `make verify` and the
  artifact names produced by `make dmg`.
- Update the docs you invalidate (README, README.zh-CN, docs/, CHANGELOG).
- Do not bump versions in a regular PR unless the PR is the upstream upgrade.

## Licensing of contributions

This project is GPL-3.0. By submitting a pull request you agree that your
contribution is licensed under the same terms. Do not copy code from sources
whose license is incompatible with GPL-3.0.
