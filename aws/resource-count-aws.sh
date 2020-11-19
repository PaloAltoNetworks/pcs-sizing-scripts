#!/bin/bash
aws_regions=(us-east-1 us-east-2 us-west-1 us-west-2 ap-south-1 ap-northeast-1 ap-northeast-2 ap-southeast-1 ap-southeast-2 eu-north-1 eu-central-1 eu-west-1 sa-east-1 eu-west-2 eu-west-3 ca-central-1)

echo "Total regions: "${#aws_regions[@]}

ec2_instance_count=0;
rds_instance_count=0;
elb_count=0;
redshift_count=0;
natgw_count=0;


for i in "${aws_regions[@]}"
do
   count=`aws ec2 describe-instances --max-items 100000 --region=$i --filters  "Name=instance-state-name,Values=running"  --output json    |jq '.[] | length'`
   echo "Region=$i EC2 instance(s) in running state = "$count
   ec2_instance_count=`expr $ec2_instance_count + $count`
done

echo "Total count of ec2 instances across all regions: "$ec2_instance_count
echo ""

for i in "${aws_regions[@]}"
do
   count=`aws rds describe-db-instances --region=$i --output json   |jq '.[] | length'`
   echo "Region=$i RDS instance(s) = "$count
   rds_instance_count=`expr $rds_instance_count + $count`
done
echo "Total count of RDS instances across all regions: "$rds_instance_count
echo ""


for i in "${aws_regions[@]}"
do
   count=`aws elb describe-load-balancers --region=$i --output json  | jq '.[] | length'`
   echo "Region=$i ELBs= "$count
   elb_count=`expr $elb_count + $count`
done
echo "Total count of ELBs across all regions: "$elb_count
echo ""

for i in "${aws_regions[@]}"
do
   count=`aws ec2 describe-nat-gateways --region=$i --output json   |jq '.[] | length'`
   echo "Region=$i NAT Gateway instances = "$count
   natgw_count=`expr $natgw_count + $count`
done
echo "Total count of NAT gateways across all regions: "$natgw_count
echo ""

#redshift
for i in "${aws_regions[@]}"
do
   count=`aws redshift describe-clusters --region=$i --output json   |jq '.[] | length'`
   echo "Region=$i Redshift instances = "$count
   redshift_count=`expr $redshift_count + $count`
done
echo "Total count of Redshift clusters across all regions: "$redshift_count
echo ""




echo ""
echo ""
echo "Total count of ec2 instances across all regions: "$ec2_instance_count
echo "Total count of RDS instances across all regions: "$rds_instance_count
echo "Total count of ELB (Classic) instances across all regions: "$elb_count
echo "Total count of Redshift clusters across all regions: "$redshift_count
echo "Total count of NAT gateways across all regions: "$natgw_count
echo "Total billable resources:"$((ec2_instance_count+rds_instance_count+elb_count+redshift_count+natgw_count))

