#!/usr/bin/env bash

# shellcheck source=/dev/null
source "${ONE_PIPELINE_PATH}"/tools/get_repo_params

APP_TOKEN_PATH="./app-token"
read -r APP_REPO_NAME APP_REPO_OWNER APP_SCM_TYPE APP_API_URL < <(get_repo_params "$(load_repo app-repo url)" "$APP_TOKEN_PATH")

if [[ $APP_SCM_TYPE == "gitlab" ]]; then
  # shellcheck disable=SC2086
  curl --location --request PUT "${APP_API_URL}/projects/$(echo ${APP_REPO_OWNER}/${APP_REPO_NAME} | jq -rR @uri)" \
    --header "PRIVATE-TOKEN: $(cat $APP_TOKEN_PATH)" \
    --header 'Content-Type: application/json' \
    --data-raw '{
    "only_allow_merge_if_pipeline_succeeds": true
    }'
else
  # If PR, then target branch of the PR is the branch to protect
  branch=$(get_env base-branch "")
  if [ -z "$branch" ]; then
    branch="$(cat /config/git-branch)"
  fi
  status_check_context_prefix="$(get_env branch-protection-status-check-prefix "tekton")"
  # Update the branch protection content - by adding contexts if needed
  checks='["code-branch-protection", "code-unit-tests", "code-cis-check", "code-vulnerability-scan", "code-detect-secrets"]'
  branch_protection_content=$(mktemp)
  curl -L -H "Authorization: Bearer $(cat ${APP_TOKEN_PATH})" -H "Accept: application/vnd.github+json" "${APP_API_URL}/repos/${APP_REPO_OWNER}/${APP_REPO_NAME}/branches/$branch/protection" > "$branch_protection_content"

  if jq -e '.required_status_checks' "$branch_protection_content" > /dev/null 2>&1; then
    # branch protection exists - update it by adding contexts
    # align content with expected input schema
    jq --arg context_prefix "$status_check_context_prefix" --argjson checks "$checks" 'del(.url) | del(.required_status_checks.url) | del(.required_status_checks.checks) | del(.required_status_checks.contexts_url) | del(.required_pull_request_reviews.url) | del(.required_signatures.url) | del(.enforce_admins.url)' "${branch_protection_content}" > "${branch_protection_content}_tmp" && mv -f "${branch_protection_content}_tmp" "${branch_protection_content}"
    jq --arg context_prefix "$status_check_context_prefix" --argjson checks "$checks" 'if has("restrictions") then . else .restrictions=null end' "${branch_protection_content}" > "${branch_protection_content}_tmp" && mv -f "${branch_protection_content}_tmp" "${branch_protection_content}"
    jq --arg context_prefix "$status_check_context_prefix" --argjson checks "$checks" '.required_signatures=.required_signatures.enabled | .enforce_admins=.enforce_admins.enabled | .required_linear_history=.required_linear_history.enabled | .allow_force_pushes=.allow_force_pushes.enabled' "${branch_protection_content}" > "${branch_protection_content}_tmp" && mv -f "${branch_protection_content}_tmp" "${branch_protection_content}"
    jq --arg context_prefix "$status_check_context_prefix" --argjson checks "$checks" '.allow_deletions=.allow_deletions.enabled | .block_creations=.block_creations.enabled | .required_conversation_resolution=.required_conversation_resolution.enabled | .lock_branch=.lock_branch.enabled | .allow_fork_syncing=.allow_fork_syncing.enabled' "${branch_protection_content}" > "${branch_protection_content}_tmp" && mv -f "${branch_protection_content}_tmp" "${branch_protection_content}"
    jq --arg context_prefix "$status_check_context_prefix" --argjson checks "$checks" 'reduce $checks[] as $check (.;.required_status_checks.contexts += [ $context_prefix + "/" + $check]) | . as $result | .required_status_checks.contexts | unique | . as $contexts | $result | .required_status_checks.contexts=$contexts' "${branch_protection_content}" > "${branch_protection_content}_tmp" && mv -f "${branch_protection_content}_tmp" "${branch_protection_content}"
  else
    # branch protection not set - initialize one
    jq -n --arg context_prefix "$status_check_context_prefix" --argjson checks "$checks" '.required_pull_request_reviews.dismiss_stale_reviews=true | .enforce_admins=null | .restrictions=null | .required_status_checks={"strict":true, "contexts":[]} | reduce $checks[] as $check (.;.required_status_checks.contexts += [ $context_prefix + "/" + $check]) | . as $result | .required_status_checks.contexts | unique | . as $contexts | $result | .required_status_checks.contexts=$contexts' > "$branch_protection_content"
  fi

  # update the branch protection
  curl -L \
    -X PUT \
    -H "Authorization: Bearer $(cat ${APP_TOKEN_PATH})" \
    -H "Accept: application/vnd.github+json" \
    "${APP_API_URL}/repos/${APP_REPO_OWNER}/${APP_REPO_NAME}/branches/$branch/protection" \
    --data "@${branch_protection_content}"
fi
