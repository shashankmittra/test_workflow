#!/usr/bin/env bash

#
# clone repos to workspace based on what we have in pipelinectl
# use put_data to dedupe repos, so we won't clone them twice if not necessary
#

workingdir="$(pwd)"

cd "$WORKSPACE" || exit 1

# Image containing the ZAP scanner, 
# this have to be deployed to global ICR
# right now you have to copy this to your namespace
IMAGE="$(get_env zap-image "us.icr.io/cocoa-zapscanner/zapscanner@sha256:c7f6af3c16e2d897b8d57572049f07648f91a6397b1f9d2a3219788abfbc52d8")"

IBMCLOUD_API="$(get_env ibmcloud-api "https://cloud.ibm.com")"
CLUSTER_NAMESPACE="$(get_env zap-namespace "zap")"
PIPELINE_TOOLCHAIN_ID=$PIPELINE_ID
IBMCLOUD_API_KEY="$(get_env ibmcloud-api-key "")"
IBMCLOUD_IKS_CLUSTER_NAME="$(get_env cluster-name "")"
SERVICE_NAME="$(get_env zap-service "zap-service")"
PIPELINE_DEBUG="$(get_env pipeline-debug "")"

if [ "${PIPELINE_DEBUG}" = "1" ]; then
  pwd
  env
  trap env EXIT
  set -x
  echo "KUBERNETES_SERVICE_ACCOUNT_NAME=${KUBERNETES_SERVICE_ACCOUNT_NAME}"
  echo "API ENDPOINT ${IBMCLOUD_API}"
  echo "IMAGE ${IMAGE}"
  echo "PIPELINE_TOOLCHAIN_ID $PIPELINE_TOOLCHAIN_ID "
  echo "CLUSTER_NAMESPACE=${CLUSTER_NAMESPACE}"
  echo "IBMCLOUD_IKS_CLUSTER_NAME $IBMCLOUD_IKS_CLUSTER_NAME"
fi

ibmcloud login -a "${IBMCLOUD_API}" --apikey "${IBMCLOUD_API_KEY}" --no-region
ibmcloud ks cluster config --cluster "$IBMCLOUD_IKS_CLUSTER_NAME"

ibmcloud ks cluster get --cluster "${IBMCLOUD_IKS_CLUSTER_NAME}" --json > "${IBMCLOUD_IKS_CLUSTER_NAME}.json"
# If the target cluster is openshift then make the appropriate additional login with oc tool
if which oc > /dev/null && jq -e '.type=="openshift"' "${IBMCLOUD_IKS_CLUSTER_NAME}.json" > /dev/null; then
  echo "${IBMCLOUD_IKS_CLUSTER_NAME} is an openshift cluster. Doing the appropriate oc login to target it"
  oc login -u apikey -p "${IBMCLOUD_API_KEY}"
fi
# Use kubectl auth to check if the kubectl client configuration is appropriate
# check if the current configuration can create a deployment in the target namespace
echo "Check ability to create a kubernetes deployment in ${CLUSTER_NAMESPACE} using kubectl CLI"
kubectl auth can-i create deployment --namespace "${CLUSTER_NAMESPACE}"

#Check cluster availability
echo "=========================================================="
echo "CHECKING CLUSTER readiness and namespace existence"
echo "Configuring cluster namespace"
if kubectl get namespace "${CLUSTER_NAMESPACE}"; then
  echo -e "Namespace ${CLUSTER_NAMESPACE} found."
else
  kubectl create namespace "${CLUSTER_NAMESPACE}"
  echo -e "Namespace ${CLUSTER_NAMESPACE} created."
fi

if [ -z "${REGISTRY_URL}" ]; then
    PATTERN="icr.io"
    REGISTRY_URL=$(echo "${IMAGE}" | awk -F"${PATTERN}" '{print $1}')
    REGISTRY_URL="${REGISTRY_URL}${PATTERN}"
fi
echo "REGISTRY_URL $REGISTRY_URL"
# Grant access to private image registry from namespace $CLUSTER_NAMESPACE
# reference https://cloud.ibm.com/docs/containers?topic=containers-images#other_registry_accounts
echo "=========================================================="
echo -e "CONFIGURING ACCESS to private image registry from namespace ${CLUSTER_NAMESPACE}"
IMAGE_PULL_SECRET_NAME="ibmcloud-toolchain-${PIPELINE_TOOLCHAIN_ID}-${REGISTRY_URL}"

echo -e "Checking for presence of ${IMAGE_PULL_SECRET_NAME} imagePullSecret for this toolchain"
if ! kubectl get secret "${IMAGE_PULL_SECRET_NAME}" --namespace "${CLUSTER_NAMESPACE}"; then
  echo -e "${IMAGE_PULL_SECRET_NAME} not found in ${CLUSTER_NAMESPACE}, creating it"
  # for Container Registry, docker username is 'token' and email does not matter
  kubectl --namespace "${CLUSTER_NAMESPACE}" create secret docker-registry "${IMAGE_PULL_SECRET_NAME}" --docker-server="${REGISTRY_URL}" --docker-password="${IBMCLOUD_API_KEY}" --docker-username=iamapikey --docker-email=a@b.com
