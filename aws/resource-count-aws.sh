#!/bin/bash

# Check for jq dependency
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install jq to run this script."
    echo "(e.g., 'sudo apt-get install jq' or 'sudo yum install jq' or 'brew install jq')"
    exit 1
fi
# Function to handle errors
function check_error {
    local exit_code=$1
    local message=$2
    if [ $exit_code -ne 0 ]; then
        echo "Error: $message (Exit Code: $exit_code)"
        # Optionally unset credentials if in org mode before exiting
        if [ "$ORG_MODE" == true ] && [ -n "$AWS_SESSION_TOKEN" ]; then
            unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
        fi
        exit $exit_code
    fi
}


function printHelp {
    echo ""
    echo "NOTES:"
    echo "* Requires AWS CLI v2 to execute"
    echo "* Requires JQ utility to be installed (TODO: Install JQ from script; exists in AWS)"
    echo "* Validated to run successfully from within CSP console CLIs"

    echo "Available flags:"
    echo " -c          Connect via SSM to EC2 instances running DBs in combination with DSPM mode"
    echo " -d          DSPM mode"
    echo "             This option will search for and count resources that are specific to data security"
    echo "             posture management (DSPM) licensing."
    echo " -h          Display the help info"
    echo " -n <region> Single region to scan"
    echo " -o          Organization mode"
    echo "             This option will fetch all sub-accounts associated with an organization"
    echo "             and assume the default (or specified) cross account role in order to iterate through and"
    echo "             scan resources in each sub-account. This is typically run from the admin user in"
    echo "             the master account."
    echo " -r <role>   Specify a non default role to assume in combination with organization mode"
    echo " -s          Include stopped compute instances in addition to running"
    exit 1
}

spinpid=
function __startspin {
	# start the spinner
	set +m
	{ while : ; do for X in '  •     ' '   •    ' '    •   ' '     •  ' '      • ' '     •  ' '    •   ' '   •    ' '  •     ' ' •      ' ; do echo -en "\b\b\b\b\b\b\b\b$X" ; sleep 0.1 ; done ; done & } 2>/dev/null
	spinpid=$!
}

function __stopspin {
	# stop the spinner
	{ kill -9 $spinpid && wait; } 2>/dev/null
	set -m
	echo -en "\033[2K\r"
}


echo ''
echo '  ___     _                  ___ _             _  '
echo ' | _ \_ _(_)____ __  __ _   / __| |___ _  _ __| | '
echo ' |  _/ '\''_| (_-< '\''  \/ _` | | (__| / _ \ || / _` | '
echo ' |_| |_| |_/__/_|_|_\__,_|  \___|_\___/\_,_\__,_| '
echo ''                                                 

# Ensure AWS CLI is configured
aws sts get-caller-identity > /dev/null 2>&1
check_error $? "AWS CLI not configured or credentials invalid. Please run 'aws configure'."

# Initialize options
ORG_MODE=false
DSPM_MODE=false
ROLE="OrganizationAccountAccessRole"
REGION=""
STATE="running"

# Get options
while getopts ":cdhn:or:s" opt; do
  case ${opt} in
    c) SSM_MODE=true ;;
    d) DSPM_MODE=true ;;
    h) printHelp ;;
    n) REGION="$OPTARG" ;;
    o) ORG_MODE=true ;;
    r) ROLE="$OPTARG" ;;
    s) STATE="running,stopped" ;;
    *) echo "Invalid option: -${OPTARG}" && printHelp exit ;;
 esac
done
shift $((OPTIND-1))

# Get enabled regions for the current account context
echo "Fetching enabled regions for the account..."
activeRegions=$(aws account list-regions --region-opt-status-contains ENABLED ENABLED_BY_DEFAULT --query "Regions[].RegionName" --output text)
check_error $? "Failed to list enabled AWS regions. Ensure 'account:ListRegions' permission is granted and AWS CLI is up-to-date."

if [ -z "$activeRegions" ]; then
    echo "Error: Could not retrieve list of enabled regions."
    exit 1
fi
echo "Enabled regions found: $activeRegions"

