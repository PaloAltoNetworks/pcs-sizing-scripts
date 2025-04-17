# Prisma Cloud AWS License Sizing Script

## Overview

This document describes how to prepare for, and how to run the Prisma Cloud AWS License Sizing Script. This script helps gather resource counts relevant for Prisma Cloud licensing.

## Prerequisites

### Required Permissions

The AWS account or role used to run the sizing script must have the required permissions to be able to collect sizing information. See the list of APIs below for guidance on minimum permissions (e.g., `ec2:DescribeInstances`, `sts:AssumeRole`, `account:ListRegions`).

### Required Tools

*   AWS CLI v2 - Ensure you are logged in (`aws configure`) and that the version is recent enough to support `aws account list-regions`.
*   `jq` - A command-line JSON processor. Install if not present (e.g., `sudo apt-get install jq` or `brew install jq`).

### Required AWS APIs

The below AWS APIs need to be enabled and accessible via the credentials/role used to run the script in order to gather information from AWS. Permissions are needed for the corresponding actions.

**Core:**
*   `sts:GetCallerIdentity`
*   `account:ListRegions` (Requires up-to-date AWS CLI v2)

**CSPM Resources (Default Mode):**
*   `ec2:DescribeInstances`
*   `eks:ListClusters`
*   `eks:ListNodegroups`
*   `eks:DescribeNodegroup`

**DSPM Resources (Requires `-d` flag):**
*   `s3api:ListBuckets`
*   `efs:DescribeFileSystems`
*   `rds:DescribeDBClusters` (specifically for Aurora)
*   `rds:DescribeDBInstances` (specifically for MySQL, MariaDB, PostgreSQL)
*   `dynamodb:ListTables`
*   `redshift:DescribeClusters`

**Organization Mode (Requires `-o` flag):**
*   `organizations:ListAccounts`
*   `sts:AssumeRole` (on the target accounts, typically `OrganizationAccountAccessRole`)

**EC2 Database Scan via SSM (Requires `-c` flag, implies `-d`):**
*   `ssm:DescribeInstanceInformation`
*   `ssm:SendCommand`
*   `ssm:ListCommandInvocations`
*   `ec2:DescribeSecurityGroups` (Used within the DB scan function)

## AWS Organization Support

The script can collect sizing information for AWS accounts attached to an AWS Organization by specifying the `-o` flag.
*   Optionally use `-r <RoleName>` to specify a different role to assume instead of the default `OrganizationAccountAccessRole`.

It does this by leveraging the specified cross-account role (defaulting to `OrganizationAccountAccessRole`).

https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_accounts_access.html

Flow and logic for AWS Organizations:
1.  Queries for **active** member accounts using the Organizations API.
2.  Loops through each member account.
3.  Authenticates into each member account via STS Assume Role into the specified role with the minimum session duration possible (900 seconds).
4.  Counts resources based on other flags (`-d`, `-c`).

The `OrganizationAccountAccessRole` is automatically created in an account if the account was provisioned via the organization. If the account was not originally provisioned in that manner, the role may not exist and assuming the role may fail. Administrators can create the role manually by following the documentation linked above.

## DSPM Support

The script counts resources relevant for Data Security Posture Management (DSPM) licensing when the `-d` flag is specified.
* Example: `./resource-count-aws.sh -d`

## EC2 Database Scan Support

When running in DSPM mode (`-d`), you can optionally enable scanning of EC2 instances via SSM to detect running database processes using the `-c` flag. This requires the SSM agent to be installed and configured on the target EC2 instances and appropriate IAM permissions for SSM commands.
* Example: `./resource-count-aws.sh -d -c`

## Compute State

By default, only running EC2 instances are counted. Use the `-s` flag to include stopped instances as well.
* Example: `./resource-count-aws.sh -s`
* Example: `./resource-count-aws.sh -d -s`

## Running the Script from AWS Cloud Shell

1.  Start a Cloud Shell session from the AWS UI, which should have the AWS CLI tool, your credentials, `git` and `jq` already prepared. Ensure the AWS CLI is v2 and up-to-date.
2.  Clone this repository, e.g. `git clone https://github.com/PaloAltoNetworks/pcs-sizing-scripts.git`
3.  `cd pcs-sizing-scripts/aws`
4.  `chmod +x resource-count-aws.sh`
5.  Run the script with desired flags (e.g., `./resource-count-aws.sh`, `./resource-count-aws.sh -o`, `./resource-count-aws.sh -d -c -s`)

