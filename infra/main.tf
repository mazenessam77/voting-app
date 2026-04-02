##############################################################################
# main.tf — Provider configuration and data sources
##############################################################################

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment and configure for remote state storage
  # backend "s3" {
  #   bucket         = "voting-app-tfstate"
  #   key            = "infra/terraform.tfstate"
  #   region         = "eu-west-2"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "voting-app"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Fetch available AZs in the selected region
data "aws_availability_zones" "available" {
  state = "available"
}

# Current AWS account ID — used for ARN construction
data "aws_caller_identity" "current" {}
