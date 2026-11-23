project_name            = "ha-notes"
environment             = "dev"
owner                   = "cloud-architect"
primary_region          = "us-east-1"
secondary_region        = "ap-south-1"
primary_vpc_cidr        = "10.10.0.0/16"
secondary_vpc_cidr      = "10.20.0.0/16"
single_nat_gateway      = true
primary_desired_count   = 2
secondary_desired_count = 1
custom_domain_name      = ""

# Phase feature flags (keep high-cost flags false until testing that phase!)
enable_secondary_region  = false
enable_aurora_global     = false
enable_storage_cdn       = false
enable_arc_cluster       = false # WARNING: $2.50/hr when true!
enable_monitoring        = false
enable_fis               = false
enable_failback_workflow = false
