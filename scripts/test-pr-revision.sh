#!/usr/bin/env bash
set -euo pipefail

# Fake only external reads; exercise the real guard without GitHub or AWS.
gh() {
  case "$*" in
    *git/ref/heads/main*) printf '%s\n' "$LIVE_MAIN" ;;
    *'pulls?state=open'*) printf '%b\n' "$OPEN_PRS" ;;
    *pulls/5*) printf '%s\t%s\t%s\n' "$LIVE_STATE" "$LIVE_HEAD" "$LIVE_BASE" ;;
    *) return 99 ;;
  esac
}
git() {
  if [[ "$*" == 'rev-parse HEAD^1' ]]; then printf '%s\n' "$CHECKOUT_BASE"; else printf '%s\n' "$CHECKOUT_SHA"; fi
}
export -f gh git
export GITHUB_REPOSITORY=example/infra PR_NUMBER=5
export PR_BASE_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
export PR_HEAD_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
export GITHUB_SHA=cccccccccccccccccccccccccccccccccccccccc
export LIVE_MAIN="$PR_BASE_SHA" LIVE_HEAD="$PR_HEAD_SHA" LIVE_STATE=open LIVE_BASE=main
export CHECKOUT_BASE="$PR_BASE_SHA" CHECKOUT_SHA="$GITHUB_SHA" OPEN_PRS=5

reject() {
  local expected="$1" output
  shift
  if output="$("$@" 2>&1)"; then echo "Expected rejection: $expected" >&2; exit 1; fi
  [[ "$output" == *"$expected"* ]] || { echo "$output" >&2; exit 1; }
}
bash scripts/check-pr-revision.sh
reject 'Main changed' env LIVE_MAIN=dddddddddddddddddddddddddddddddddddddddd bash scripts/check-pr-revision.sh
reject 'Main changed' env CHECKOUT_BASE=dddddddddddddddddddddddddddddddddddddddd bash scripts/check-pr-revision.sh
reject 'PR closed, retargeted or updated' env LIVE_HEAD=dddddddddddddddddddddddddddddddddddddddd bash scripts/check-pr-revision.sh
reject 'PR closed, retargeted or updated' env LIVE_STATE=closed bash scripts/check-pr-revision.sh
reject 'PR closed, retargeted or updated' env LIVE_BASE=other bash scripts/check-pr-revision.sh
reject 'Checkout does not match' env CHECKOUT_SHA=dddddddddddddddddddddddddddddddddddddddd bash scripts/check-pr-revision.sh
reject 'Only one owner-authored PR' env OPEN_PRS='5\n6' bash scripts/check-pr-revision.sh
echo 'PR revision guard: 8 cases passed.'
