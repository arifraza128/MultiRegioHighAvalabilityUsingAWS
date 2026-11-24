terraform {
  required_version = ">= 1.6.0, < 2.0.0"

  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.80"
      configuration_aliases = [aws.primary, aws.secondary]
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
