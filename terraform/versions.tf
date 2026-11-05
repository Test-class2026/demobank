terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  # Every resource gets these tags, so you can always tell what Terraform built and for whom
  default_tags {
    tags = {
      Project   = "demobank"
      Owner     = var.owner
      ManagedBy = "terraform"
    }
  }
}
