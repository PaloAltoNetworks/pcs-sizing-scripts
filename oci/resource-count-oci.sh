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
# - oci iam compartment list
# - oci compute instance list
##########################################################################################

##########################################################################################
## Use of jq is required by this script.
##########################################################################################

if ! type "jq" > /dev/null; then
  echo "Error: jq not installed or not in execution path, jq is required for script execution."
  exit 1
fi

##########################################################################################
## Utility functions.
##########################################################################################

oci_compartments_list() {
  # shellcheck disable=SC2086
  RESULT=$(oci iam compartment list --all 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

oci_compute_instances_list() {
  # shellcheck disable=SC2086
  RESULT=$(oci compute instance list --all --compartment-id "${1}" --lifecycle-state "RUNNING" 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

oci_db_system_list(){
  RESULT=$(oci db system list --all --compartment-id "${1}" --lifecycle-state "AVAILABLE" 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

oci_load_balancer_list(){
  RESULT=$(oci lb load-balancer list --all --compartment-id "${1}" --lifecycle-state "ACTIVE" 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

####

get_compartments() {
  COMPARTMENTS=($(oci_compartments_list | jq -r '.data[]."compartment-id"' 2>/dev/null))
  TOTAL_COMPARTMENTS=${#COMPARTMENTS[@]}
}

##########################################################################################
## Set or reset counters.
##########################################################################################

reset_local_counters() {
  COMPUTE_INSTANCES_COUNT=0
  WORKLOAD_COUNT=0
  BARE_METAL_VM_DB_COUNT=0
  LOAD_BALANCER_COUNT=0
}

reset_global_counters() {
  COMPUTE_INSTANCES_COUNT_GLOBAL=0
  WORKLOAD_COUNT_GLOBAL=0
  BARE_METAL_VM_DB_COUNT_GLOBAL=0
  LOAD_BALANCER_COUNT_GLOBAL=0
}

##########################################################################################
## Iterate through the billable resource types.
##########################################################################################

count_resources() {
  for ((COMPARTMENT_INDEX=0; COMPARTMENT_INDEX<=(TOTAL_COMPARTMENTS-1); COMPARTMENT_INDEX++))
  do
    COMPARTMENT="${COMPARTMENTS[$COMPARTMENT_INDEX]}"

    echo "###################################################################################"
    echo "Processing Compartment: ${COMPARTMENT}"

    RESOURCE_COUNT=$(oci_compute_instances_list "${COMPARTMENT}" | jq -r '.data[].id' 2>/dev/null | wc -l)
    COMPUTE_INSTANCES_COUNT=$((COMPUTE_INSTANCES_COUNT + RESOURCE_COUNT))
    echo "  Count of Compute Instances: ${COMPUTE_INSTANCES_COUNT}"
    
    RESOURCE_COUNT_VM=$(oci_db_system_list "${COMPARTMENT}" | jq -r '.data[].id' 2>/dev/null | wc -l)
    BARE_METAL_VM_DB_COUNT=$((BARE_METAL_VM_DB_COUNT + RESOURCE_COUNT_VM))
    echo " Count of Bare Metal VM Database Systems : ${BARE_METAL_VM_DB_COUNT}"

    RESOURCE_COUNT_LB=$(oci_load_balancer_list "${COMPARTMENT}" | jq -r '.data[].id' 2>/dev/null | wc -l)
    LOAD_BALANCER_COUNT=$((LOAD_BALANCER_COUNT + RESOURCE_COUNT_LB))
    echo " Count of Load Balancers : ${LOAD_BALANCER_COUNT}"


    WORKLOAD_COUNT=$((COMPUTE_INSTANCES_COUNT + LOAD_BALANCER_COUNT + BARE_METAL_VM_DB_COUNT))
    echo "Total billable resources for Compartment: ${WORKLOAD_COUNT}"
    echo "###################################################################################"
    echo ""

    COMPUTE_INSTANCES_COUNT_GLOBAL=$((COMPUTE_INSTANCES_COUNT_GLOBAL + COMPUTE_INSTANCES_COUNT))
    BARE_METAL_VM_DB_COUNT_GLOBAL=$((BARE_METAL_VM_DB_COUNT_GLOBAL + BARE_METAL_VM_DB_COUNT))
    LOAD_BALANCER_COUNT_GLOBAL=$((LOAD_BALANCER_COUNT_GLOBAL+LOAD_BALANCER_COUNT))
    reset_local_counters
  done

  echo "###################################################################################"
  echo "Totals"
  echo "  Count of Compute Instances: ${COMPUTE_INSTANCES_COUNT_GLOBAL}"
  echo "  Count of Bare Metal VM DB Systems: ${BARE_METAL_VM_DB_COUNT_GLOBAL}"
  echo "  Count of Load Balancers: ${LOAD_BALANCER_COUNT_GLOBAL}"
  WORKLOAD_COUNT_GLOBAL=$((COMPUTE_INSTANCES_COUNT_GLOBAL + BARE_METAL_VM_DB_COUNT_GLOBAL + LOAD_BALANCER_COUNT_GLOBAL))
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

get_compartments
reset_global_counters
count_resources
