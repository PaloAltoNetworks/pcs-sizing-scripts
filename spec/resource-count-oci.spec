# To use this test, call: shellspec spec/resource-count-oci.spec

Describe 'resource-count-oci'

  ########################################################################################
  # https://github.com/shellspec/shellspec#include---include-a-script-file
  ########################################################################################

  Include oci/resource-count-oci.sh

  ########################################################################################
  # https://github.com/shellspec/shellspec#function-based-mock
  ########################################################################################

  oci_compartments_list() {
    cat << EOJ
{
  "data": [
    {
      "compartment-id": "ocid1.tenancy.123456789012",
      "id": "ocid1.compartment.123456789012"
    },
    {
      "compartment-id": "ocid1.tenancy.123456789012",
      "id": "ocid1.compartment.234567891234"
    }
  ]
}
EOJ
  }

  oci_compute_instances_list() {
    if [ "$1" == "ocid1.compartment.123456789012" ]; then
      cat << EOJ
{
  "data": [
    {
      "id": "ocid1.instance.123456789012",
      "lifecycle-state": "RUNNING"
    },
    {
      "id": "ocid1.instance.234567891234",
      "lifecycle-state": "RUNNING"
    }
  ]
}
EOJ
    else
      cat << EOJ2
{
  "data": [
    {
      "id": "ocid1.instance.234567891234",
      "lifecycle-state": "RUNNING"
    }
  ]
}
EOJ2
    fi  
  }

  oci_db_system_list() {
    cat << EOJ
{
  "data": [
    {
      "id": "ocid1.dbsystem.123456789012",
      "lifecycle-state": "AVAILABLE"
    },
    {
      "id": "ocid1.dbsystem.234567891234",
      "lifecycle-state": "AVAILABLE"
    }
  ]
}
EOJ
  }

  oci_load_balancer_list() {
    cat << EOJ
{
  "data": [
    {
      "id": "ocid1.loadbalancer.123456789012",
      "lifecycle-state": "ACTIVE"
    },
    {
      "id": "ocid1.loadbalancer.234567891234",
      "lifecycle-state": "ACTIVE"
    }
  ]
}
EOJ
  }


  ########################################################################################
  # https://github.com/shellspec/shellspec#it-specify-example---example-block
  ########################################################################################

  It 'returns a list of compartments'
    When call get_compartments
    The output should not include "Error:"
    The variable TOTAL_COMPARTMENTS should eq 2
  End

  ####

  It 'counts compartment resources'
    get_compartments > /dev/null 2>&1
    reset_local_counters
    reset_global_counters
    #
    When call count_resources
    The output should include "Count"
    The variable TOTAL_COMPARTMENTS should eq 2
    The variable WORKLOAD_COUNT_GLOBAL should eq 11
  End

End
