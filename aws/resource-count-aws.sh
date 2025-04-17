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
SSM_MODE=false # Initialize SSM_MODE

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
total_eks_clusters=0
total_docker_hosts=0
total_ecs_clusters=0
total_ecs_tasks=0
total_lambda_functions=0 # Added
total_s3_buckets=0
total_efs=0
total_aurora=0
total_rds=0
total_dynamodb=0
total_redshift=0
total_ec2_db=0
ec2_db_count=0 # Local counter for check_running_databases

# Functions
check_running_databases() {
    # Required ports for database identification
    local DATABASE_PORTS=(3306 5432 27017 1433 33060)

    echo "Fetching all $STATE EC2 instances for DB check..."
    local instances_json # Use a local variable for JSON output
    if [[ "${REGION}" ]]; then
        instances_json=$(aws ec2 describe-instances \
        --region "$REGION" --filters "Name=instance-state-name,Values=$STATE" \
        --query "Reservations[*].Instances[*].{ID:InstanceId,IP:PrivateIpAddress,Name:Tags[?Key=='Name']|[0].Value}" \
        --output json)
    else
        instances_json=$(aws ec2 describe-instances \
        --filters "Name=instance-state-name,Values=$STATE" \
        --query "Reservations[*].Instances[*].{ID:InstanceId,IP:PrivateIpAddress,Name:Tags[?Key=='Name']|[0].Value}" \
        --output json)
    fi
    local describe_exit_code=$?
    if [ $describe_exit_code -ne 0 ]; then
        echo "  Warning: Failed to describe EC2 instances for DB check (Exit Code: $describe_exit_code). Skipping DB check."
        return
    fi

    # Check if any instances were returned
    if [[ -z "$instances_json" || "$instances_json" == "[]" || "$(echo "$instances_json" | jq 'flatten | length')" -eq 0 ]]; then
        echo "  No $STATE EC2 instances found for DB check."
        return 0
    fi

    echo "  Found $STATE EC2 instances. Checking each instance for database activity..."
    ec2_db_count=0 # Reset local counter for this account/run

    # Parse instances and check for databases
    echo "$instances_json" | jq -c '.[] | .[]' | while IFS= read -r instance; do
        local instance_id=$(echo "$instance" | jq -r '.ID')
        local private_ip=$(echo "$instance" | jq -r '.IP')
        local instance_name=$(echo "$instance" | jq -r '.Name // "Unnamed Instance"')

        # Skip if instance ID is null or empty
        if [ -z "$instance_id" ] || [ "$instance_id" == "null" ]; then
            continue
        fi

        echo "  Checking instance: $instance_name (ID: $instance_id, IP: $private_ip)"

        # Optional: Check for running database processes via Systems Manager
        if [ "$SSM_MODE" == true ]; then
            # Check if instance is managed by SSM first
            if aws ssm describe-instance-information --query "InstanceInformationList[?InstanceId=='$instance_id']" --output text &>/dev/null; then
                echo "    Instance is managed by Systems Manager. Checking for database processes..."
                local command_id=$(aws ssm send-command \
                    --instance-ids "$instance_id" \
                    --document-name "AWS-RunShellScript" \
                    --comment "Check for running database processes" \
                    --parameters 'commands=["ps aux | grep -E \"postgres|mongo|mysql|mariadb|sqlserver\" | grep -v grep"]' \
                    --query "Command.CommandId" --output text 2>/dev/null) # Suppress stderr on send-command too
                local send_cmd_exit_code=$?

                if [ $send_cmd_exit_code -ne 0 ] || [ -z "$command_id" ]; then
                    echo "    Warning: Failed to send SSM command to instance $instance_id. Skipping process check."
                    continue # Skip to next instance
                fi

                echo "    SSM Command ID: $command_id. Waiting for completion..."
                local ssm_status="Pending"
                local ssm_output=""
                local attempts=0
                local max_attempts=12 # Wait for max 60 seconds (12 * 5s)

                while [[ "$ssm_status" == "Pending" || "$ssm_status" == "InProgress" || "$ssm_status" == "Delayed" ]] && [ $attempts -lt $max_attempts ]; do
                    sleep 5
                    local invocation_details=$(aws ssm list-command-invocations --command-id "$command_id" --details --output json 2>/dev/null)
                    # Check if invocation details were retrieved and not empty
                    if [ -z "$invocation_details" ] || [ "$(echo "$invocation_details" | jq '.CommandInvocations | length')" -eq 0 ]; then
                         echo "    Warning: Could not retrieve SSM invocation details for $command_id yet. Retrying..."
                         attempts=$((attempts + 1))
                         continue
                    fi
                    ssm_status=$(echo "$invocation_details" | jq -r '.CommandInvocations[0].Status // "Error"') # Default to Error if Status is missing
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
        else
             echo "    SSM mode not enabled (-c). Skipping process check."
        fi # End SSM_MODE check
    done <<< "$(echo "$instances_json" | jq -c '.[] | .[]')" # Feed jq output to the while loop correctly

    echo "  Database scan complete for this account."
    echo "  EC2 DB instances found in this account (via SSM): $ec2_db_count"
    total_ec2_db=$((total_ec2_db + ec2_db_count)) # Add to global total
}

