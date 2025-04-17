# To use this test, call: shellspec spec/resource-count-oci.spec

Describe 'resource-count-oci'

  ########################################################################################
  # Includes and Setup
  ########################################################################################

  Include oci/resource-count-oci.sh

  # Mock oci CLI command
  oci() {
    # echo "Mock oci called with: $@" >&2 # Debugging line
    if [ "$1" == "search" ] && [ "$2" == "resource" ] && [ "$3" == "structured-search" ]; then
      # Mock the search results based on the query used in the script
      # The script queries for 'Instance', 'DbSystem', 'LoadBalancer', 'Function'
      # Let's mock 3 Instances, 2 DbSystems, 1 LoadBalancer, 4 Functions
      cat << EOJ
{
  "data": {
    "items": [
      {"resource-type": "Instance"},
      {"resource-type": "Instance"},
      {"resource-type": "Instance"},
      {"resource-type": "DbSystem"},
      {"resource-type": "DbSystem"},
      {"resource-type": "LoadBalancer"},
      {"resource-type": "Function"},
      {"resource-type": "Function"},
      {"resource-type": "Function"},
      {"resource-type": "Function"}
    ]
  }
}
EOJ
      return 0
    else
      # Default mock for unhandled commands
      echo "Unhandled mock oci command: $@" >&2
      return 1 # Indicate error
    fi
  }
  # Export the mock function
  export -f oci

  ########################################################################################
  # Tests
  ########################################################################################

  # Reset counters before test
  # Before 'reset_global_counters' # reset_global_counters is not defined in the new script, counters are local to count_resources

  It 'counts tenancy resources correctly'
    # Expected counts based on the mock oci search output
    expected_instances=3
    expected_dbsystems=2
    expected_lbs=1
    expected_functions=4
    expected_total=$((expected_instances + expected_dbsystems + expected_lbs + expected_functions)) # 3 + 2 + 1 + 4 = 10

    When run script oci/resource-count-oci.sh # Run the main script logic

    # Check final counts - Variables are now local to count_resources, check output instead
    # The variable COMPUTE_INSTANCES_COUNT_GLOBAL should eq "$expected_instances"
    # The variable BARE_METAL_VM_DB_COUNT_GLOBAL should eq "$expected_dbsystems"
    # The variable LOAD_BALANCER_COUNT_GLOBAL should eq "$expected_lbs"
    # The variable FUNCTION_COUNT_GLOBAL should eq "$expected_functions"
    # The variable WORKLOAD_COUNT_GLOBAL should eq "$expected_total"

    The status should be success
    The error should be empty # Check no errors printed
    The output should include "Count of Compute Instances (Instance, RUNNING): $expected_instances"
    The output should include "Count of DB Systems (DbSystem, AVAILABLE): $expected_dbsystems"
    The output should include "Count of Load Balancers (LoadBalancer, ACTIVE): $expected_lbs"
    The output should include "Count of Functions (Function, ACTIVE): $expected_functions"
    The output should include "Total billable resources: $expected_total"
  End

End
