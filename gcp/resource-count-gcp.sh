#!/bin/bash

# shellcheck disable=SC2102,SC2181,SC2207

# Instructions:
#
# - Go to the GCP Console
#
# - Open Cloud Shell >_
#
# - Click on three dot vertical menu on the right side (left of minimize button)
#
# - Upload this script
#
# - Make this script executable:
#   chmod +x resource-count-gcp.sh
#
# - Run this script:
#   resource-count-gcp.sh
#   resource-count-gcp.sh verbose (see below)
#
# This script may generate errors when:
#
# - The API is not enabled (and gcloud prompts you to enable the API).
# - You don't have permission to make the API calls.
#
# API/CLI used:
#
# - gcloud projects list
# - gcloud compute instances list
# - gcloud compute routers list
# - gcloud compute routers nats list
# - gcloud sql instances list
##########################################################################################

##########################################################################################
## Use of jq is required by this script.
##########################################################################################

if ! type "jq" > /dev/null; then
  echo "Error: jq not installed or not in execution path, jq is required for script execution."
  exit 1
fi

##########################################################################################
## Optionally enable verbose mode by passing "verbose" as an argument.
##########################################################################################

# By default:
#
# - You will not be prompted to enable an API (we assume that you don't use the service, thus resource count is assumed to be 0).
# - When an error is encountered, you most likely don't have API access, thus resource count is assumed to be 0).

if [ "${1}X" == "verboseX" ]; then
  VERBOSITY_ARGS="--verbosity error"
else
  VERBOSITY_ARGS="--verbosity critical --quiet"
fi

##########################################################################################
## GCP Utility functions.
##########################################################################################

