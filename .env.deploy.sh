#!/bin/false
# shellcheck disable=SC1008,SC2155 shell=bash
# shebang to indicate if can only be invoked using source . command
if [ -z "$DEPLOYMENT_FILE" ]; then
  # In case of polyglot the DEPLOYMENT_FILE may not be set
  if [ -f "deployment_iks.yml" ]; then
    DEPLOYMENT_FILE="deployment_iks.yml"
  else
    DEPLOYMENT_FILE="deployment_os.yml"
  fi
fi
echo "Updating Cookie secrets in the deployment file $DEPLOYMENT_FILE"
COOKIE_SECRET="$(get_env "cookie-secret" "mycookiesecret" | base64)" # pragma: allowlist secret
sed -i "s/COOKIE_SECRET/${COOKIE_SECRET}/g" "${DEPLOYMENT_FILE}" 
