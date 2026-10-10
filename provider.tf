provider "aws" {
  region = "us-east-1"
}

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.66.0"
    }
  }
  backend "s3" {
    bucket = "sctp-tfstate-ce13"
    key    = "yq/tfstate/coaching-18"
    region = "us-east-1"
    # use_lockfile = true
  }
}
