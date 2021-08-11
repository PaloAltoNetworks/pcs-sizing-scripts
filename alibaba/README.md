# Prisma Cloud Alibaba Cloud License Sizing Script

## Overview

This document describes how to prepare for, and how to run the Prisma Cloud Alibaba Cloud License Sizing Script.

## Prerequisites

### Required Permissions

The Alibaba Cloud account that is used to run the sizing script must have the required permissions to be able to collect sizing information.

### Required Alibaba Cloud API/CLIs

The below Alibaba Cloud APIs need to be enabled in order to gather information from Alibaba Cloud.

* aliyun ecs DescribeRegions
* aliyun ecs DescribeInstances

## Running the Script

Follow the steps below to run the Prisma Cloud Alibaba Cloud License Sizing Script.

1. Download the sizing script to your local computer
    1. [resource-count-abc.sh](resource-count-abc.sh)
1. Log into your Alibaba Cloud Console
1. Launch the Alibaba Cloud Cloud Shell
1. Click on the cloud on the left side of the Cloud Shell window
1. Select "Upload"
1. Upload the sizing script to your Alibaba Cloud Shell
1. Run the sizing script.
    1. `chmod +x resource-count-abc.sh`
    1. `./resource-count-abc.sh`
1. Share the results with your Palo Alto Networks team