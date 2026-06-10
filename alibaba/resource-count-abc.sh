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
# - aliyun rds DescribeDBInstances
# - aliyun slb DescribeLoadBalancers # Assumed command
# - aliyun fc-open GET /2021-04-06/services
# - aliyun fc-open GET /2021-04-06/services/{serviceName}/functions
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

abc_rds_instances_list() {
  # Assuming pagination uses PageNumber and PageSize
  PAGE_NUMBER=1
  PAGE_SIZE=50
  TOTAL_COUNT=-1 # Use -1 to indicate not yet fetched or error

  while true; do
    # shellcheck disable=SC2086
    RESULT=$(aliyun rds DescribeDBInstances --region "${1}" --PageNumber ${PAGE_NUMBER} --PageSize ${PAGE_SIZE} 2>/dev/null)

    if [ $? -ne 0 ]; then
      TOTAL_COUNT=-1
      break
    fi

    CURRENT_ITEMS=$(echo "${RESULT}" | jq -r '.Items.DBInstance | length' 2>/dev/null)
    if [ ${PAGE_NUMBER} -eq 1 ]; then
       TOTAL_COUNT=0
    fi

    if ! [[ "${CURRENT_ITEMS}" =~ ^[0-9]+$ ]]; then
        TOTAL_COUNT=-1
        break
    fi

    TOTAL_COUNT=$((TOTAL_COUNT + CURRENT_ITEMS))

    if [ "${CURRENT_ITEMS}" -lt "${PAGE_SIZE}" ]; then
      break
    fi
    PAGE_NUMBER=$((PAGE_NUMBER + 1))
  done
  echo "${TOTAL_COUNT}"
}

abc_slb_instances_list() {
  # Assuming pagination uses PageNumber and PageSize for SLB as well
  PAGE_NUMBER=1
  PAGE_SIZE=50
  TOTAL_COUNT=-1 # Use -1 to indicate not yet fetched or error

  while true; do
    # shellcheck disable=SC2086
    # Using assumed command: DescribeLoadBalancers
    RESULT=$(aliyun slb DescribeLoadBalancers --region "${1}" --PageNumber ${PAGE_NUMBER} --PageSize ${PAGE_SIZE} 2>/dev/null)

    if [ $? -ne 0 ]; then
      TOTAL_COUNT=-1
      break
    fi

    # Adjust jq path based on actual API response structure for SLB
    CURRENT_ITEMS=$(echo "${RESULT}" | jq -r '.LoadBalancers.LoadBalancer | length' 2>/dev/null)
    if [ ${PAGE_NUMBER} -eq 1 ]; then
       TOTAL_COUNT=0
    fi

    if ! [[ "${CURRENT_ITEMS}" =~ ^[0-9]+$ ]]; then
        TOTAL_COUNT=-1
        break
    fi

    TOTAL_COUNT=$((TOTAL_COUNT + CURRENT_ITEMS))

    if [ "${CURRENT_ITEMS}" -lt "${PAGE_SIZE}" ]; then
      break
    fi
    PAGE_NUMBER=$((PAGE_NUMBER + 1))
  done
  echo "${TOTAL_COUNT}"
}

