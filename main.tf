# aws provider
provider "aws" {
  region  = var.region
  profile = var.profile
}

# variables
variable "region" {
  default = "us-west-2"
}

variable "profile" {
  default = "isengard-sbx"
}

module "splunk_delivery" {
  source           = "./splunk-delivery"
  splunk_hec_url   = "https://prd-p-sja86.splunkcloud.com:8080"
  splunk_hec_token = "45f39c10-0876-4e25-9302-a976a9d58040"
  prefix           = "svb-splunk-test"
}
