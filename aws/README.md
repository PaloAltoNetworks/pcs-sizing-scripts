# Prisma Cloud AWS License Sizing Script

## Overview

This document describes how to prepare for, and how to run the Prisma Cloud AWS License Sizing Script.

## Prerequisites

### Required Permissions

The AWS account that is used to run the sizing script must have the required permissions to be able to collect sizing information.

### Required AWS APIs

The below AWS APIs need to be enabled in order to gather information from AWS.

* aws organizations describe-organization (optional, when running as `resource-count-aws.sh org`)
* aws organizations list-accounts (optional, when running as `resource-count-aws.sh org`)
* aws sts assume-role (optional, when running as `resource-count-aws.sh org`)
* aws ec2 describe-instances
* aws rds describe-db-instances
* aws ec2 describe-nat-gateways
* aws redshift describe-clusters
* aws elb describe-load-balancer
* aws lambda get-account-settings (optional, when running as `resource-count-aws.sh cwp`)

## AWS Organization Support

The script can collect sizing information for AWS accounts attached to an AWS Organization by specifying `org` as a parameter.

It does this by leveraging the AWS `OrganizationAccountAccessRole`

https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_accounts_access.html

Flow and logic for AWS Organizations:

1. Queries for member accounts using the Organizations API
1. Loops through each member account
1. Authenticates into each member account via STS Assume Role into the `OrganizationAccountAccessRole` with the minimum session duration possible (900 seconds)
1. Counts resources

The `OrganizationAccountAccessRole` is automatically created in an account if the account was provisioned via the organization.
If the account was not originally provisioned in that manner, the role may not exist and assuming the role may fail.
Administrators can create the role manually by following this documentation:

https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_accounts_access.html

## Compute Support

The script can collect sizing information for Prisma Cloud Compute (CWP, aka Cloud Workload Protection) by specifying `cwp` as a parameter.

Currently, this is limited to counting AWS Lambda Functions.

## Running the Script from AWS Cloud Shell

1. Start a Cloud Shell session from the AWS UI, which should have the AWS CLI tool, your credentials, ```git``` and ``jq`` already prepared
2. Clone this repository, e.g. ```git clone https://github.com/PaloAltoNetworks/pcs-sizing-scripts.git```
3. ```cd pcs-sizing-scripts/aws```
4. ```chmod +x  resource-count-aws.sh```
5. ```./resource-count-aws.sh```

## Running the Script on Windows

### Prerequisites on Windows

Follow the steps below to install prerequisites, if you plan to run the script on a Windows system. 

1. Install, and enable the Windows Subsystem for Linux
    1. Navigate to "Windows Control Panel" - "Turn Windows Features On or Off"
    1. Install the "Windows Subsystem for Linux" component
1. Install a Linux distribution on Windows
    1. Navigate to the "Microsoft Store"
    1. Search for Ubuntu, and Install the "Ubuntu 20.04 LTS" Linux distribution
    1. Important​: Click "Launch" to finish the Ubuntu installation, and set a Linux username/password
1. Install Python in your Linux distribution
    1. If the Ubuntu shell is not open, launch it from the Start menu
    1. Run the following commands to install Python
        1. `sudo apt-get update -y`
        1. `sudo apt-get install python3-pip -y`
1. Install JQ and Unzip in your Linux distribution
    1. If the Ubuntu shell is not open, launch it from the Start menu
    1. Run the following command to install jq and unzip:
        1. `sudo apt install jq -y`
        1. `sudo apt install unzip -y`
1. Install the AWS Command Line Interface (CLI) in your Linux distribution
    1. If the Ubuntu shell is not open, launch it from the Start menu
    1. Run the following to install the AWS CLI
        1. `curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"`
        1. `unzip awscliv2.zip`
        1. `cd aws`
        1. `sudo ./install`
    1. Run `aws --version` to verify the install
    1. Refer to the​Install Guide​from AWS for updated information
        1. https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-install.html

### Executing the Script on Windows

Follow the steps below to run the Prisma Cloud AWS License Sizing Script on Windows.

1. Download the sizing script to your local computer
    1. Create a "Prisma Cloud" folder on your local Windows drive ("C:\Prisma Cloud" in this example)
    1. Download the Prisma Cloud licensing script to the new Prisma Cloud folder
    1. [resource-count-aws.sh](resource-count-aws.sh)
1. Execute the sizing script in your Linux distribution
    1. If the Ubuntu shell is not open, launch it from the Start menu
    1. Run "aws configure" command to connect to your AWS account
        1. Provide the AWS Access Key for the AWS account you want to analyze
        1. Provide the AWS Secret Key for the AWS account you want to analyze
        1. Set the default region to none
        1. Set the output format to none
    1. Run the following command to mount the local Windows c:\Prisma Cloud drive in Ubuntu
        1. `cd /mnt/c/Prisma\ Cloud`
    1. Run the following command to run the sizing script
        1. `./resource-count-aws.sh`
1. Share the results with your Palo Alto Networks Team
    1. Share the output from the licensing script with your Palo Alto Networks team
    1. Remember to run the sizing script for each AWS account in your environment, and share the output from each account

## Running the Script on Mac OSX or Linux

### Prerequisites on Mac OSX

Follow the steps below to install prerequisites, if you plan to run the script on a Mac OSX system. 

1. Install JQ on your Mac computer
    1. Download and install Homebrew from the following location:
        1. ​https://brew.sh/
    1. Start a Terminal session
    1. Run the following command to install jq
        1. `brew install jq`
    1. Additional details can be found here, if needed
        1. https://stedolan.github.io/jq/download/
1. Install the AWS CLI on your Mac computer
    1. Start a Terminal session
    1. Run the following command to install the AWS CLI
        1. `brew install awscli`
    1. Run the following command to verify the AWS CLI installation
        1. `aws --version`
    1. Additional details can be found here, if needed
        1. http://docs.aws.amazon.com/cli/latest/userguide/cli-install-macos.html
        1. http://docs.aws.amazon.com/cli/latest/userguide/cli-install-macos.html#awscli install-osx-path

### Executing the Script on Mac OSX or Linux

1. Download the Prisma Cloud AWS License Sizing Script
    1. Download the Prisma Cloud licensing script to your local drive ("Downloads" in this example)
1. Execute the sizing script
    1. Start a Terminal session
    1. Run `aws configure` to connect to your AWS account
        1. Provide AWS Access Key for the AWS account you want to analyze
        1. Provide AWS Secret Key for the AWS account you want to analyze
        1. Set the default region to none
        1. Set the output format to none
    1. Within the Terminal, navigate to the directory with the sizing script
    1. Run the sizing script:
        1. `chmod +x resource-count-aws.sh`
        1. `./resource-count-aws.sh`
1. Share the results with your Palo Alto Networks Team
    1. Share the output from the licensing script with your Palo Alto Networks team
    1. Remember to run the sizing script for each AWS account in your environment, and share the output from each account
