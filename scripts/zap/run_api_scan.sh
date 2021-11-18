#!/usr/bin/env bash

source "${ONE_PIPELINE_PATH}"/tools/retry

workingdir="$(pwd)"

cd "$WORKSPACE" || exit 1

repo="app-repo"
APP_REPO="$(load_repo "${repo}" "url")"

export DATA
export REPORT

# 
# this was set and exported in scripts/zap/trigger_api_scan.sh
#
TARGET_APPLICATION_SERVER_URL="$(get_env target-application-server-url "")"

#
# alternative modes to find a deployed app
#
TARGET_APPLICATION_NAMESPACE="$(get_env target-application-namespace "")"
TARGET_APPLICATION_SERVICE_NAME="$(get_env target-application-service-name "")"

IBMCLOUD_API="$(get_env ibmcloud-api "https://cloud.ibm.com")"
IAM_ENDPOINT="$(get_env iam-token-endpoint "https://iam.cloud.ibm.com/identity/token")"

CLUSTER_NAMESPACE="$(get_env zap-namespace "zap")"
SERVICE_NAME="$(get_env zap-service "zap-service")"

IBMCLOUD_API_KEY="$(get_env ibmcloud-api-key "")"
IBMCLOUD_IKS_CLUSTER_NAME="$(get_env cluster-name "")"
PIPELINE_DEBUG="$(get_env pipeline-debug "")"

TARGET_API_KEY="$(get_env target-api-key "")"
CUSTOM_SCRIPT_PATH="$(get_env zap-custom-script "")"

FILE_PATH_ROOT=$(basename "${APP_REPO}")
FILE_PATH_ROOT=$(echo "${FILE_PATH_ROOT}" | awk -F.git '{print $1}')
PIPELINE_DEBUG="$(get_env pipeline-debug "")"

retry 5 2 \
    ibmcloud login -a "${IBMCLOUD_API}" -apikey "${IBMCLOUD_API_KEY}" --no-region

retry 5 2 \
    ibmcloud ks cluster config --cluster "$IBMCLOUD_IKS_CLUSTER_NAME"

ibmcloud ks cluster get --cluster "${IBMCLOUD_IKS_CLUSTER_NAME}" --json > "${IBMCLOUD_IKS_CLUSTER_NAME}.json"

if which oc > /dev/null && jq -e '.type=="openshift"' "${IBMCLOUD_IKS_CLUSTER_NAME}.json" > /dev/null; then
  echo "${IBMCLOUD_IKS_CLUSTER_NAME} is an openshift cluster. Doing the appropriate oc login to target it" >&2
  oc login -u apikey -p "${IBMCLOUD_API_KEY}"
fi

IP_ADDRESS=$(kubectl get nodes -o json | jq -r '[.items[] | .status.addresses[] | select(.type == "ExternalIP") | .address] | .[0]')
PORT=$(kubectl get service -n  "$CLUSTER_NAMESPACE" "${SERVICE_NAME}" -o json | jq -r '.spec.ports[0].nodePort')
ZAP_BASE_URL="${IP_ADDRESS}:${PORT}"
echo "ZAP_URL ${ZAP_BASE_URL}" >&2

#use a known application URL or infer based on known cluster details, application namespace and service name
getTargetApplicationURL() {
  if [ "${TARGET_APPLICATION_SERVER_URL}" ]; then
    echo "Targeting ${TARGET_APPLICATION_SERVER_URL}" >&2
  else
    echo "Finding target" >&2
    if [[ "$TARGET_APPLICATION_NAMESPACE" && "$TARGET_APPLICATION_SERVICE_NAME" ]]; then
      PORT=$(kubectl get service -n  "$TARGET_APPLICATION_NAMESPACE" "${TARGET_APPLICATION_SERVICE_NAME}" -o json | jq -r '.spec.ports[0].nodePort')
      TARGET_APPLICATION_SERVER_URL="${IP_ADDRESS}:${PORT}"
    else
      echo "No application namespace or service name provided" >&2
      exit 0
    fi
    echo "Targeting ${TARGET_APPLICATION_SERVER_URL}" >&2
    TARGET_APPLICATION_SERVER_URL="http://${TARGET_APPLICATION_SERVER_URL}"
  fi
}

