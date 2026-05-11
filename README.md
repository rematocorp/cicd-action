# cicd-action

Composite GitHub Actions that automate the forward-merge loop and PR plumbing for repositories using the **main → release/v\* → develop** branching model.

- **`merge-main-to-next`** — when `main` is updated (typically by a hotfix or a release merge), forward-merge `main` into the currently open `release/*` branch, or into `develop` if no release is in flight.
- **`merge-release-to-develop`** — when a `release/*` branch is updated and has an open PR into `main`, forward-merge that release branch into `develop` so develop stays current with staging fixes.
- **`open-release-or-hotfix-pr`** — when a `release/*` or `hotfix/*` branch is created, optionally write the version carried in the branch name (e.g. `release/v1.2.3` → `1.2.3`) into configured `package.json` files, then open a PR from that branch to `main`. Prefixes and target are configurable.

On any merge conflict the merge actions open a manual-resolution PR rather than guessing — except for the narrow case of a single `"version"`-line conflict in configured `package.json` files, which is auto-resolved to keep HEAD.

## Branching model

Three long-lived branches:

- **`main`** — production. The shipping state.
- **`release/v*`** — staging. Cut from `develop` for each release; merged to `main` to ship.
- **`develop`** — next. Where `feature/*` work integrates.

Code moves through human-reviewed PRs from the side branches into the long-lived ones (forward path), and automerges back down so lower branches stay current with what landed upstream (back-propagation):

```
   bugfix/*
   feature/*                bugfix/*               hotfix/*
       │ PR                     │ PR                    │ PR*
       │                        │                       │
       ▼                        ▼                       ▼
    develop ◄── automerge ── release/v* ──── PR* ────► main
       ▲                        ▲                       │
       │                        │                       │
       │                        └─── automerge ─────────┤
       │                          (when release open)   │
       │                                                │
       └─── automerge (when no release/v* is open) ─────┘

   * PR auto-opened by open-release-or-hotfix-pr
```

The back-flow runs in two hops: `main → release/v*` via **`merge-main-to-next`**, then `release/v* → develop` via **`merge-release-to-develop`**. When there's no open `release/v*`, **`merge-main-to-next`** routes `main` straight into `develop` instead.

What this repo automates:

| When | What happens | Action |
|---|---|---|
| A `release/*` or `hotfix/*` branch is created | (Optionally) the version from the branch name is written into configured `package.json` files; then a PR from that branch to `main` is opened | `open-release-or-hotfix-pr` |
| `main` receives a push (hotfix or release-ship) | `main` is merged into the open `release/v*` (or `develop` if no release is in flight) | `merge-main-to-next` |
| `release/v*` receives a push (with a PR to `main` open) | `release/v*` is merged into `develop` | `merge-release-to-develop` |

Without automation, every push to `main` and every push to `release/*` needs a human to remember to forward-merge, and every release/hotfix branch needs someone to open the PR. These actions close those loops.

## Quick start

In each consumer repo, add the workflow files for the actions you want.

### `.github/workflows/automerge-main.yml`

```yaml
name: Automerge main

on:
  push:
    branches: [main]

permissions:
  contents: write
  pull-requests: write

jobs:
  automerge:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: rematocorp/cicd-action/merge-main-to-next@v1
        with:
          git-user-name: my-org-bot
          git-user-email: bot@example.com
```

### `.github/workflows/automerge-release.yml`

```yaml
name: Automerge release → develop

on:
  push:
    branches: ['release/*']

permissions:
  contents: write
  pull-requests: write

jobs:
  automerge:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: rematocorp/cicd-action/merge-release-to-develop@v1
        with:
          git-user-name: my-org-bot
          git-user-email: bot@example.com
```

### `.github/workflows/open-release-or-hotfix-pr.yml`

```yaml
name: Open Release/Hotfix PR

on:
  create:

permissions:
  contents: write       # only needed when version-write-files is set
  pull-requests: write

jobs:
  open-pr:
    if: |
      github.event.ref_type == 'branch' && (
        startsWith(github.event.ref, 'release/') ||
        startsWith(github.event.ref, 'hotfix/')
      )
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4   # only needed when version-write-files is set
      - uses: rematocorp/cicd-action/open-release-or-hotfix-pr@v1
        with:
          version-write-files: |
            frontend/package.json
            backend/package.json
          git-user-name: my-org-bot
          git-user-email: bot@example.com
```

The job-level `if:` keeps a runner from spinning up for every branch creation — the `on: create` trigger fires for *every* new branch and tag, so without the guard you'd pay for a runner that then exits as a no-op. Keep this `startsWith(...)` list in sync with the action's `branch-prefixes` input.

If you don't want the version write, drop `version-write-files`, the checkout step, and the `contents: write` permission — the action will just open the PR.

> **Note on the token:** PRs opened with the default `GITHUB_TOKEN` do *not* trigger downstream workflows (e.g. CI on the new PR). To get CI to run on the auto-opened PR, pass a PAT from a bot account via the `github-token` input.

That's the whole integration.

## Inputs

### `merge-main-to-next`