# Validate region flag
if [[ "${REGION}" ]]; then
    # Use grep -w for whole word match to avoid partial matches (e.g., "us-east" matching "us-east-1")
    if echo "$activeRegions" | grep -qw "$REGION";
        then echo "Requested region is valid";
    else echo "Invalid region requested: $REGION";
    exit 1
    fi 
fi

if [ "$ORG_MODE" == true ]; then
  echo "Organization mode active"
  echo "Role to assume: $ROLE"
fi
if [ "$DSPM_MODE" == true ]; then
  echo "DSPM mode active"
fi

# Initialize counters
total_ec2_instances=0
total_eks_nodes=0
total_s3_buckets=0
total_efs=0
total_aurora=0
total_rds=0
total_dynamodb=0
total_redshift=0
total_ec2_db=0
ec2_db_count=0

# Functions
check_running_databases() {
    # # Ensure AWS CLI is configured
    # if ! aws sts get-caller-identity &>/dev/null; then
    #     echo "Please configure your AWS CLI using 'aws configure' before running this script."
    #     return 1
    # fi

    # Required ports for database identification
#    __startspin

    local DATABASE_PORTS=(3306 5432 27017 1433 33060)

    echo "Fetching all running EC2 instances..."
    if [[ "${REGION}" ]]; then
        local instances=$(aws ec2 describe-instances \
        --region $REGION --filters "Name=instance-state-name,Values=$STATE" \
        --query "Reservations[*].Instances[*].{ID:InstanceId,IP:PrivateIpAddress,Name:Tags[?Key=='Name']|[0].Value}" \
        --output json)  
    else
        local instances=$(aws ec2 describe-instances \
        --filters "Name=instance-state-name,Values=$STATE" \
        --query "Reservations[*].Instances[*].{ID:InstanceId,IP:PrivateIpAddress,Name:Tags[?Key=='Name']|[0].Value}" \
        --output json)    
    fi   

    # Check if any instances were returned
    if [[ -z "$instances" || "$instances" == "[]" ]]; then
        echo "No running EC2 instances found."
        return 0
    fi

    echo "  Found running EC2 instances. Checking each instance for database activity..."

    # Parse instances and check for databases
    for instance in $(echo "$instances" | jq -c '.[][]'); do
        local instance_id=$(echo "$instance" | jq -r '.ID')
        local private_ip=$(echo "$instance" | jq -r '.IP')
        local instance_name=$(echo "$instance" | jq -r '.Name // "Unnamed Instance"')

        echo "  Checking instance: $instance_name (ID: $instance_id, IP: $private_ip)"

        # Fetch security group details
        local sg_ids=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query "Reservations[0].Instances[0].SecurityGroups[*].GroupId" \
            --output text)

        echo "    Security Groups: $sg_ids"

        for sg_id in $sg_ids; do
            local open_ports=$(aws ec2 describe-security-groups \
                --group-ids "$sg_id" \
                --query "SecurityGroups[0].IpPermissions[*].FromPort" \
                --output text | tr '\t' ',' )

            echo "      Open Ports: $open_ports"

            # Check for database ports
            for port in "${DATABASE_PORTS[@]}"; do
                # Use grep -qw to check if the port exists as a whole word in the list of open ports
                if echo "$open_ports" | grep -qw "$port"; then
                    echo "      Database port $port detected in Security Group $sg_id"
                    # Optionally break here if finding one DB port is enough, or continue to list all found
                fi
            done
        done

        # Optional: Check for running database processes via Systems Manager
        if aws ssm describe-instance-information \
            --query "InstanceInformationList[?InstanceId=='$instance_id']" \
            --output text &>/dev/null; then
            echo "    Instance is managed by Systems Manager. Checking for database processes..."
            local command_id=$(aws ssm send-command \
                --instance-ids "$instance_id" \
                --document-name "AWS-RunShellScript" \
                --comment "Check for running database processes" \
                --parameters 'commands=["ps aux | grep -E \"postgres|mongo|mysql|mariadb|sqlserver\" | grep -v grep"]' \
                --query "Command.CommandId" --output text)
            check_error $? "Failed to send SSM command to instance $instance_id."

            if [ -z "$command_id" ]; then
                echo "    Warning: Failed to get Command ID for SSM check on $instance_id. Skipping process check."
                continue # Skip to next instance
            fi

            echo "    SSM Command ID: $command_id. Waiting for completion..."
            local ssm_status="Pending"
            local ssm_output=""
            local attempts=0
            local max_attempts=12 # Wait for max 60 seconds (12 * 5s)

            while [[ "$ssm_status" == "Pending" || "$ssm_status" == "InProgress" || "$ssm_status" == "Delayed" ]] && [ $attempts -lt $max_attempts ]; do
                sleep 5
                local invocation_details=$(aws ssm list-command-invocations --command-id "$command_id" --details --output json)
                # Check if invocation details were retrieved
                if [ -z "$invocation_details" ] || [ "$(echo "$invocation_details" | jq '.CommandInvocations | length')" -eq 0 ]; then
                     echo "    Warning: Could not retrieve SSM invocation details for $command_id. Retrying..."
                     attempts=$((attempts + 1))
                     continue
                fi
                ssm_status=$(echo "$invocation_details" | jq -r '.CommandInvocations[0].Status')
                ssm_output=$(echo "$invocation_details" | jq -r '.CommandInvocations[0].CommandPlugins[0].Output // ""')
                echo "    SSM Status: $ssm_status (Attempt: $((attempts + 1))/$max_attempts)"
                attempts=$((attempts + 1))
            done

            if [ "$ssm_status" != "Success" ]; then
                echo "    Warning: SSM command execution did not succeed (Status: $ssm_status). Skipping process check result."
                local ssm_error_output=$(echo "$invocation_details" | jq -r '.CommandInvocations[0].CommandPlugins[0].StandardErrorContent // ""')
                 if [ -n "$ssm_error_output" ]; then
                    echo "    SSM Error Output: $ssm_error_output"
                 fi
            elif [[ -n "$ssm_output" ]]; then
                echo "    Database processes detected:"
                # Indent the output for clarity
                echo "$ssm_output" | sed 's/^/    /'
                echo "    Total EC2 DBs incremented"
                ec2_db_count=$((ec2_db_count + 1))
            else
                echo "    No database processes detected via SSM."
            fi

        else
            echo "    Instance is not managed by Systems Manager. Skipping process check."
        fi
    done

    echo "  Database scan complete."
    echo "  EC2 DB instances: $ec2_db_count"
    total_ec2_db=$((total_ec2_db + ec2_db_count))

