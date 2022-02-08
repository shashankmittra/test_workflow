#!/usr/bin/env bash

#
# prepare data for the release step. Here we upload all the metadata to the Inventory Repo.
# If you want to add any information or artifact to the inventory repo then use the "cocoa inventory add command"
#


INVENTORY="$(get_env inventory-repo)"
INVENTORY_ORG=${INVENTORY%/*}
INVENTORY_ORG=${INVENTORY_ORG##*/}
INVENTORY_REPO=${INVENTORY##*/}
INVENTORY_REPO=${INVENTORY_REPO%.git}

APP_REPO="$(load_repo app-repo url)"
APP_REPO_ORG=${APP_REPO%/*}
APP_REPO_ORG=${APP_REPO_ORG##*/}
APP_REPO_NAME=${APP_REPO##*/}
APP_REPO_NAME=${APP_REPO_NAME%.git}

COMMIT_SHA="$(load_repo app-repo commit)"

# shellcheck disable=SC1091 # sourced path is in a different repo
. "${ONE_PIPELINE_PATH}/git/get_credentials" "./git-token"

#
# collect common parameters into an array
#
params=(
    --repository-url="${APP_REPO}" \
    --commit-sha="${COMMIT_SHA}" \
    --version="${COMMIT_SHA}" \
    --build-number="${BUILD_NUMBER}" \
    --pipeline-run-id="${PIPELINE_RUN_ID}" \
    --git-token-path="./git-token" \
    --org="$INVENTORY_ORG" \
    --repo="$INVENTORY_REPO"
)

#
# add the deployment file as a build artifact to the inventory
#
function upload_deployment_files_artifacts() {
    deployment_file=$1
    deployment_type=$2

DEPLOYMENT_ARTIFACT="https://raw.github.ibm.com/${APP_REPO_ORG}/${APP_REPO_NAME}/${COMMIT_SHA}/${deployment_file}"
DEPLOYMENT_ARTIFACT_PATH="$(load_repo app-repo path)"
DEPLOYMENT_ARTIFACT_DIGEST="$(shasum -a256 "${WORKSPACE}/${DEPLOYMENT_ARTIFACT_PATH}/${deployment_file}" | awk '{print $1}')"

cocoa inventory add \
    --artifact="${DEPLOYMENT_ARTIFACT}" \
    --type="deployment" \
    --sha256="${DEPLOYMENT_ARTIFACT_DIGEST}" \
    --signature="${DEPLOYMENT_ARTIFACT_DIGEST}" \
    --name="${APP_REPO_NAME}_${deployment_type}_deployment" \
    "${params[@]}"
}

DEPLOYMENT_FILE="$(get_env deployment-file)"
CLUSTER_TYPE="$(get_env cluster-type)"
if [ "${CLUSTER_TYPE}" == "OPENSHIFT" ]; then
   upload_deployment_files_artifacts ${DEPLOYMENT_FILE} OPENSHIFT
  else
   upload_deployment_files_artifacts deployment_iks.yml IKS
fi



#
# add all built images as build artifacts to the inventory
#
while read -r artifact ; do
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
done < <(list_artifacts)
