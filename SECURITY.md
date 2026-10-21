# Security Policy

## Supported versions

Only the most recent release receives security fixes. Because the shipped
version always tracks the pinned upstream release, a security fix almost always
means bumping the upstream pin and publishing a new release.

| Version | Supported |
| --- | --- |
| Latest release | Yes |
| Older releases | No |

## Reporting a vulnerability

**Please do not open a public GitHub issue for security problems.**

Report privately using either:

- GitHub's private vulnerability reporting:
  <https://github.com/ftzahao/kiss-translator-safari/security/advisories/new>
  (recommended, encrypted and tracked), or
- Email the maintainer listed on the <https://github.com/ftzahao> profile.

Please include:

- A description of the issue and its impact
- Steps to reproduce, or a proof of concept
- Affected version(s): the app version and, if relevant, the upstream version
  shown in the extension settings
- macOS and Safari versions
- Whether the same issue reproduces with the upstream extension in Chrome or
  Firefox (this helps us decide where the fix belongs)

We aim to acknowledge reports within 7 days. We will coordinate a disclosure
timeline with you and credit you in the advisory unless you prefer otherwise.

## Scope

In scope for this repository:

- The macOS container app and the way it embeds and launches the extension
- Build tooling, including supply-chain integrity of the pinned
  upstream source (pin verification, artifact checksums)
- Code signing and packaging mistakes that would weaken distribution security
- Documentation that gives unsafe installation instructions

Out of scope here — report upstream instead:

- Vulnerabilities in the extension's JavaScript, in third-party API adapters,
  or in the translation flow itself
  (<https://github.com/fishjar/kiss-translator/security>)
- Issues in translation service providers (Google, DeepL, OpenAI, etc.)

## Third-party services and data flow

Understanding the network model matters when judging a report:

- This project operates **no servers** and collects **no telemetry**. There is
  no backend owned by the maintainers of this repository.
- The extension sends the text it translates to the translation service **the
  user configures**. Depending on the selected service, that text leaves the
  machine and reaches a third party (a commercial API, an aggregator, a
  self-hosted endpoint such as Ollama/DeepLX, or the browser's built-in AI).
- Configuration sync, if enabled, talks to a user-supplied endpoint such as a
  self-hosted [KISS-Worker](https://github.com/fishjar/kiss-worker) deployment
  or a WebDAV server. Credentials live in extension storage on the device.
- API keys are stored in the extension's local storage. They are not transmitted
  anywhere except to the service the key belongs to. Anyone with access to your
  Safari profile can read them — treat the profile like a credential store.

We cannot audit or control the privacy practices of third-party translation
services. Choose services whose terms you accept.

## Distribution integrity

- Release artifacts are published with a `checksums.txt` (SHA-256). Verify it
  before installing:
  ```sh
  shasum -a 256 -c checksums.txt
  ```
- Release builds are **ad-hoc signed and not notarized**. This is a known
  limitation documented in the README, not a vulnerability in itself. Clearing
  the quarantine flag is therefore a deliberate act of trust: if you do not want
  to grant that trust, build from source.
- The pinned upstream commit in `config/build.config.mjs` is verified by
  `make verify`. A PR that changes the pin without a corresponding upstream
  release will be scrutinized.
