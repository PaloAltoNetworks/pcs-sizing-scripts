# To use this test, call: shellspec spec/resource-count-gcp.spec

Describe 'resource-count-gcp'

  ########################################################################################
  # Includes and Setup
  ########################################################################################

  Include gcp/resource-count-gcp.sh

  # Mock gcloud CLI commands
  gcloud() {
    # echo "Mock gcloud called with: $@" >&2 # Debugging line
    case "$1 $2" in
      "auth list") # Mock successful authentication check
        echo "test@example.com"
        return 0
        ;;
      "organizations list") # Mock finding a single organization
        echo "123456789012" # Mock Org ID
        return 0
        ;;
      "asset search-all-resources")
        # Mock asset search based on --asset-types
        local asset_type=""
        # Simple loop to find --asset-types value
        for i in $(seq 1 $#); do
          if [ "${!i}" == "--asset-types" ]; then
            local next_i=$((i + 1))
            asset_type="${!next_i}"
            break
          fi
        done

        # Return mock resource names based on asset type for wc -l counting
        case "$asset_type" in
          'compute.googleapis.com/Instance')
            # Mock 3 compute instances
            echo "//compute.googleapis.com/projects/p1/zones/z1/instances/i1"
            echo "//compute.googleapis.com/projects/p1/zones/z1/instances/i2"
            echo "//compute.googleapis.com/projects/p2/zones/z2/instances/i3"
            ;;
          'container.googleapis.com/Cluster')
            # Mock 2 GKE clusters
            echo "//container.googleapis.com/projects/p1/locations/l1/clusters/c1"
            echo "//container.googleapis.com/projects/p2/locations/l2/clusters/c2"
            ;;
          'cloudfunctions.googleapis.com/CloudFunction')
             # Mock 4 Cloud Functions
            echo "//cloudfunctions.googleapis.com/projects/p1/locations/l1/functions/f1"
            echo "//cloudfunctions.googleapis.com/projects/p1/locations/l1/functions/f2"
            echo "//cloudfunctions.googleapis.com/projects/p2/locations/l2/functions/f3"
            echo "//cloudfunctions.googleapis.com/projects/p3/locations/l3/functions/f4"
            ;;
          *)
            # Return nothing for unmocked types
            ;;
        esac
        return 0
        ;;
      "config set") # Mock setting project config
         # Assume success
         return 0
         ;;
      "container clusters")
         if [ "$3" == "describe" ]; then
            # Mock describe cluster - return 2 nodes for each cluster
            echo "2" # Mock currentNodeCount
            return 0
         fi
         ;;
      *)
        # Default mock for unhandled commands
        echo "Unhandled mock gcloud command: $@" >&2
        return 1 # Indicate error for unhandled commands
        ;;
    esac
  }
  # Export the mock function
  export -f gcloud

  ########################################################################################
  # Tests
  ########################################################################################

  # Reset counters before test
  Before 'reset_global_counters'

  It 'counts organization resources correctly'
    # Mock Org ID argument for simplicity, could also test auto-detection
    ORG_ID_ARG="123456789012"

    # Expected counts based on mocks:
    # Instances: 3
    # Clusters: 2
    # Nodes: 2 clusters * 2 nodes/cluster = 4
    # Functions: 4
    expected_instances=3
    expected_gke_nodes=4
    expected_functions=4

    When run script gcp/resource-count-gcp.sh "$ORG_ID_ARG"

    # Check final counts
    The variable total_compute_instances should eq "$expected_instances"
    The variable total_gke_nodes should eq "$expected_gke_nodes"
    The variable total_cloud_functions should eq "$expected_functions"

    The status should be success
    The error should be empty # Check no errors printed
    The output should include "Total Compute Engine instances found: $expected_instances"
    The output should include "Total GKE nodes found: $expected_gke_nodes"
    The output should include "Total Cloud Functions found: $expected_functions"
    The output should include "VM Instances:      $expected_instances"
    The output should include "GKE container VMs: $expected_gke_nodes"
    The output should include "Cloud Functions:   $expected_functions"
  End

End
