# GitHub repo settings

These settings live in GitHub, not in the code, so this file is the only record of them.

## In place

### Branch ruleset `main` (api#5, set 2026-11-28)

Settings → Rules → Rulesets. Active on the default branch, with no bypass list, so it applies to admins too.

- Restrict deletions and block force pushes.
- Require a pull request before merging, with 0 required approvals. GitHub doesn't let you approve your own pull request, so any higher number would block every merge.
- Require the status checks `scan`, `lint` and `test` to pass, with branches up to date before merging.
- `image` is left out. It runs only on pushes to `main`, so a pull request would wait for it forever.

Every change to `main`, including small edits, goes through a pull request.

### Visibility

- The repo is public on purpose, so it can be shown to recruiters and interviewers.
- The GHCR package `ghcr.io/nleffers/chaos-desk-api` is public and linked to this repo. Treat every image and CI log as public, and never bake secrets into an image.
