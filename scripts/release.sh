#!/usr/bin/env bash

#
# prepare data for the release step. Here we upload all the metadata to the Inventory Repo.
# If you want to add any information or artifact to the inventory repo then use the "cocoa inventory add command"
#

# shellcheck source=/dev/null
. "${ONE_PIPELINE_PATH}/tools/get_repo_params"
. "${ONE_PIPELINE_PATH}/internal/tools/logging"

# Check the status of pipeline and then release the artifacts to inventory

ONE_PIPELINE_STATUS=$(get_env one-pipeline-status 0)
if [ "$(get_env skip-inventory-update-on-failure 1)" == "1" ]; then
    if [ $ONE_PIPELINE_STATUS -eq 1 ]; then
          echo "Skipping release stage as some of the pipeline stages are not successfull."
          exit 1
    fi
fi

function upload_deployment_artifact (){
    while read -r artifact; do
    type="$(load_artifact "${artifact}" type)"
    if [[ ${type} != "image" ]]; then
        DEPLOYMENT_ARTIFACT_NAME="$(load_artifact "${artifact}" name)"
        DEPLOYMENT_ARTIFACT_PROVENANCE="$(load_artifact "${artifact}" provenance)"
        DEPLOYMENT_ARTIFACT_DIGEST="$(load_artifact "${artifact}" digest)"
        DEPLOYMENT_ARTIFACT_SIGN="$(load_artifact "${artifact}" signature)"
        APP_ARTIFACTS='{"origin": "'${DEPLOYMENT_ARTIFACT_PROVENANCE}'" }'
        cocoa inventory add \
            --name="$DEPLOYMENT_ARTIFACT_NAME" \
            --artifact="$DEPLOYMENT_ARTIFACT_NAME.yml" \
            --type="deployment" \
            --app-artifacts="${APP_ARTIFACTS}" \
            --provenance="${DEPLOYMENT_ARTIFACT_PROVENANCE}" \
            --sha256="${DEPLOYMENT_ARTIFACT_DIGEST}" \
            --signature="${DEPLOYMENT_ARTIFACT_SIGN}" \
            "${params[@]}"
    fi
    done < <(list_artifacts)
}

function upload_image_artifact (){
    read -r APP_REPO_NAME < <(get_repo_name "$(get_env APP_REPO)")
    while read -r artifact; do
    type="$(load_artifact "${artifact}" type)"
    if [[ ${type} == "image" ]]; then
        image="$(load_artifact "${artifact}" name)"
        signature="$(load_artifact "${artifact}" signature)"
        digest="$(load_artifact "${artifact}" digest)"
        tags="$(load_artifact "${artifact}" tags)"
        APP_NAME="$(get_env app-name)"
        APP_ARTIFACTS='{ "app": "'${APP_NAME}'", "tags": "'${tags}'" }'
        cocoa inventory add \
            --artifact="${image}@${digest}" \
            --name="${APP_REPO_NAME}" \
            --app-artifacts="${APP_ARTIFACTS}" \
            --signature="${signature}" \
            --provenance="${image}@${digest}" \
            --sha256="${digest}" \
            --type="image" \
            "${params[@]}"
    fi
    done < <(list_artifacts)
}

INVENTORY_TOKEN_PATH="./inventory-token"
read -r INVENTORY_REPO_NAME INVENTORY_REPO_OWNER INVENTORY_SCM_TYPE INVENTORY_API_URL < <(get_repo_params "$(get_env INVENTORY_URL)" "$INVENTORY_TOKEN_PATH")

#
# collect common parameters into an array
#
params=(
    --repository-url="${APP_REPO}"
    --commit-sha="${COMMIT_SHA}"
    --version="${COMMIT_SHA}"
    --build-number="${BUILD_NUMBER}"
    --pipeline-run-id="${PIPELINE_RUN_ID}"
    --org="$INVENTORY_REPO_OWNER"
    --repo="$INVENTORY_REPO_NAME"
    --git-provider="$INVENTORY_SCM_TYPE"
    --git-token-path="$INVENTORY_TOKEN_PATH"
    --git-api-url="$INVENTORY_API_URL"
)


#
# add all deployment files as build artifacts to the inventory
#
upload_deployment_artifact

#
# add all built images as build artifacts to the inventory
#
upload_image_artifact
