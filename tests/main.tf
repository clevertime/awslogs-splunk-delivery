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

variable "splunk_hec_url" {}

variable "splunk_hec_token" {}

module "splunk_delivery" {
  source           = "../splunk-delivery"
  splunk_hec_url   = var.splunk_hec_url
  splunk_hec_token = var.splunk_hec_token
  prefix           = "svb-splunk-test"
}
