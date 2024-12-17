#!/usr/bin/env bash
if [[ "$PIPELINE_DEBUG" == 1 ]]; then
  trap env EXIT
  env
  set -x
fi

save_deployment_artifact(){
    . "${ONE_PIPELINE_PATH}/tools/get_repo_params"
    deployment_file=$1
    deployment_type=$2
    deployment_file_type="${3:-"deployment"}"
    APP_TOKEN_PATH="./app-token"
    read -r APP_REPO_NAME APP_REPO_OWNER APP_SCM_TYPE APP_API_URL < <(get_repo_params "$(load_repo app-repo url)" "$APP_TOKEN_PATH")
    read -r APP_ABSOLUTE_SCM_TYPE < <(get_absolute_scm_type "$(load_repo app-repo url)")
    token=$(cat $APP_TOKEN_PATH)
    if [[ "$APP_ABSOLUTE_SCM_TYPE" == "hostedgit" || "$APP_ABSOLUTE_SCM_TYPE" == "gitlab" ]]; then
        id=$(curl --header "PRIVATE-TOKEN: ${token}" "${APP_API_URL}/projects/$(echo ${APP_REPO_OWNER}/${APP_REPO_NAME} | jq -rR @uri)" | jq .id)
        DEPLOYMENT_ARTIFACT="${APP_API_URL}/projects/${id}/repository/files/${deployment_file}/raw?ref=${COMMIT_SHA}"
        DEPLOYMENT_ARTIFACT_ORIGIN=$DEPLOYMENT_ARTIFACT
    elif [ "$APP_ABSOLUTE_SCM_TYPE" == "github_integrated" ]; then
        DEPLOYMENT_ARTIFACT="https://raw.github.ibm.com/${APP_REPO_OWNER}/${APP_REPO_NAME}/${COMMIT_SHA}/${deployment_file}"
        DEPLOYMENT_ARTIFACT_ORIGIN="https://github.ibm.com/${APP_REPO_OWNER}/${APP_REPO_NAME}/blob/${COMMIT_SHA}/${deployment_file}"
    elif [ "$APP_ABSOLUTE_SCM_TYPE" == "githubconsolidated" ]; then
        git_type="$(jq -r --arg git_repo "$(load_repo app-repo url)" '[ .services[] | select (.dashboard_url == $git_repo) | .parameters.git_id ] | first' "$TOOLCHAIN_CONFIG_JSON")"
        if [ "$git_type" == "integrated" ]; then
            DEPLOYMENT_ARTIFACT="https://raw.github.ibm.com/${APP_REPO_OWNER}/${APP_REPO_NAME}/${COMMIT_SHA}/${deployment_file}"
            DEPLOYMENT_ARTIFACT_ORIGIN="https://github.ibm.com/${APP_REPO_OWNER}/${APP_REPO_NAME}/blob/${COMMIT_SHA}/${deployment_file}"
        else
            DEPLOYMENT_ARTIFACT="https://raw.githubusercontent.com/${APP_REPO_OWNER}/${APP_REPO_NAME}/${COMMIT_SHA}/${deployment_file}"
            DEPLOYMENT_ARTIFACT_ORIGIN=$DEPLOYMENT_ARTIFACT
        fi
    else
        warning "$APP_ABSOLUTE_SCM_TYPE is not supported"
        exit 1
    fi
    DEPLOYMENT_ARTIFACT_PATH="$(load_repo app-repo path)"
    DEPLOYMENT_ARTIFACT_DIGEST="$(sha256sum "${WORKSPACE}/${DEPLOYMENT_ARTIFACT_PATH}/${deployment_file}" | awk '{print $1}')"
    
    save_artifact "artifact_${deployment_file_type}_${deployment_type}" \
      "name=${APP_REPO_NAME}_${deployment_type}_${deployment_file_type}" \
      "type=${deployment_file_type}" \
      "signature=${DEPLOYMENT_ARTIFACT_DIGEST}" \
      "deployment_type=${deployment_type}"\
      "artifact_origin=${DEPLOYMENT_ARTIFACT_ORIGIN}" \
      "digest=sha256:${DEPLOYMENT_ARTIFACT_DIGEST}" \
      "provenance=${DEPLOYMENT_ARTIFACT}"
}

