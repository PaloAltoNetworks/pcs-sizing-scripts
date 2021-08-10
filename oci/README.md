# Prisma Cloud OCI License Sizing Script

## Overview

This document describes how to prepare for, and how to run the Prisma Cloud OCI License Sizing Script.

## Prerequisites

### Required Permissions

The OCI account that is used to run the sizing script must have the required permissions to be able to collect sizing information.

### Required OCI API/CLIs

The below OCI APIs need to be enabled in order to gather information from OCI.

* oci iam compartment list
* oci compute instance list

## Running the Script

Follow the steps below to run the Prisma Cloud OCI License Sizing Script.

1. Download the sizing script to your local computer
    1. [resource-count-oci.sh](resource-count-oci.sh)
1. Log into your OCI Console
1. Launch the OCI Cloud Shell
1. Click on the three bar vertical menu on the left side of the Cloud Shell window
1. Select "Upload File"
1. Upload the sizing script to your OCI Cloud Shell
1. Run the sizing script.
    1. `chmod +x resource-count-oci.sh`
    1. `./resource-count-oci.sh`
1. Share the results with your Palo Alto Networks team