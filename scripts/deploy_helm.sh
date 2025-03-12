#!/usr/bin/env bash
REGISTRY_AUTH=""
if [[ -n "$BREAK_GLASS" ]]; then
  REGISTRY_AUTH=$(jq .parameters.docker_config_json /config/artifactory)
else
  # Use the API key used for the image build as IAM API key to create the image pull secret, if corresponding parameter has been set.
  # See build_setup.sh for the container registry credentials/login
  CR_IAM_API_KEY="$(cat /config/api-key)" # pragma: allowlist secret
  REGISTRY_AUTH=$(echo "{\"auths\":{\"${REGISTRY_URL}\":{\"auth\":\"$(echo -n iamapikey:"${CR_IAM_API_KEY}" | base64 -w 0)\",\"username\":\"iamapikey\",\"email\":\"iamapikey\",\"password\":\"${CR_IAM_API_KEY}\"}}}" | base64 -w 0)
fi

INGRESS_RULE_HOST=$(yq r --doc 0 "$WORKSPACE/$(load_repo app-repo path)/chart/node-compliance-app-helm/values.yaml" ingress.host)
CLUSTER_INGRESS_SUBDOMAIN=$(ibmcloud ks cluster get --cluster "${IBMCLOUD_IKS_CLUSTER_NAME}" --json | jq -r '.ingressHostname // .ingress.hostname' | cut -d, -f1)
IMAGE="${IMAGE#*"@"}"
APP_NAME="$(get_env app-name "hello-compliance-app-helm")"
helm_name=$(echo "${APP_NAME}"-"${IBMCLOUD_IKS_CLUSTER_NAMESPACE}"| sed 's/_/-/g')

is_ingress_enabled="false"
ingress_secret=""
service_type="$(yq r --doc 0 "$WORKSPACE/$(load_repo app-repo path)/chart/node-compliance-app-helm/values.yaml" service.type)"
if [ -n "$CLUSTER_INGRESS_SUBDOMAIN" ]; then
  is_ingress_enabled="true"
  ingress_secret="$(ibmcloud ks cluster get --cluster "${IBMCLOUD_IKS_CLUSTER_NAME}" --json | jq -r '.ingressSecretName // .ingress.secretName' | cut -d, -f1 )"
  service_type="ClusterIP"
fi

# ensure the target namespace exists for the helm install
if kubectl get namespace "$IBMCLOUD_IKS_CLUSTER_NAMESPACE"; then
  echo "Namespace ${IBMCLOUD_IKS_CLUSTER_NAMESPACE} found !"
else
  kubectl create namespace "$IBMCLOUD_IKS_CLUSTER_NAMESPACE"
fi

for ITER in {1..3}
do
  # shellcheck disable=SC2086
  if helm upgrade --install "${helm_name}" "$WORKSPACE/$(load_repo app-repo path)/chart/node-compliance-app-helm" \
      --namespace "${IBMCLOUD_IKS_CLUSTER_NAMESPACE}" \
      --set image="${IMAGE}" \
      --set cluster.type="${CLUSTER_TYPE}" \
      --set service.type="${service_type}" \
      --set ingress.enabled="${is_ingress_enabled}" \
      --set secret.dockerconfigjson="${REGISTRY_AUTH}" \
      --set ingress.host="${CLUSTER_INGRESS_SUBDOMAIN}" \
      --set ingress.secret="$ingress_secret" \
      --values "$WORKSPACE/$(load_repo app-repo path)/chart/$(get_env target-environment "dev")-values.yaml"; then
    echo "Helm deployment is successful"
    break;
  else
    echo "Helm deployment is failed, tried $ITER times."
  fi
done

if kubectl rollout status --namespace "$IBMCLOUD_IKS_CLUSTER_NAMESPACE" "deployment/${helm_name}-deployment"; then
  status=success
else
  status=failure
fi
kubectl get events --sort-by=.metadata.creationTimestamp -n "$IBMCLOUD_IKS_CLUSTER_NAMESPACE"

if [ "$status" = failure ]; then
  echo "Deployment failed"
  if [[ -z "$BREAK_GLASS" ]]; then
    ibmcloud cr quota
  fi
  exit 1
fi

export APPURL
if [ "${CLUSTER_TYPE}" == "OPENSHIFT" ]; then
  route_json_file=$(mktemp)
  kubectl get route --namespace "$IBMCLOUD_IKS_CLUSTER_NAMESPACE" "${helm_name}" -o json > $route_json_file
  route_host="$(jq -r '.spec.host//empty' "$route_json_file")"
  route_path="$(jq -r '.spec.path//empty' "$route_json_file")"
  # Remove the last / from selected_route_path if any
  route_path="${route_path%/}"
  if jq -e '.spec.tls' "$route_json_file" > /dev/null 2>&1; then
    route_protocol="https"
  else
    route_protocol="http"
  fi
  APPURL="${route_protocol}://${route_host}${route_path}"
else
  sleep 10
  if [ -n "${CLUSTER_INGRESS_SUBDOMAIN}" ] && [ "${KEEP_INGRESS_CUSTOM_DOMAIN}" != true ]; then
    # shellcheck disable=SC2034
    for ITER in {1..30}
    do
      INGRESS_JSON=$(kubectl get ingress --namespace "${IBMCLOUD_IKS_CLUSTER_NAMESPACE}" "${helm_name}" -o json)
      # Expose app using ingress host and path for the service
      APP_HOST=$(echo "$INGRESS_JSON" | jq -r --arg service_name "${helm_name}" '.spec.rules[] | first(select(.http.paths[].backend.serviceName==$service_name or .http.paths[].backend.service.name==$service_name)) | .host' | head -n1)
      APP_PATH=$(echo "$INGRESS_JSON" | jq -r --arg service_name "${helm_name}" '.spec.rules[].http.paths[] | first(select(.backend.serviceName==$service_name or .backend.service.name==$service_name)) | .path' | head -n1)
      # Remove any group in the path in case of regex in ingress path definition
      # https://kubernetes.github.io/ingress-nginx/user-guide/ingress-path-matching/
      # shellcheck disable=SC2001
      APP_PATH=$(echo "$APP_PATH" | sed "s/([^)]*)//g")
      # Remove the last / from APP_PATH if any
      APP_PATH="${APP_PATH%/}"
      if [ -n  "${APP_HOST}"  ]; then
        APPURL="https://${APP_HOST}""${APP_PATH}"
        break
      fi
      sleep 2
    done
  fi

  # If unable to find the APP_URL and Ingress sub domain is not available.
  if [ -z  "${APPURL}"  ] || [[  "${APPURL}" = "null"  ]]; then
    IP_ADDRESS=$(kubectl get nodes -o json | jq -r '[.items[] | .status.addresses[] | select(.type == "ExternalIP") | .address] | .[0]')
    PORT=$(kubectl get service -n "$IBMCLOUD_IKS_CLUSTER_NAMESPACE" "${helm_name}" -o json | jq -r '.spec.ports[0].nodePort')
    APPURL="http://${IP_ADDRESS}:${PORT}"
  fi
fi

if [ -z  "${APPURL}"  ] || [[  "${APPURL}" = "null"  ]] || [[  "${APPURL}" = ":"  ]]; then
    echo "Unable to get Application URL....."
    exit 1
fi

echo "Application URL: ${APPURL}"
echo -n "${APPURL}" >../app-url
set_env app-url "${APPURL}"
