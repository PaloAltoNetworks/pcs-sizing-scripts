# Prisma Cloud Azure License Sizing Script

## Overview

This document describes how to prepare for and run the Prisma Cloud Azure License Sizing Script. This script uses Azure Resource Graph for efficient resource counting across subscriptions.

## Prerequisites

### Required Permissions

The Azure account used to run the sizing script must have the required permissions to query Azure Resource Graph across the desired subscriptions. Typically, the built-in `Reader` role assigned at a management group level encompassing the target subscriptions is sufficient.

### Required Tools

*   Azure CLI (`az`) - Ensure you are logged in (`az login`).
*   `jq` - A command-line JSON processor. Install if not present (e.g., `sudo apt-get install jq` or `brew install jq`).

### Required Azure APIs/Services

The script relies on the Azure Resource Graph service being available and accessible.

## Running the Script

Follow the steps below to run the script.

1.  Download the sizing script to your local computer or Cloud Shell environment:
    *   [resource-count-azure.sh](resource-count-azure.sh)
2.  Log into your Azure account using the Azure CLI:
    *   `az login`
3.  Ensure you have selected the correct tenant if you have access to multiple tenants.
4.  Run the sizing script from a Bash shell (like Azure Cloud Shell or a local terminal):
    *   `bash resource-count-azure.sh`
5.  The script will query Azure Resource Graph and output the total count of VMs and AKS nodes across all accessible subscriptions.
6.  Share the results with your Palo Alto Networks team.

## Notes

*   This script counts all Virtual Machines (`microsoft.compute/virtualmachines`).
*   This script counts all AKS nodes by summing the node counts across all agent pools in all found AKS clusters (`microsoft.containerservice/managedclusters`).