publish_to_doi_unit_test(){
    local test_result_file_name="$1"
    local reusedEvidenceJson="${2:-""}"

    local app_url
    local label
    app_url=$(load_repo app-repo url "")
    
    source "${COMMONS_PATH}/doi/doi-publish-testrecord.sh" 
    source "${ONE_PIPELINE_PATH}/internal/doi/helper/doi_ibmcloud_login"
    if [[ -z "${app_url}" ]]; then
        echo "Please provide the app-url as the running application url to publish unitest results to Devops insights" >&2
    elif [[ "$(get_env pipeline_namespace)" != *"pr"* ]]; then
        refresh_ibmcloud_session
        if [[ -z "$reusedEvidenceJson" ]]; then
            doi-publish-testrecord "unittest" $test_result_file_name "$app_url" # upload unittest xml file to DOI 
        else
            label=$(basename "$test_result_file_name")
            doi_exit_code=0
            doi-publish --evidence-file "${reusedEvidenceJson}" --record-type "unittest" --attachment-label "${label}" --url "$app_url" --attachment-output-path "${test_result_file_name}" || doi_exit_code=$?
        fi
    fi
}

run_unit_test() {
    local test_name="test"
    local test_evidence_type="com.ibm.unit_tests"
    local test_result_file_name="unit-test-result.xml"
    local params
    local reusedEvidenceJson
    local status

    params=(
      --tool-type "jest" \
      --evidence-type $test_evidence_type \
      --asset-type "repo" \
      --asset-key "app-repo"
    )
      
    reusedEvidenceJson="$(mktemp)"
    status_file="$(mktemp)"
    if (check-evidence-for-reuse "${params[@]}" --output-path "${reusedEvidenceJson}" >"${status_file}"); then
        status=$(cat "${status_file}")
        publish_to_doi_unit_test "${test_result_file_name}" "${reusedEvidenceJson}"
    else
        collect-evidence \
          "${params[@]}" \
          --status "pending"

        cd ../"$(load_repo app-repo path)"

        # save exit code for old evidence collection
        exit_code=0
        npm "$test_name" || exit_code=$?
   
        # save status for new evidence collection
        status="success"
        if [ "$exit_code" != "0" ]; then
          status="failure"
        fi

        mv jest-junit.xml $test_result_file_name

        publish_to_doi_unit_test "${test_result_file_name}"

        collect-evidence \
          "${params[@]}" \
          --status "$status" \
          --attachment $test_result_file_name
    fi
}

run_acceptance_test() {
    local test_name="acceptance-test"
    local test_evidence_type="com.ibm.acceptance_tests"
    local test_result_file_name="acceptance-test-result.xml"
    local tool_type="jest"
    local params
    local status

    params=(
      --tool-type "$tool_type" \
      --status "pending" \
      --evidence-type $test_evidence_type \
    )
    while read -r artifact; do
        params+=(--assets "$artifact":"artifact")
    done < <(list_artifacts)
    collect-evidence "${params[@]}"

    cd ../"$(load_repo app-repo path)"
    npm ci

    # save exit code for old evidence collection
    exit_code=0
    npm run $test_name || exit_code=$?

    # save status for new evidence collection
    status="success"
    if [ "$exit_code" != "0" ]; then
      status="failure"
    fi

    mv jest-junit.xml $test_result_file_name

    params=(
      --tool-type "$tool_type" \
      --status "$status" \
      --evidence-type $test_evidence_type \
      --attachment $test_result_file_name \
    )
    while read -r artifact; do
        params+=(--assets "$artifact":"artifact")
    done < <(list_artifacts)
    collect-evidence "${params[@]}"
}
