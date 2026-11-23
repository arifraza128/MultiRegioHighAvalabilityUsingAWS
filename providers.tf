# Primary Region Provider (Default & Alias: aws.primary)
provider "aws" {
  region = var.primary_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
      CostCenter  = "MultiRegionHA-Lab"
      RegionRole  = "primary"
    }
  }
}

provider "aws" {
  alias  = "primary"
  region = var.primary_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
      CostCenter  = "MultiRegionHA-Lab"
      RegionRole  = "primary"
    }
  }
}

# Secondary (DR) Region Provider (Alias: aws.secondary)
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
      CostCenter  = "MultiRegionHA-Lab"
      RegionRole  = "secondary"
    }
  }
}
