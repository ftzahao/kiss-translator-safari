## Summary

<!-- What does this PR change, and why? Link the issue it closes. -->

Closes #

## Type of change

- [ ] Packaging / build pipeline
- [ ] CI or release workflow
- [ ] Container app (SwiftUI)
- [ ] Documentation
- [ ] Upstream version bump
- [ ] Other (describe below)

## Checklist

- [ ] `make clean && make all SIGNING=0` succeeds from a clean tree
- [ ] `make verify` passes
- [ ] No generated artifacts committed (`build/`, `dist/`, `*.xcodeproj`, `.build/`)
- [ ] Tested in Safari (extension loads and translates a page)
- [ ] Docs updated if behaviour or requirements changed (README, README.zh-CN, docs/, CHANGELOG)
- [ ] Upstream sources remain unmodified; any required patch is documented below

## Upstream pin

<!-- Only for version bumps. Otherwise write "unchanged". -->

- Upstream version: ``
- Upstream commit: ``
- Corresponding `app.marketingVersion`: ``

## Verification evidence

<!-- CI run link, or the output of `make verify` and the artifact names from `make dmg`. -->

```
```

## Notes for reviewers

<!-- Risks, follow-ups, anything intentionally left out of scope. -->
