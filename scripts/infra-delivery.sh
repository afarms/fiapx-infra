#!/usr/bin/env bash
set -euo pipefail
umask 077

fail() { echo "::error::$1" >&2; exit 1; }
mode="${1:-}"
[[ "$mode" == plan || "$mode" == apply ]] || fail 'Expected plan or apply.'
[[ "${GITHUB_REF:-}" == refs/heads/main ]] || fail 'Run only on main.'
[[ "${GITHUB_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || fail 'Invalid commit.'
[[ "${EXPECTED_ACCOUNT:-}" =~ ^[0-9]{12}$ ]] || fail 'Invalid account configuration.'
[[ "${TF_VAR_media_bucket_name:-}" =~ ^fiapx-media-[a-z0-9][a-z0-9-]{0,48}[a-z0-9]$ ]] || fail 'Configure MEDIA_BUCKET_NAME.'
[[ "$(git rev-parse HEAD)" == "$GITHUB_SHA" ]] || fail 'Checkout does not match the selected commit.'
[[ "${GITHUB_RUN_ID:-}" =~ ^[0-9]+$ && "${GITHUB_RUN_ATTEMPT:-}" =~ ^[0-9]+$ ]] || fail 'Invalid run identifier.'
if [[ "$mode" == apply ]]; then
  [[ "${PLAN_ID:-}" =~ ^[0-9]+-[0-9]+$ ]] || fail 'Invalid plan ID.'
  [[ "${PLAN_SHA256:-}" =~ ^[0-9a-f]{64}$ ]] || fail 'Invalid plan SHA-256.'
  [[ "${PLAN_COMMIT:-}" == "$GITHUB_SHA" ]] || fail 'Main changed since planning. Generate and review a new plan.'
fi

bucket=fiap-fase-05
mkdir -p .local
work="$(mktemp -d "$PWD/.local/delivery.XXXXXXXX")"
trap 'rm -f "$work"/*; rmdir "$work"' EXIT

# Read-only prerequisite checks. No changes to the pre-existing state bucket.
aws s3api get-bucket-versioning --bucket "$bucket" --expected-bucket-owner "$EXPECTED_ACCOUNT" > "$work/versioning.json"
jq -e '.Status == "Enabled"' "$work/versioning.json" > /dev/null || fail 'Enable versioning on the state bucket before proceeding.'
aws s3api get-public-access-block --bucket "$bucket" --expected-bucket-owner "$EXPECTED_ACCOUNT" > "$work/access.json"
jq -e '.PublicAccessBlockConfiguration | .BlockPublicAcls and .IgnorePublicAcls and .BlockPublicPolicy and .RestrictPublicBuckets' "$work/access.json" > /dev/null || fail 'Enable all public-access blocks on the state bucket.'
aws s3api get-bucket-encryption --bucket "$bucket" --expected-bucket-owner "$EXPECTED_ACCOUNT" > "$work/encryption.json"
jq -e '.ServerSideEncryptionConfiguration.Rules | any(.ApplyServerSideEncryptionByDefault.SSEAlgorithm == "AES256")' "$work/encryption.json" > /dev/null || fail 'This pipeline expects SSE-S3 on the state bucket; KMS requires a separate permissions review.'

diagnostics="fiapx-infra/plans/diagnostics-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
printf '\nPrivate diagnostics, if needed: `s3://%s/%s/`\n' "$bucket" "$diagnostics" >> "$GITHUB_STEP_SUMMARY"
if ! bash scripts/init-backend.sh > "$work/init.log" 2>&1; then
  aws s3api put-object --bucket "$bucket" --key "$diagnostics/init.txt" --body "$work/init.log" --server-side-encryption AES256 --expected-bucket-owner "$EXPECTED_ACCOUNT" > /dev/null
  fail 'Backend initialization failed; review the private diagnostics.'
fi

if [[ "$mode" == plan ]]; then
  [[ "${GITHUB_RUN_ID:-}" =~ ^[0-9]+$ && "${GITHUB_RUN_ATTEMPT:-}" =~ ^[0-9]+$ ]] || fail 'Invalid run identifier.'
  plan_id="${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
  prefix="fiapx-infra/plans/$plan_id"
  # Terraform's detailed exit code 2 means a valid plan with changes.
  result=0
  terraform -chdir=terraform plan -input=false -lock=true -lock-timeout=60s -detailed-exitcode -no-color -out="$work/plan.tfplan" > "$work/plan.txt" 2>&1 || result=$?
  if [[ "$result" != 0 && "$result" != 2 ]]; then
    aws s3api put-object --bucket "$bucket" --key "$diagnostics/plan.txt" --body "$work/plan.txt" --server-side-encryption AES256 --expected-bucket-owner "$EXPECTED_ACCOUNT" > /dev/null
    fail 'Terraform plan failed; review the private diagnostics. No applicable plan was published.'
  fi
  digest="$(sha256sum "$work/plan.tfplan" | cut -d ' ' -f 1)"
  terraform -chdir=terraform show -json "$work/plan.tfplan" > "$work/plan.json"
  # Deletion/replacement is outside this delivery workflow.
  jq -e '[.resource_changes[]? | select(.change.actions | index("delete"))] | length == 0' "$work/plan.json" > /dev/null || fail 'Destructive changes require a separate reviewed procedure.'
  jq -n --arg commit "$GITHUB_SHA" --arg digest "$digest" --arg bucket "$TF_VAR_media_bucket_name" --arg id "$plan_id" --argjson created "$(date +%s)" '{commit:$commit,sha256:$digest,media_bucket:$bucket,id:$id,created:$created}' > "$work/manifest.json"
  for file in plan.tfplan plan.txt manifest.json; do
    aws s3api put-object --bucket "$bucket" --key "$prefix/$file" --body "$work/$file" --server-side-encryption AES256 --expected-bucket-owner "$EXPECTED_ACCOUNT" > /dev/null
  done
  {
    echo '### Terraform plan ready for private review'
    printf '\nPlan ID: `%s`\nCommit: `%s`\nSHA-256: `%s`\n' "$plan_id" "$GITHUB_SHA" "$digest"
    printf '\nReview `s3://%s/%s/plan.txt` before running apply.\n' "$bucket" "$prefix"
    echo 'The binary and full plan are private in S3; no GitHub artifacts were published.'
    echo 'This plan expires after 24 hours. Apply must use the same main commit.'
  } >> "$GITHUB_STEP_SUMMARY"
else
  [[ "${PLAN_ID:-}" =~ ^[0-9]+-[0-9]+$ ]] || fail 'Invalid plan ID.'
  [[ "${PLAN_SHA256:-}" =~ ^[0-9a-f]{64}$ ]] || fail 'Invalid plan SHA-256.'
  [[ "${PLAN_COMMIT:-}" == "$GITHUB_SHA" ]] || fail 'Main changed since planning. Generate and review a new plan.'
  prefix="fiapx-infra/plans/$PLAN_ID"
  for file in manifest.json plan.tfplan; do
    aws s3api get-object --bucket "$bucket" --key "$prefix/$file" --expected-bucket-owner "$EXPECTED_ACCOUNT" "$work/$file" > /dev/null
  done
  jq -e --arg commit "$GITHUB_SHA" --arg digest "$PLAN_SHA256" --arg bucket "$TF_VAR_media_bucket_name" --arg id "$PLAN_ID" --argjson now "$(date +%s)" '.commit == $commit and .sha256 == $digest and .media_bucket == $bucket and .id == $id and (.created | type) == "number" and .created <= $now and ($now - .created) <= 86400' "$work/manifest.json" > /dev/null || fail 'Plan metadata does not match or has expired.'
  [[ "$(sha256sum "$work/plan.tfplan" | cut -d ' ' -f 1)" == "$PLAN_SHA256" ]] || fail 'Plan checksum mismatch.'
  result=0
  terraform -chdir=terraform apply -input=false -lock=true -lock-timeout=60s -no-color "$work/plan.tfplan" > "$work/apply.txt" 2>&1 || result=$?
  # Keep diagnostic output private, including failures/partial applies.
  aws s3api put-object --bucket "$bucket" --key "$prefix/apply-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}.txt" --body "$work/apply.txt" --server-side-encryption AES256 --expected-bucket-owner "$EXPECTED_ACCOUNT" > /dev/null
  [[ "$result" == 0 ]] || fail 'Apply failed or was partial. Review the private apply log and generate a new plan; do not force-unlock or blindly retry.'
  result=0
  terraform -chdir=terraform plan -input=false -lock=true -lock-timeout=60s -detailed-exitcode -no-color > "$work/verify.txt" 2>&1 || result=$?
  aws s3api put-object --bucket "$bucket" --key "$prefix/verify-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}.txt" --body "$work/verify.txt" --server-side-encryption AES256 --expected-bucket-owner "$EXPECTED_ACCOUNT" > /dev/null
  [[ "$result" == 0 ]] || fail 'Post-apply verification failed or found changes. Review the private verification log.'
  echo '### Terraform apply completed; post-apply plan has no changes' >> "$GITHUB_STEP_SUMMARY"
fi