| Input | Default | Required |
|---|---|---|
| `github-token` | `${{ github.token }}` | no |
| `main-branch` | `main` | no |
| `develop-branch` | `develop` | no |
| `release-branch-prefix` | `release/` | no |
| `version-conflict-files` | — (empty = no auto-resolution) | no |
| `git-user-name` | — | **yes** |
| `git-user-email` | — | **yes** |

### `merge-release-to-develop`

| Input | Default | Required |
|---|---|---|
| `github-token` | `${{ github.token }}` | no |
| `main-branch` | `main` | no |
| `develop-branch` | `develop` | no |
| `release-branch-prefix` | `release/` | no |
| `git-user-name` | — | **yes** |
| `git-user-email` | — | **yes** |

`main-branch` is the **gate** for this action: the merge into `develop` only runs if there's an open PR `release/* → <main-branch>`. Without that PR, a push to a `release/*` branch is treated as a stale/abandoned release and skipped. Override `main-branch` if your production branch is named something other than `main`.

### `open-release-or-hotfix-pr`

| Input | Default | Required |
|---|---|---|
| `github-token` | `${{ github.token }}` | no |
| `branch-prefixes` | `release/`<br>`hotfix/` (newline-separated) | no |
| `base-branch` | `main` | no |
| `version-write-files` | — (empty = don't write version) | no |
| `git-user-name` | — | **yes** when `version-write-files` is set |
| `git-user-email` | — | **yes** when `version-write-files` is set |

PR title is derived from the matched prefix: e.g. `release/v1.2.3` → `Release/v1.2.3`, `hotfix/1.2.4` → `Hotfix/1.2.4`. Both `release/v1.2.3` and `release/1.2.3` work — the leading `v` is optional, and the same applies to `hotfix/`. If any open PR from a branch sharing the matched prefix to `base-branch` already exists, the step is a no-op — this prevents duplicate release/hotfix PRs when multiple `release/*` (or `hotfix/*`) branches get created.

**Version writing (optional).** If `version-write-files` is non-empty, the action takes the branch suffix (everything after the matched prefix), strips any leading `v`, and writes the result into the top-level `"version"` field of each listed `package.json` (rewriting only the version string — no `yarn`/`npm` runs, no lockfile updates). So `release/v1.2.3` *and* `release/1.2.3` both produce `"version": "1.2.3"`. It then commits as the configured git identity and pushes back to the new branch *before* opening the PR. The suffix must be a valid semver (`X.Y.Z`, optionally with `-prerelease` or `+build`); otherwise the action fails. Requires the workflow to run `actions/checkout` and to grant `contents: write`.

`git-user-name` and `git-user-email` are intentionally required — the action makes commits on your behalf and there's no sensible cross-org default.

## Required permissions

Both actions need:

```yaml
permissions:
  contents: write       # push merge commits
  pull-requests: write  # read PR state, open manual-resolution PRs
```

If you use a custom `github-token` (e.g. a PAT from a bot account), it needs the same scopes.

## Branch protection

The action pushes commits directly to `release/*` (from `merge-main-to-next`) and to `develop` (from both actions). **These branches must allow direct pushes from the action's identity** — if they're protected by required status checks, required reviews, or "require a pull request before merging", the push will be rejected and the action will fall back to opening a manual-resolution PR for *every* run.

Recommended setup:
- **`main`** — protect as you wish; this action never pushes to `main`. Pushes here come from human-merged `release/* → main` PRs.
- **`release/*`** — leave unprotected, or add a bypass for the bot identity / `github-actions[bot]`.
- **`develop`** — same as `release/*`.

If you must keep protection on `develop`/`release/*`, use GitHub's "Allow specified actors to bypass required pull requests" in the branch ruleset and add your bot (or the `github-actions` app) to the bypass list.

## Version conflict auto-resolution

When `merge-main-to-next` merges and hits a conflict:

1. It lists the unmerged paths.
2. If any unmerged path is **not** in `version-conflict-files`, it aborts and opens a manual PR.
3. Otherwise it runs a conflict resolver on each listed file. The resolver succeeds only when the conflict in that file is a single `"version": "..."` line on each side — it keeps HEAD's value. Any other shape (extra lines on either side, multiple conflict blocks where any is not version-only) aborts to manual PR.

Practically, this lets release-version bumps from `main` flow into the open `release/*` branch (or `develop`) without human intervention, while *any* substantive conflict surfaces as a PR.

## Pinning a version

Recommended: pin the floating major tag.

```yaml
uses: rematocorp/cicd-action/merge-main-to-next@v1
```

For reproducibility, pin an exact version:

```yaml
uses: rematocorp/cicd-action/merge-main-to-next@v1.0.0
```

The major tag (`v1`) is updated on each `v1.x.y` release.

## Customizing defaults

The defaults (`main`, `develop`, `release/`) assume a `main → release/v* → develop` branching model. If your conventions differ, override the relevant inputs. The git identity inputs are always required and have no built-in fallback.

```yaml
uses: rematocorp/cicd-action/merge-main-to-next@v1
with:
  main-branch: master
  develop-branch: dev
  release-branch-prefix: rel/
  version-conflict-files: |
    apps/web/package.json
    apps/api/package.json
  git-user-name: my-org-bot
  git-user-email: bot@example.com
```

## License

MIT — see `LICENSE`.
