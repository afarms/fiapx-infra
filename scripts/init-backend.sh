#!/usr/bin/env bash
set -euo pipefail

# Supplied by the workflow from the validated AWS_ROLE_ARN repository secret.
if [[ ! "${EXPECTED_ACCOUNT:-}" =~ ^[0-9]{12}$ ]]; then
  echo 'EXPECTED_ACCOUNT must contain the 12-digit account ID derived from AWS_ROLE_ARN.' >&2
  exit 1
fi

exec terraform -chdir=terraform init -reconfigure -input=false \
  -backend-config="allowed_account_ids=[\"${EXPECTED_ACCOUNT}\"]"