else
  echo -e "Namespace ${CLUSTER_NAMESPACE} already has an imagePullSecret for this toolchain."
fi
if [ -z "${KUBERNETES_SERVICE_ACCOUNT_NAME}" ]; then KUBERNETES_SERVICE_ACCOUNT_NAME="default" ; fi
SERVICE_ACCOUNT=$(kubectl get serviceaccount "${KUBERNETES_SERVICE_ACCOUNT_NAME}"  -o json --namespace "${CLUSTER_NAMESPACE}" )
if ! echo "${SERVICE_ACCOUNT}" | jq -e '. | has("imagePullSecrets")' > /dev/null ; then
  kubectl patch --namespace "${CLUSTER_NAMESPACE}" serviceaccount/"${KUBERNETES_SERVICE_ACCOUNT_NAME}" -p '{"imagePullSecrets":[{"name":"'"${IMAGE_PULL_SECRET_NAME}"'"}]}'
else
  if echo "${SERVICE_ACCOUNT}" | jq -e '.imagePullSecrets[] | select(.name=="'"${IMAGE_PULL_SECRET_NAME}"'")' > /dev/null ; then
    echo -e "Pull secret already found in ${KUBERNETES_SERVICE_ACCOUNT_NAME} serviceAccount"
  else
    echo "Inserting toolchain pull secret into ${KUBERNETES_SERVICE_ACCOUNT_NAME} serviceAccount"
    kubectl patch --namespace "${CLUSTER_NAMESPACE}" serviceaccount/"${KUBERNETES_SERVICE_ACCOUNT_NAME}" --type='json' -p='[{"op":"add","path":"/imagePullSecrets/-","value":{"name": "'"${IMAGE_PULL_SECRET_NAME}"'"}}]'
  fi
fi
echo "${KUBERNETES_SERVICE_ACCOUNT_NAME} serviceAccount:"
kubectl get serviceaccount "${KUBERNETES_SERVICE_ACCOUNT_NAME}" --namespace "${CLUSTER_NAMESPACE}" -o yaml
echo -e "Namespace ${CLUSTER_NAMESPACE} authorizing with private image registry using patched ${KUBERNETES_SERVICE_ACCOUNT_NAME} serviceAccount"

echo "=========================================================="
mkdir zap-scan
echo "Creating DEPLOYMENT.YML manifest"
  cat > zap-scan/deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: zap-deployment
  labels:
    app: zap
spec:
  replicas: 1
  selector:
    matchLabels:
      app: zap
  template:
    metadata:
      labels:
        app: zap
    spec:
      containers:
      - name: zap-ubi
        image: ""
        ports:
        - containerPort: 9080
EOF
DEPLOYMENT_FILE=zap-scan/deployment.yaml

echo "=========================================================="
echo "UPDATING manifest with image information"
echo -e "Updating ${DEPLOYMENT_FILE} with image name: ${IMAGE}"
NEW_DEPLOYMENT_FILE="$(dirname "$DEPLOYMENT_FILE")/tmp.$(basename "$DEPLOYMENT_FILE")"
# find the yaml document index for the K8S deployment definition
DEPLOYMENT_DOC_INDEX=$(yq read --doc "*" --tojson "$DEPLOYMENT_FILE" | jq -r 'to_entries | .[] | select(.value.kind | ascii_downcase=="deployment") | .key')
if [ -z "$DEPLOYMENT_DOC_INDEX" ]; then
  echo "No Kubernetes Deployment definition found in $DEPLOYMENT_FILE. Updating YAML document with index 0"
  DEPLOYMENT_DOC_INDEX=0
fi
# Update deployment with image name
yq write "$DEPLOYMENT_FILE" --doc "$DEPLOYMENT_DOC_INDEX" "spec.template.spec.containers[0].image" "${IMAGE}" > "${NEW_DEPLOYMENT_FILE}"
DEPLOYMENT_FILE="${NEW_DEPLOYMENT_FILE}" # use modified file
cat "${DEPLOYMENT_FILE}"

echo "=========================================================="
echo "DEPLOYING using manifest"
kubectl apply --namespace "${CLUSTER_NAMESPACE}" -f "${DEPLOYMENT_FILE}"

kubectl expose deployment zap-deployment --type=NodePort --name="${SERVICE_NAME}" --namespace "${CLUSTER_NAMESPACE}"

IP_ADDRESS=$(kubectl get nodes -o json | jq -r '[.items[] | .status.addresses[] | select(.type == "ExternalIP") | .address] | .[0]')
PORT=$(kubectl get service -n  "$CLUSTER_NAMESPACE" "${SERVICE_NAME}" -o json | jq -r '.spec.ports[0].nodePort')
ZAP_URL="${IP_ADDRESS}:${PORT}"
echo "ZAP_URL ${ZAP_URL}"

cd "$workingdir" || exit 1
