#!/bin/bash

# shellcheck disable=SC2102,SC2181,SC2207

##########################################################################################
# Instructions:
#
# - Make this script executable:
#   chmod +x resource-count-aws.sh
#
# - Run this script:
#   resource-count-aws.sh
#   resource-count-aws.sh org (see below)
#
# API/CLI used:
#
# - aws organizations describe-organization (optional)
# - aws organizations list-accounts (optional)
# - aws sts assume-role (optional)
#
# - aws ec2 describe-instances
# - aws rds describe-db-instances
# - aws ec2 describe-nat-gateways
# - aws redshift describe-clusters
# - aws elb describe-load-balancer
# - aws lambda get-account-settings (optional)
# - aws ecs list-clusters (optional)
# - aws ecs list-tasks (optional)
# - aws s3api list-buckets (optional)
# - aws s3api list-objects (optional)
##########################################################################################

##########################################################################################
## Use of jq is required by this script.
##########################################################################################

if ! type "jq" > /dev/null; then
  echo "Error: jq not installed or not in execution path, jq is required for script execution."
  exit 1
fi

##########################################################################################
## Optionally query the AWS Organization by passing "org" as an argument.
##########################################################################################

if [ "${1}X" == "orgX" ] || [ "${2}X" == "orgX" ] || [ "${3}X" == "orgX" ]; then
   USE_AWS_ORG="true"
else
   USE_AWS_ORG="false"
fi

##########################################################################################
## Optionally report on Compute by passing "cwp" as an argument.
##########################################################################################

if [ "${1}X" == "cwpX" ] || [ "${2}X" = "cwpX" ] || [ "${3}X" == "cwpX" ]; then
   WITH_CWP="true"
else
   WITH_CWP="false"
fi

##########################################################################################
## Optionally report on S3 Bucket Size by passing "data" as an argument.
## NOTE: This can take a long time depending on the size of your buckets
##########################################################################################

if [ "${1}X" == "dataX" ] || [ "${2}X" = "dataX" ] || [ "${3}X" == "dataX" ]; then
   WITH_DATA="true"
else
   WITH_DATA="false"
fi

##########################################################################################
## Utility functions.
##########################################################################################

error_and_exit() {
  echo
  echo "ERROR: ${1}"
  echo
  exit 1
}

##########################################################################################
## AWS Utility functions.
##########################################################################################

