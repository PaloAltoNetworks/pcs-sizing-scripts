#!/bin/bash

# shellcheck disable=SC2102,SC2181,SC2207

# Instructions:
#
# - Go to the OCI Console
#
# - Open Cloud Shell >_
#
# - Click on the three bar vertical menu on the left side of the Cloud Shell window
#
# - Upload this script
#
# - Make this script executable:
#   chmod +x resource-count-oci.sh
#
# - Run this script:
#   ./resource-count-oci.sh
#
# This script may generate errors when:
#
# - The API/CLI is not enabled.
# - You don't have permission to make the API/CLI calls.
#
# API/CLI used:
#
# - oci search resource structured-search
##########################################################################################
## Use of jq is required by this script.
##########################################################################################

if ! type "jq" > /dev/null; then
  echo "Error: jq not installed or not in execution path, jq is required for script execution."
  exit 1
fi

##########################################################################################
## Define resource types to count.
##########################################################################################

# Note: Resource type names can be found via `oci search resource-type list`
#       or by inspecting the 'resource-type' field in the output of `oci search resource structured-search`.
COMPUTE_INSTANCE_TYPE="Instance"
DB_SYSTEM_TYPE="DbSystem"
LOAD_BALANCER_TYPE="LoadBalancer"
FUNCTION_TYPE="Function" # Added Function type

##########################################################################################
## Count resources using OCI Search.
##########################################################################################

count_resources() {
  echo "Querying OCI resources using the search service..."

  # Construct the query string
  # We are looking for resources of specific types that are in an ACTIVE/RUNNING/AVAILABLE state.
  # Adjust lifecycle states as needed based on OCI documentation for each resource type.
  # Assuming 'ACTIVE' is the relevant state for Functions.
  QUERY="query all resources where (resourceType = '${COMPUTE_INSTANCE_TYPE}' && lifecycleState = 'RUNNING') || (resourceType = '${DB_SYSTEM_TYPE}' && lifecycleState = 'AVAILABLE') || (resourceType = '${LOAD_BALANCER_TYPE}' && lifecycleState = 'ACTIVE') || (resourceType = '${FUNCTION_TYPE}' && lifecycleState = 'ACTIVE')"

  # Execute the search command
  # We only need the count, jq can sum this up directly if we query just the resource type.
  # Using --raw-output to get plain text count.
  SEARCH_RESULTS=$(oci search resource structured-search --query-text "${QUERY}" --query "data.items[*].\"resource-type\"" --all 2>/dev/null)

  if [ $? -ne 0 ]; then
    echo "Error executing OCI search command. Please check OCI CLI configuration and permissions."
    exit 1
  fi

  # Count occurrences of each resource type using jq
  COMPUTE_INSTANCES_COUNT_GLOBAL=$(echo "${SEARCH_RESULTS}" | jq -r --arg type "${COMPUTE_INSTANCE_TYPE}" 'map(select(. == $type)) | length')
  BARE_METAL_VM_DB_COUNT_GLOBAL=$(echo "${SEARCH_RESULTS}" | jq -r --arg type "${DB_SYSTEM_TYPE}" 'map(select(. == $type)) | length')
  LOAD_BALANCER_COUNT_GLOBAL=$(echo "${SEARCH_RESULTS}" | jq -r --arg type "${LOAD_BALANCER_TYPE}" 'map(select(. == $type)) | length')
  FUNCTION_COUNT_GLOBAL=$(echo "${SEARCH_RESULTS}" | jq -r --arg type "${FUNCTION_TYPE}" 'map(select(. == $type)) | length') # Added Function count

  # Handle potential nulls from jq if no resources are found
  COMPUTE_INSTANCES_COUNT_GLOBAL=${COMPUTE_INSTANCES_COUNT_GLOBAL:-0}
  BARE_METAL_VM_DB_COUNT_GLOBAL=${BARE_METAL_VM_DB_COUNT_GLOBAL:-0}
  LOAD_BALANCER_COUNT_GLOBAL=${LOAD_BALANCER_COUNT_GLOBAL:-0}
  FUNCTION_COUNT_GLOBAL=${FUNCTION_COUNT_GLOBAL:-0} # Added Function count handling

  echo "###################################################################################"
  echo "Totals (across all compartments)"
  echo "  Count of Compute Instances (${COMPUTE_INSTANCE_TYPE}, RUNNING): ${COMPUTE_INSTANCES_COUNT_GLOBAL}"
  echo "  Count of DB Systems (${DB_SYSTEM_TYPE}, AVAILABLE): ${BARE_METAL_VM_DB_COUNT_GLOBAL}"
  echo "  Count of Load Balancers (${LOAD_BALANCER_TYPE}, ACTIVE): ${LOAD_BALANCER_COUNT_GLOBAL}"
  echo "  Count of Functions (${FUNCTION_TYPE}, ACTIVE): ${FUNCTION_COUNT_GLOBAL}" # Added Function output
  # Update total workload count
  WORKLOAD_COUNT_GLOBAL=$((COMPUTE_INSTANCES_COUNT_GLOBAL + BARE_METAL_VM_DB_COUNT_GLOBAL + LOAD_BALANCER_COUNT_GLOBAL + FUNCTION_COUNT_GLOBAL))
  echo "Total billable resources: ${WORKLOAD_COUNT_GLOBAL}"
  echo "###################################################################################"
}

##########################################################################################
# Allow shellspec to source this script.
##########################################################################################

${__SOURCED__:+return}

##########################################################################################
# Main.
##########################################################################################

count_resources
