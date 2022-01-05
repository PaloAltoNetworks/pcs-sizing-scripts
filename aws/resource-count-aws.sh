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

if [ "${1}X" == "orgX" ]; then
   USE_AWS_ORG="true"
else
   USE_AWS_ORG="false"
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
  RESULT=$(aws sts assume-role --role-arn="${1}" --role-session-name=prisma-cloud-sizing-resources --duration-seconds=999 --output json 2>/dev/null)
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
  unset AWS_ACCESS_KEY_ID
  unset AWS_SECRET_ACCESS_KEY
  unset AWS_SESSION_TOKEN
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
  WORKLOAD_COUNT=0
}

reset_global_counters() {
  EC2_INSTANCE_COUNT_GLOBAL=0
  RDS_INSTANCE_COUNT_GLOBAL=0
  REDSHIFT_COUNT_GLOBAL=0
  NATGW_COUNT_GLOBAL=0
  ELB_COUNT_GLOBAL=0
  WORKLOAD_COUNT_GLOBAL=0
  WORKLOAD_COUNT_GLOBAL_WITH_IAM_MODULE=0
}

##########################################################################################
## Iterate through the (or each member) account, region, and billable resource type.
##########################################################################################

count_account_resources() {
  for ((ACCOUNT_INDEX=0; ACCOUNT_INDEX<=(TOTAL_ACCOUNTS-1); ACCOUNT_INDEX++))
  do
    if [ "${USE_AWS_ORG}" = "true" ]; then
      ACCOUNT_NAME=$(echo "${ACCOUNT_LIST}" | jq -r .Accounts[$ACCOUNT_INDEX].Name 2>/dev/null)
      ACCOUNT_ID=$(echo "${ACCOUNT_LIST}"   | jq -r .Accounts[$ACCOUNT_INDEX].Id   2>/dev/null)
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
      RESOURCE_COUNT=$(aws_ec2_describe_instances "${i}" | jq '.[] | length' 2>/dev/null)
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

    if [ "${USE_AWS_ORG}" = "true" ]; then
      WORKLOAD_COUNT=$((EC2_INSTANCE_COUNT + RDS_INSTANCE_COUNT + REDSHIFT_COUNT + NATGW_COUNT + ELB_COUNT))
      echo "###################################################################################"
      echo "Member Account Totals"
      echo "Total billable resources for Member Account ${ACCOUNT_NAME} ($ACCOUNT_ID): ${WORKLOAD_COUNT}"
      echo "###################################################################################"
      echo ""
    fi

    EC2_INSTANCE_COUNT_GLOBAL=$((EC2_INSTANCE_COUNT_GLOBAL + EC2_INSTANCE_COUNT))
    RDS_INSTANCE_COUNT_GLOBAL=$((RDS_INSTANCE_COUNT_GLOBAL + RDS_INSTANCE_COUNT))
    NATGW_COUNT_GLOBAL=$((NATGW_COUNT_GLOBAL + NATGW_COUNT))
    REDSHIFT_COUNT_GLOBAL=$((REDSHIFT_COUNT_GLOBAL + REDSHIFT_COUNT))
    ELB_COUNT_GLOBAL=$((ELB_COUNT_GLOBAL + ELB_COUNT))

    reset_account_counters

    if [ "${USE_AWS_ORG}" = "true" ]; then
      unassume_role
    fi
  done

  WORKLOAD_COUNT_GLOBAL=$((EC2_INSTANCE_COUNT_GLOBAL + RDS_INSTANCE_COUNT_GLOBAL + NATGW_COUNT_GLOBAL + REDSHIFT_COUNT_GLOBAL + ELB_COUNT_GLOBAL))
  WORKLOAD_COUNT_GLOBAL_WITH_IAM_MODULE=$((WORKLOAD_COUNT_GLOBAL*125/100))

  echo "###################################################################################"
  echo "Totals"
  echo "  Count of EC2 Instances across all regions: ${EC2_INSTANCE_COUNT_GLOBAL}"
  echo "  Count of RDS Instances across all regions: ${RDS_INSTANCE_COUNT_GLOBAL}"
  echo "  Count of NAT Gateways across all regions: ${NATGW_COUNT_GLOBAL}"
  echo "  Count of RedShift Clusters across all regions: ${REDSHIFT_COUNT_GLOBAL}"
  echo "  Count of ELBs across all regions: ${ELB_COUNT_GLOBAL}"
  echo "Total billable resources: ${WORKLOAD_COUNT_GLOBAL}"
  echo "(If you will be using the IAM Security Module, total billable resources will be: ${WORKLOAD_COUNT_GLOBAL_WITH_IAM_MODULE})"
  echo "###################################################################################"
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