# Function to count resources in a single account
count_resources() {
    local account_id=$1
    local current_region=$2 # Pass region if specified

    echo "--------------------------------------------------"
    echo "Processing Account: $account_id"
    if [ -n "$current_region" ]; then
        echo "Region specified: $current_region"
    fi
    echo "--------------------------------------------------"


    if [ "$ORG_MODE" == true ]; then
        # Assume role in the account
        echo "  Attempting to assume role '$ROLE' in account $account_id..."
        creds=$(aws sts assume-role --role-arn "arn:aws:iam::$account_id:role/$ROLE" \
            --role-session-name "OrgSession" --query "Credentials" --output json 2> /dev/null)
        local assume_role_exit_code=$?

        if [ $assume_role_exit_code -ne 0 ]; then
            echo "  Warning: Unable to assume role '$ROLE' in account $account_id (Exit Code: $assume_role_exit_code). Skipping account..."
            return
        fi
        if [ -z "$creds" ] || [ "$creds" == "null" ]; then
             echo "  Warning: Assumed role in account $account_id but credentials seem empty or null. Skipping account..."
             return
        fi

        # Export temporary credentials
        export AWS_ACCESS_KEY_ID=$(echo "$creds" | jq -r ".AccessKeyId")
        export AWS_SECRET_ACCESS_KEY=$(echo "$creds" | jq -r ".SecretAccessKey")
        export AWS_SESSION_TOKEN=$(echo "$creds" | jq -r ".SessionToken")

        # Verify assumed identity
        assumed_identity=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null)
        if [ $? -ne 0 ] || [[ ! "$assumed_identity" =~ "$account_id" ]]; then
            echo "  Warning: Failed to verify assumed role identity for account $account_id. Skipping account."
            unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
            return
        fi
        echo "  Successfully assumed role in account $account_id."
    fi


    if [ "$DSPM_MODE" == false ]; then
        echo "Counting Cloud Security resources in account: $account_id"
        local account_ec2_count=0
        local account_eks_nodes=0
        local account_eks_clusters=0
        local account_ecs_clusters=0
        local account_ecs_tasks=0
        local account_lambda_functions=0 # Added
        local account_docker_hosts=0
        local docker_host_tag_key="DockerHost" # Define tag key here

        # Count EC2 instances
        echo "  Counting EC2 instances..."
        if [[ -n "${current_region}" ]]; then
            count_in_region=$(aws ec2 describe-instances --region "$current_region" --filters "Name=instance-state-name,Values=$STATE" --query "Reservations[*].Instances[*]" --output json 2>/dev/null | jq 'length')
            if [ $? -eq 0 ] && [[ "$count_in_region" =~ ^[0-9]+$ ]]; then
                if [ "$count_in_region" -gt 0 ]; then echo "    Region $current_region: $count_in_region instances"; fi
                account_ec2_count=$((account_ec2_count + count_in_region))
            else
                 echo "    Warning: Failed to count EC2 in region $current_region."
            fi
        else
            echo "    Across all accessible regions..."
            for r in $activeRegions; do
                count_in_region=$(aws ec2 describe-instances --region "$r" --filters "Name=instance-state-name,Values=$STATE" --query "Reservations[*].Instances[*]" --output json 2>/dev/null | jq 'length')
                if [ $? -eq 0 ] && [[ "$count_in_region" =~ ^[0-9]+$ ]]; then
                    if [ "$count_in_region" -gt 0 ]; then echo "      Region $r: $count_in_region instances"; fi
                    account_ec2_count=$((account_ec2_count + count_in_region))
                # else echo "      Skipping region $r (no access or error)" # Optional: more verbose logging
                fi
            done
        fi
        echo "  EC2 instances in account: $account_ec2_count"
        total_ec2_instances=$((total_ec2_instances + account_ec2_count))

        # Count EKS Clusters and Nodes
        echo "  Counting EKS clusters and nodes..."
        local eks_clusters=""
        local list_eks_clusters_exit_code=0
        local eks_cluster_map_file=""
        if [[ -z "${current_region}" ]]; then
            eks_cluster_map_file=$(mktemp /tmp/eks_map.XXXXXX) # Use mktemp for safety
        fi

        if [[ -n "${current_region}" ]]; then
            eks_clusters=$(aws eks list-clusters --region "$current_region" --query "clusters" --output text 2>/dev/null)
            list_eks_clusters_exit_code=$?
        else
             echo "    Across all accessible regions..."
             eks_cluster_list_all_regions=""
             for r in $activeRegions; do
                 clusters_in_region=$(aws eks list-clusters --region "$r" --query "clusters" --output text 2>/dev/null)
                 if [ $? -eq 0 ] && [ -n "$clusters_in_region" ]; then
                     if [ -n "$eks_cluster_list_all_regions" ]; then
                         eks_cluster_list_all_regions="$eks_cluster_list_all_regions $clusters_in_region"
                     else
                         eks_cluster_list_all_regions="$clusters_in_region"
                     fi
                     # Use process substitution to avoid subshell issues with the map file
                     while IFS= read -r cl; do echo "$r $cl"; done <<< "$clusters_in_region" >> "$eks_cluster_map_file"
                 fi
             done
             eks_clusters=$eks_cluster_list_all_regions
             list_eks_clusters_exit_code=0
        fi

        if [ $list_eks_clusters_exit_code -ne 0 ] && [ -z "$eks_clusters" ]; then
            echo "    Warning: Failed to list EKS clusters for account $account_id. Skipping EKS counts."
        else
            # Count EKS Clusters found
            if [ -n "$eks_clusters" ]; then
                account_eks_clusters=$(echo "$eks_clusters" | wc -w)
            else
                account_eks_clusters=0
            fi
            echo "    EKS clusters found in account: $account_eks_clusters"
            total_eks_clusters=$((total_eks_clusters + account_eks_clusters))

            # Count EKS Nodes
            account_eks_nodes=0 # Reset node count for this account
            if [[ -n "${current_region}" ]]; then
                 # Single region processing
                 for cluster in $eks_clusters; do
                     echo "    Processing EKS cluster '$cluster' in region '$current_region'..."
                     node_groups=$(aws eks list-nodegroups --region "$current_region" --cluster-name "$cluster" --query 'nodegroups' --output text 2>/dev/null)
                     list_nodegroups_exit_code=$?
                     if [ $list_nodegroups_exit_code -ne 0 ] || [ -z "$node_groups" ]; then
                         echo "      Warning: Failed to list nodegroups for EKS cluster '$cluster' in region $current_region. Skipping cluster nodes."
                         continue
                     fi
                     for node_group in $node_groups; do
                         node_count=$(aws eks describe-nodegroup --region "$current_region" --cluster-name "$cluster" --nodegroup-name "$node_group" --query "nodegroup.scalingConfig.desiredSize" --output text 2>/dev/null)
                         if [ $? -eq 0 ] && [[ "$node_count" =~ ^[0-9]+$ ]]; then
                             echo "      EKS Cluster '$cluster' nodegroup '$node_group' nodes: $node_count"
                             account_eks_nodes=$((account_eks_nodes + node_count))
                         else
                             echo "      Warning: Failed to get node count for nodegroup '$node_group' in cluster '$cluster'."
                         fi
                     done
                 done
            elif [ -f "$eks_cluster_map_file" ]; then
                 # All regions processing using the map file
                 while IFS=' ' read -r cluster_region cluster_name; do
                     if [ -z "$cluster_region" ] || [ -z "$cluster_name" ]; then continue; fi
                     echo "    Processing EKS cluster '$cluster_name' in region '$cluster_region'..."
                     node_groups=$(aws eks list-nodegroups --region "$cluster_region" --cluster-name "$cluster_name" --query 'nodegroups' --output text 2>/dev/null)
                     list_nodegroups_exit_code=$?
                     if [ $list_nodegroups_exit_code -ne 0 ] || [ -z "$node_groups" ]; then
                         echo "      Warning: Failed to list nodegroups for EKS cluster '$cluster_name' in region $cluster_region. Skipping cluster nodes."
                         continue
                     fi
                     for node_group in $node_groups; do
                         node_count=$(aws eks describe-nodegroup --region "$cluster_region" --cluster-name "$cluster_name" --nodegroup-name "$node_group" --query "nodegroup.scalingConfig.desiredSize" --output text 2>/dev/null)
                         if [ $? -eq 0 ] && [[ "$node_count" =~ ^[0-9]+$ ]]; then
                             echo "      EKS Cluster '$cluster_name' nodegroup '$node_group' nodes: $node_count"
                             account_eks_nodes=$((account_eks_nodes + node_count))
                         else
                             echo "      Warning: Failed to get node count for nodegroup '$node_group' in cluster '$cluster_name'."
                         fi
                     done
                 done < "$eks_cluster_map_file"
            fi
            echo "    EKS nodes found in account: $account_eks_nodes"
            total_eks_nodes=$((total_eks_nodes + account_eks_nodes))
        fi
        if [ -f "$eks_cluster_map_file" ]; then
            rm "$eks_cluster_map_file"
        fi

        # Count ECS Clusters and Tasks
        echo "  Counting ECS clusters and tasks..."
        local ecs_clusters=""
        local list_ecs_clusters_exit_code=0
        local ecs_cluster_map_file=""
         if [[ -z "${current_region}" ]]; then
            ecs_cluster_map_file=$(mktemp /tmp/ecs_map.XXXXXX) # Use mktemp for safety
        fi

        if [[ -n "${current_region}" ]]; then
            ecs_clusters=$(aws ecs list-clusters --region "$current_region" --query "clusterArns" --output text 2>/dev/null)
            list_ecs_clusters_exit_code=$?
        else
            echo "    Across all accessible regions..."
            ecs_cluster_list_all_regions=""
            for r in $activeRegions; do
                clusters_in_region=$(aws ecs list-clusters --region "$r" --query "clusterArns" --output text 2>/dev/null)
                 if [ $? -eq 0 ] && [ -n "$clusters_in_region" ]; then
                     if [ -n "$ecs_cluster_list_all_regions" ]; then
                         ecs_cluster_list_all_regions="$ecs_cluster_list_all_regions $clusters_in_region"
                     else
                         ecs_cluster_list_all_regions="$clusters_in_region"
                     fi
                     # Use process substitution to avoid subshell issues with the map file
                     while IFS= read -r cl_arn; do echo "$r $cl_arn"; done <<< "$clusters_in_region" >> "$ecs_cluster_map_file"
                 fi
            done
            ecs_clusters=$ecs_cluster_list_all_regions
            list_ecs_clusters_exit_code=0
        fi

        if [ $list_ecs_clusters_exit_code -ne 0 ] && [ -z "$ecs_clusters" ]; then
             echo "    Warning: Failed to list ECS clusters for account $account_id. Skipping ECS counts."
        else
            # Count ECS Clusters found
            if [ -n "$ecs_clusters" ]; then
                account_ecs_clusters=$(echo "$ecs_clusters" | wc -w)
            else
                account_ecs_clusters=0
            fi
            echo "    ECS clusters found in account: $account_ecs_clusters"
            total_ecs_clusters=$((total_ecs_clusters + account_ecs_clusters))

            # Count ECS Tasks
            account_ecs_tasks=0 # Reset task count for this account
            process_ecs_cluster() {
                local cluster_region=$1
                local cluster_arn=$2
                local cluster_name # Extract name later if needed, use ARN for commands

                # Ensure cluster_region and cluster_arn are not empty
                if [ -z "$cluster_region" ] || [ -z "$cluster_arn" ]; then return; fi

                cluster_name=$(basename "$cluster_arn") # Extract name from ARN for logging
                echo "    Processing ECS cluster '$cluster_name' in region '$cluster_region'..."
                local services_output
                local next_token=""
                local services_in_cluster=() # Array to hold all service ARNs

                # Paginate through list-services
                while true; do
                    if [ -z "$next_token" ] || [ "$next_token" == "null" ]; then
                        services_output=$(aws ecs list-services --region "$cluster_region" --cluster "$cluster_arn" --output json 2>/dev/null)
                    else
                        services_output=$(aws ecs list-services --region "$cluster_region" --cluster "$cluster_arn" --starting-token "$next_token" --output json 2>/dev/null)
                    fi

                    if [ $? -ne 0 ]; then
                        echo "      Warning: Failed to list services for ECS cluster '$cluster_name' in region $cluster_region. Skipping task count for this cluster."
                        return # Exit function for this cluster
                    fi

                    # Safely extract service ARNs using jq
                    current_services_json=$(echo "$services_output" | jq -c '.serviceArns // []')
                    readarray -t current_services < <(jq -r '.[]' <<< "$current_services_json")

                    if [ ${#current_services[@]} -gt 0 ]; then
                        services_in_cluster+=("${current_services[@]}")
                    fi

                    next_token=$(echo "$services_output" | jq -r '.nextToken // empty')
                    if [ -z "$next_token" ]; then
                        break # No more pages
                    fi
                done

                if [ ${#services_in_cluster[@]} -eq 0 ]; then
                    echo "      No active services found in cluster '$cluster_name'."
                    return
                fi

                # Describe services in batches of 10
                local i=0
                while [ $i -lt ${#services_in_cluster[@]} ]; do
                    # Prepare batch carefully, quoting each ARN
                    local batch_args=()
                    for j in $(seq $i $((i + 9))); do
                        if [ $j -lt ${#services_in_cluster[@]} ]; then
                            batch_args+=("${services_in_cluster[j]}")
                        fi
                    done

                    if [ ${#batch_args[@]} -eq 0 ]; then break; fi # Should not happen, but safety check

                    local describe_output
                    # Pass batch arguments correctly to --services
                    describe_output=$(aws ecs describe-services --region "$cluster_region" --cluster "$cluster_arn" --services "${batch_args[@]}" --query "services[*].runningCount" --output json 2>/dev/null)


                    if [ $? -eq 0 ] && [ -n "$describe_output" ] && [ "$describe_output" != "null" ]; then
                        # Sum runningCount from the batch using jq
                        local batch_task_count=$(echo "$describe_output" | jq '[.[]] | add // 0')
                        if [[ "$batch_task_count" =~ ^[0-9]+$ ]]; then
                             account_ecs_tasks=$((account_ecs_tasks + batch_task_count))
                        fi
                    else
                        echo "      Warning: Failed to describe some services in batch starting at index $i for cluster '$cluster_name'."
                    fi
                    i=$((i + 10))
                done
            }

            if [[ -n "${current_region}" ]]; then
                 for cluster_arn in $ecs_clusters; do
                     process_ecs_cluster "$current_region" "$cluster_arn"
                 done
            elif [ -f "$ecs_cluster_map_file" ]; then
                 while IFS=' ' read -r cluster_region cluster_arn; do
                     process_ecs_cluster "$cluster_region" "$cluster_arn"
                 done < "$ecs_cluster_map_file"
            fi
            echo "    ECS running tasks found in account: $account_ecs_tasks"
            total_ecs_tasks=$((total_ecs_tasks + account_ecs_tasks))
        fi
         if [ -f "$ecs_cluster_map_file" ]; then
            rm "$ecs_cluster_map_file"
        fi

        # Count Lambda Functions
        echo "  Counting Lambda functions..."
        if [[ -n "${current_region}" ]]; then
            # Use --no-paginate and jq length for a simple count in a single region
            count_in_region=$(aws lambda list-functions --region "$current_region" --no-paginate --query "Functions" --output json 2>/dev/null | jq 'length')
             if [ $? -eq 0 ] && [[ "$count_in_region" =~ ^[0-9]+$ ]]; then
                 if [ "$count_in_region" -gt 0 ]; then echo "    Region $current_region: $count_in_region Lambda Functions"; fi
                 account_lambda_functions=$((account_lambda_functions + count_in_region))
             else echo "    Warning: Failed to count Lambda Functions in region $current_region."; fi
        else
            echo "    Across all accessible regions..."
            for r in $activeRegions; do
                # Use --no-paginate and jq length for a simple count per region
                count_in_region=$(aws lambda list-functions --region "$r" --no-paginate --query "Functions" --output json 2>/dev/null | jq 'length')
                 if [ $? -eq 0 ] && [[ "$count_in_region" =~ ^[0-9]+$ ]]; then
                     if [ "$count_in_region" -gt 0 ]; then echo "      Region $r: $count_in_region Lambda Functions"; fi
                     account_lambda_functions=$((account_lambda_functions + count_in_region))
                 # else echo "      Skipping region $r (no access or error)" # Optional
                 fi
            done
        fi
        echo "  Lambda functions found in account: $account_lambda_functions"
        total_lambda_functions=$((total_lambda_functions + account_lambda_functions))


        # Count EC2 instances tagged as Docker Hosts
        echo "  Counting EC2 instances tagged as Docker Hosts (Tag Key: $docker_host_tag_key)..."
        if [[ -n "${current_region}" ]]; then
            count_in_region=$(aws ec2 describe-instances --region "$current_region" --filters "Name=instance-state-name,Values=$STATE" "Name=tag-key,Values=$docker_host_tag_key" --query "Reservations[*].Instances[*]" --output json 2>/dev/null | jq 'length')
            if [ $? -eq 0 ] && [[ "$count_in_region" =~ ^[0-9]+$ ]]; then
                if [ "$count_in_region" -gt 0 ]; then echo "    Region $current_region: $count_in_region Docker Hosts"; fi
                account_docker_hosts=$((account_docker_hosts + count_in_region))
            else
                 echo "    Warning: Failed to count Docker Hosts in region $current_region."
            fi
        else
            echo "    Across all accessible regions..."
            for r in $activeRegions; do
                count_in_region=$(aws ec2 describe-instances --region "$r" --filters "Name=instance-state-name,Values=$STATE" "Name=tag-key,Values=$docker_host_tag_key" --query "Reservations[*].Instances[*]" --output json 2>/dev/null | jq 'length')
                if [ $? -eq 0 ] && [[ "$count_in_region" =~ ^[0-9]+$ ]]; then
                    if [ "$count_in_region" -gt 0 ]; then echo "      Region $r: $count_in_region Docker Hosts"; fi
                    account_docker_hosts=$((account_docker_hosts + count_in_region))
                # else echo "      Skipping region $r (no access or error)" # Optional
                fi
            done
        fi
        echo "  EC2 Docker Hosts found in account (tagged '$docker_host_tag_key'): $account_docker_hosts"
        total_docker_hosts=$((total_docker_hosts + account_docker_hosts))

    fi # End of non-DSPM mode block

    if [ "$DSPM_MODE" == true ]; then
        echo "Counting DSPM Security resources in account: $account_id"
        local account_s3_count=0
        local account_efs_count=0
        local account_aurora_count=0
        local account_rds_count=0
        local account_dynamodb_count=0
        local account_redshift_count=0

        # Count S3 buckets (Global service, no region loop needed)
        echo "  Counting S3 buckets..."
        s3_count=$(aws s3api list-buckets --query "Buckets[*].Name" --output text 2>/dev/null | wc -w)
        if [ $? -eq 0 ] && [[ "$s3_count" =~ ^[0-9]+$ ]]; then
            account_s3_count=$s3_count
        else
            echo "    Warning: Failed to list S3 buckets."
            account_s3_count=0
        fi
        echo "  S3 buckets in account: $account_s3_count"
        total_s3_buckets=$((total_s3_buckets + account_s3_count))

        # Count EFS file systems
        echo "  Counting EFS file systems..."
        if [[ -n "${current_region}" ]]; then
             count_in_region=$(aws efs describe-file-systems --region "$current_region" --query "FileSystems[*].FileSystemId" --output text 2>/dev/null | wc -w)
             if [ $? -eq 0 ] && [[ "$count_in_region" =~ ^[0-9]+$ ]]; then
                 if [ "$count_in_region" -gt 0 ]; then echo "    Region $current_region: $count_in_region EFS"; fi
                 account_efs_count=$((account_efs_count + count_in_region))
             else echo "    Warning: Failed to count EFS in region $current_region."; fi
        else
             echo "    Across all accessible regions..."
             for r in $activeRegions; do
                 count_in_region=$(aws efs describe-file-systems --region "$r" --query "FileSystems[*].FileSystemId" --output text 2>/dev/null | wc -w)
                 if [ $? -eq 0 ] && [[ "$count_in_region" =~ ^[0-9]+$ ]]; then
                     if [ "$count_in_region" -gt 0 ]; then echo "      Region $r: $count_in_region EFS"; fi
                     account_efs_count=$((account_efs_count + count_in_region))
                 fi
             done
        fi
        echo "  EFS file systems in account: $account_efs_count"
        total_efs=$((total_efs + account_efs_count))

        # Count Aurora clusters
        echo "  Counting Aurora clusters..."
         if [[ -n "${current_region}" ]]; then
             count_in_region=$(aws rds describe-db-clusters --region "$current_region" --query "DBClusters[?Engine=='aurora' || Engine=='aurora-mysql' || Engine=='aurora-postgresql'].DBClusterIdentifier" --output text 2>/dev/null | wc -w)
             if [ $? -eq 0 ] && [[ "$count_in_region" =~ ^[0-9]+$ ]]; then
                 if [ "$count_in_region" -gt 0 ]; then echo "    Region $current_region: $count_in_region Aurora"; fi
                 account_aurora_count=$((account_aurora_count + count_in_region))
             else echo "    Warning: Failed to count Aurora in region $current_region."; fi
        else
             echo "    Across all accessible regions..."
             for r in $activeRegions; do
                 count_in_region=$(aws rds describe-db-clusters --region "$r" --query "DBClusters[?Engine=='aurora' || Engine=='aurora-mysql' || Engine=='aurora-postgresql'].DBClusterIdentifier" --output text 2>/dev/null | wc -w)
                 if [ $? -eq 0 ] && [[ "$count_in_region" =~ ^[0-9]+$ ]]; then
                     if [ "$count_in_region" -gt 0 ]; then echo "      Region $r: $count_in_region Aurora"; fi
                     account_aurora_count=$((account_aurora_count + count_in_region))
                 fi
             done
        fi
        echo "  Aurora clusters in account: $account_aurora_count"
        total_aurora=$((total_aurora + account_aurora_count))

        # Count RDS instances (non-Aurora MySQL, MariaDB, PostgreSQL)
        echo "  Counting RDS instances (non-Aurora)..."
        if [[ -n "${current_region}" ]]; then
             count_in_region=$(aws rds describe-db-instances --region "$current_region" --query "DBInstances[?!contains(Engine, 'aurora') && (Engine=='mysql' || Engine=='mariadb' || Engine=='postgres')].DBInstanceIdentifier" --output text 2>/dev/null | wc -w)
             if [ $? -eq 0 ] && [[ "$count_in_region" =~ ^[0-9]+$ ]]; then
                  if [ "$count_in_region" -gt 0 ]; then echo "    Region $current_region: $count_in_region RDS"; fi
                  account_rds_count=$((account_rds_count + count_in_region))
             else echo "    Warning: Failed to count RDS in region $current_region."; fi
        else
             echo "    Across all accessible regions..."
             for r in $activeRegions; do
                 count_in_region=$(aws rds describe-db-instances --region "$r" --query "DBInstances[?!contains(Engine, 'aurora') && (Engine=='mysql' || Engine=='mariadb' || Engine=='postgres')].DBInstanceIdentifier" --output text 2>/dev/null | wc -w)
                 if [ $? -eq 0 ] && [[ "$count_in_region" =~ ^[0-9]+$ ]]; then
                     if [ "$count_in_region" -gt 0 ]; then echo "      Region $r: $count_in_region RDS"; fi
                     account_rds_count=$((account_rds_count + count_in_region))
                 fi
             done
        fi
        echo "  RDS instances (non-Aurora) in account: $account_rds_count"
        total_rds=$((total_rds + account_rds_count))

        # Count DynamoDB tables
        echo "  Counting DynamoDB tables..."
         if [[ -n "${current_region}" ]]; then
             count_in_region=$(aws dynamodb list-tables --region "$current_region" --query "TableNames" --output text 2>/dev/null | wc -w)
              if [ $? -eq 0 ] && [[ "$count_in_region" =~ ^[0-9]+$ ]]; then
                  if [ "$count_in_region" -gt 0 ]; then echo "    Region $current_region: $count_in_region DynamoDB"; fi
                  account_dynamodb_count=$((account_dynamodb_count + count_in_region))
             else echo "    Warning: Failed to count DynamoDB in region $current_region."; fi
        else
             echo "    Across all accessible regions..."
             for r in $activeRegions; do
                 count_in_region=$(aws dynamodb list-tables --region "$r" --query "TableNames" --output text 2>/dev/null | wc -w)
                 if [ $? -eq 0 ] && [[ "$count_in_region" =~ ^[0-9]+$ ]]; then
                     if [ "$count_in_region" -gt 0 ]; then echo "      Region $r: $count_in_region DynamoDB"; fi
                     account_dynamodb_count=$((account_dynamodb_count + count_in_region))
                 fi
             done
        fi
        echo "  DynamoDB tables in account: $account_dynamodb_count"
        total_dynamodb=$((total_dynamodb + account_dynamodb_count))

        # Count Redshift clusters
        echo "  Counting Redshift clusters..."
        if [[ -n "${current_region}" ]]; then
             count_in_region=$(aws redshift describe-clusters --region "$current_region" --query "Clusters[*].ClusterIdentifier" --output text 2>/dev/null | wc -w)
             if [ $? -eq 0 ] && [[ "$count_in_region" =~ ^[0-9]+$ ]]; then
                  if [ "$count_in_region" -gt 0 ]; then echo "    Region $current_region: $count_in_region Redshift"; fi
                  account_redshift_count=$((account_redshift_count + count_in_region))
             else echo "    Warning: Failed to count Redshift in region $current_region."; fi
        else
             echo "    Across all accessible regions..."
             for r in $activeRegions; do
                 count_in_region=$(aws redshift describe-clusters --region "$r" --query "Clusters[*].ClusterIdentifier" --output text 2>/dev/null | wc -w)
                 if [ $? -eq 0 ] && [[ "$count_in_region" =~ ^[0-9]+$ ]]; then
                     if [ "$count_in_region" -gt 0 ]; then echo "      Region $r: $count_in_region Redshift"; fi
                     account_redshift_count=$((account_redshift_count + count_in_region))
                 fi
             done
        fi
        echo "  Redshift clusters in account: $account_redshift_count"
        total_redshift=$((total_redshift + account_redshift_count))

        # Count EC2 DBs (only if SSM mode is enabled)
        if [ "$SSM_MODE" == true ]; then
            check_running_databases # This function updates total_ec2_db
        else
            echo "  Skipping EC2 DB check (SSM mode not enabled with -c flag)."
        fi

    fi # End DSPM_MODE check

    # Unset temporary credentials only if they were successfully set
    if [ "$ORG_MODE" == true ] && [ -n "$AWS_SESSION_TOKEN" ]; then
        # Unset temporary credentials
        unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
        echo "  Unset temporary credentials for account $account_id."
    fi

}

# Main logic
if [ "$ORG_MODE" == true ]; then
    # Get the list of all accounts in the AWS Organization
    echo "Fetching accounts from AWS Organization..."
    accounts=$(aws organizations list-accounts --query "Accounts[?Status=='ACTIVE'].Id" --output text)
    check_error $? "Failed to list accounts in the organization. Ensure you have 'organizations:ListAccounts' permission."

    if [ -z "$accounts" ]; then
        echo "No active accounts found in the organization."
        exit 0
    fi
    echo "Found accounts: $accounts"

    # Loop through each account in the organization
    for account_id in $accounts; do
        count_resources "$account_id" "$REGION" # Pass region if specified
    done
else
    # Run for the standalone account
    current_account=$(aws sts get-caller-identity --query "Account" --output text)
    check_error $? "Failed to get caller identity for the current account."
    count_resources "$current_account" "$REGION" # Pass region if specified
fi

# Define docker_host_tag_key again for the summary section consistency
docker_host_tag_key="DockerHost"

# Final Summary Section
echo ""
echo "##########################################"
echo "** FINAL SUMMARY (Across all processed accounts) **"
echo "##########################################"
echo ""

if [ "$DSPM_MODE" == false ]; then
    echo "** Cloud Security Counts **"
    echo "==============================="
    echo "EC2 instances ($STATE): $total_ec2_instances"
    echo "EKS nodes (desired):    $total_eks_nodes"
    echo "EKS clusters:           $total_eks_clusters"
    echo "ECS tasks (running):    $total_ecs_tasks"
    echo "ECS clusters:           $total_ecs_clusters"
    echo "Lambda functions:       $total_lambda_functions" # Added
    echo "EC2 Docker Hosts (tagged '$docker_host_tag_key', $STATE): $total_docker_hosts"
    echo ""
fi

if [ "$DSPM_MODE" == true ]; then
    echo "** DSPM Counts **"
    echo "==============================="
    echo "S3 buckets:             $total_s3_buckets"
    echo "EFS file systems:       $total_efs"
    echo "Aurora clusters:        $total_aurora"
    echo "RDS instances:          $total_rds"
    echo "DynamoDB tables:        $total_dynamodb"
    echo "Redshift clusters:      $total_redshift"
    if [ "$SSM_MODE" == true ]; then
       echo "EC2 DBs (via SSM):      $total_ec2_db"
    else
       echo "EC2 DBs (via SSM):      (Skipped, use -c flag to enable)"
    fi
    echo ""
fi

echo "Script finished."
