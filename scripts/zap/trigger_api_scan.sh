#!/usr/bin/env bash

source "${ONE_PIPELINE_PATH}"/tools/trigger-task

#
# save "target-application-server-url" using set_env
# then mark it to export, so it will be synced 
# to the "owasp-zap-api" task triggered async to a sub-pipeline
#
set_env "target-application-server-url" "$APP_URL"
export_env "target-application-server-url"

trigger-task "owasp-zap-api" "dynamic_scan"