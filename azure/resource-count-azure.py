##########################################
# Azure Subscription Resource Census
#
# Prerequisites: None
#
# API used:
# - az account list
# - az resource list
#
# Instruction:
# - Go to Azure Portal
# - Turn on Cloud SHell (Bash)
# - Upload the script
# - run the script:
#       python3 <script_name.py>
#


import subprocess
import json


mapping = {
    "Microsoft.Network/loadBalancers" : "Load Balancers",
    "Microsoft.Sql/servers/databases" : "SQL Server and databases",
    "Microsoft.Sql/servers": "SQL Server and databases",
    "Microsoft.Sql/managedInstances:": "SQL Managed Instances",
    "Microsoft.DBforPostgreSQL/servers": "PostgreSQL Servers"
}

errors = []

accounts = json.loads(subprocess.getoutput("az account list --all --output json 2>&1"))

global_count = 0
for account in accounts:
    if account['state'] != 'Enabled':
        continue

    print("Processing account {} ({})".format(account['name'], account['id']))

    total_count = 0
    census = {}

    try:
        # Get running VM separately
        running_vms = json.loads(subprocess.getoutput("az vm list -d --query \"[?powerState=='VM running']\" --subscription {} --output json 2>&1 | jq '.[].id' | wc -l".format(account['id'])))
        if running_vms > 0:
            census["(running) Virtual Machines"] = running_vms
            total_count += running_vms
    except Exception as e:
        error = '{} ({}) - Error encountered when trying to run az vm list. Continuing...'.format(account['name'], account['id'])
        errors.append(error)
        print(error)

    try:
        resources = json.loads(subprocess.getoutput("az resource list --subscription {} --output json 2>&1".format(account['id'])))

        for resource in resources:
            resource_type = resource['type']

            if resource_type in mapping:
                total_count += 1
                if mapping[resource_type] in census:
                    census[mapping[resource_type]] += 1
                else:
                    census[mapping[resource_type]] = 1



        for resource_type, count in sorted(census.items()):
            print("{} : {}".format(resource_type, count))
    except Exception as e:
        error = '{} ({}) - Error encountered when executing az resource list. Received unexpected response from Azure API'.format(account['name'], account['id'])
        errors.append(error)
        print(error)





    print("TOTAL BILLABLE RESOURCE: {} \n\n\n".format(total_count))
    global_count += total_count


print("###########################\nGrant total billable resource count: {}\n###########################".format(global_count))

print("\n\nList of errors encountered:")
for error in errors:
    print(error)