abc_fc_function_count() {
    local region=$1
    local total_functions_in_region=0
    local next_token=""

    echo "    Listing FC services in region $region..."
    # List services first (paginated)
    local service_names=()
    while true; do
        local service_list_cmd="aliyun fc-open GET /2021-04-06/services --region \"$region\""
        if [ -n "$next_token" ] && [ "$next_token" != "null" ]; then
            service_list_cmd="$service_list_cmd --nextToken \"$next_token\""
        fi

        local services_output
        services_output=$(eval "$service_list_cmd" 2>/dev/null) # Use eval carefully or find safer alternative if possible
        local list_services_exit_code=$?

        if [ $list_services_exit_code -ne 0 ]; then
            echo "      Warning: Failed to list FC services in region $region. Skipping function count for this region."
            return -1 # Indicate error
        fi

        # Extract service names from current page
        local current_services=()
        readarray -t current_services < <(echo "$services_output" | jq -r '.services[]?.serviceName // empty')
        if [ ${#current_services[@]} -gt 0 ]; then
             service_names+=("${current_services[@]}")
        fi

        # Get next token
        next_token=$(echo "$services_output" | jq -r '.nextToken // empty')
        if [ -z "$next_token" ]; then
            break # No more pages
        fi
    done

    if [ ${#service_names[@]} -eq 0 ]; then
        echo "      No FC services found in region $region."
        echo 0 # Return 0 if no services
        return 0
    fi

    echo "      Found ${#service_names[@]} FC services. Listing functions in each..."
    # List functions within each service (paginated)
    for service_name in "${service_names[@]}"; do
         echo "        Listing functions in service '$service_name'..."
         local functions_in_service=0
         local func_next_token=""
         while true; do
            local func_list_cmd="aliyun fc-open GET /2021-04-06/services/\"$service_name\"/functions --region \"$region\""
             if [ -n "$func_next_token" ] && [ "$func_next_token" != "null" ]; then
                 func_list_cmd="$func_list_cmd --nextToken \"$func_next_token\""
             fi

             local functions_output
             functions_output=$(eval "$func_list_cmd" 2>/dev/null)
             local list_func_exit_code=$?

             if [ $list_func_exit_code -ne 0 ]; then
                 echo "          Warning: Failed to list functions for service '$service_name' in region $region. Skipping function count for this service."
                 # Continue to next service, maybe add -1 to indicate partial failure? For now, just skip.
                 functions_in_service=-1 # Mark service as failed
                 break
             fi

             # Count functions on the current page
             local current_functions_count
             current_functions_count=$(echo "$functions_output" | jq '.functions | length // 0')
             if [[ "$current_functions_count" =~ ^[0-9]+$ ]]; then
                  functions_in_service=$((functions_in_service + current_functions_count))
             fi

             # Get next token
             func_next_token=$(echo "$functions_output" | jq -r '.nextToken // empty')
             if [ -z "$func_next_token" ]; then
                 break # No more pages
             fi
         done
         if [ $functions_in_service -gt 0 ]; then
             echo "          Found $functions_in_service functions in service '$service_name'."
             total_functions_in_region=$((total_functions_in_region + functions_in_service))
         elif [ $functions_in_service -lt 0 ]; then
             # Propagate error indicator if listing functions failed for any service
             total_functions_in_region=-1
             break # Stop processing services in this region if one failed
         fi
    done

    echo $total_functions_in_region
}


####

get_regions() {
  REGIONS=($(abc_regions_list | jq -r '.Regions.Region[].RegionId' 2>/dev/null | sort))
  TOTAL_REGIONS=${#REGIONS[@]}
}

get_instance_count() {
  # This function specifically gets ECS instance count using TotalCount field if available
  COUNT=0
  RESULT=$(abc_compute_instances_list "${1}")
  # Check if TotalCount exists and is a number
  TOTAL_COUNT_VAL=$(echo "${RESULT}" | jq -r '.TotalCount' 2>/dev/null)
  if [[ "${TOTAL_COUNT_VAL}" =~ ^[0-9]+$ ]]; then
      COUNT=${TOTAL_COUNT_VAL}
  else
      # Fallback to pagination if TotalCount is not reliable
      COUNT=$(get_instance_count_via_pagination "${1}")
  fi
  echo "${COUNT}"
}

get_instance_count_via_pagination() {
  # This function specifically gets ECS instance count via pagination
  COUNT=0
  NEXTTOKEN=""
  INSTANCES_ON_PAGE=0
  PAGE_NUM=1 # For safety break

  while [ -z "$NEXTTOKEN" ] || [ "$NEXTTOKEN" != "null" ] && [ "$NEXTTOKEN" != "" ] && [ $PAGE_NUM -lt 100 ]; do # Safety break after 100 pages
      if [ -z "$NEXTTOKEN" ] || [ "$NEXTTOKEN" == "null" ]; then
          RESULT=$(abc_compute_instances_list "${1}")
      else
          RESULT=$(abc_compute_instances_list "${1}" "${NEXTTOKEN}")
      fi

      if [ $? -ne 0 ]; then
          # If first page fails, return error (-1)
          [ $PAGE_NUM -eq 1 ] && echo "-1" && return 1
          # Otherwise break loop, returning current count
          break
      fi

      INSTANCES_ON_PAGE=$(echo "${RESULT}" | jq -r '.Instances.Instance | length' 2>/dev/null)
      if ! [[ "${INSTANCES_ON_PAGE}" =~ ^[0-9]+$ ]]; then
          [ $PAGE_NUM -eq 1 ] && echo "-1" && return 1
          break
      fi

      COUNT=$((COUNT + INSTANCES_ON_PAGE))
      NEXTTOKEN=$(echo "${RESULT}" | jq -r '.NextToken' 2>/dev/null)
      PAGE_NUM=$((PAGE_NUM + 1))

      # Break if no instances on page (should coincide with empty NextToken)
      [ $INSTANCES_ON_PAGE -eq 0 ] && break

  done
  echo "${COUNT}"
}

##########################################################################################
## Set or reset counters.
##########################################################################################

reset_local_counters() {
  COMPUTE_INSTANCES_COUNT=0
  RDS_INSTANCES_COUNT=0
  SLB_INSTANCES_COUNT=0
  FC_FUNCTIONS_COUNT=0 # Added
  WORKLOAD_COUNT=0
}

reset_global_counters() {
  COMPUTE_INSTANCES_COUNT_GLOBAL=0
  RDS_INSTANCES_COUNT_GLOBAL=0
  SLB_INSTANCES_COUNT_GLOBAL=0
  FC_FUNCTIONS_COUNT_GLOBAL=0 # Added
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
    reset_local_counters # Reset local counters for each region

    # Get ECS count
    RESOURCE_COUNT_ECS=$(get_instance_count "${REGION}")
     if [ "${RESOURCE_COUNT_ECS}" -lt 0 ]; then
      echo "  Warning: Could not retrieve ECS instance count for region ${REGION}."
      RESOURCE_COUNT_ECS=0
    fi
    COMPUTE_INSTANCES_COUNT=$((COMPUTE_INSTANCES_COUNT + RESOURCE_COUNT_ECS))
    echo "  Count of Compute Instances (ECS): ${COMPUTE_INSTANCES_COUNT}"

    # Get RDS count
    RESOURCE_COUNT_RDS=$(abc_rds_instances_list "${REGION}")
    if [ "${RESOURCE_COUNT_RDS}" -lt 0 ]; then
      echo "  Warning: Could not retrieve RDS instance count for region ${REGION}."
      RESOURCE_COUNT_RDS=0
    fi
    RDS_INSTANCES_COUNT=$((RDS_INSTANCES_COUNT + RESOURCE_COUNT_RDS))
    echo "  Count of RDS Instances: ${RDS_INSTANCES_COUNT}"

    # Get SLB count
    RESOURCE_COUNT_SLB=$(abc_slb_instances_list "${REGION}")
     if [ "${RESOURCE_COUNT_SLB}" -lt 0 ]; then
      echo "  Warning: Could not retrieve SLB instance count for region ${REGION}."
      RESOURCE_COUNT_SLB=0
    fi
    SLB_INSTANCES_COUNT=$((SLB_INSTANCES_COUNT + RESOURCE_COUNT_SLB))
    echo "  Count of Load Balancers (SLB): ${SLB_INSTANCES_COUNT}"

    # Get Function Compute count
    RESOURCE_COUNT_FC=$(abc_fc_function_count "${REGION}")
    if [ "${RESOURCE_COUNT_FC}" -lt 0 ]; then
         echo "  Warning: Could not retrieve full Function Compute count for region ${REGION} due to errors."
         # Decide how to handle partial failure - currently counted as 0 for the region
         RESOURCE_COUNT_FC=0
    fi
    FC_FUNCTIONS_COUNT=$((FC_FUNCTIONS_COUNT + RESOURCE_COUNT_FC))
    echo "  Count of Function Compute Functions: ${FC_FUNCTIONS_COUNT}"


    # Update workload count
    WORKLOAD_COUNT=$((COMPUTE_INSTANCES_COUNT + RDS_INSTANCES_COUNT + SLB_INSTANCES_COUNT + FC_FUNCTIONS_COUNT))
    echo "Total billable resources for Region: ${WORKLOAD_COUNT}"
    echo "###################################################################################"
    echo ""

    # Update global counters
    COMPUTE_INSTANCES_COUNT_GLOBAL=$((COMPUTE_INSTANCES_COUNT_GLOBAL + COMPUTE_INSTANCES_COUNT))
    RDS_INSTANCES_COUNT_GLOBAL=$((RDS_INSTANCES_COUNT_GLOBAL + RDS_INSTANCES_COUNT))
    SLB_INSTANCES_COUNT_GLOBAL=$((SLB_INSTANCES_COUNT_GLOBAL + SLB_INSTANCES_COUNT))
    FC_FUNCTIONS_COUNT_GLOBAL=$((FC_FUNCTIONS_COUNT_GLOBAL + FC_FUNCTIONS_COUNT)) # Added FC
    # reset_local_counters # Moved reset to the beginning of the loop
  done

  echo "###################################################################################"
  echo "Totals"
  echo "  Count of Compute Instances (ECS): ${COMPUTE_INSTANCES_COUNT_GLOBAL}"
  echo "  Count of RDS Instances: ${RDS_INSTANCES_COUNT_GLOBAL}"
  echo "  Count of Load Balancers (SLB): ${SLB_INSTANCES_COUNT_GLOBAL}"
  echo "  Count of Function Compute Functions: ${FC_FUNCTIONS_COUNT_GLOBAL}" # Added FC to summary
  # Update final workload count
  WORKLOAD_COUNT_GLOBAL=$((COMPUTE_INSTANCES_COUNT_GLOBAL + RDS_INSTANCES_COUNT_GLOBAL + SLB_INSTANCES_COUNT_GLOBAL + FC_FUNCTIONS_COUNT_GLOBAL))
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
