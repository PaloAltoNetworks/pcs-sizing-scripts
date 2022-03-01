# Prisma Cloud Azure License Sizing Script

## Overview

This document describes how to prepare for and run the Prisma Cloud Azure License Sizing Script.

## Prerequisites

### Required Permissions

The Azure account that is used to run the sizing script must have the required permissions to be able to collect sizing information.

### Required Azure APIs

The Azure APIs below need to be enabled in order to gather information from Azure.

* `az account list`
* `az resource list`
* `az vm list`

## Running the Script

Follow the steps below to run the script.

1. Download the sizing script to your local computer
    1. [resource-count-azure.py](resource-count-azure.py)
1. Log into your Azure Console
1. Launch Azure Cloud Shell
1. Select "Bash" as your shell in your Azure Console.
1. Click the "Upload/Download Files" button to upload the sizing script
1. Run the sizing script
    1. `python3 resource-count-azure.py`
1. Share the results with your Palo Alto Networks team
