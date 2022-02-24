# To use this test, call: shellspec spec/resource-count-gcp_spec.sh

Describe 'resource-count-gcp'

  ########################################################################################
  # https://github.com/shellspec/shellspec#include---include-a-script-file
  ########################################################################################

  Include gcp/resource-count-gcp.sh

  ########################################################################################
  # https://github.com/shellspec/shellspec#function-based-mock
  ########################################################################################

  gcloud_projects_list() {
    cat << EOJ
[
  {
    "lifecycleState": "ACTIVE",
    "name": "project1",
    "parent": {
      "id": "012345678901",
      "type": "folder"
    },
    "projectId": "project-123456",
    "projectNumber": "123456789123"
  },
  {
    "lifecycleState": "ACTIVE",
    "name": "project2",
    "parent": {
      "id": "012345678901",
      "type": "folder"
    },
    "projectId": "project-234567",
    "projectNumber": "234567891234"
  }
]
EOJ
  }

  gcloud_compute_instances_list() {
    cat << EOJ
[
  {
    "id": "123456789012",
    "name": "instance1",
    "region": "us-central1"
  },
  {
    "id": "234567891234",
    "name": "instance2",
    "region": "us-central1"
  }
]
EOJ
  }

  gcloud_compute_routers_list() {
    cat << EOJ
[
  {
    "id": "123456789012",
    "name": "router1",
    "region": "us-central1"
  },
  {
    "id": "234567891234",
    "name": "router2",
    "region": "us-central1"
  }
]
EOJ
  }

  gcloud_compute_routers_nats_list() {
    cat << EOJ
[
  {
    "id": "123456789012",
    "name": "nats1",
    "region": "us-central1"
  },
  {
    "id": "234567891234",
    "name": "nats2",
    "region": "us-central1"
  }
]
EOJ
  }

  gcloud_compute_routers_nats_list() {
    cat << EOJ
[
  {
    "id": "123456789012",
    "name": "nats1",
    "region": "us-central1"
  },
  {
    "id": "234567891234",
    "name": "nats2",
    "region": "us-central1"
  }
]
EOJ
  }

  gcloud_compute_backend_services_list() {
    cat << EOJ
[
  {
    "id": "123456789012",
    "name": "service1",
    "region": "us-central1"
  },
  {
    "id": "234567891234",
    "name": "service2",
    "region": "us-central1"
  }
]
EOJ
  }

  gcloud_sql_instances_list() {
    cat << EOJ
[
  {
    "id": "123456789012",
    "name": "instance1",
    "region": "us-central1"
  },
  {
    "id": "234567891234",
    "name": "instance2",
    "region": "us-central1"
  }
]
EOJ
  }

  ########################################################################################
  # https://github.com/shellspec/shellspec#it-specify-example---example-block
  ########################################################################################

  It 'returns a list of projects'
    When call get_project_list
    The output should not include "Error:"
    The variable TOTAL_PROJECTS should eq 2
  End

  ####

  It 'counts project resources'
    get_project_list > /dev/null 2>&1
    reset_project_counters
    reset_global_counters
    #
    When call count_project_resources
    The output should include "Count"
    The variable TOTAL_PROJECTS should eq 2
    The variable WORKLOAD_COUNT_GLOBAL should eq 20
  End

End
