#!/bin/bash

# Script to fetch Azure inventory for Prisma Cloud sizing using Azure Resource Graph.
# Requirements: az cli (with graph extension potentially needed, though often built-in now), jq
# Permissions: Requires Azure Resource Graph read permissions across target subscriptions.

# Function to handle errors
function check_error {
    local exit_code=$1
    local message=$2
    if [ $exit_code -ne 0 ]; then
        echo "Error: $message (Exit Code: $exit_code)"
        exit $exit_code
    fi
}

# Check for jq dependency
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install jq to run this script."
    echo "(e.g., 'sudo apt-get install jq' or 'sudo yum install jq' or 'brew install jq')"
    exit 1
fi

# Ensure Azure CLI is logged in
az account show > /dev/null 2>&1
check_error $? "Azure CLI not logged in. Please run 'az login'."

echo "Counting resources across accessible subscriptions using Azure Resource Graph..."

# Initialize counts
total_vm_count=0
total_node_count=0

# --- Count VMs using Azure Resource Graph ---
echo "Querying Azure Resource Graph for VM count..."
# Query for all VMs across all accessible subscriptions
vm_query="Resources | where type =~ 'microsoft.compute/virtualmachines' | count"
vm_result_json=$(az graph query -q "$vm_query" --output json)
vm_query_exit_code=$?

if [ $vm_query_exit_code -ne 0 ]; then
    echo "  Warning: Failed to query Azure Resource Graph for VMs (Exit Code: $vm_query_exit_code). Assuming 0 VMs."
    total_vm_count=0
else
    # Extract count using jq
    total_vm_count=$(echo "$vm_result_json" | jq '.count // 0')
    if ! [[ "$total_vm_count" =~ ^[0-9]+$ ]]; then
         echo "  Warning: Could not parse VM count from Resource Graph result. Assuming 0 VMs."
         total_vm_count=0
    fi
fi
echo "Total VM Instances found: $total_vm_count"


# --- Count AKS Nodes using Azure Resource Graph ---
echo "Querying Azure Resource Graph for AKS node count..."
# Query for AKS clusters, expand agent pools, and sum node counts
aks_query="Resources | where type =~ 'microsoft.containerservice/managedclusters' | project properties.agentPoolProfiles | mv-expand profile = properties_agentPoolProfiles | summarize sum(toint(profile.count))"
aks_result_json=$(az graph query -q "$aks_query" --output json)
aks_query_exit_code=$?

if [ $aks_query_exit_code -ne 0 ]; then
    echo "  Warning: Failed to query Azure Resource Graph for AKS nodes (Exit Code: $aks_query_exit_code). Assuming 0 nodes."
    total_node_count=0
else
    # Extract sum using jq - the field name is typically 'sum_' followed by the summarized field
    total_node_count=$(echo "$aks_result_json" | jq '.data[0].sum_profile_count // 0')
     if ! [[ "$total_node_count" =~ ^[0-9]+$ ]]; then
         echo "  Warning: Could not parse AKS node count from Resource Graph result. Assuming 0 nodes."
         total_node_count=0
    fi
fi
echo "Total AKS container VMs (nodes) found: $total_node_count"


echo "##########################################"
echo "Prisma Cloud Azure inventory collection complete (using Azure Resource Graph)."
echo ""
echo "VM Summary (all accessible subscriptions):"
echo "==============================="
echo "VM Instances:      $total_vm_count"
echo "AKS container VMs: $total_node_count"