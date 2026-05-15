#!/usr/bin/env bash
# Cut a new release/vX.Y.Z branch from <main-branch>, merge <develop-branch>
# into it, and push. Refuses to run when a stale forward-merge PR exists or
# when develop has nothing ahead of main. On merge conflict the action aborts
# without pushing — the operator must resolve develop/main divergence by hand
# before re-running.
#
# Required env (set by action.yml):
#   GH_TOKEN                       gh CLI auth
#   INPUT_BUMP_TYPE                "major" or "minor"
#   INPUT_MAIN_BRANCH
#   INPUT_DEVELOP_BRANCH
#   INPUT_RELEASE_BRANCH_PREFIX
#   INPUT_GIT_USER_NAME
#   INPUT_GIT_USER_EMAIL

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source-path=SCRIPTDIR
# shellcheck source=_common.sh
source "${SCRIPTS_DIR}/_common.sh"

BUMP_TYPE="${INPUT_BUMP_TYPE:?INPUT_BUMP_TYPE not set}"
MAIN_BRANCH="${INPUT_MAIN_BRANCH:?INPUT_MAIN_BRANCH not set}"
DEVELOP_BRANCH="${INPUT_DEVELOP_BRANCH:?INPUT_DEVELOP_BRANCH not set}"
RELEASE_PREFIX="${INPUT_RELEASE_BRANCH_PREFIX:?INPUT_RELEASE_BRANCH_PREFIX not set}"
GIT_USER_NAME="${INPUT_GIT_USER_NAME:?INPUT_GIT_USER_NAME not set}"
GIT_USER_EMAIL="${INPUT_GIT_USER_EMAIL:?INPUT_GIT_USER_EMAIL not set}"

# 1. Validate bump-type.
if [[ "${BUMP_TYPE}" != "major" && "${BUMP_TYPE}" != "minor" ]]; then
  echo "Invalid bump-type: '${BUMP_TYPE}'. Must be 'major' or 'minor'." >&2
  exit 1
fi

# 2. Block on stale forward-merge PRs.
stale_release_to_develop=$(gh pr list --base "${DEVELOP_BRANCH}" --state open \
  --json headRefName,url \
  --jq "[.[] | select(.headRefName | startswith(\"${RELEASE_PREFIX}\"))] | .[].url")

stale_main_to_develop=$(gh pr list \
  --head "${MAIN_BRANCH}" --base "${DEVELOP_BRANCH}" --state open \
  --json url --jq '.[].url')

if [[ -n "${stale_release_to_develop}" || -n "${stale_main_to_develop}" ]]; then
  echo "Refusing to cut release: stale forward-merge PR(s) open:" >&2
  [[ -n "${stale_release_to_develop}" ]] && \
    echo "  ${RELEASE_PREFIX}* -> ${DEVELOP_BRANCH}: ${stale_release_to_develop}" >&2
  [[ -n "${stale_main_to_develop}" ]] && \
    echo "  ${MAIN_BRANCH} -> ${DEVELOP_BRANCH}: ${stale_main_to_develop}" >&2
  exit 1
fi

# 3. Configure git, fetch.
setup_git "${GIT_USER_NAME}" "${GIT_USER_EMAIL}"
git fetch --all --prune

# 4. Discover next version.
next_version=$(
  git for-each-ref --format='%(refname:short)' "refs/remotes/origin/${RELEASE_PREFIX}*" \
    | sed "s|^origin/||" \
    | python3 "${SCRIPTS_DIR}/next_release_version.py" \
        --bump "${BUMP_TYPE}" \
        --prefix "${RELEASE_PREFIX}"
)
new_branch="${RELEASE_PREFIX}v${next_version}"
echo "Next release branch: ${new_branch}"

# 5. Require develop ahead of main.
ahead=$(git rev-list --count "origin/${MAIN_BRANCH}..origin/${DEVELOP_BRANCH}")
if [[ "${ahead}" -eq 0 ]]; then
  echo "Refusing to cut release: ${DEVELOP_BRANCH} is not ahead of ${MAIN_BRANCH} — nothing to release." >&2
  exit 1
fi

# 6. Create branch from main.
git checkout -B "${new_branch}" "origin/${MAIN_BRANCH}"

# 7. Merge develop in. On conflict, abort and fail without pushing.
if ! git merge --no-ff "origin/${DEVELOP_BRANCH}" \
    -m "Merge ${DEVELOP_BRANCH} into ${new_branch}"; then
  echo "Merge conflict cutting ${new_branch}; aborting without push." >&2
  git merge --abort || true
  exit 1
fi

# 8. Push.
if ! git push origin "${new_branch}"; then
  echo "Push of ${new_branch} failed." >&2
  exit 1
fi

echo "Created ${new_branch} successfully."
