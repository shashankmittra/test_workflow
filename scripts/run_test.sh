#!/usr/bin/env bash    

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

    app_url=$(get_env APP_REPO "")

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
    exit $exit_code
}

