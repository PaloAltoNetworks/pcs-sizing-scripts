# pcs-sizing-scripts

Prisma Cloud Sizing Scripts
PDF licensing guide located here: [https://www.paloaltonetworks.com/resources/guides/prisma-cloud-enterprise-edition-licensing-guide](https://www.paloaltonetworks.com/resources/guides/prisma-cloud-enterprise-edition-licensing-guide)

* Please refer to the individual folders for instructions on running these scripts for each cloud provider/usage.
* **Note:** All scripts have been recently updated for improved accuracy, error handling, and performance (using Cloud Asset Inventory for GCP, Azure Resource Graph for Azure, and OCI Search API for OCI). Key enhancements include adding serverless function counts (Lambda, Azure Functions, Cloud Functions, OCI Functions, Function Compute) and additional container counts in AWS (EKS/ECS Clusters, tagged Docker Hosts).

## Cloud Providers:

* [AWS](/aws) 
* [Azure](/azure)
* [GCP](/gcp)
* [OCI](/oci)
* [Alibaba](/alibaba)

## Other Credit Usage:

* [Code Security](/code-security)

## Development Testing

Please check your changes to the shell scripts with https://www.shellcheck.net/ 
and update the associated spec tests in the `spec` directory, which use https://shellspec.info/