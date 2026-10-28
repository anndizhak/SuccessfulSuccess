terraform {
  required_version = ">= 1.10"

  # State, locking and runs live in HCP Terraform. Runs get short-lived AWS
  # credentials through OIDC (TFC_AWS_PROVIDER_AUTH / TFC_AWS_RUN_ROLE_ARN in
  # the workspace), so no AWS key is stored anywhere.
  cloud {
    organization = "ooad-anndizhak"

    workspaces {
      name = "successfulsuccess-dev"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.region

  # Every taggable resource gets the project tag without repeating it.
  default_tags {
    tags = {
      PROJECT_NAME = var.project_name
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

# The network, API, database, site and CI stacks stay CloudFormation for now.
# Terraform reads what it needs from them instead of copying values by hand.
data "aws_cloudformation_stack" "backend" {
  name = "${var.project_name}-backend"
}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.region
  partition   = data.aws_partition.current.partition
  db_endpoint = data.aws_cloudformation_stack.backend.outputs["DatabaseEndpoint"]
}
