#!/usr/bin/env bash
set -euo pipefail

# Exercise rejection paths without AWS credentials, network, jq or Terraform.
git() { printf '%s\n' "${TEST_HEAD:-$GITHUB_SHA}"; }
aws() { echo 'UNEXPECTED_AWS_CALL'; return 90; }
export -f git aws
export GITHUB_REF=refs/heads/main
export GITHUB_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
export EXPECTED_ACCOUNT=000000000000
export TF_VAR_media_bucket_name=fiapx-media-unit-test
export GITHUB_RUN_ID=123 GITHUB_RUN_ATTEMPT=1
export PLAN_ID=123-1 PLAN_COMMIT="$GITHUB_SHA"
export PLAN_SHA256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

reject() {
  local expected="$1"
  shift
  local output
  if output="$("$@" 2>&1)"; then
    echo "Expected rejection: $expected" >&2
    exit 1
  fi
  [[ "$output" == *"$expected"* && "$output" != *UNEXPECTED_AWS_CALL* ]] || { echo "Unexpected result: $output" >&2; exit 1; }
}

reject 'Expected plan or apply' bash scripts/infra-delivery.sh destroy
reject 'Run only on main' env GITHUB_REF=refs/heads/feature bash scripts/infra-delivery.sh plan
reject 'Invalid account' env EXPECTED_ACCOUNT=invalid bash scripts/infra-delivery.sh plan
reject 'Configure MEDIA_BUCKET_NAME' env TF_VAR_media_bucket_name=fiap-fase-05 bash scripts/infra-delivery.sh plan
reject 'Checkout does not match' env TEST_HEAD=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb bash scripts/infra-delivery.sh plan
reject 'Invalid plan ID' env PLAN_ID=../../other bash scripts/infra-delivery.sh apply
reject 'Invalid plan SHA-256' env PLAN_SHA256=wrong bash scripts/infra-delivery.sh apply
reject 'Main changed since planning' env PLAN_COMMIT=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb bash scripts/infra-delivery.sh apply
echo 'Delivery guards: 8 passed; no AWS calls.'
