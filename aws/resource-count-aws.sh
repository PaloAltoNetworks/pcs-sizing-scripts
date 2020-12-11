#!/bin/bash

# shellcheck disable=SC2003,SC2102,SC2188,SC2207

##########################################################################################
## Use of jq is required by this script.
##########################################################################################

if ! type "jq" > /dev/null; then
  echo "Error: jq not installed or not in execution path, jq is required for script execution."
  exit $?
fi

##########################################################################################
## Define script variables.
##########################################################################################

XIFS=$IFS
IFS=$'\n' aws_regions=($(aws ec2 describe-regions 2>/dev/null | jq -r '.Regions[] | .RegionName' | sort))
XIFS=$XIFS

if [ ${#aws_regions[@]} -eq 0 ]; then
   echo "Using default regions"
   aws_regions=(us-east-1 us-east-2 us-west-1 us-west-2 ap-south-1 ap-northeast-1 ap-northeast-2 ap-southeast-1 ap-southeast-2 eu-north-1 eu-central-1 eu-west-1 sa-east-1 eu-west-2 eu-west-3 ca-central-1)
fi

echo "Total number of regions: ${#aws_regions[@]}"
echo

ec2_instance_count=0
rds_instance_count=0
natgw_count=0
redshift_count=0
elb_count=0
elbv2_count=0

##########################################################################################
## Iterate through each region and type.
##########################################################################################

echo "EC2 instances"
for i in "${aws_regions[@]}"
do
   count=$(aws ec2 describe-instances --max-items 100000 --region="${i}" --filters  "Name=instance-state-name,Values=running" --output json | jq '.[] | length')
   echo "Region = ${i} EC2 instance(s) in running state = ${count}"
   ec2_instance_count=$((ec2_instance_count + count))
done
echo "Total count of EC2 instances across all regions: ${ec2_instance_count}"
echo

echo "RDS instances"
for i in "${aws_regions[@]}"
do
   count=$(aws rds describe-db-instances --region="${i}" --output json | jq '.[] | length')
   echo "Region = ${i} RDS instance(s) in running state = ${count}"
   rds_instance_count=$((rds_instance_count + count))
done
echo "Total count of RDS instances across all regions: ${rds_instance_count}"
echo

echo "NAT Gateways"
for i in "${aws_regions[@]}"
do
   count=$(aws ec2 describe-nat-gateways --region="${i}" --output json | jq '.[] | length')
   echo "Region = ${i} NAT Gateway instances = ${count}"
   natgw_count=$((natgw_count + count))
done
echo "Total count of NAT Gateways across all regions: ${natgw_count}"
echo

echo "RedShift Clusters"
for i in "${aws_regions[@]}"
do
   count=$(aws redshift describe-clusters --region="${i}" --output json | jq '.[] | length')
   echo "Region = ${i} RedShift Cluster instances in running state = ${count}"
   redshift_count=$((redshift_count + count))
done
echo "Total count of RedShift Clusters across all regions: ${redshift_count}"
echo

echo "ELBs"
for i in "${aws_regions[@]}"
do
   count=$(aws elb describe-load-balancers --region="${i}" --output json | jq '.[] | length')
   echo "Region = ${i} ELBs = ${count}"
   elb_count=$((elb_count + count))
done
echo "Total count of ELBs across all regions: ${elb_count}"
echo

echo "Application ELBs"
for i in "${aws_regions[@]}"
do
   count=$(aws elbv2 describe-load-balancers --region="${i}" --output json | jq '.[] | length')
   echo "Region = ${i} Application ELBs = ${count}"
   elbv2_count=$((elbv2_count + count))
done
echo "Total count of Application ELBs across all regions: ${elbv2_count}"
echo

##########################################################################################
## Output totals.
##########################################################################################

echo
echo "###################################################################################"
echo "Total count of EC2 Instances across all regions: ${ec2_instance_count}"
echo "Total count of RDS Instances across all regions: ${rds_instance_count}"
echo "Total count of NAT Gateways across all regions: ${natgw_count}"
echo "Total count of RedShift Clusters across all regions: ${redshift_count}"
echo "Total count of ELBs across all regions: ${elb_count}"
echo "Total count of Application ELBs across all regions: ${elbv2_count}"
echo
echo "Total billable resources: $((ec2_instance_count + rds_instance_count + natgw_count + redshift_count + elb_count + elbv2_count))"
echo "###################################################################################"