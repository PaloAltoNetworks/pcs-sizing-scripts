# To use this test, call: shellspec spec/resource-count-aws.spec

Describe 'resource-count-aws'

  ########################################################################################
  # Includes and Setup
  ########################################################################################

  Include aws/resource-count-aws.sh

  # Mock AWS CLI commands
  # Mock basic identity and region listing
  aws() {
    case "$1 $2" in
      "sts get-caller-identity")
        echo '{"Account": "123456789012", "UserId": "AIDACKCEVSQ6C2EXAMPLE", "Arn": "arn:aws:iam::123456789012:user/testuser"}'
        return 0
        ;;
      "account list-regions")
        # Mock fewer regions for simpler test calculations
        echo '{"Regions": [{"RegionName": "us-east-1"}, {"RegionName": "us-west-2"}]}'
        return 0
        ;;
      "organizations list-accounts")
         # Mock only one active sub-account for simplicity in org mode test
         echo '{"Accounts": [{"Id": "111111111111", "Status": "ACTIVE"}, {"Id": "222222222222", "Status": "ACTIVE"}]}'
         return 0
        ;;
       "sts assume-role")
         # Mock successful role assumption
         echo '{"Credentials": {"AccessKeyId": "ASIA...", "SecretAccessKey": "...", "SessionToken": "...", "Expiration": "..."}}'
         return 0
         ;;
       "ec2 describe-instances")
         # Check for DockerHost tag filter
         if [[ "$*" =~ Name=tag-key,Values=DockerHost ]]; then
            # Mock 1 Docker Host per region
            echo '{"Reservations": [{"Instances": [{"InstanceId": "i-dockerhost1"}]}]}'
         else
            # Mock 2 general EC2 instances per region
            echo '{"Reservations": [{"Instances": [{"InstanceId": "i-instance1"}, {"InstanceId": "i-instance2"}]}]}'
         fi
         return 0
         ;;
       "eks list-clusters")
         # Mock 1 EKS cluster per region
         echo '{"clusters": ["eks-cluster-1"]}'
         return 0
         ;;
       "eks list-nodegroups")
         # Mock 1 nodegroup per cluster
         echo '{"nodegroups": ["eks-nodegroup-1"]}'
         return 0
         ;;
       "eks describe-nodegroup")
         # Mock 2 desired nodes per nodegroup
         echo '{"nodegroup": {"scalingConfig": {"desiredSize": 2}}}'
         return 0
         ;;
       "ecs list-clusters")
         # Mock 1 ECS cluster per region
         echo '{"clusterArns": ["arn:aws:ecs:us-east-1:123456789012:cluster/ecs-cluster-1"]}'
         return 0
         ;;
       "ecs list-services")
         # Mock 2 services per cluster, no pagination needed for test
         echo '{"serviceArns": ["arn:aws:ecs:us-east-1:123456789012:service/ecs-cluster-1/service-1", "arn:aws:ecs:us-east-1:123456789012:service/ecs-cluster-1/service-2"]}'
         return 0
         ;;
       "ecs describe-services")
         # Mock running counts for the 2 services (e.g., 3 + 1 = 4 tasks per cluster)
         echo '{"services": [{"runningCount": 3}, {"runningCount": 1}]}'
         return 0
         ;;
       "lambda list-functions")
         # Mock 5 functions per region (using --no-paginate approach)
         echo '{"Functions": [{}, {}, {}, {}, {}]}'
         return 0
         ;;
       # Keep DSPM mocks simple for now, focus on Cloud Security counts
       "s3api list-buckets") echo '{"Buckets": [{"Name": "bucket1"}, {"Name": "bucket2"}]}' ;;
       "efs describe-file-systems") echo '{"FileSystems": [{"FileSystemId": "fs-1"}]}' ;;
       "rds describe-db-clusters") echo '{"DBClusters": [{"DBClusterIdentifier": "aurora-1"}]}' ;;
       "rds describe-db-instances") echo '{"DBInstances": [{"DBInstanceIdentifier": "rds-1"}]}' ;;
       "dynamodb list-tables") echo '{"TableNames": ["table1", "table2", "table3"]}' ;;
       "redshift describe-clusters") echo '{"Clusters": [{"ClusterIdentifier": "redshift-1"}]}' ;;
       # Mock SSM commands to succeed but find no DBs for simplicity unless -c is tested
       "ssm describe-instance-information") echo '{"InstanceInformationList": [{"InstanceId": "i-instance1"}]}' ;; # Assume one instance is managed
       "ssm send-command") echo '{"Command": {"CommandId": "cmd-123"}}' ;;
       "ssm list-command-invocations") echo '{"CommandInvocations": [{"Status": "Success", "CommandPlugins": [{"Output": ""}]}]}' ;; # Mock no output found
       *)
         # Default mock for unhandled commands (e.g., config set)
         # echo "Mocked AWS command: $@" >&2
         return 0
         ;;
    esac
  }
  # Export the mock function to be used by the included script
  export -f aws

  ########################################################################################
  # Tests
  ########################################################################################

  # Reset counters before each test group if necessary
  BeforeEach 'reset_global_counters'

  Describe 'Standalone Account Mode (No Org)'
    Parameters
      # DSPM_MODE, SSM_MODE, Expected EC2, EKS Nodes, EKS Clusters, ECS Tasks, ECS Clusters, Lambda, Docker Hosts
      false false 4 4 2 8 2 10 2 # Default Cloud Security
      true  false 0 0 0 0 0 0  0 # DSPM only (Cloud Security counts skipped)
      true  true  0 0 0 0 0 0  0 # DSPM + SSM (Cloud Security counts skipped)
    End

    It "counts resources correctly (DSPM=$1, SSM=$2)"
      DSPM_MODE=$1
      SSM_MODE=$2
      ORG_MODE=false # Ensure standalone mode
      REGION=""      # Ensure all regions scan

      # Expected counts based on 2 mocked regions
      local expected_ec2=$3
      local expected_eks_nodes=$4
      local expected_eks_clusters=$5
      local expected_ecs_tasks=$6
      local expected_ecs_clusters=$7
      local expected_lambda=$8
      local expected_docker_hosts=$9
      # DSPM counts (simple mocks, 2 regions where applicable)
      local expected_s3=2 # Global
      local expected_efs=2
      local expected_aurora=2
      local expected_rds=2
      local expected_dynamo=6
      local expected_redshift=2
      local expected_ec2_db=0 # Mock finds no DBs via SSM

      When run script aws/resource-count-aws.sh # Rerun script logic with current settings

      # Check Cloud Security Counts
      if [ "$DSPM_MODE" == false ]; then
        The variable total_ec2_instances should eq "$expected_ec2"
        The variable total_eks_nodes should eq "$expected_eks_nodes"
        The variable total_eks_clusters should eq "$expected_eks_clusters"
        The variable total_ecs_tasks should eq "$expected_ecs_tasks"
        The variable total_ecs_clusters should eq "$expected_ecs_clusters"
        The variable total_lambda_functions should eq "$expected_lambda"
        The variable total_docker_hosts should eq "$expected_docker_hosts"
      fi

       # Check DSPM Counts
      if [ "$DSPM_MODE" == true ]; then
        The variable total_s3_buckets should eq "$expected_s3"
        The variable total_efs should eq "$expected_efs"
        The variable total_aurora should eq "$expected_aurora"
        The variable total_rds should eq "$expected_rds"
        The variable total_dynamodb should eq "$expected_dynamo"
        The variable total_redshift should eq "$expected_redshift"
        if [ "$SSM_MODE" == true ]; then
           The variable total_ec2_db should eq "$expected_ec2_db"
        fi
      fi

      The status should be success
      The error should be empty # Check no errors printed
    End
  End

  Describe 'Organization Mode'
    Parameters
      # DSPM_MODE, SSM_MODE, Expected EC2, EKS Nodes, EKS Clusters, ECS Tasks, ECS Clusters, Lambda, Docker Hosts
      false false 8 8 4 16 4 20 4 # Default Cloud Security (2 accounts * standalone counts)
      true  false 0 0 0 0  0 0  0 # DSPM only
      true  true  0 0 0 0  0 0  0 # DSPM + SSM
    End

     It "counts resources correctly across org (DSPM=$1, SSM=$2)"
      DSPM_MODE=$1
      SSM_MODE=$2
      ORG_MODE=true # Enable Org mode
      REGION=""     # Ensure all regions scan

      # Expected counts based on 2 mocked regions and 2 mocked accounts
      local expected_ec2=$3
      local expected_eks_nodes=$4
      local expected_eks_clusters=$5
      local expected_ecs_tasks=$6
      local expected_ecs_clusters=$7
      local expected_lambda=$8
      local expected_docker_hosts=$9
      # DSPM counts (simple mocks, 2 regions where applicable, 2 accounts)
      local expected_s3=4 # Global
      local expected_efs=4
      local expected_aurora=4
      local expected_rds=4
      local expected_dynamo=12
      local expected_redshift=4
      local expected_ec2_db=0 # Mock finds no DBs via SSM

      When run script aws/resource-count-aws.sh # Rerun script logic

      # Check Cloud Security Counts
      if [ "$DSPM_MODE" == false ]; then
        The variable total_ec2_instances should eq "$expected_ec2"
        The variable total_eks_nodes should eq "$expected_eks_nodes"
        The variable total_eks_clusters should eq "$expected_eks_clusters"
        The variable total_ecs_tasks should eq "$expected_ecs_tasks"
        The variable total_ecs_clusters should eq "$expected_ecs_clusters"
        The variable total_lambda_functions should eq "$expected_lambda"
        The variable total_docker_hosts should eq "$expected_docker_hosts"
      fi

       # Check DSPM Counts
      if [ "$DSPM_MODE" == true ]; then
        The variable total_s3_buckets should eq "$expected_s3"
        The variable total_efs should eq "$expected_efs"
        The variable total_aurora should eq "$expected_aurora"
        The variable total_rds should eq "$expected_rds"
        The variable total_dynamodb should eq "$expected_dynamo"
        The variable total_redshift should eq "$expected_redshift"
        if [ "$SSM_MODE" == true ]; then
           The variable total_ec2_db should eq "$expected_ec2_db"
        fi
      fi

      The status should be success
      The error should be empty
    End
  End

End
