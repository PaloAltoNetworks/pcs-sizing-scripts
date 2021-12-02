# To use this test, call: shellspec spec/resource-count-abc_spec.sh

Describe 'resource-count-abc'

  ########################################################################################
  # https://github.com/shellspec/shellspec#include---include-a-script-file
  ########################################################################################

  Include alibaba/resource-count-abc.sh

  ########################################################################################
  # https://github.com/shellspec/shellspec#function-based-mock
  ########################################################################################

  abc_regions_list() {
    cat << EOJ
{
        "Regions": {
                "Region": [
                        {
                                "RegionEndpoint": "ecs.aliyuncs.com",
                                "RegionId": "cn-beijing"
                        },
                        {
                                "RegionEndpoint": "ecs.aliyuncs.com",
                                "RegionId": "cn-shanghai"
                        },
                        {
                                "RegionEndpoint": "ecs.aliyuncs.com",
                                "RegionId": "us-east-1"
                        },
                        {
                                "RegionEndpoint": "ecs.aliyuncs.com",
                                "RegionId": "us-west-1"
                        }
                ]
        },
        "RequestId": "1111"
}
EOJ
  }

  abc_compute_instances_list() {
    if [ "${1}" == "us-west-1" ]; then
      cat << EOJ
{
	"Instances": {
		"Instance": [{
				"InstanceId": "p1-111",
				"InstanceName": "111",
				"RegionId": "us-west-1"
			},
			{
				"InstanceId": "p1-222",
				"InstanceName": "222",
				"RegionId": "us-west-1"
			}
		]
	},
	"NextToken": "abcd",
	"RequestId": "1111",
	"TotalCount": 3
}
EOJ
    else
      cat << EOJ
{
	"Instances": {
		"Instance": [],
		"NextToken": "",
		"RequestId": "1122"
	},
	"TotalCount": 0
	}
}
EOJ
    fi
  }

  ########################################################################################
  # https://github.com/shellspec/shellspec#it-specify-example---example-block
  ########################################################################################

  It 'returns a list of regions'
    When call get_regions
    The output should not include "Error:"
    The variable TOTAL_REGIONS should eq 4
  End

  ####

  It 'counts instances in a region'
    When call get_instance_count "us-west-1"
    The output should not include "Error:"
    The variable COUNT should eq 3
  End

  It 'does not count instances in another region'
    When call get_instance_count "us-east-1"
    The output should not include "Error:"
    The variable COUNT should eq 0
  End

  It 'counts resources'
    get_regions > /dev/null 2>&1
    reset_local_counters
    reset_global_counters
    #
    When call count_resources
    The output should include "Count"
    The variable TOTAL_REGIONS should eq 4
    The variable WORKLOAD_COUNT_GLOBAL should eq 3
  End

End
