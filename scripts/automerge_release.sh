#!/usr/bin/env bash
# Merge pushes to a release/* branch into <develop-branch>, but only when a
# corresponding release/*->main PR is open and no release/*->develop PR
# already exists. On any failure, open a manual-resolution PR.
#
# Required env vars (set by action.yml):
#   GH_TOKEN                  gh CLI auth
#   GITHUB_REF_NAME           the pushed branch name (set by runner)
#   INPUT_MAIN_BRANCH
#   INPUT_DEVELOP_BRANCH
#   INPUT_GIT_USER_NAME
#   INPUT_GIT_USER_EMAIL

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source-path=SCRIPTDIR
# shellcheck source=_common.sh
source "${SCRIPTS_DIR}/_common.sh"

MAIN_BRANCH="${INPUT_MAIN_BRANCH}"
DEVELOP_BRANCH="${INPUT_DEVELOP_BRANCH}"
GIT_USER_NAME="${INPUT_GIT_USER_NAME}"
GIT_USER_EMAIL="${INPUT_GIT_USER_EMAIL}"

release_branch="${GITHUB_REF_NAME:-}"
if [[ -z "${release_branch}" ]]; then
  echo "GITHUB_REF_NAME is empty; cannot determine the pushed branch."
  exit 1
fi

# 1. Require an open <release>->main PR.
to_main=$(gh pr list --head "${release_branch}" --base "${MAIN_BRANCH}" --state open \
  --json url --jq '.[0].url // ""')
if [[ -z "${to_main}" ]]; then
  echo "No open PR from ${release_branch} to ${MAIN_BRANCH}. Skipping merge."
  exit 0
fi

# 2. Bail if a <release>->develop PR already exists.
to_develop=$(gh pr list --head "${release_branch}" --base "${DEVELOP_BRANCH}" --state open \
  --json url --jq '.[0].url // ""')
if [[ -n "${to_develop}" ]]; then
  echo "An open PR from ${release_branch} to ${DEVELOP_BRANCH} already exists: ${to_develop}. Skipping."
  exit 0
fi

# 3. Configure git, fetch, checkout develop.
setup_git "${GIT_USER_NAME}" "${GIT_USER_EMAIL}"
git fetch --all
git checkout "${DEVELOP_BRANCH}"

# 4. Merge release into develop.
if ! git merge "origin/${release_branch}" --no-ff \
    -m "Merge ${release_branch} into ${DEVELOP_BRANCH}"; then
  echo "Merge failed."
  open_manual_pr "${release_branch}" "${DEVELOP_BRANCH}"
  exit 1
fi

# 5. Push.
if ! git push origin "${DEVELOP_BRANCH}"; then
  echo "Push failed."
  open_manual_pr "${release_branch}" "${DEVELOP_BRANCH}"
  exit 1
fi

echo "Merged ${release_branch} into ${DEVELOP_BRANCH} successfully."