startScan() {
  echo "Start ZAP scan" >&2

  echo "Using data: \n${DATA}" >&2

  curl --request POST \
    --url http://"${ZAP_BASE_URL}"/scan \
    --header "Content-Type: application/json" \
    --data "${DATA}"
}

#check the status of the zap scan and poll until results are available
report() {
    echo "CHECK REPORTS"
    MESSAGE="IN_PROGRESS"
    STATUS=""
    while [[ "${MESSAGE}" == "IN_PROGRESS" ]]
    do
        sleep 60s
        echo "Checking status" >&2
        STATUS=$(curl -X GET http://"${ZAP_BASE_URL}"/status)
        MESSAGE=$(echo "${STATUS}" | jq -r .scan_status)
        echo "${STATUS}" >&2
    done

    echo "SCAN COMPLETE. STATUS MESSAGE: $MESSAGE"
    REPORT=$(curl -X GET http://"${ZAP_BASE_URL}"/report)
    if [[ "${MESSAGE}" == "COMPLETED" ]]; then
        echo "DISPLAYING SCAN RESULT" >&2
    else
        echo "Please see zap scanner logs for more details" >&2
    fi

    result="${WORKSPACE}/zap-result"
    echo "${REPORT}" > "$result"

    cd "$workingdir" || exit 1
    collect_evidence
}

#update the swagger definition wrapper with details for authenication details if required
#and process custom modification of data by user provided script
prepareData() {
  if [[ "${CUSTOM_SCRIPT_PATH}" ]]; then
    . "${FILE_PATH_ROOT}/$CUSTOM_SCRIPT_PATH"
  fi

  if [ "${PIPELINE_DEBUG}" = "1" ]; then
    pwd
    env
    trap env EXIT
    set -x
    echo "DATA ${DATA}"
  fi

  DATA=$(jq --arg server "${TARGET_APPLICATION_SERVER_URL}" '.server = $server' <<< "${DATA}")
  if [[ "$TARGET_API_KEY" && "$IAM_ENDPOINT" ]]; then
      DATA=$(jq --arg key "${TARGET_API_KEY}" '.apikey = $key' <<< "${DATA}")
      DATA=$(jq --arg iamendpoint "${IAM_ENDPOINT}" '.iamTokenUrl = $iamendpoint' <<< "${DATA}")
  fi
}

runScan() {
  echo "\nInitiating scan\n" >&2
  echo "***********************" >&2

  DATA="$(get_env swagger-definition "")"

  if [[ -z "${DATA}" ]]; then
    #expecting comma separated definitions
    #FILE_PATH_ROOT="/workspace/app/$(load_repo app-repo path)"
    #SUB_PATH is path within the repository containing the json definitions
    SUB_PATH="$(get_env swagger-definition-files "definitions/definitions1.json")"
    IFS=',' read -ra tokens <<< "${SUB_PATH}"
    for i in "${!tokens[@]}"
    do
      #trim whitespace
      DEFINITION_FILE=$(echo "${tokens[i]}" | xargs echo -n)
      FULL_DEFINITION_PATH="${FILE_PATH_ROOT}/$DEFINITION_FILE"
      DATA=$(cat "${FULL_DEFINITION_PATH}")
      prepareData
      startScan
      report
      sleep 60
    done
  else
    prepareData
    startScan
    report
  fi
}

collect_evidence() {
  #
  # register the result to the image type artifact we have
  # named "app-image", see scripts/build.sh
  #
  artifact="app-image"
  save_result "${artifact}-dynamic_scan-attachments" "${WORKSPACE}/zap-result"
  save_artifact "${artifact}" dynamic_scan-result=1

  collect-evidence \
    --tool-type "owasp-zap" \
    --status "failure" \
    --evidence-type "com.ibm.dynamic_scan" \
    --asset-type "artifact" \
    --asset-key "$artifact" \
    --attachment "${WORKSPACE}/zap-result"
}

getTargetApplicationURL
runScan
