terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # No remote backend is configured. State is local by default; see
  # docs/DEPLOYMENT.md for guidance on migrating to a remote backend
  # (S3 + DynamoDB lock table) for team use. terraform.tfstate is git-ignored
  # and must never be committed.
}