gcloud_projects_list() {
  RESULT=$(gcloud projects list --format json 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

gcloud_compute_instances_list() {
  # shellcheck disable=SC2086
  RESULT=$(gcloud compute instances list --filter="status:(RUNNING)" --project "${1}" --format json $VERBOSITY_ARGS 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

gcloud_compute_routers_list() {
  # shellcheck disable=SC2086
  RESULT=$(gcloud compute routers list --project "${1}" --format json $VERBOSITY_ARGS 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

gcloud_compute_routers_nats_list() {
  # shellcheck disable=SC2086
  RESULT=$(gcloud compute routers nats list --project "${1}" --region "${2}" --router "${3}" --format json $VERBOSITY_ARGS 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

gcloud_compute_backend_services_list() {
  # shellcheck disable=SC2086
  RESULT=$(gcloud compute backend-services list --project "${1}" --format json $VERBOSITY_ARGS 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

gcloud_sql_instances_list() {
  # shellcheck disable=SC2086
  RESULT=$(gcloud sql instances list --project "${1}" --format json $VERBOSITY_ARGS 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

####

get_project_list() {
  PROJECTS=($(gcloud_projects_list | jq  -r '.[].projectId'))
  TOTAL_PROJECTS=${#PROJECTS[@]}
}

##########################################################################################
## Set or reset counters.
##########################################################################################

reset_project_counters() {
  COMPUTE_INSTANCES_COUNT=0
  COMPUTE_NAT_COUNT=0
  COMPUTE_BACKEND_SERVICES_COUNT=0
  SQL_INSTANCES_COUNT=0
  WORKLOAD_COUNT=0
}

reset_global_counters() {
  COMPUTE_INSTANCES_COUNT_GLOBAL=0
  COMPUTE_NAT_COUNT_GLOBAL=0
  COMPUTE_BACKEND_SERVICES_COUNT_GLOBAL=0
  SQL_INSTANCES_COUNT_GLOBAL=0
  WORKLOAD_COUNT_GLOBAL=0
}

##########################################################################################
## Iterate through the projects, and billable resource types.
##########################################################################################

count_project_resources() {
  for ((PROJECT_INDEX=0; PROJECT_INDEX<=(TOTAL_PROJECTS-1); PROJECT_INDEX++))
  do
    PROJECT="${PROJECTS[$PROJECT_INDEX]}"

    echo "###################################################################################"
    echo "Processing Project: ${PROJECT}"

    RESOURCE_COUNT=$(gcloud_compute_instances_list "${PROJECT}" | jq '.[].name' | wc -l)
    COMPUTE_INSTANCES_COUNT=$((COMPUTE_INSTANCES_COUNT + RESOURCE_COUNT))
    echo "  Count of Running Compute Instances: ${COMPUTE_INSTANCES_COUNT}"

    ROUTERS=($(gcloud_compute_routers_list "${PROJECT}" | jq  -r '.[] | "\(.name);\(.region)"'))
    for ROUTER in "${ROUTERS[@]}"
    do
        ROUTER_REGION=${ROUTER##*/}
        ROUTER_NAME=$(cut -d ';' -f 1 <<< "${ROUTER}")
        RESOURCE_COUNT=$(gcloud_compute_routers_nats_list "${PROJECT}" "${ROUTER_REGION}" "${ROUTER_NAME}" | jq -r '.[].name' | wc -l)
        COMPUTE_NAT_COUNT=$((COMPUTE_NAT_COUNT + RESOURCE_COUNT))
    done
    echo "  Count of NAT: ${COMPUTE_NAT_COUNT}"

    RESOURCE_COUNT=$(gcloud_compute_backend_services_list "${PROJECT}" | jq '.[].name' | wc -l)
    COMPUTE_BACKEND_SERVICES_COUNT=$((COMPUTE_BACKEND_SERVICES_COUNT + RESOURCE_COUNT))
    echo "  Count of Compute Load Balancing Services: ${COMPUTE_BACKEND_SERVICES_COUNT}"

    RESOURCE_COUNT=$(gcloud_sql_instances_list "${PROJECT}" | jq '.[].name' | wc -l)
    SQL_INSTANCES_COUNT=$((SQL_INSTANCES_COUNT + RESOURCE_COUNT))
    echo "  Count of SQL Instances: ${SQL_INSTANCES_COUNT}"

    WORKLOAD_COUNT=$((COMPUTE_INSTANCES_COUNT + COMPUTE_NAT_COUNT + COMPUTE_BACKEND_SERVICES_COUNT + SQL_INSTANCES_COUNT))
    echo "Total billable resources for Project ${PROJECTS[$PROJECT_INDEX]}: ${WORKLOAD_COUNT}"
    echo "###################################################################################"
    echo ""

    COMPUTE_INSTANCES_COUNT_GLOBAL=$((COMPUTE_INSTANCES_COUNT_GLOBAL + COMPUTE_INSTANCES_COUNT))
    COMPUTE_NAT_COUNT_GLOBAL=$((COMPUTE_NAT_COUNT_GLOBAL + COMPUTE_NAT_COUNT))
    COMPUTE_BACKEND_SERVICES_COUNT_GLOBAL=$((COMPUTE_BACKEND_SERVICES_COUNT_GLOBAL + COMPUTE_BACKEND_SERVICES_COUNT))
    SQL_INSTANCES_COUNT_GLOBAL=$((SQL_INSTANCES_COUNT_GLOBAL + SQL_INSTANCES_COUNT))

    reset_project_counters
  done

  echo "###################################################################################"
  echo "Totals for all projects"
  echo "  Count of Running Compute Instances: ${COMPUTE_INSTANCES_COUNT_GLOBAL}"
  echo "  Count of NAT: ${COMPUTE_NAT_COUNT_GLOBAL}"
  echo "  Count of Compute Load Balancing Services: ${COMPUTE_BACKEND_SERVICES_COUNT_GLOBAL}"
  echo "  Count of SQL Instances: ${SQL_INSTANCES_COUNT_GLOBAL}"
  WORKLOAD_COUNT_GLOBAL=$((COMPUTE_INSTANCES_COUNT_GLOBAL + COMPUTE_NAT_COUNT_GLOBAL + COMPUTE_BACKEND_SERVICES_COUNT_GLOBAL + SQL_INSTANCES_COUNT_GLOBAL))
  echo "Total billable resources for all projects: ${WORKLOAD_COUNT_GLOBAL}"
  echo "###################################################################################"
}

##########################################################################################
# Allow shellspec to source this script.
##########################################################################################

${__SOURCED__:+return}

##########################################################################################
# Main.
##########################################################################################

get_project_list
reset_project_counters
reset_global_counters
count_project_resources