#__stopspin
}

# Function to count resources in a single account
count_resources() {
#    __startspin
    
    local account_id=$1

    if [ "$ORG_MODE" == true ]; then
        # Assume role in the account (replace "OrganizationAccountAccessRole" with your role name if different)
        # Capture stderr to prevent it from cluttering the output if it fails
        creds=$(aws sts assume-role --role-arn "arn:aws:iam::$account_id:role/$ROLE" \
            --role-session-name "OrgSession" --query "Credentials" --output json 2> /dev/null)
        local assume_role_exit_code=$?

        if [ $assume_role_exit_code -ne 0 ]; then
            echo "  Warning: Unable to assume role '$ROLE' in account $account_id (Exit Code: $assume_role_exit_code). Skipping account..."
            # No need to unset creds as they weren't successfully set
            return
        fi

        # Double check creds are not empty even if command succeeded
        if [ -z "$creds" ]; then
             echo "  Warning: Assumed role in account $account_id but credentials seem empty. Skipping account..."
             return
        fi

        # Export temporary credentials
        export AWS_ACCESS_KEY_ID=$(echo $creds | jq -r ".AccessKeyId")
        export AWS_SECRET_ACCESS_KEY=$(echo $creds | jq -r ".SecretAccessKey")
        export AWS_SESSION_TOKEN=$(echo $creds | jq -r ".SessionToken")
    fi


    if [ "$DSPM_MODE" == false ]; then
        echo "Counting Cloud Security resources in account: $account_id"
       
        # Count EC2 instances
        if [[ "${REGION}" ]]; then
            ec2_count=$(aws ec2 describe-instances --region $REGION --filters "Name=instance-state-name,Values=$STATE" --query "Reservations[*].Instances[*]" --output json | jq 'length')
            check_error $? "Failed to describe EC2 instances in region $REGION for account $account_id."
        else
            echo "  Counting EC2 instances across all accessible regions..."
            ec2_count=0
            # Use the activeRegions variable fetched earlier
            for r in $activeRegions; do
                # Capture stderr to avoid cluttering output for regions where API might not be enabled/accessible
                count_in_region=$(aws ec2 describe-instances --region "$r" --filters "Name=instance-state-name,Values=$STATE" --query "Reservations[*].Instances[*]" --output json 2>/dev/null | jq 'length')
                if [ $? -eq 0 ] && [[ "$count_in_region" =~ ^[0-9]+$ ]]; then
                    # Only print if count > 0 to reduce noise
                    if [ "$count_in_region" -gt 0 ]; then
                       echo "    Region $r: $count_in_region instances"
                    fi
                    ec2_count=$((ec2_count + count_in_region))
                fi
            done
        fi
        echo "  EC2 instances: $ec2_count"
        total_ec2_instances=$((total_ec2_instances + ec2_count))

        # Count EKS nodes
        if [[ "${REGION}" ]]; then
            clusters=$(aws eks list-clusters --region $REGION --query "clusters" --output text)
            check_error $? "Failed to list EKS clusters in region $REGION for account $account_id."
        else
            clusters=$(aws eks list-clusters --query "clusters" --output text)
            check_error $? "Failed to list EKS clusters (all regions) for account $account_id."
        fi        
        for cluster in $clusters; do
            node_groups=$(aws eks list-nodegroups --cluster-name "$cluster" --query 'nodegroups' --output text)
            # If listing nodegroups fails, log warning and skip this cluster
            if [ $? -ne 0 ]; then
                echo "    Warning: Failed to list nodegroups for EKS cluster '$cluster' in account $account_id. Skipping cluster."
                continue
            fi
            total_nodes=0
            for node_group in $node_groups; do
                node_count=$(aws eks describe-nodegroup --cluster-name "$cluster" --nodegroup-name "$node_group" --query "nodegroup.scalingConfig.desiredSize" --output text)
                # If describing nodegroup fails, log warning and skip this nodegroup
                if [ $? -ne 0 ]; then
                    echo "    Warning: Failed to describe nodegroup '$node_group' for cluster '$cluster' in account $account_id. Skipping nodegroup."
                    continue
                fi
                total_nodes=$((total_nodes + node_count))
                echo "  EKS cluster '$cluster' nodegroup $node_group nodes: $node_count"
                total_eks_nodes=$((total_eks_nodes + node_count))
            done
        done
    fi

    if [ "$DSPM_MODE" == true ]; then
        echo "Counting DSPM Security resources in account: $account_id"
        # Count S3 buckets
        if [[ "${REGION}" ]]; then
            s3_count=$(aws s3api list-buckets --region $REGION --query "Buckets[*].Name" --output text | wc -w)
            check_error $? "Failed to list S3 buckets in region $REGION for account $account_id."
        else
            s3_count=$(aws s3api list-buckets --query "Buckets[*].Name" --output text | wc -w)
            check_error $? "Failed to list S3 buckets (all regions) for account $account_id."
        fi   
        echo "  S3 buckets: $s3_count"
        total_s3_buckets=$((total_s3_buckets + s3_count))

        # Count EFS file systems
        if [[ "${REGION}" ]]; then
            efs_count=$(aws efs describe-file-systems --region $REGION --query "FileSystems[*].FileSystemId" --output text | wc -w)
            check_error $? "Failed to describe EFS file systems in region $REGION for account $account_id."
        else
            efs_count=$(aws efs describe-file-systems --query "FileSystems[*].FileSystemId" --output text | wc -w)
            check_error $? "Failed to describe EFS file systems (all regions) for account $account_id."
        fi  
        echo "  EFS file systems: $efs_count"
        total_efs=$((total_efs + efs_count))

        # Count Aurora clusters
        if [[ "${REGION}" ]]; then
            aurora_count=$(aws rds describe-db-clusters --region $REGION --query "DBClusters[?Engine=='aurora'].DBClusterIdentifier" --output text | wc -w)
            check_error $? "Failed to describe Aurora clusters in region $REGION for account $account_id."
        else
            aurora_count=$(aws rds describe-db-clusters --query "DBClusters[?Engine=='aurora'].DBClusterIdentifier" --output text | wc -w)
            check_error $? "Failed to describe Aurora clusters (all regions) for account $account_id."
        fi         
        echo "  Aurora clusters: $aurora_count"
        total_aurora=$((total_aurora + aurora_count))

        # Count RDS instances
        if [[ "${REGION}" ]]; then
            rds_count=$(aws rds describe-db-instances --region $REGION --query "DBInstances[?Engine=='mysql' || Engine=='mariadb' || Engine=='postgres'].DBInstanceIdentifier" --output text | wc -w)
            check_error $? "Failed to describe RDS instances in region $REGION for account $account_id."
        else
            rds_count=$(aws rds describe-db-instances --query "DBInstances[?Engine=='mysql' || Engine=='mariadb' || Engine=='postgres'].DBInstanceIdentifier" --output text | wc -w)
            check_error $? "Failed to describe RDS instances (all regions) for account $account_id."
        fi   
        echo "  RDS instances (MySQL, MariaDB, PostgreSQL): $rds_count"
        total_rds=$((total_rds + rds_count))

        # Count DynamoDB tables
        if [[ "${REGION}" ]]; then
            dynamodb_count=$(aws dynamodb list-tables --region $REGION --query "TableNames" --output text | wc -w)
            check_error $? "Failed to list DynamoDB tables in region $REGION for account $account_id."
        else
            dynamodb_count=$(aws dynamodb list-tables --query "TableNames" --output text | wc -w)
            check_error $? "Failed to list DynamoDB tables (all regions) for account $account_id."
        fi 
        echo "  DynamoDB tables: $dynamodb_count"
        total_dynamodb=$((total_dynamodb + dynamodb_count))

        # Count Redshift clusters
        if [[ "${REGION}" ]]; then
            redshift_count=$(aws redshift describe-clusters --region $REGION --query "Clusters[*].ClusterIdentifier" --output text | wc -w)
            check_error $? "Failed to describe Redshift clusters in region $REGION for account $account_id."
        else
            redshift_count=$(aws redshift describe-clusters --query "Clusters[*].ClusterIdentifier" --output text | wc -w)
            check_error $? "Failed to describe Redshift clusters (all regions) for account $account_id."
        fi 
        echo "  Redshift clusters: $redshift_count"
        total_redshift=$((total_redshift + redshift_count))
 
   	if [ "$SSM_MODE" == true ]; then
    	check_running_databases
    	fi
    
    fi

    # Unset temporary credentials only if they were successfully set
    if [ "$ORG_MODE" == true ] && [ -n "$AWS_SESSION_TOKEN" ]; then
        # Unset temporary credentials
        unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    fi

#    __stopspin
}

