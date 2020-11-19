# GCP project Resource Count
#
# API/CLI used:
# - gcloud compute instances list
# - gcloud sql instances list
# - gcloud compute forwarding-rules list
# - gcloud compute routers list
# - gcloud compute routers nats list
#
#
# Instructions
# - Go to GCP console
# - Open Cloud Shell >_
# - Click on three dot vertical menu on the right side (left of minimize button)
# - Upload this script
# - Run the script:
#   /bin/bash <script_name.sh>

#
# Script may generate error when:
# - API is not enabled (gcloud ask user prompt to enable the API)
# - you don't have access to make the API call
#
# If silent mode is set to true:
# - you won't get prompt to enable the API (we assume that you don't use the service, thus resource count is assumed to be 0)
# - when an error is encountered, you are most likely don't have API access. Resource count is set to 0
silent_mode=true



if [[ $silent_mode = true ]]; then
    verbosity_args="--verbosity critical --quiet"
else
    verbosity_args="--verbosity error"
fi


projects=($(gcloud projects list --format json | jq  -r '.[].projectId'))
project_total_count=${#projects[@]}

global_count=0

current_project_count=1
for i in "${projects[@]}"
do
    echo "### Project $current_project_count of $project_total_count : $i"
    total_count=0
    current_project_count=$((current_project_count + 1))

    ## Grab GCP instances
    count=`gcloud compute instances list --filter="status:(RUNNING)" --project $i  --format json $verbosity_args | jq '.[].name'  | wc -l`
    echo "    Total running compute instance: $count"
    total_count=$(( $total_count + count ))

    ## Grab GCP Cloud SQL
    count=`gcloud sql instances list --project $i --format json $verbosity_args  | jq '.[].name'  | wc -l`
    echo "    Total Cloud SQL instances: $count"
    total_count=$(( $total_count + count ))


    ## Grab GCP Load balancer (forwarding rules)
    count=`gcloud compute forwarding-rules list --project $i --format  json | jq '.[].id' | wc -l`
    echo "    Total load balancer forwarding rules: $count"
    total_count=$(( $total_count + count ))


    ## Grab NAT Count
    nat_count=0
    routers=($(gcloud compute routers list --project $i --format json $verbosity_args | jq  -r '.[] | "\(.name);\(.region)"'))
    for j in "${routers[@]}"
    do
        name=$(cut -d ';' -f 1 <<< "$j")
        region=${j##*/}
        count=`gcloud compute routers nats list --project $i --region $region --router $name --format json $verbosity_args | jq -r '.[].name' | wc -l`
        nat_count=$(( $nat_count + count ))
    done
    echo "    Total Cloud NAT: $nat_count"
    total_count=$(( total_count + nat_count ))


    ## Grab Google Cloud Load Balancing (gcloud-compute-internal-lb-backend-service)
    count=`gcloud compute backend-services list --project $i --format json $verbosity_args | jq '.[].name'  | wc -l`
    echo "Total Load Balancing services: $count"
    total_count=$(( $total_count + count ))



    echo -e "Total billable resource count: $total_count \n\n"
    global_count=$(( global_count + total_count ))
done

echo -e "###########################\n Grant total billable resource count: $global_count \n###########################"

