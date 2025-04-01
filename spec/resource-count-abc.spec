# To use this test, call: shellspec spec/resource-count-abc.spec

Describe 'resource-count-abc'

  ########################################################################################
  # Includes and Setup
  ########################################################################################

  Include alibaba/resource-count-abc.sh

  ########################################################################################
  # Mocks for helper functions
  ########################################################################################

  # Mock region list (keep simple for testing)
  abc_regions_list() {
    cat << EOJ
{
        "Regions": {
                "Region": [
                        {"RegionId": "us-west-1"},
                        {"RegionId": "us-east-1"}
                ]
        },
        "RequestId": "mock-regions"
}
EOJ
  }

  # Mock ECS instance count (returns TotalCount directly)
  # Let's mock 3 instances in us-west-1 and 0 elsewhere
  get_instance_count() {
    if [ "$1" == "us-west-1" ]; then
      echo 3
    else
      echo 0
    fi
  }

  # Mock RDS instance count (returns total count after pagination logic)
  # Let's mock 2 instances in us-west-1 and 1 elsewhere
  abc_rds_instances_list() {
     if [ "$1" == "us-west-1" ]; then
      echo 2
    else
      echo 1
    fi
  }

  # Mock SLB instance count (returns total count after pagination logic)
  # Let's mock 1 instance in us-west-1 and 0 elsewhere
  abc_slb_instances_list() {
     if [ "$1" == "us-west-1" ]; then
      echo 1
    else
      echo 0
    fi
  }

  # Mock Function Compute count (returns total count after service/function listing)
  # Let's mock 5 functions in us-west-1 and 2 elsewhere
  abc_fc_function_count() {
     if [ "$1" == "us-west-1" ]; then
      echo 5
    else
      echo 2
    fi
  }

  ########################################################################################
  # Tests
  ########################################################################################

  It 'returns a list of regions'
    When call get_regions
    The output should not include "Error:"
    The variable TOTAL_REGIONS should eq 2 # Based on mock
    The variable REGIONS should eq "us-east-1 us-west-1" # Check sorting
  End

  ####

  It 'counts resources correctly across regions'
    # Expected counts based on mocks (us-west-1 + us-east-1)
    expected_ecs=3  # 3 + 0
    expected_rds=3  # 2 + 1
    expected_slb=1  # 1 + 0
    expected_fc=7   # 5 + 2
    expected_total=$((expected_ecs + expected_rds + expected_slb + expected_fc)) # 3 + 3 + 1 + 7 = 14

    # Setup: Ensure global counters are reset and regions are fetched
    get_regions > /dev/null 2>&1
    reset_global_counters

    # Execute the main counting function
    When call count_resources

    # Assert global counts
    The variable COMPUTE_INSTANCES_COUNT_GLOBAL should eq "$expected_ecs"
    The variable RDS_INSTANCES_COUNT_GLOBAL should eq "$expected_rds"
    The variable SLB_INSTANCES_COUNT_GLOBAL should eq "$expected_slb"
    The variable FC_FUNCTIONS_COUNT_GLOBAL should eq "$expected_fc"
    The variable WORKLOAD_COUNT_GLOBAL should eq "$expected_total"

    # Check output includes expected lines
    The output should include "Count of Compute Instances (ECS): $expected_ecs"
    The output should include "Count of RDS Instances: $expected_rds"
    The output should include "Count of Load Balancers (SLB): $expected_slb"
    The output should include "Count of Function Compute Functions: $expected_fc"
    The output should include "Total billable resources: $expected_total"

    The status should be success
    The error should be empty
  End

End
