#!/bin/bash

# shellcheck disable=SC2102,SC2181,SC2207

# Instructions:
#
# - Go to the Alibaba Cloud Console
#
# - Open Cloud Shell >_
#
# - Click on the cloud on the left side of the Cloud Shell window
#
# - Upload this script
#
# - Make this script executable:
#   chmod +x resource-count-abc.sh
#
# - Run this script:
#   ./resource-count-abc.sh
#
# This script may generate errors when:
#
# - The API/CLI is not enabled.
# - You don't have permission to make the API/CLI calls.
#
# API/CLI used:
#
# - aliyun ecs DescribeRegions
# - aliyun ecs DescribeInstances
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

abc_regions_list() {
  # shellcheck disable=SC2086
  RESULT=$(aliyun ecs DescribeRegions 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

abc_compute_instances_list() {
  if [ -z "${2}" ]; then
    # shellcheck disable=SC2086
    RESULT=$(aliyun ecs DescribeInstances --region "${1}" --Status Running --MaxResults 100 2>/dev/null)
  else
    # shellcheck disable=SC2086
    RESULT=$(aliyun ecs DescribeInstances --region "${1}" --Status Running --MaxResults 100 --NextToken "${2}" 2>/dev/null)
  fi
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

####

get_regions() {
  REGIONS=($(abc_regions_list | jq -r '.Regions.Region[].RegionId' 2>/dev/null | sort))
  TOTAL_REGIONS=${#REGIONS[@]}
}

get_instance_count() {
  COUNT=0
  RESULT=$(abc_compute_instances_list "${1}")
  COUNT=$(echo "${RESULT}" | jq -r '.TotalCount' 2>/dev/null)
  echo "${COUNT}"
}

get_instance_count_via_pagination() {
  COUNT=0
  RESULT=$(abc_compute_instances_list "${1}")
  INSTANCES=($(echo "${RESULT}" | jq -r '.Instances.Instance[].InstanceId' 2>/dev/null))
  COUNT=$((COUNT + ${#INSTANCES[@]}))
  NEXTTOKEN=$(echo "${RESULT}" | jq -r '.NextToken' 2>/dev/null)
  while [ -n "${NEXTTOKEN}" ]; do
    RESULT=$(abc_compute_instances_list "${1}" "${NEXTTOKEN}")
    INSTANCES=($(echo "${RESULT}" | jq -r '.Instances.Instance[].InstanceId' 2>/dev/null))
    COUNT=$((COUNT + ${#INSTANCES[@]}))
    NEXTTOKEN=$(echo "${RESULT}" | jq -r '.NextToken' 2>/dev/null)
  done
  echo "${COUNT}"
}

##########################################################################################
## Set or reset counters.
##########################################################################################

reset_local_counters() {
  COMPUTE_INSTANCES_COUNT=0
  WORKLOAD_COUNT=0
}

reset_global_counters() {
  COMPUTE_INSTANCES_COUNT_GLOBAL=0
  WORKLOAD_COUNT_GLOBAL=0
}

##########################################################################################
## Iterate through the billable resource types.
##########################################################################################

count_resources() {
  for ((REGION_INDEX=0; REGION_INDEX<=(TOTAL_REGIONS-1); REGION_INDEX++))
  do
    REGION="${REGIONS[$REGION_INDEX]}"

    echo "###################################################################################"
    echo "Processing Region: ${REGION}"

    RESOURCE_COUNT=$(get_instance_count_via_pagination "${REGION}") 
    COMPUTE_INSTANCES_COUNT=$((COMPUTE_INSTANCES_COUNT + RESOURCE_COUNT))
    echo "  Count of Compute Instances: ${COMPUTE_INSTANCES_COUNT}"

    WORKLOAD_COUNT=$((COMPUTE_INSTANCES_COUNT + 0))
    echo "Total billable resources for Region: ${WORKLOAD_COUNT}"
    echo "###################################################################################"
    echo ""

    COMPUTE_INSTANCES_COUNT_GLOBAL=$((COMPUTE_INSTANCES_COUNT_GLOBAL + COMPUTE_INSTANCES_COUNT))
    reset_local_counters
  done

  echo "###################################################################################"
  echo "Totals"
  echo "  Count of Compute Instances: ${COMPUTE_INSTANCES_COUNT_GLOBAL}"
  WORKLOAD_COUNT_GLOBAL=$((COMPUTE_INSTANCES_COUNT_GLOBAL + 0))
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

get_regions
reset_global_counters
count_resources
