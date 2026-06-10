# Prisma Cloud GCP License Sizing Script

## Overview

This document describes how to prepare for, and how to run the Prisma Cloud GCP License Sizing Script. This script uses Cloud Asset Inventory for efficient resource counting across an organization.

## Prerequisites

### Required Permissions

The GCP account used to run the sizing script must have the required permissions to be able to collect sizing information across the target organization. This typically includes:
*   `resourcemanager.organizations.get` (to find the organization ID if not provided)
*   `cloudasset.assets.searchAllResources` (at the organization level)
*   `container.clusters.get` (on projects containing GKE clusters)
*   Permissions to set the gcloud project context (`gcloud config set project`) for describing GKE clusters.

### Required GCP APIs

The following APIs need to be enabled in a project where billing is enabled (often the project running Cloud Shell or a dedicated admin project) and potentially within the target projects/organization depending on configuration:
*   Cloud Asset API (`cloudasset.googleapis.com`)
*   Compute Engine API (`compute.googleapis.com`) - Although not directly called by the optimized script, it's related.
*   Kubernetes Engine API (`container.googleapis.com`) - Needed for `gcloud container clusters describe`.

### Required Tools

*   Google Cloud SDK (`gcloud`) - Ensure you are logged in (`gcloud auth login`).
*   `jq` - A command-line JSON processor. Install if not present (e.g., `sudo apt-get install jq` or `brew install jq`). Cloud Shell usually has this pre-installed.

## Running the Script

Follow the steps below to run the Prisma Cloud GCP License Sizing Script.

1.  Download the sizing script to your local computer or Cloud Shell environment:
    *   [resource-count-gcp.sh](resource-count-gcp.sh)
2.  Log into your GCP account using the gcloud CLI:
    *   `gcloud auth login`
    *   `gcloud config set account ACCOUNT_EMAIL`
3.  Launch the GCP Cloud Shell or use a local terminal with gcloud configured.
4.  If running locally or if Cloud Shell doesn't have the necessary APIs enabled by default, ensure the Cloud Asset API is enabled in your active project:
    *   `gcloud services enable cloudasset.googleapis.com`
5.  Make the script executable:
    *   `chmod +x resource-count-gcp.sh`
6.  Run the sizing script. You can optionally provide the numeric Organization ID as an argument. If omitted, the script will attempt to detect it (requires appropriate permissions and works best if the user belongs to only one organization).
    *   `./resource-count-gcp.sh [ORGANIZATION_ID]`
    *   Example (auto-detect): `./resource-count-gcp.sh`
    *   Example (specific org): `./resource-count-gcp.sh 123456789012`
7.  The script will query Cloud Asset Inventory and GKE APIs, then output the total count of Compute Engine instances and GKE nodes across the organization.
8.  Share the results with your Palo Alto Networks team.

## Notes

*   This script counts all Compute Engine VM Instances (`compute.googleapis.com/Instance`).
*   This script counts all GKE nodes by finding all Clusters (`container.googleapis.com/Cluster`) via Asset Inventory and then describing each cluster to get its current node count.