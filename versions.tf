terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # version = "~> 5.100" # Explicitly request 5.100.x
    }
    signalfx = {
      source = "splunk-terraform/signalfx"
      # version = "~> 9.0"
    }
    splunk = {
      source = "splunk/splunk"
      # version = "~> 1.0"
    }
  }
  required_version = "~> 1.14"
}
