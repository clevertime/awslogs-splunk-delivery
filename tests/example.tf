# aws provider
provider "aws" {
  region  = var.region
  profile = var.profile
}

# variables
variable "region" {
  default = "us-west-2"
}

variable "profile" {}

variable "splunk_hec_url" {}

variable "splunk_hec_token" {}

variable "sender_account_ids" {
  type = list
}

# run module
module "splunk_delivery" {
  source             = "../splunk-delivery"
  splunk_hec_url     = var.splunk_hec_url
  splunk_hec_token   = var.splunk_hec_token
  prefix             = "test"
  sender_account_ids = var.sender_account_ids
}
