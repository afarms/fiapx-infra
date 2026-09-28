#!/usr/bin/env bash
set -euo pipefail

fail() { echo "::error::$1" >&2; exit 1; }
[[ "${PR_NUMBER:-}" =~ ^[0-9]+$ ]] || fail 'Invalid pull request number.'
[[ "${PR_HEAD_SHA:-}" =~ ^[0-9a-f]{40}$ && "${PR_BASE_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || fail 'Invalid pull request revision.'

# Serialization alone is insufficient while a previous applied PR is unmerged.
open_prs="$(gh api --paginate "repos/$GITHUB_REPOSITORY/pulls?state=open&base=main&per_page=100" --jq '.[] | select(.head.repo.id == .base.repo.id and .user.login == .base.repo.owner.login) | .number')"
[[ "$open_prs" == "$PR_NUMBER" ]] || fail 'Only one owner-authored PR from this repository may be open for main while applying shared infrastructure.'

# Read live metadata after the exclusivity check, not the queued event alone.
pr="$(gh api "repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER" --jq '[.state, .head.sha, .base.ref] | @tsv')"
[[ "$pr" == $'open\t'"$PR_HEAD_SHA"$'\tmain' ]] || fail 'PR closed, retargeted or updated. Run the workflow for its current revision.'
main_sha="$(gh api "repos/$GITHUB_REPOSITORY/git/ref/heads/main" --jq '.object.sha')"
[[ "$(git rev-parse HEAD)" == "$GITHUB_SHA" ]] || fail 'Checkout does not match this run.'
[[ "$PR_BASE_SHA" == "$main_sha" && "$(git rev-parse HEAD^1)" == "$main_sha" ]] || fail 'Main changed since this merge revision was created. Update the PR branch and run its new workflow.'

echo 'PR revision matches current main and is the only deployment PR.'
