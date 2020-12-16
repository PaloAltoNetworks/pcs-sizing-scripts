#!/bin/bash

# shellcheck disable=SC2003,SC2102,SC2181,SC2188,SC2207

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
## Optionally define organization variables.
##########################################################################################

if [ "${USE_AWS_ORG}" = "true" ]; then
  echo "###################################################################################"
  echo "Querying AWS Organization"
  echo "###################################################################################"
  master_account_id=$(aws organizations describe-organization --output json | jq -r '.Organization.MasterAccountId')
  if [ $? -ne 0 ] || [ -z "${master_account_id}" ]; then 1>&2
    echo ""
    echo "Error: Failed to describe AWS Organization, check aws cli setup, and access to the AWS Organizations API."
    echo ""
    exit 1
  fi
  account_list=$(aws organizations list-accounts --output json)
  if [ $? -ne 0 ]; then 1>&2
    echo ""
    echo "Error: Failed to list AWS Organization accounts, check aws cli setup, and access to the AWS Organizations API."
    echo ""
    exit 1
  fi
  total_accounts=$(echo "${account_list}" | jq '.Accounts | length')
  echo ""
  echo "Total number of member accounts is: ${total_accounts}"
  echo ""
else
  account_list=""
  total_accounts=1
fi

##########################################################################################
## Define region and count variables.
##########################################################################################

echo "###################################################################################"
echo "Querying AWS Regions"
echo "###################################################################################"
echo ""

XIFS=$IFS
IFS=$'\n' aws_regions=($(aws ec2 describe-regions 2>/dev/null | jq -r '.Regions[] | .RegionName' | sort))
IFS=$XIFS

