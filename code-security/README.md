## Count IaC resources with Checkov
1. [Install](https://github.com/bridgecrewio/checkov/blob/master/docs/2.Basics/Installing%20Checkov.md) / update checkov to version 2.0.427 or later (use `checkov -v` to check the version).
2. Optional (recommended): Install _jq_
3. Clone the repo(s) to be counted.
4. From the root of each repo that you plan to scan with Bridgecrew, run one of the following commands:

#### If you have _jq_ installed

`checkov -d . --download-external-modules true -o json | jq 'if type=="array" then . else [.]  end | [.[].summary.resource_count] | add'`

Example:

`checkov -d . --download-external-modules true -o json | jq 'if type=="array" then . else [.]  end | [.[].summary.resource_count] | add'`
`5`

#### If you do not have _jq_ installed

`checkov -d . --download-external-modules true -o json | grep resource_count | awk '{print substr($2, 0, length($2) - 1)}' | awk '{s += $1} END {print s}'`

Example:

`checkov -d . --download-external-modules true -o json | grep resource_count | awk '{print substr($2, 0, length($2) - 1)}' | awk '{s += $1} END {print s}'`
`5`

#### On Windows/Powershell (_jq_ not required):
`((checkov -d . --download-external-modules true -o json)| convertFrom-Json).summary.resource_count`
`5`

The resource count for the repo is 5.

### To count many repos at once

##### Example 1

Clone all the repos under the same top-level directory. Then run the following command (replace __COMMAND__ with one of the commands from above).

`for d in $(ls); do cd $d; COMMAND; cd -; done | awk '{s += $1} END {print s}'`

Example (using the _jq_ command):

`for d in $(ls); do cd $d; checkov -d . --download-external-modules true -o json | jq 'if type=="array" then . else [.]  end | [.[].summary.resource_count] | add'; cd -; done | awk '{s += $1} END {print s}'`
`10`

There are 10 total resources in the repos in this directory.


##### Example 2

Create a file named _repos.txt_ with a list of repository paths on your system. Then run the following command (replace __COMMAND__ with one of the commands from above):

`cat repos.txt | while read d; do cd $d; __COMMAND__; cd -; done | awk '{s += $1} END {print s}'`

Example (using the _jq_ command):

`cat repos.txt | while read d; do cd $d; checkov -d . --download-external-modules true -o json | jq 'if type=="array" then . else [.]  end | [.[].summary.resource_count] | add'; cd -; done | awk '{s += $1} END {print s}'`
`10`

There are 10 total resources in the repos listed in the file.