# Main logic
if [ "$ORG_MODE" == true ]; then
    # Get the list of all accounts in the AWS Organization
    # Filter for ACTIVE accounts only
    accounts=$(aws organizations list-accounts --query "Accounts[?Status=='ACTIVE'].Id" --output text)
    check_error $? "Failed to list accounts in the organization. Ensure you have 'organizations:ListAccounts' permission."

    if [ -z "$accounts" ]; then
        echo "No accounts found in the organization."
        exit 0
    fi

    # Loop through each account in the organization
    for account_id in $accounts; do
        count_resources "$account_id"
    done
else
    # Run for the standalone account
    current_account=$(aws sts get-caller-identity --query "Account" --output text)
    check_error $? "Failed to get caller identity for the current account."
    count_resources "$current_account"
fi

if [ "$ORG_MODE" == true ] && [ "$DSPM_MODE" == false ]; then
    echo ""
    echo "** TOTAL COUNTS **"
    echo "  EC2 instances: $total_ec2_instances"
    echo "  EKS nodes: $total_eks_nodes"
fi

if [ "$ORG_MODE" == true ] && [ "$DSPM_MODE" == true ]; then
    echo ""
    echo "** TOTAL DSPM COUNTS **"
    echo "  S3 buckets: $total_s3_buckets"
    echo "  EFS file systems: $total_efs"
    echo "  Aurora clusters: $total_aurora"
    echo "  RDS instances: $total_rds"
    echo "  DynamoDB tables: $total_dynamodb"
    echo "  Redshift clusters: $total_redshift"
    echo "  EC2 DBs: $total_ec2_db"
fi