aws_ec2_describe_regions() {
  RESULT=$(aws ec2 describe-regions --output json 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

####

aws_organizations_describe_organization() {
  RESULT=$(aws organizations describe-organization --output json 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

aws_organizations_list_accounts() {
  RESULT=$(aws organizations list-accounts --output json 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

aws_sts_assume_role() {
  RESULT=$(aws sts assume-role --role-arn="${1}" --role-session-name=pcs-sizing-script --duration-seconds=999 --output json 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

####

aws_ec2_describe_instances() {
  RESULT=$(aws ec2 describe-instances --max-items 99999 --region="${1}" --filters "Name=instance-state-name,Values=running" --output json 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  else
    echo '{"Error": [] }'
  fi
}

aws_ecs_list_clusters() {
  RESULT=$(aws ecs list-clusters --max-items 99999 --region="${1}" --output json 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  else
    echo '{"Error": [] }'
  fi
}

aws_ecs_list_tasks() {
  RESULT=$(aws ecs list-tasks --max-items 99999 --region "${1}" --cluster "${2}" --desired-status running --output json 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  else
    echo '{"Error": [] }'
  fi
}

aws_ec2_describe_db_instances() {
  RESULT=$(aws rds describe-db-instances --max-items 99999 --region="${1}" --output json 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  else
    echo '{"Error": [] }'
  fi
}

aws_ec2_describe_nat_gateways() {
  RESULT=$(aws ec2 describe-nat-gateways --max-items 99999 --region="${1}" --output json 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  else
    echo '{"Error": [] }'
  fi
}

aws_redshift_describe_clusters() {
  RESULT=$(aws redshift describe-clusters --max-items 99999 --region="${1}" --output json 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  else
    echo '{"Error": [] }'
  fi
}

aws_elb_describe_load_balancers() {
  RESULT=$(aws elb describe-load-balancers --max-items 99999 --region="${1}" --output json 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  else
    echo '{"Error": [] }'
  fi
}

aws_lambda_get_account_settings() {
  RESULT=$(aws lambda get-account-settings --region="${1}" --output json 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  else
    echo '{"Error": [] }'
  fi
}

aws_s3api_list_buckets() {
  RESULT=$(aws s3api list-buckets --query "Buckets[].Name[]" --output json 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  else
    echo '{"Error": [] }'
  fi
}

aws_s3_ls_bucket_size() {
  RESULT=$(aws s3api list-objects --bucket "${1}" --output json --query "sum(Contents[].Size)" 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  else
    echo '-1'
  fi
}

####

get_ecs_fargate_task_count() {
  REGION=$1
  ECS_FARGATE_CLUSTERS=$(aws_ecs_list_clusters "${REGION}")

  XIFS=$IFS
  # shellcheck disable=SC2206
  IFS=$'\n' ECS_FARGATE_CLUSTERS_LIST=($ECS_FARGATE_CLUSTERS)
  IFS=$XIFS

  ECS_FARGATE_TASK_LIST_COUNT=0
  RESULT=0

  for CLUSTER in "${ECS_FARGATE_CLUSTERS_LIST[@]}"
  do
    ECS_FARGATE_TASK_LIST_COUNT=($(aws_ecs_list_tasks "${REGION}" --cluster "${CLUSTER}" --desired-status running --output json | jq -r '[.taskArns[]] | length' 2>/dev/null))
    RESULT=$((RESULT + ECS_FARGATE_TASK_LIST_COUNT))
  done
  echo "${RESULT}"
}

get_s3_bucket_list() {
  S3_BUCKETS=$(aws_s3api_list_buckets | jq -r '.[]' 2>/dev/null)

  XIFS=$IFS
  # shellcheck disable=SC2206
  IFS=$'\n' S3_BUCKETS_LIST=($S3_BUCKETS)
  IFS=$XIFS
}

####

get_region_list() {
  echo "###################################################################################"
  echo "Querying AWS Regions"

  REGIONS=$(aws_ec2_describe_regions | jq -r '.Regions[] | .RegionName' 2>/dev/null | sort)

  XIFS=$IFS
  # shellcheck disable=SC2206
  IFS=$'\n' REGION_LIST=($REGIONS)
  IFS=$XIFS

  if [ ${#REGION_LIST[@]} -eq 0 ]; then
    echo "  Warning: Using default region list"
    REGION_LIST=(us-east-1 us-east-2 us-west-1 us-west-2 ap-south-1 ap-northeast-1 ap-northeast-2 ap-southeast-1 ap-southeast-2 eu-north-1 eu-central-1 eu-west-1 sa-east-1 eu-west-2 eu-west-3 ca-central-1)
  fi

  echo "  Total number of regions: ${#REGION_LIST[@]}"
  echo "###################################################################################"
  echo ""
}

get_account_list() {
  if [ "${USE_AWS_ORG}" = "true" ]; then
    echo "###################################################################################"
    echo "Querying AWS Organization"
    MASTER_ACCOUNT_ID=$(aws_organizations_describe_organization | jq -r '.Organization.MasterAccountId' 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "${MASTER_ACCOUNT_ID}" ]; then
      error_and_exit "Error: Failed to describe AWS Organization, check aws cli setup, and access to the AWS Organizations API."
    fi
    # Save current environment variables of the master account.
    MASTER_AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
    MASTER_AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
    MASTER_AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN
    #
    ACCOUNT_LIST=$(aws_organizations_list_accounts)
    if [ $? -ne 0 ] || [ -z "${ACCOUNT_LIST}" ]; then
      error_and_exit "Error: Failed to list AWS Organization accounts, check aws cli setup, and access to the AWS Organizations API."
    fi
    TOTAL_ACCOUNTS=$(echo "${ACCOUNT_LIST}" | jq '.Accounts | length' 2>/dev/null)
    echo "  Total number of member accounts: ${TOTAL_ACCOUNTS}"
    echo "###################################################################################"
    echo ""
  else
    MASTER_ACCOUNT_ID=""
    ACCOUNT_LIST=""
    TOTAL_ACCOUNTS=1
  fi
}

assume_role() {
  ACCOUNT_NAME="${1}"
  ACCOUNT_ID="${2}"
  echo "###################################################################################"
  echo "Processing Account: ${ACCOUNT_NAME} (${ACCOUNT_ID})"
  if [ "${ACCOUNT_ID}" = "${MASTER_ACCOUNT_ID}" ]; then
    echo "  Account is the master account, skipping assume role ..."
  else
    ACCOUNT_ASSUME_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/OrganizationAccountAccessRole"
    SESSION_JSON=$(aws_sts_assume_role "${ACCOUNT_ASSUME_ROLE_ARN}")
    if [ $? -ne 0 ] || [ -z "${SESSION_JSON}" ]; then
      ASSUME_ROLE_ERROR="true"
      echo "  Warning: Failed to assume role into Member Account ${ACCOUNT_NAME} (${ACCOUNT_ID}), skipping ..."
    else
      # Export environment variables used to connect to this member account.
      AWS_ACCESS_KEY_ID=$(echo "${SESSION_JSON}"     | jq .Credentials.AccessKeyId     2>/dev/null | sed -e 's/^"//' -e 's/"$//')
      AWS_SECRET_ACCESS_KEY=$(echo "${SESSION_JSON}" | jq .Credentials.SecretAccessKey 2>/dev/null | sed -e 's/^"//' -e 's/"$//')
      AWS_SESSION_TOKEN=$(echo "${SESSION_JSON}"     | jq .Credentials.SessionToken    2>/dev/null | sed -e 's/^"//' -e 's/"$//')
      export AWS_ACCESS_KEY_ID
      export AWS_SECRET_ACCESS_KEY
      export AWS_SESSION_TOKEN
    fi
  fi
  echo "###################################################################################"
  echo ""
}

##########################################################################################
# Unset environment variables used to assume role into the last member account.
##########################################################################################

unassume_role() {
  AWS_ACCESS_KEY_ID=$MASTER_AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY=$MASTER_AWS_SECRET_ACCESS_KEY
  AWS_SESSION_TOKEN=$MASTER_AWS_SESSION_TOKEN
}

##########################################################################################
## Set or reset counters.
##########################################################################################

reset_account_counters() {
  EC2_INSTANCE_COUNT=0
  RDS_INSTANCE_COUNT=0
  NATGW_COUNT=0
  REDSHIFT_COUNT=0
  ELB_COUNT=0
  LAMBDA_COUNT=0
  ECS_FARGATE_TASK_COUNT=0
  S3_BUCKETS_SIZE=0
}

reset_global_counters() {
  EC2_INSTANCE_COUNT_GLOBAL=0
  RDS_INSTANCE_COUNT_GLOBAL=0
  REDSHIFT_COUNT_GLOBAL=0
  NATGW_COUNT_GLOBAL=0
  ELB_COUNT_GLOBAL=0
  LAMBDA_COUNT_GLOBAL=0
  ECS_FARGATE_TASK_COUNT_GLOBAL=0
  S3_BUCKETS_SIZE_GLOBAL=0
  S3_BUCKETS_CREDIT_EXPOSURE_USAGE_GLOBAL=0
  S3_BUCKETS_CREDIT_FULL_USAGE_GLOBAL=0
  WORKLOAD_COUNT_GLOBAL=0
  WORKLOAD_COUNT_GLOBAL_WITH_IAM_MODULE=0
  LAMBDA_CREDIT_USAGE_GLOBAL=0
  COMPUTE_CREDIT_USAGE_GLOBAL=0
}

##########################################################################################
## Iterate through the (or each member) account, region, and billable resource type.
##########################################################################################

count_account_resources() {
  for ((ACCOUNT_INDEX=0; ACCOUNT_INDEX<=(TOTAL_ACCOUNTS-1); ACCOUNT_INDEX++))
  do
    if [ "${USE_AWS_ORG}" = "true" ]; then
      ACCOUNT_NAME=$(echo "${ACCOUNT_LIST}" | jq -r .Accounts["${ACCOUNT_INDEX}"].Name 2>/dev/null)
      ACCOUNT_ID=$(echo "${ACCOUNT_LIST}"   | jq -r .Accounts["${ACCOUNT_INDEX}"].Id   2>/dev/null)
      ASSUME_ROLE_ERROR=""
      assume_role "${ACCOUNT_NAME}" "${ACCOUNT_ID}"
      if [ -n "${ASSUME_ROLE_ERROR}" ]; then
        continue
      fi
    fi

    echo "###################################################################################"
    echo "Running EC2 Instances"
    for i in "${REGION_LIST[@]}"
    do
      RESOURCE_COUNT=$(aws_ec2_describe_instances "${i}" | jq '[ .Reservations[].Instances[] ] | length' 2>/dev/null)
      echo "  Count of Running EC2 Instances in Region ${i}: ${RESOURCE_COUNT}"
      EC2_INSTANCE_COUNT=$((EC2_INSTANCE_COUNT + RESOURCE_COUNT))
    done
    echo "Total EC2 Instances across all regions: ${EC2_INSTANCE_COUNT}"
    echo "###################################################################################"
    echo ""

    echo "###################################################################################"
    echo "RDS Instances"
    for i in "${REGION_LIST[@]}"
    do
      RESOURCE_COUNT=$(aws_ec2_describe_db_instances "${i}" | jq '.[] | length' 2>/dev/null)
      echo "  Count of RDS Instances in Region ${i}: ${RESOURCE_COUNT}"
      RDS_INSTANCE_COUNT=$((RDS_INSTANCE_COUNT + RESOURCE_COUNT))
    done
    echo "Total RDS Instances across all regions: ${RDS_INSTANCE_COUNT}"
    echo "###################################################################################"
    echo ""

    echo "###################################################################################"
    echo "NAT Gateways"
    for i in "${REGION_LIST[@]}"
    do
      RESOURCE_COUNT=$(aws_ec2_describe_nat_gateways "${i}" | jq '.[] | length' 2>/dev/null)
      echo "  Count of NAT Gateways in Region ${i}: ${RESOURCE_COUNT}"
      NATGW_COUNT=$((NATGW_COUNT + RESOURCE_COUNT))
    done
    echo "Total NAT Gateways across all regions: ${NATGW_COUNT}"
    echo "###################################################################################"
    echo ""

    echo "###################################################################################"
    echo "RedShift Clusters"
    for i in "${REGION_LIST[@]}"
    do
      RESOURCE_COUNT=$(aws_redshift_describe_clusters "${i}" | jq '.[] | length' 2>/dev/null)
      echo "  Count of RedShift Clusters in Region: ${i}: ${RESOURCE_COUNT}"
      REDSHIFT_COUNT=$((REDSHIFT_COUNT + RESOURCE_COUNT))
    done
    echo "Total RedShift Clusters across all regions: ${REDSHIFT_COUNT}"
    echo "###################################################################################"
    echo ""

    echo "###################################################################################"
    echo "ELBs"
    for i in "${REGION_LIST[@]}"
    do
      RESOURCE_COUNT=$(aws_elb_describe_load_balancers "${i}" | jq '.[] | length' 2>/dev/null)
      echo " Count of ELBs in Region ${i}: ${RESOURCE_COUNT}"
      ELB_COUNT=$((ELB_COUNT + RESOURCE_COUNT))
    done
    echo "Total ELBs across all regions: ${ELB_COUNT}"
    echo "###################################################################################"
    echo ""

    if [ "${WITH_CWP}" = "true" ]; then

      echo "###################################################################################"
      echo "Lambda Functions"
      for i in "${REGION_LIST[@]}"
      do
        RESOURCE_COUNT=$(aws_lambda_get_account_settings "${i}" | jq '.AccountUsage.FunctionCount' 2>/dev/null)
        echo " Count of Lambda Functions in Region ${i}: ${RESOURCE_COUNT}"
        LAMBDA_COUNT=$((LAMBDA_COUNT + RESOURCE_COUNT))
      done
      echo "Total Lambda Functions across all regions: ${LAMBDA_COUNT}"
      echo "###################################################################################"
      echo ""

      echo "###################################################################################"
      echo "ECS Fargate Tasks"
      for i in "${REGION_LIST[@]}"
      do
        RESOURCE_COUNT=$(get_ecs_fargate_task_count "${i}")
        echo "  Count of Running ECS Tasks in Region ${i}: ${RESOURCE_COUNT}"
        ECS_FARGATE_TASK_COUNT=$((ECS_FARGATE_TASK_COUNT + RESOURCE_COUNT))
      done
      echo "Total ECS Fargate Task Count (Instances) across all regions: ${ECS_FARGATE_TASK_COUNT}"
      echo "###################################################################################"
      echo ""

    fi

    if [ "${WITH_DATA}" = "true" ]; then
      echo "###################################################################################"
      echo "S3 Bucket Sizes"
      get_s3_bucket_list
      for i in "${S3_BUCKETS_LIST[@]}"
        do
        S3_BUCKET_SIZE=$(aws_s3_ls_bucket_size "${i}" 2>/dev/null)
        echo "  Size of S3 Bucket ${i}: ${S3_BUCKET_SIZE} bytes"
        S3_BUCKETS_SIZE=$((S3_BUCKETS_SIZE + S3_BUCKET_SIZE))
      done
      echo "Total S3 Buckets Size: ${S3_BUCKETS_SIZE} bytes"
      echo "###################################################################################"
      echo ""
    fi

    EC2_INSTANCE_COUNT_GLOBAL=$((EC2_INSTANCE_COUNT_GLOBAL + EC2_INSTANCE_COUNT))
    RDS_INSTANCE_COUNT_GLOBAL=$((RDS_INSTANCE_COUNT_GLOBAL + RDS_INSTANCE_COUNT))
    NATGW_COUNT_GLOBAL=$((NATGW_COUNT_GLOBAL + NATGW_COUNT))
    REDSHIFT_COUNT_GLOBAL=$((REDSHIFT_COUNT_GLOBAL + REDSHIFT_COUNT))
    ELB_COUNT_GLOBAL=$((ELB_COUNT_GLOBAL + ELB_COUNT))
    LAMBDA_COUNT_GLOBAL=$((LAMBDA_COUNT_GLOBAL + LAMBDA_COUNT))
    ECS_FARGATE_TASK_COUNT_GLOBAL=$((ECS_FARGATE_TASK_COUNT_GLOBAL + ECS_FARGATE_TASK_COUNT))
    S3_BUCKETS_SIZE_GLOBAL=$((S3_BUCKETS_SIZE_GLOBAL + S3_BUCKETS_SIZE))

    reset_account_counters

    if [ "${USE_AWS_ORG}" = "true" ]; then
      unassume_role
    fi
  done

  WORKLOAD_COUNT_GLOBAL=$((EC2_INSTANCE_COUNT_GLOBAL + RDS_INSTANCE_COUNT_GLOBAL + NATGW_COUNT_GLOBAL + REDSHIFT_COUNT_GLOBAL + ELB_COUNT_GLOBAL))
  WORKLOAD_COUNT_GLOBAL_WITH_IAM_MODULE=$((WORKLOAD_COUNT_GLOBAL*125/100))
  echo "###################################################################################"
  echo "CSPM: Total Billable Resources:"
  echo "  Count of EC2 Instances:     ${EC2_INSTANCE_COUNT_GLOBAL}"
  echo "  Count of RDS Instances:     ${RDS_INSTANCE_COUNT_GLOBAL}"
  echo "  Count of NAT Gateways:      ${NATGW_COUNT_GLOBAL}"
  echo "  Count of RedShift Clusters: ${REDSHIFT_COUNT_GLOBAL}"
  echo "  Count of ELBs:              ${ELB_COUNT_GLOBAL}"
  echo ""
  echo "CSPM: Total Credit Consumption: ${WORKLOAD_COUNT_GLOBAL}"
  echo "(If using the IAM Security Module: ${WORKLOAD_COUNT_GLOBAL_WITH_IAM_MODULE})"
  echo "###################################################################################"

  if [ "${WITH_CWP}" = "true" ]; then
    LAMBDA_CREDIT_USAGE_GLOBAL=$((LAMBDA_COUNT_GLOBAL/6))
    COMPUTE_CREDIT_USAGE_GLOBAL=$((LAMBDA_CREDIT_USAGE_GLOBAL + ECS_FARGATE_TASK_COUNT_GLOBAL))
    echo ""
    echo "###################################################################################"
    echo "CWP Total Credit Consumption:"
    echo "  Count of Lambda Functions: ${LAMBDA_COUNT_GLOBAL} Credit Consumption: ${LAMBDA_CREDIT_USAGE_GLOBAL}"
    echo "  Count of ECS Fargate Tasks: ${ECS_FARGATE_TASK_COUNT_GLOBAL}"
    echo ""
    echo "CWP Total Credit Consumption: ${COMPUTE_CREDIT_USAGE_GLOBAL}"
    echo "###################################################################################"
  fi

  if [ "${WITH_DATA}" = "true" ]; then
    S3_BUCKETS_SIZE_GIG_GLOBAL=$((S3_BUCKETS_SIZE_GLOBAL/1000/1000/1000))
    S3_BUCKETS_CREDIT_EXPOSURE_USAGE_GLOBAL=$((S3_BUCKETS_SIZE_GIG_GLOBAL/200))
    S3_BUCKETS_CREDIT_FULL_USAGE_GLOBAL=$((S3_BUCKETS_SIZE_GIG_GLOBAL/33))
    echo ""
    echo "###################################################################################"
    echo "Data Security Total Size:"
    echo "  Bytes: ${S3_BUCKETS_SIZE_GLOBAL}"
    echo "  GB:    ${S3_BUCKETS_SIZE_GIG_GLOBAL}"
    echo "Data Security Total Credit Consumption (based upon GB):"
    echo "  For Exposure Scan: ${S3_BUCKETS_CREDIT_EXPOSURE_USAGE_GLOBAL}"
    echo "  For Full Scan:     ${S3_BUCKETS_CREDIT_FULL_USAGE_GLOBAL}"
    echo "###################################################################################"
  fi

  echo ""
  echo "Totals are based upon resource counts at the time that this script is executed."
  echo "If you have any questions/concerns, please see the following licensing guide:"
  echo "https://www.paloaltonetworks.com/resources/guides/prisma-cloud-enterprise-edition-licensing-guide"
}

##########################################################################################
# Allow shellspec to source this script.
##########################################################################################

${__SOURCED__:+return}

##########################################################################################
# Main.
##########################################################################################

get_account_list
get_region_list
reset_account_counters
reset_global_counters
count_account_resources
