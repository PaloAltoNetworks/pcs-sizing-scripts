#!/bin/bash

# Script to fetch GCP inventory for Prisma Cloud sizing.

# This script can be run from Azure Cloud Shell.
# Run ./pcs_azure_sizing.sh -h for help on how to run the script.
# Or just read the text in printHelp below.

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
        # Add any GCP specific cleanup here if needed in the future
        exit $exit_code
    fi
}

function printHelp {
    echo ""
    echo "NOTES:"
    echo "* Requires gcloud CLI to execute"
    echo "* Requires JQ utility to be installed (TODO: Install JQ from script; exists in AWS, GCP)"
    echo "* Validated to run successfully from within CSP console CLIs"
    echo ""
    echo "Usage: $0 [organization-id]"
    echo "  If organization-id is not provided, the script will attempt to find it."
    echo ""
    echo "Available flags:"
    echo " -h       Display this help info"
    exit 1
}

# Initialize options
# No options needed currently besides -h

# Get options
while getopts ":h" opt; do
  case ${opt} in
    h) printHelp ;;
    *) echo "Invalid option: -${OPTARG}" && printHelp exit ;;
 esac
done
shift $((OPTIND-1))

# Ensure gcloud CLI is authenticated
gcloud auth list --filter=status:ACTIVE --format="value(account)" > /dev/null 2>&1
check_error $? "gcloud CLI not authenticated. Please run 'gcloud auth login'."

# Determine Organization ID
ORG_ID=""
if [ -n "$1" ]; then
    # Use Org ID provided as argument
    ORG_ID=$1
    echo "Using provided Organization ID: $ORG_ID"
    # Basic validation if it looks like a number
    if ! [[ "$ORG_ID" =~ ^[0-9]+$ ]]; then
        echo "Error: Provided Organization ID '$ORG_ID' does not appear to be numeric."
        exit 1
    fi
else
    # Attempt to fetch organization ID programatically
    echo "Attempting to detect Organization ID..."
    org_list=$(gcloud organizations list --format="value(ID)")
    check_error $? "Failed to list organizations. Ensure you have 'resourcemanager.organizations.get' permission or provide the Organization ID as an argument."
    
    org_count=$(echo "$org_list" | wc -w)

    if [ "$org_count" -eq 0 ]; then
        echo "Error: No organizations found for the current user. Please provide the Organization ID as an argument."
        exit 1
    elif [ "$org_count" -eq 1 ]; then
        ORG_ID=$org_list
        echo "Automatically detected Organization ID: $ORG_ID"
    else
        echo "Error: Multiple Organization IDs found. Please specify one as an argument:"
        echo "$org_list"
        exit 1
    fi
fi

echo "Counting Compute Engine instances, GKE nodes, and Cloud Functions in organization: $ORG_ID"

# Initialize counters
total_compute_instances=0
total_gke_nodes=0
total_cloud_functions=0 # Added

# --- Optimized Instance Counting ---
echo "Counting Compute Engine instances across organization $ORG_ID using Cloud Asset Inventory..."
# Use gcloud asset search to find all instances and count them
# Requires Cloud Asset API enabled (cloudasset.googleapis.com) and roles/cloudasset.viewer permission at the org level
instance_list=$(gcloud asset search-all-resources --scope=organizations/$ORG_ID --asset-types='compute.googleapis.com/Instance' --format='value(name)' --quiet)
check_error $? "Failed to search for Compute Engine instances using Cloud Asset Inventory. Ensure API is enabled and permissions are set."

if [ -n "$instance_list" ]; then
    total_compute_instances=$(echo "$instance_list" | wc -l)
else
    total_compute_instances=0
fi
echo "  Total Compute Engine instances found: $total_compute_instances"

# --- Optimized GKE Node Counting ---
echo "Counting GKE nodes across organization $ORG_ID using Cloud Asset Inventory..."
# 1. Find all GKE clusters in the organization
cluster_list=$(gcloud asset search-all-resources --scope=organizations/$ORG_ID --asset-types='container.googleapis.com/Cluster' --format='value(name)' --quiet)
check_error $? "Failed to search for GKE clusters using Cloud Asset Inventory. Ensure API is enabled and permissions are set."

if [ -z "$cluster_list" ]; then
    echo "  No GKE clusters found in organization $ORG_ID."
else
    echo "  Found GKE clusters. Describing each to get node counts..."
    total_gke_nodes=0
    # 2. Iterate through clusters and get node counts
    # Cluster name format: //container.googleapis.com/projects/PROJECT_ID/locations/LOCATION/clusters/CLUSTER_NAME
    # We need PROJECT_ID, LOCATION, and CLUSTER_NAME for the describe command
    echo "$cluster_list" | while IFS= read -r cluster_full_name; do
        # Extract components using parameter expansion or awk/sed
        # Example using parameter expansion (might need refinement based on exact format)
        cluster_path=${cluster_full_name#*//} # Remove //container.googleapis.com/
        project_id=$(echo "$cluster_path" | cut -d'/' -f2)
        location=$(echo "$cluster_path" | cut -d'/' -f4)
        cluster_name=$(echo "$cluster_path" | cut -d'/' -f6)

        if [ -z "$project_id" ] || [ -z "$location" ] || [ -z "$cluster_name" ]; then
             echo "    Warning: Could not parse cluster details from '$cluster_full_name'. Skipping."
             continue
        fi

        echo "    Describing cluster '$cluster_name' in project '$project_id' location '$location'..."
        # Set project context for the describe command - suppress stderr
        gcloud config set project "$project_id" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "      Warning: Failed to set project context to '$project_id' for describing cluster '$cluster_name'. Skipping cluster."
            continue
        fi

        # Attempt to get node count, default to 0 on error - suppress stderr
        node_count=$(gcloud container clusters describe "$cluster_name" --location "$location" --format="value(currentNodeCount)" --quiet 2>/dev/null)
        if [ $? -ne 0 ] || ! [[ "$node_count" =~ ^[0-9]+$ ]]; then
             echo "      Warning: Failed to get node count for cluster '$cluster_name'. Assuming 0 nodes."
             node_count=0
        fi
        echo "      Cluster '$cluster_name' has $node_count nodes."
        total_gke_nodes=$((total_gke_nodes + node_count))
    done
fi
echo "  Total GKE nodes found: $total_gke_nodes"

# --- Optimized Cloud Function Counting ---
echo "Counting Cloud Functions across organization $ORG_ID using Cloud Asset Inventory..."
# Use gcloud asset search to find all Cloud Functions (Gen1 and Gen2) and count them
# Requires Cloud Asset API enabled (cloudasset.googleapis.com) and roles/cloudasset.viewer permission at the org level
# Asset type for Gen1/Gen2 functions: cloudfunctions.googleapis.com/CloudFunction
function_list=$(gcloud asset search-all-resources --scope=organizations/$ORG_ID --asset-types='cloudfunctions.googleapis.com/CloudFunction' --format='value(name)' --quiet)
check_error $? "Failed to search for Cloud Functions using Cloud Asset Inventory. Ensure API is enabled and permissions are set."

if [ -n "$function_list" ]; then
    total_cloud_functions=$(echo "$function_list" | wc -l)
else
    total_cloud_functions=0
fi
echo "  Total Cloud Functions found: $total_cloud_functions"


echo "##########################################"
echo "Prisma Cloud GCP inventory collection complete."
echo ""
echo "Resource Summary (Organization: $ORG_ID):"
echo "==============================="
echo "VM Instances:      $total_compute_instances"
echo "GKE container VMs: $total_gke_nodes"
echo "Cloud Functions:   $total_cloud_functions" # Added
