#!/bin/false
# shellcheck disable=SC1008,SC2155 shell=bash
# shebang to indicate if can only be invoked using source . command
if [ -z "$DEPLOYMENT_FILE" ]; then
  # In case of polyglot the DEPLOYMENT_FILE may not be set
  if [ -f "deployment_iks.yml" ]; then
    DEPLOYMENT_FILE="deployment_iks.yml"
  elif [ -f "deployment_os.yml" ]; then
    DEPLOYMENT_FILE="deployment_os.yml"
  fi
fi
if [ -n "$DEPLOYMENT_FILE" ]; then
  echo "Updating Cookie secrets in the deployment file $DEPLOYMENT_FILE"
  COOKIE_SECRET="$(get_env "cookie-secret" "mycookiesecret" | base64)" # pragma: allowlist secret
  sed -i "s/COOKIE_SECRET/${COOKIE_SECRET}/g" "${DEPLOYMENT_FILE}"
fi

# export cluster type for dynamic scan if cluster_type is populated
cluster_type="${cluster_type:-""}"
if [ -n "$cluster_type" ]; then
  echo "Set and export cluster-type env property to $cluster_type for dynamic scan customization"
  set_env "cluster-type" "$cluster_type"
  export_env "cluster-type"
fi