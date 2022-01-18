# To use this test, call: shellspec spec/resource-count-aws_spec.sh

Describe 'resource-count-aws'

  ########################################################################################
  # https://github.com/shellspec/shellspec#include---include-a-script-file
  ########################################################################################

  Include aws/resource-count-aws.sh

  ########################################################################################
  # https://github.com/shellspec/shellspec#function-based-mock
  ########################################################################################

  aws_ec2_describe_regions() {
    cat << EOJ
{
    "Regions": [
        {
            "Endpoint": "ec2.us-east-1.amazonaws.com",
            "RegionName": "us-east-1",
            "OptInStatus": "opt-in-not-required"
        },
        {
            "Endpoint": "ec2.us-east-2.amazonaws.com",
            "RegionName": "us-east-2",
            "OptInStatus": "opt-in-not-required"
        },
        {
            "Endpoint": "ec2.us-west-1.amazonaws.com",
            "RegionName": "us-west-1",
            "OptInStatus": "opt-in-not-required"
        },
        {
            "Endpoint": "ec2.us-west-2.amazonaws.com",
            "RegionName": "us-west-2",
            "OptInStatus": "opt-in-not-required"
        }
    ]
}
EOJ
  }

  aws_organizations_describe_organization() {
    cat << EOJ
{
	"Organization": {
		"MasterAccountArn": "arn:aws:organizations::011111111111:account/o-exampleorgid/011111111111",
		"MasterAccountEmail": "bill@example.com",
		"MasterAccountId": "011111111111",
		"Id": "o-exampleorgid",
		"FeatureSet": "ALL",
		"Arn": "arn:aws:organizations::011111111111:organization/o-exampleorgid",
		"AvailablePolicyTypes": [{
			"Status": "ENABLED",
			"Type": "SERVICE_CONTROL_POLICY"
		}]
	}
}
EOJ
  }

  aws_organizations_list_accounts() {
    cat << EOJ
{
	"Accounts": [{
			"Arn": "arn:aws:organizations::011111111111:account/o-exampleorgid/011111111111",
			"JoinedMethod": "INVITED",
			"JoinedTimestamp": 1481830215.45,
			"Id": "011111111111",
			"Name": "MasterAccount",
			"Email": "bill@example.com",
			"Status": "ACTIVE"
		},
		{
			"Arn": "arn:aws:organizations::011111111111:account/o-exampleorgid/222222222222",
			"JoinedMethod": "INVITED",
			"JoinedTimestamp": 1481835741.044,
			"Id": "222222222222",
			"Name": "ProductionAccount",
			"Email": "alice@example.com",
			"Status": "ACTIVE"
		},
		{
			"Arn": "arn:aws:organizations::011111111111:account/o-exampleorgid/333333333333",
			"JoinedMethod": "INVITED",
			"JoinedTimestamp": 1481835795.536,
			"Id": "333333333333",
			"Name": "DevelopmentAccount",
			"Email": "juan@example.com",
			"Status": "ACTIVE"
		},
		{
			"Arn": "arn:aws:organizations::011111111111:account/o-exampleorgid/444444444444",
			"JoinedMethod": "INVITED",
			"JoinedTimestamp": 1481835812.143,
			"Id": "444444444444",
			"Name": "TestAccount",
			"Email": "anika@example.com",
			"Status": "ACTIVE"
		}
	]
}
EOJ
  }

  aws_sts_assume_role() {
    cat << EOJ
{
    "AssumedRoleUser": {
        "AssumedRoleId": "AROA3XFRBF535PLBIFPI4:s3-access-example",
        "Arn": "arn:aws:organizations::011111111111:account/o-exampleorgid/222222222222"
    },
    "Credentials": {
        "SecretAccessKey": "9drTJvcXLB89EXAMPLELB8923FB892xMFI",
        "SessionToken": "AQoXdzELDDY//////////wEaoAK1wvxJY12r2IrDFT2IvAzTCn3zHoZ7YNtpiQLF0MqZye/qwjzP2iEXAMPLEbw/m3hsj8VBTkPORGvr9jM5sgP+w9IZWZnU+LWhmg+a5fDi2oTGUYcdg9uexQ4mtCHIHfi4citgqZTgco40Yqr4lIlo4V2b2Dyauk0eYFNebHtYlFVgAUj+7Indz3LU0aTWk1WKIjHmmMCIoTkyYp/k7kUG7moeEYKSitwQIi6Gjn+nyzM+PtoA3685ixzv0R7i5rjQi0YE0lf1oeie3bDiNHncmzosRM6SFiPzSvp6h/32xQuZsjcypmwsPSDtTPYcs0+YN/8BRi2/IcrxSpnWEXAMPLEXSDFTAQAM6Dl9zR0tXoybnlrZIwMLlMi1Kcgo5OytwU=",
        "Expiration": "2020-12-15T00:00:00Z",
        "AccessKeyId": "EXAMPLE2222222EXAMPLE"
    }
}
EOJ
  }
 
  ####

  aws_ec2_describe_instances() {
    cat << EOJ
{
	"Instances": [{
		"InstanceId": "0abcdef1234567890"
	}]
}
EOJ
  }

  aws_ec2_describe_db_instances() {
    cat << EOJ
{
	"Instances": [{
		"InstanceId": "0abcdef1234567890"
	}]
}
EOJ
  }

  aws_ec2_describe_nat_gateways() {
    cat << EOJ
{
	"Instances": [{
		"InstanceId": "0abcdef1234567890"
	}]
}
EOJ
  }

  aws_redshift_describe_clusters() {
    cat << EOJ
{
	"Instances": [{
		"InstanceId": "0abcdef1234567890"
	}]
}
EOJ
  }

  aws_elb_describe_load_balancers() {
    cat << EOJ
{
	"Instances": [{
		"InstanceId": "0abcdef1234567890"
	}]
}
EOJ
  }

  aws_lambda_get_account_settings() {
    cat << EOJ
{
    "AccountLimit": {},
    "AccountUsage": {
       "FunctionCount": 4
    }
}
EOJ
  }

  ########################################################################################
  # https://github.com/shellspec/shellspec#it-specify-example---example-block
  ########################################################################################

  It 'returns a list of regions or the default list'
    When call get_region_list
    The output should not include "Warning:"
    The variable REGION_LIST[@] should eq "us-east-1 us-east-2 us-west-1 us-west-2"
  End

  ####

  It 'returns a list of one account'
    USE_AWS_ORG="false"
    When call get_account_list
    The output should not include "Error:"
    The variable TOTAL_ACCOUNTS should eq 1
  End

  It 'returns a list of organization member accounts'
    USE_AWS_ORG="true"
    #
    When call get_account_list
    The output should not include "Error:"
    The variable TOTAL_ACCOUNTS should eq 4
  End

  It 'assumes a role'
    MASTER_ACCOUNT_ID=011111111111
    #
    When call assume_role "ProductionAccount" 222222222222
    The output should not include "skipping"
    The variable AWS_ACCESS_KEY_ID should eq "EXAMPLE2222222EXAMPLE"
  End

  ####

  It 'returns a list of Regions'
    When call aws_ec2_describe_regions
    The output should not include "Error"
  End

  It 'returns a list of EC2 Instances'
    When call aws_ec2_describe_instances
    The output should not include "Error"
  End

  It 'returns a list of RDS Instances'
    When call aws_ec2_describe_db_instances
    The output should not include "Error"
  End

  It 'returns a list of NAT Gateways'
    When call aws_ec2_describe_nat_gateways
    The output should not include "Error"
  End

  It 'returns a list of RedShift Clusters'
    When call aws_redshift_describe_clusters
    The output should not include "Error"
  End

  It 'returns a list of ELBs'
    When call aws_elb_describe_load_balancers
    The output should not include "Error"
  End

  ####

  It 'counts account resources'
    USE_AWS_ORG="false"
    get_account_list > /dev/null 2>&1
    get_region_list  > /dev/null 2>&1
    reset_account_counters
    reset_global_counters
    #
    When call count_account_resources
    The output should include "Count"
    The variable TOTAL_ACCOUNTS should eq 1
    The variable WORKLOAD_COUNT_GLOBAL should eq 20
    The variable WORKLOAD_COUNT_GLOBAL_WITH_IAM_MODULE should eq 25
  End

  It 'counts organization member account resources'
    USE_AWS_ORG="true"
    get_account_list > /dev/null 2>&1
    get_region_list  > /dev/null 2>&1
    reset_account_counters
    reset_global_counters
    #
    When call count_account_resources
    The output should include "Count"
    The variable TOTAL_ACCOUNTS should eq 4
    The variable WORKLOAD_COUNT_GLOBAL should eq 80
    The variable WORKLOAD_COUNT_GLOBAL_WITH_IAM_MODULE should eq 100
  End

End
