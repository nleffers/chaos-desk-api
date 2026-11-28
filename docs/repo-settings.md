# GitHub repo settings

These settings live in GitHub, not in the code, so this file is the only record of them.

## To do

- [ ] Require CI to pass before merging to `main` (api#5).
  - When: after `.github/workflows/ci.yml` has run once on `main`, so its check names exist to pick from.
  - Where: Settings → Rules → Rulesets → New branch ruleset, targeting `main`.
  - What: require a pull request before merging, and require the status checks `scan`, `lint` and `test`.
  - Leave out `image`. It runs only on pushes to `main`, so a pull request would wait for it forever.
  - As of 2026-11-28, `main` has no branch protection and no rulesets.
