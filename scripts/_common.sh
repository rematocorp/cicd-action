#!/usr/bin/env bash
# Shared helpers for automerge scripts. Sourced by automerge_main.sh and
# automerge_release.sh. Assumes `gh` (with GH_TOKEN exported) and `git`.

setup_git() {
  local name="$1"
  local email="$2"
  git config user.name "${name}"
  git config user.email "${email}"
}

# open_manual_pr <head> <base>
# Idempotent: returns 0 without creating a new PR if one already exists with
# the same head/base in the open state.
open_manual_pr() {
  local head="$1"
  local base="$2"
  local existing
  existing=$(gh pr list --head "${head}" --base "${base}" --state open \
    --json url --jq '.[0].url // ""')
  if [[ -n "${existing}" ]]; then
    echo "Manual PR already exists: ${existing}"
    return 0
  fi
  gh pr create \
    --head "${head}" \
    --base "${base}" \
    --title "Manual merge ${head} into ${base}" \
    --body "This PR was created due to a merge conflict or a push failure. Please resolve manually."
}