## Running the Script on Windows

### Prerequisites on Windows

Follow the steps below to install prerequisites, if you plan to run the script on a Windows system using WSL.

1.  Install, and enable the Windows Subsystem for Linux
    *   Navigate to "Windows Control Panel" - "Turn Windows Features On or Off"
    *   Install the "Windows Subsystem for Linux" component
2.  Install a Linux distribution on Windows
    *   Navigate to the "Microsoft Store"
    *   Search for Ubuntu, and Install the "Ubuntu 20.04 LTS" (or later) Linux distribution
    *   Important​: Click "Launch" to finish the Ubuntu installation, and set a Linux username/password
3.  Install JQ and Unzip in your Linux distribution
    *   If the Ubuntu shell is not open, launch it from the Start menu
    *   Run the following command to install jq and unzip:
        *   `sudo apt-get update -y && sudo apt-get install -y jq unzip`
4.  Install/Update the AWS Command Line Interface (CLI) v2 in your Linux distribution
    *   If the Ubuntu shell is not open, launch it from the Start menu
    *   Run the following to install/update AWS CLI v2:
        *   `curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"`
        *   `unzip -o awscliv2.zip`
        *   `sudo ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update`
        *   `rm -rf aws awscliv2.zip`
    *   Run `aws --version` to verify the install (should be 2.x).
    *   Refer to the​ Install Guide​ from AWS for updated information: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

### Executing the Script on Windows

Follow the steps below to run the Prisma Cloud AWS License Sizing Script on Windows via WSL.

1.  Download or clone the sizing script repository to your local computer
    *   Example: Create a "Prisma Cloud" folder on your local Windows drive (`C:\Prisma Cloud`)
    *   Place the `resource-count-aws.sh` script (or the whole cloned repo) there.
2.  Execute the sizing script in your Linux distribution (WSL)
    *   If the Ubuntu shell is not open, launch it from the Start menu
    *   Run `aws configure` command to connect to your AWS account if not already configured.
        *   Provide the AWS Access Key and Secret Key.
        *   Set the default region (or leave as none if scanning all enabled regions).
        *   Set the output format (e.g., json).
    *   Navigate to the script directory using the WSL path (e.g., `cd /mnt/c/Prisma\ Cloud/pcs-sizing-scripts/aws`)
    *   Make the script executable: `chmod +x resource-count-aws.sh`
    *   Run the script with desired flags: `./resource-count-aws.sh [flags]`
3.  Share the results with your Palo Alto Networks Team
    *   Share the output from the licensing script with your Palo Alto Networks team.
    *   Remember to run the sizing script for each AWS account/organization in your environment, and share the output from each.

## Running the Script on Mac OSX or Linux

### Prerequisites on Mac OSX / Linux

1.  Install JQ
    *   **macOS (using Homebrew):** `brew install jq`
    *   **Linux (Debian/Ubuntu):** `sudo apt-get update && sudo apt-get install -y jq`
    *   **Linux (CentOS/RHEL/Fedora):** `sudo yum install -y jq` or `sudo dnf install -y jq`
    *   See https://stedolan.github.io/jq/download/ for other methods.
2.  Install/Update the AWS CLI v2
    *   **macOS (using Homebrew):** `brew install awscli` (ensure it installs v2) or follow official AWS guide.
    *   **Linux:** Follow the official AWS guide: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html (Similar steps to the WSL instructions above).
    *   Verify with `aws --version`.

### Executing the Script on Mac OSX or Linux

1.  Download or clone the sizing script repository.
2.  Execute the sizing script
    *   Start a Terminal session.
    *   Run `aws configure` to connect to your AWS account if not already configured.
    *   Within the Terminal, navigate to the script directory (e.g., `cd pcs-sizing-scripts/aws`).
    *   Make the script executable: `chmod +x resource-count-aws.sh`
    *   Run the sizing script with desired flags: `./resource-count-aws.sh [flags]`
3.  Share the results with your Palo Alto Networks Team
    *   Share the output from the licensing script with your Palo Alto Networks team.
    *   Remember to run the sizing script for each AWS account/organization in your environment, and share the output from each.
