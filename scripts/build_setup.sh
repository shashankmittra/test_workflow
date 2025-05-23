#!/usr/bin/env bash
source "${ONE_PIPELINE_PATH}"/tools/retry

set -euo pipefail

if [[ "${PIPELINE_DEBUG:-0}" == 1 ]]; then
  set -x
  trap env EXIT
fi

# Check if the registry details are provided, If not exit the script. 
ICR_REGISTRY_NAMESPACE="$(get_env registry-namespace "")"
IBM_LOGIN_REGISTRY_REGION="$(get_env registry-region "")" 

# Check if any of the variables are empty
if [ -z "$ICR_REGISTRY_NAMESPACE" ] || [ -z "$IBM_LOGIN_REGISTRY_REGION" ]; then
    echo "Error: registry-namespace or registry-region variables are empty. Please provide all the necessary cluster and registry details."
    echo "If you are using custom deployment, please modify setup/build/deploy scripts to support your usecase"
    echo "For more details check this https://cloud.ibm.com/docs/devsecops?topic=devsecops-cd-devsecops-pipeline-parm"
    exit 0
fi

get-icr-region() {
  # convert long synax region (like ibm:yp:us-east) to short syntax region (like us-east)
  short_syntax_region="$(echo "$1" | awk -F: '{print $NF}')"
  case "$short_syntax_region" in
    us-south)
      echo us
      ;;
    us-east)
      echo us
      ;;
    eu-de)
      echo de
      ;;
    eu-gb)
      echo uk
      ;;
    eu-es)
      echo es
      ;;
    jp-tok)
      echo jp
      ;;
    jp-osa)
      echo jp2
      ;;
    au-syd)
      echo au
      ;;
    br-sao)
      echo br
      ;;
    eu-fr2)
      echo fr2
      ;;
    ca-tor)
      echo ca
      ;;
    stg)
      echo stg
      ;;
    *)
      echo "Unknown region: $1 (short syntax region: $short_syntax_region)" >&2
      exit 1
      ;;
  esac
}

# curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
# add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
# apt-get update && apt-get install docker-ce-cli

IBMCLOUD_API=$(get_env ibmcloud-api "https://cloud.ibm.com")

if [[ -s "/config/repository" ]]; then
  REPOSITORY="$(cat /config/repository)"
else
  REPOSITORY="$(load_repo app-repo url)"
fi

IMAGE_NAME="$(get_env image-name "$(basename "$REPOSITORY" .git)")"
IMAGE_TAG="$(date +%Y%m%d%H%M%S)-$(cat /config/git-branch | tr -c '[:alnum:]_.-' '_')-$(cat /config/git-commit)"
IMAGE_TAG=${IMAGE_TAG////_}

if [[ -f "/config/break_glass" ]]; then
  ARTIFACTORY_URL="$(jq -r .parameters.repository_url /config/artifactory)"
  ARTIFACTORY_REGISTRY="$(sed -E 's~https://(.*)/?~\1~' <<<"$ARTIFACTORY_URL")"
  ARTIFACTORY_INTEGRATION_ID="$(jq -r .instance_id /config/artifactory)"
  IMAGE="$ARTIFACTORY_REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
  jq -j --arg instance_id "$ARTIFACTORY_INTEGRATION_ID" '.services[] | select(.instance_id == $instance_id) | .parameters.token' /toolchain/toolchain.json | docker login -u "$(jq -r '.parameters.user_id' /config/artifactory)" --password-stdin "$(jq -r '.parameters.repository_url' /config/artifactory)"
else
  ICR_REGISTRY_NAMESPACE="$(cat /config/registry-namespace)"
  ICR_REGISTRY_DOMAIN="$(get_env registry-domain "")"
  if [ -z "$ICR_REGISTRY_DOMAIN" ]; then
    # Default to icr domain from registry-region
    ICR_REGISTRY_REGION="$(get-icr-region "$(cat /config/registry-region)")"
    ICR_REGISTRY_DOMAIN="$ICR_REGISTRY_REGION.icr.io"
  fi
  IMAGE="$ICR_REGISTRY_DOMAIN/$ICR_REGISTRY_NAMESPACE/$IMAGE_NAME:$IMAGE_TAG"
  retry 5 5 \
    docker login -u iamapikey --password-stdin "$ICR_REGISTRY_DOMAIN" < /config/api-key

  # Create the namespace if needed to ensure the push will be can be successfull
  echo "Checking registry namespace: ${ICR_REGISTRY_NAMESPACE}"
  IBM_LOGIN_REGISTRY_REGION=$(< /config/registry-region awk -F: '{print $NF}')
  ibmcloud config --check-version false
  retry 5 2 \
    ibmcloud login --apikey @/config/api-key -r "$IBM_LOGIN_REGISTRY_REGION" -a "$IBMCLOUD_API"
  NS=$( ibmcloud cr namespaces | sed 's/ *$//' | grep -x "${ICR_REGISTRY_NAMESPACE}" ||: )

  if [ -z "${NS}" ]; then
      echo "Registry namespace ${ICR_REGISTRY_NAMESPACE} not found"
      ibmcloud cr namespace-add "${ICR_REGISTRY_NAMESPACE}"
      echo "Registry namespace ${ICR_REGISTRY_NAMESPACE} created."
  else
      echo "Registry namespace ${ICR_REGISTRY_NAMESPACE} found."
  fi
fi

# shellcheck disable=SC2034 # next sourced script is using it where this script is also sourced
DOCKER_BUILD_ARGS="-t $IMAGE"
