# Count IaC resources with Checkov

## Prerequisites
1. [Install](https://github.com/bridgecrewio/checkov/blob/master/docs/2.Basics/Installing%20Checkov.md) / update checkov to version 2.0.427 or later (use `checkov -v` to check the version).
2. Optional (recommended): Install _jq_
3. Clone the repo(s) to be counted.
4. From the root of each repo that you plan to scan with Bridgecrew/Code Security, run one of the following commands:

### Running the script

#### If you have _jq_ installed (recommended)

```console
checkov -d . --download-external-modules true -o json | jq 'if type=="array" then . else [.] end | [.[].summary.resource_count] | add' | awk '{bc=$1 ; pc=($1/3); printf "Total resource count: " ; printf"%0.0f\n", bc ; {printf "Code Security credit usage (total resources divided by 3): "}; printf"%0.0f\n", pc}';
```

#### If you do not have _jq_ installed

```console
checkov -d . --download-external-modules true -o json | grep resource_count | awk '{print substr($2, 0, length($2) - 1)}' | awk '{s += $1} END {print s}' | awk '{bc=$1 ; pc=($1/3); printf "Total resource count: " ; printf"%0.0f\n", bc ; {printf "Code Security credit usage (total resources divided by 3): "}; printf"%0.0f\n", pc}';
```

Example output:

```
Total resource count: 160
Code Security credit usage (total resources divided by 3): 53
```
There are a total of 160 resources, or 53 credits to be consumed by the scanned repo


#### On Windows/Powershell (_jq_ not required):
```console
((checkov -d . --download-external-modules true -o json)| convertFrom-Json).summary.resource_count
5
```

The resource count for the repo is 5.


### To count multiple repos at once

#### Count all repos under a top-level directory

Clone all the repos under the same top-level directory. Then run the following command (replace __COMMAND__ with one of the commands from above).

```console
for d in $(ls); do cd $d; COMMAND; cd -; done | awk '{s += $1} END {print s}' | awk '{bc=$1 ; pc=($1/3); printf "Total resource count: " ; printf"%0.0f\n", bc ; {printf "Code Security credit usage (total resources divided by 3): "}; printf"%0.0f\n", pc}';
```

##### If you have _jq_ installed (recommended)

Example (using the _jq_ command):

```console
for d in $(ls); do cd $d; checkov -d . --download-external-modules true -o json | jq 'if type=="array" then . else [.] end | [.[].summary.resource_count] | add'; cd -; done | awk '{s += $1} END {print s}' | awk '{bc=$1 ; pc=($1/3); printf "Total resource count: " ; printf"%0.0f\n", bc ; {printf "Code Security credit usage (total resources divided by 3): "}; printf"%0.0f\n", pc}';
```

##### If you do not have _jq_ installed

Example (**without** using _jq_)

```console
for d in $(ls); do cd $d; checkov -d . --download-external-modules true -o json | grep resource_count | awk '{print substr($2, 0, length($2) - 1)}' | awk '{s += $1} END {print s}'; cd -; done | awk '{s += $1} END {print s}' | awk '{bc=$1 ; pc=($1/3); printf "Total resource count: " ; printf"%0.0f\n", bc ; {printf "Code Security credit usage (total resources divided by 3): "}; printf"%0.0f\n", pc}';
```

Example output:

```
Total resource count: 277
Code Security credit usage (total resources divided by 3): 92
```

There are a total of 277 resources, or 92 credits to be consumed by the scanned repos


##### Count all repos in a specified file

Create a file named _repos.txt_ with a list of repository paths on your system. 
* _repos.txt_ example file:
```
./GitHub/pcs-iac
./GitHub/terragoat
```

Then run the following command (replace __COMMAND__ with one of the commands from above):

`cat repos.txt | while read d; do cd $d; __COMMAND__; cd -; done | awk '{s += $1} END {print s}'`

##### If you have _jq_ installed (recommended)
Example (using the _jq_ command):

`cat repos.txt | while read d; do cd $d; checkov -d . --download-external-modules true -o json | jq 'if type=="array" then . else [.] end | [.[].summary.resource_count] | add'; cd -; done | awk '{s += $1} END {print s}' | awk '{print "Total resource count:"};{print int};{print "Code Security credit usage (total resources divided by 3):"};{printf "%0.0f\n",int/3 " credits "}'`

##### If you do not have _jq_ installed
Example (**without** using _jq_)

`cat repos.txt | while read d; do cd $d; checkov -d . --download-external-modules true -o json | grep resource_count | awk '{print substr($2, 0, length($2) - 1)}' | awk '{s += $1} END {print s}'; cd -; done | awk '{s += $1} END {print s}' | awk '{print "Total resource count:"};{print int};{print "Code Security credit usage (total resources divided by 3):"};{printf "%0.0f\n",int/3 " credits "}'`

Example output:

```
Total resource count:
277
Code Security credit usage (total resources divided by 3):
92
```

There are a total of 277 resources, or 92 credits to be consumed by the scanned repos
