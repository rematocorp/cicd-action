#!/usr/bin/env bash
# On branch create: if the branch matches one of the configured prefixes,
# optionally set the version in configured package.json files to the version
# carried in the branch name (the suffix after the matched prefix, with any
# leading 'v' stripped), commit & push it back, then open a PR to the base
# branch. Skips if any open PR from a branch sharing the matched prefix to
# the base branch already exists.
#
# Required env (always):
#   GH_TOKEN              — for gh CLI
#   GITHUB_REF_NAME       — created branch name (set by GitHub Actions)
#   GITHUB_REPOSITORY     — "owner/repo" (set by GitHub Actions)
#   INPUT_BRANCH_PREFIXES — newline-separated prefix list (e.g. "release/\nhotfix/")
#   INPUT_BASE_BRANCH     — PR base branch
#
# Required env (only when version setting is configured):
#   INPUT_VERSION_WRITE_FILES   — newline-separated package.json paths to update
#   INPUT_GIT_USER_NAME   — author name for the version commit
#   INPUT_GIT_USER_EMAIL  — author email for the version commit

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BRANCH="${GITHUB_REF_NAME:?GITHUB_REF_NAME not set}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY not set}"
BASE="${INPUT_BASE_BRANCH:?INPUT_BASE_BRANCH not set}"

matched_prefix=""
while IFS= read -r prefix; do
  prefix="${prefix%$'\r'}"
  [[ -z "$prefix" ]] && continue
  if [[ "$BRANCH" == "$prefix"* ]]; then
    matched_prefix="$prefix"
    break
  fi
done <<< "${INPUT_BRANCH_PREFIXES:-}"

if [[ -z "$matched_prefix" ]]; then
  echo "Branch '$BRANCH' does not match any configured prefix; skipping."
  exit 0
fi

prefix_clean="${matched_prefix%/}"
suffix="${BRANCH#"$matched_prefix"}"
prefix_cap="$(tr '[:lower:]' '[:upper:]' <<< "${prefix_clean:0:1}")${prefix_clean:1}"
TITLE="${prefix_cap}/${suffix}"

existing=$(gh pr list \
  --repo "$REPO" \
  --state open \
  --base "$BASE" \
  --json headRefName,url \
  --jq "[.[] | select(.headRefName | startswith(\"$matched_prefix\"))] | .[0].headRefName + \" \" + .[0].url")

if [[ -n "${existing// /}" ]]; then
  echo "Open PR with prefix '$matched_prefix' → '$BASE' already exists: $existing; skipping."
  exit 0
fi

# --- optional: set version from branch suffix ---

version_files=()
while IFS= read -r f; do
  f="${f%$'\r'}"
  [[ -z "$f" ]] && continue
  version_files+=("$f")
done <<< "${INPUT_VERSION_WRITE_FILES:-}"

if [[ ${#version_files[@]} -gt 0 ]]; then
  if [[ -z "${INPUT_GIT_USER_NAME:-}" || -z "${INPUT_GIT_USER_EMAIL:-}" ]]; then
    echo "git-user-name and git-user-email are required when version-write-files is set." >&2
    exit 1
  fi

  version="${suffix#v}"

  git config user.name "$INPUT_GIT_USER_NAME"
  git config user.email "$INPUT_GIT_USER_EMAIL"

  python3 "$SCRIPTS_DIR/set_version.py" "$version" "${version_files[@]}"

  git add -- "${version_files[@]}"
  if git diff --cached --quiet; then
    echo "Setting version $version produced no changes; skipping commit."
  else
    git commit -m "chore: set version to $version"
    git push origin "$BRANCH"
  fi
fi

# --- open the PR ---

gh pr create \
  --repo "$REPO" \
  --base "$BASE" \
  --head "$BRANCH" \
  --title "$TITLE" \
  --body ""
