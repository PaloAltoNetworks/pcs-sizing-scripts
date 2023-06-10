##########################################
# Azure Subscription Resource Count
#
# Prerequisites: None
#
# Azure APIs Used:
#
# - az account list
# - az resource list
# - az vm list
# - az aks list
# - az aks show
#
# Instructions:
#
# - Go to Azure Portal
# - Use Cloud Shell (Bash)
# - Upload the script
# - Run the script:
#       python3 resource-count-azure.py
#
# Limitations:
#
# - In this release, AKS nodes are only counted in the first node pool.
##########################################

import subprocess
import json

# (This script queries for running VMs separately.)

resource_mapping = {
    'Microsoft.DBforPostgreSQL/servers': 'PostgreSQL Servers',
    'Microsoft.Network/loadBalancers'  : 'Network Load Balancers',
    'Microsoft.Sql/managedInstances:'  : 'SQL Managed Instances',
    'Microsoft.Sql/servers'            : 'SQL Server and Databases',
    'Microsoft.Sql/servers/databases'  : 'SQL Server and Databases'
}

global_az_resource_count = 0
global_az_aks_node_count = 0
error_list = []

az_account_list = json.loads(subprocess.getoutput('az account list --all --output json 2>&1'))

for az_account in az_account_list:
    if az_account['state'] != 'Enabled':
        continue
    print('###################################################################################')
    print("Processing Account: {} ({})".format(az_account['name'], az_account['id']))

    az_aks_node_count = 0
    az_account_aks_node_count = 0
    az_account_resource_count = 0
    az_account_census = {}

    #---------------------------------------------------------------
    # Scan for running Azure VM's based on current Azure account id.
    #---------------------------------------------------------------
    try:
        # Query for running VMs separately.
        az_vm_list_count = subprocess.getoutput("az vm list -d --query \"[?powerState=='VM running']\" --subscription {} --output json 2>&1 | jq '.[].id' | wc -l".format(az_account['id']))
        az_vm_list_count = json.loads(az_vm_list_count)
        if az_vm_list_count > 0:
            az_account_census['(running) Virtual Machines'] = az_vm_list_count
            az_account_resource_count += az_vm_list_count
    except Exception as e:
        this_error = "{} ({}) - Error executing 'az vm list'.".format(az_account['name'], az_account['id'])
        error_list.append(this_error)
        print(this_error)

    #------------------------------------------------------------
    # Scan for Azure resources based on current Azure account id.
    #------------------------------------------------------------
    try:
        az_resource_list = subprocess.getoutput("az resource list --subscription {} --output json 2>&1".format(az_account['id']))
        az_resources = json.loads(az_resource_list)
        for az_resource in az_resources:
            resource_type = az_resource['type']
            if resource_type in resource_mapping:
                az_account_resource_count += 1
                if resource_mapping[resource_type] in az_account_census:
                    az_account_census[resource_mapping[resource_type]] += 1
                else:
                    az_account_census[resource_mapping[resource_type]] = 1
        for resource_type, resource_count in sorted(az_account_census.items()):
            print("{}: {}".format(resource_type, resource_count))
    except Exception as e:
        this_error = "{} ({}) - Error executing 'az resource list'.".format(az_account['name'], az_account['id'])
        error_list.append(this_error)
        print(this_error)

    #---------------------------------------------------------
    # Scan for AKS clusters based on current Azure account id.
    #---------------------------------------------------------
    try:
        az_aks_list = subprocess.getoutput("az aks list --subscription {} --output json 2>&1".format(az_account['id']))
        az_aks_clusters = json.loads(az_aks_list)
        for az_aks_cluster in az_aks_clusters:
            az_aks_node_count = subprocess.getoutput("az aks show --name {} --resource-group {} --subscription {} --query agentPoolProfiles[0].count".format(az_aks_cluster['name'], az_aks_cluster['resourceGroup'], az_account['id']))
            if int(az_aks_node_count) > 0:
                print("  Cluster: " + az_aks_cluster['name'] + " - Nodes: " + az_aks_node_count)
                az_account_aks_node_count += int(az_aks_node_count)


    except Exception as e:
        this_error = "{} ({}) - Error executing 'az aks list'.".format(az_account['name'], az_account['id'])
        error_list.append(this_error)
        print(this_error)

    print("Total Billable Resources: {}".format(az_account_resource_count))
    print("Total AKS Nodes {}".format(az_account_aks_node_count))
    print('###################################################################################')
    global_az_resource_count += az_account_resource_count
    global_az_aks_node_count += az_account_aks_node_count

print()
print('###################################################################################')
print("Grand Total Billable Resources: {}".format(global_az_resource_count))
print()
print("If you will be using the IAM Security Module, total billable resources will be: {}".format(round(global_az_resource_count * 1.25)))
print('###################################################################################')
print("Grand Total AKS Nodes: {} - Currently not added to billable resources (ex. VM's)".format(global_az_aks_node_count))
print("Note: In this release, AKS nodes are only counted in the first node pool.")
print()

if error_list:
    print('###################################################################################')
    print('Errors:')
    for this_error in error_list:
        print(this_error)
    print('###################################################################################')
    print()

