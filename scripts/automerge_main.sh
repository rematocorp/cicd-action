#!/usr/bin/env bash
# Merge pushes to <main-branch> forward into an open release/* branch (or
# develop if none). On conflict, attempt to auto-resolve only the configured
# package.json version files; otherwise open a manual-resolution PR.
#
# Required env vars (set by action.yml):
#   GH_TOKEN                       gh CLI auth
#   INPUT_MAIN_BRANCH
#   INPUT_DEVELOP_BRANCH
#   INPUT_RELEASE_BRANCH_PREFIX
#   INPUT_VERSION_CONFLICT_FILES   newline-separated; may be empty
#   INPUT_GIT_USER_NAME
#   INPUT_GIT_USER_EMAIL

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source-path=SCRIPTDIR
# shellcheck source=_common.sh
source "${SCRIPTS_DIR}/_common.sh"

MAIN_BRANCH="${INPUT_MAIN_BRANCH}"
DEVELOP_BRANCH="${INPUT_DEVELOP_BRANCH}"
RELEASE_PREFIX="${INPUT_RELEASE_BRANCH_PREFIX}"
GIT_USER_NAME="${INPUT_GIT_USER_NAME}"
GIT_USER_EMAIL="${INPUT_GIT_USER_EMAIL}"
RESOLVER="${SCRIPTS_DIR}/resolve_package_versions.py"

# Parse newline-separated allowlist into an array; skip empty lines.
VERSION_CONFLICT_FILES=()
while IFS= read -r line; do
  [[ -n "${line}" ]] && VERSION_CONFLICT_FILES+=("${line}")
done <<< "${INPUT_VERSION_CONFLICT_FILES:-}"

# 1. Pick target: any open release/*->main PR, else develop.
target="${DEVELOP_BRANCH}"
release_head=$(gh pr list --base "${MAIN_BRANCH}" --state open \
  --json headRefName \
  --jq ".[] | select(.headRefName | startswith(\"${RELEASE_PREFIX}\")) | .headRefName" \
  | head -n1)

if [[ -n "${release_head}" ]]; then
  target="${release_head}"
fi
echo "Target branch for merging ${MAIN_BRANCH}: ${target}"

# 2. Idempotency: bail if a main->target PR already exists.
existing=$(gh pr list --head "${MAIN_BRANCH}" --base "${target}" --state open \
  --json url --jq '.[0].url // ""')
if [[ -n "${existing}" ]]; then
  echo "An open PR from ${MAIN_BRANCH} to ${target} already exists: ${existing}. Exiting."
  exit 0
fi

# 3. Configure git and fetch.
setup_git "${GIT_USER_NAME}" "${GIT_USER_EMAIL}"
git fetch origin
git checkout "${target}"

# 4. Attempt the merge.
if git merge "origin/${MAIN_BRANCH}" --no-ff -m "Merge ${MAIN_BRANCH} into ${target}"; then
  echo "Merge clean."
else
  # 5a. Read unmerged paths.
  mapfile -t UNMERGED < <(git diff --name-only --diff-filter=U)
  echo "Unmerged paths: ${UNMERGED[*]:-<none>}"

  # 5b. Every unmerged path must be in the allowlist.
  for path in "${UNMERGED[@]}"; do
    found=0
    if (( ${#VERSION_CONFLICT_FILES[@]} > 0 )); then
      for allow in "${VERSION_CONFLICT_FILES[@]}"; do
        [[ "${path}" == "${allow}" ]] && { found=1; break; }
      done
    fi
    if (( found == 0 )); then
      echo "Unexpected conflict in '${path}' (not in version-conflict-files allowlist)."
      open_manual_pr "${MAIN_BRANCH}" "${target}"
      exit 1
    fi
  done

  # 5c. Run the resolver on each unmerged path.
  for path in "${UNMERGED[@]}"; do
    if ! python3 "${RESOLVER}" "${path}"; then
      echo "Resolver failed on ${path}."
      open_manual_pr "${MAIN_BRANCH}" "${target}"
      exit 1
    fi
  done

  # 5d. Defense-in-depth: re-scan for markers.
  for path in "${UNMERGED[@]}"; do
    if grep -qE '^(<<<<<<<|=======|>>>>>>>)' "${path}"; then
      echo "Conflict markers still present in ${path} after resolution."
      open_manual_pr "${MAIN_BRANCH}" "${target}"
      exit 1
    fi
  done

  # 5e. Stage resolved files; verify no unmerged paths remain.
  git add -- "${UNMERGED[@]}"
  remaining=$(git diff --name-only --diff-filter=U)
  if [[ -n "${remaining}" ]]; then
    echo "Unresolved conflicts remain: ${remaining}"
    open_manual_pr "${MAIN_BRANCH}" "${target}"
    exit 1
  fi

  git commit -m "Resolve version conflicts"
fi

# 6. Push.
if ! git push origin "${target}"; then
  echo "Push failed."
  open_manual_pr "${MAIN_BRANCH}" "${target}"
  exit 1
fi

echo "Merged ${MAIN_BRANCH} into ${target} successfully."
