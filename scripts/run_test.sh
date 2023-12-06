#!/usr/bin/env bash    

save_deployment_artifact(){
    . "${ONE_PIPELINE_PATH}/tools/get_repo_params"
    deployment_file=$1
    deployment_type=$2
    APP_TOKEN_PATH="./app-token"
    read -r APP_REPO_NAME APP_REPO_OWNER APP_SCM_TYPE APP_API_URL < <(get_repo_params "$(load_repo app-repo url)" "$APP_TOKEN_PATH")
    read -r APP_ABSOLUTE_SCM_TYPE < <(get_absolute_scm_type "$(load_repo app-repo url)")
    token=$(cat $APP_TOKEN_PATH)
    if [ "$APP_ABSOLUTE_SCM_TYPE" == "hostedgit" ]; then
        id=$(curl --header "PRIVATE-TOKEN: ${token}" "${APP_API_URL}/projects/$(echo ${APP_REPO_OWNER}/${APP_REPO_NAME} | jq -rR @uri)" | jq .id)
        DEPLOYMENT_ARTIFACT="${APP_API_URL}/projects/${id}/repository/files/${deployment_file}/raw?ref=${COMMIT_SHA}"
    elif [ "$APP_ABSOLUTE_SCM_TYPE" == "github_integrated" ]; then
        DEPLOYMENT_ARTIFACT="https://raw.github.ibm.com/${APP_REPO_OWNER}/${APP_REPO_NAME}/${COMMIT_SHA}/${deployment_file}"
    elif [ "$APP_ABSOLUTE_SCM_TYPE" == "githubconsolidated" ]; then
        git_type="$(jq -r --arg git_repo "$(load_repo app-repo url)" '[ .services[] | select (.dashboard_url == $git_repo) | .parameters.git_id ] | first' "$TOOLCHAIN_CONFIG_JSON")"
        if [ "$git_type" == "integrated" ]; then
            DEPLOYMENT_ARTIFACT="https://raw.github.ibm.com/${APP_REPO_OWNER}/${APP_REPO_NAME}/${COMMIT_SHA}/${deployment_file}"
        else
            DEPLOYMENT_ARTIFACT="https://raw.githubusercontent.com/${APP_REPO_OWNER}/${APP_REPO_NAME}/${COMMIT_SHA}/${deployment_file}"
        fi
    else
        warning "$APP_ABSOLUTE_SCM_TYPE is not supported"
        exit 1
    fi
    DEPLOYMENT_ARTIFACT_PATH="$(load_repo app-repo path)"
    DEPLOYMENT_ARTIFACT_DIGEST="$(sha256sum "${WORKSPACE}/${DEPLOYMENT_ARTIFACT_PATH}/${deployment_file}" | awk '{print $1}')"
    
    save_artifact "artifact-${deployment_type}" \
      "name=${APP_REPO_NAME}_${deployment_type}_deployment" \
      "type=deployment" \
      "signature=${DEPLOYMENT_ARTIFACT_DIGEST}" \
      "deployment_type=${deployment_type}"\
      "digest=sha256:${DEPLOYMENT_ARTIFACT_DIGEST}" \
      "provenance=${DEPLOYMENT_ARTIFACT}"
}

run_test() {
    test_name=$1
    test_evidence_type=$2
    test_result_file_name=$3
    publish_test_to_doi=$4
    
    source "${COMMONS_PATH}/doi/doi-publish-testrecord.sh" 
    source "${ONE_PIPELINE_PATH}/internal/doi/helper/doi_ibmcloud_login"

    collect-evidence \
      --tool-type "jest" \
      --status "pending" \
      --evidence-type $test_evidence_type \
      --asset-type "repo" \
      --asset-key "app-repo"

    while read -r artifact; do
      collect-evidence \
        --tool-type "jest" \
        --status "pending" \
        --evidence-type "$test_evidence_type" \
        --asset-type "artifact" \
        --asset-key "$artifact"
    done < <(list_artifacts)

    cd ../"$(load_repo app-repo path)"
    npm ci

    # save exit code for old evidence collection
    exit_code=0
    if [[ $test_name == "test" ]]; then
      npm test || exit_code=$?
    else
      npm run $test_name || exit_code=$?
    fi
   
    # save status for new evidence collection
    status="success"
    if [ "$exit_code" != "0" ]; then
      status="failure"
    fi

    mv jest-junit.xml $test_result_file_name

    app_url=$(load_repo app-repo url "")

    if [[ $publish_test_to_doi == 1 ]]; then
      if [[ -z "${app_url}" ]]; then
        echo "Please provide the app-url as the running application url to publish unitest results to Devops insights" >&2
      elif [[ "$(get_env pipeline_namespace)" != *"pr"* ]]; then
        refresh_ibmcloud_session 
        doi-publish-testrecord "unittest" $test_result_file_name "$app_url" # upload unittest xml file to DOI  
      fi
    fi

    collect-evidence \
      --tool-type "jest" \
      --status "$status" \
      --evidence-type $test_evidence_type \
      --asset-type "repo" \
      --asset-key "app-repo" \
      --attachment $test_result_file_name

    while read -r artifact; do
      collect-evidence \
        --tool-type "jest" \
        --status "$status" \
        --evidence-type "$test_evidence_type" \
        --asset-type "artifact" \
        --asset-key "$artifact" \
        --attachment $test_result_file_name
    done < <(list_artifacts)
}