if [ ${#aws_regions[@]} -eq 0 ]; then
  echo "Using default regions"
  aws_regions=(us-east-1 us-east-2 us-west-1 us-west-2 ap-south-1 ap-northeast-1 ap-northeast-2 ap-southeast-1 ap-southeast-2 eu-north-1 eu-central-1 eu-west-1 sa-east-1 eu-west-2 eu-west-3 ca-central-1)
fi

echo "Total number of regions: ${#aws_regions[@]}"
echo ""

ec2_instance_count=0
rds_instance_count=0
natgw_count=0
redshift_count=0
elb_count=0
workload_count=0

ec2_instance_count_global=0
rds_instance_count_global=0
redshift_count_global=0
natgw_count_global=0
elb_count_global=0

##########################################################################################
## Iterate through each account, region, and billable resource type.
##########################################################################################

for ((account_process=0; account_process<=(total_accounts-1); account_process++))
  do
    if [ "${USE_AWS_ORG}" = "true" ]; then
      account_name=$(echo "${account_list}" | jq -r .Accounts[$account_process].Name)
      account_id=$(echo "${account_list}" | jq -r .Accounts[$account_process].Id)
      echo ""
      echo "###################################################################################"
      echo "Processing Member Account: ${account_name} (${account_id})"
      echo "###################################################################################"
      echo ""
      if [[ account_id -eq master_account_id ]]; then 
        echo ""
        echo "Processing Master Account, skipping assume role"
        echo ""
      else  
        account_assume_role_arn=arn:aws:iam::${account_id}:role/OrganizationAccountAccessRole
        session_json=$(aws sts assume-role --role-arn="${account_assume_role_arn}" --role-session-name=prisma-cloud-sizing-resources --duration-seconds=900 --output json)
        if [ $? -ne 0 ]; then 1>&2
          echo ""
          echo "Failed to assume role into Member Account ${account_name} (${account_id}), skipping ..."
          echo ""
          continue
        fi
        # Set environment variables used to connect to this account.
        AWS_ACCESS_KEY_ID=$(echo "${session_json}" | jq .Credentials.AccessKeyId | sed -e 's/^"//' -e 's/"$//')
        AWS_SECRET_ACCESS_KEY=$(echo "${session_json}" | jq .Credentials.SecretAccessKey | sed -e 's/^"//' -e 's/"$//')
        AWS_SESSION_TOKEN=$(echo "${session_json}" | jq .Credentials.SessionToken | sed -e 's/^"//' -e 's/"$//')
        export AWS_ACCESS_KEY_ID
        export AWS_SECRET_ACCESS_KEY
        export AWS_SESSION_TOKEN
      fi
      echo ""
    fi

    echo "# EC2 Instances ###################################################################"
    for i in "${aws_regions[@]}"
    do
      count=$(aws ec2 describe-instances --max-items 100000 --region="${i}" --filters  "Name=instance-state-name,Values=running" --output json | jq '.[] | length')
      echo "Region = ${i} EC2 Instances in running state = ${count}"
      ec2_instance_count=$((ec2_instance_count + count))
    done
    echo "###################################################################################"
    echo "Count of EC2 Instances across all regions: ${ec2_instance_count}"
    echo "###################################################################################"
    echo ""

    echo "# RDS Instances ###################################################################"
    for i in "${aws_regions[@]}"
    do
      count=$(aws rds describe-db-instances --region="${i}" --output json | jq '.[] | length')
      echo "Region = ${i} RDS Instances in running state = ${count}"
      rds_instance_count=$((rds_instance_count + count))
    done
    echo "###################################################################################"
    echo "Count of RDS Instances across all regions: ${rds_instance_count}"
    echo "###################################################################################"
    echo ""

    echo "# NAT Gateways ####################################################################"
    for i in "${aws_regions[@]}"
    do
      count=$(aws ec2 describe-nat-gateways --region="${i}" --output json | jq '.[] | length')
      echo "Region = ${i} NAT Gateways = ${count}"
      natgw_count=$((natgw_count + count))
    done
    echo "###################################################################################"
    echo "Count of NAT Gateways across all regions: ${natgw_count}"
    echo "###################################################################################"
    echo ""

    echo "# RedShift Clusters ###############################################################"
    for i in "${aws_regions[@]}"
    do
      count=$(aws redshift describe-clusters --region="${i}" --output json | jq '.[] | length')
      echo "Region = ${i} RedShift Clusters in running state = ${count}"
      redshift_count=$((redshift_count + count))
    done
    echo "###################################################################################"
    echo "Count of RedShift Clusters across all regions: ${redshift_count}"
    echo "###################################################################################"
    echo ""

    echo "# ELBs ############################################################################"
    for i in "${aws_regions[@]}"
    do
      count=$(aws elb describe-load-balancers --region="${i}" --output json | jq '.[] | length')
      echo "Region = ${i} ELBs = ${count}"
      elb_count=$((elb_count + count))
    done
    echo "###################################################################################"
    echo "Count of ELBs across all regions: ${elb_count}"
    echo "###################################################################################"
    echo ""

    if [ "${USE_AWS_ORG}" = "true" ]; then
      echo ""
      echo "# Member Account Totals ##################################################################"
      echo "###################################################################################"
      workload_count=$(expr $ec2_instance_count + $rds_instance_count + $redshift_count + $natgw_count + $elb_count)
      echo "Total billable resources for Member Account ${account_name} ($account_id): ${workload_count}"
      echo "###################################################################################"
      echo ""
    fi

    # Increment global variables.
    ec2_instance_count_global=$(expr $ec2_instance_count_global + $ec2_instance_count)
    rds_instance_count_global=$(expr $rds_instance_count_global + $rds_instance_count)
    natgw_count_global=$(expr $natgw_count_global + $natgw_count)
    redshift_count_global=$(expr $redshift_count_global + $redshift_count)
    elb_count_global=$(expr $elb_count_global + $elb_count)

    # Reset account variables.
    ec2_instance_count=0
    rds_instance_count=0
    natgw_count=0
    redshift_count=0
    elb_count=0
    workload_count=0

    if [ "${USE_AWS_ORG}" = "true" ]; then
      # Unset environment variables used to connect to this account.
      unset AWS_ACCESS_KEY_ID
      unset AWS_SECRET_ACCESS_KEY
      unset AWS_SESSION_TOKEN
    fi
done

##########################################################################################
## Output totals.
##########################################################################################

echo ""
echo "# Totals ##########################################################################"
echo "Total count of EC2 Instances across all regions: ${ec2_instance_count_global}"
echo "Total count of RDS Instances across all regions: ${rds_instance_count_global}"
echo "Total count of NAT Gateways across all regions: ${natgw_count_global}"
echo "Total count of RedShift Clusters across all regions: ${redshift_count_global}"
echo "Total count of ELBs across all regions: ${elb_count_global}"
echo "###################################################################################"
echo "Total billable resources: $((ec2_instance_count_global + rds_instance_count_global + natgw_count_global + redshift_count_global + elb_count_global))"
echo "###################################################################################"
