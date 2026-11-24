# =============================================================================
# S3 Cross-Region Replication (CRR) + CloudFront Origin Group + ACM (us-east-1)
# NOTE (AGENTS.md Section 1.2): CloudFront requires viewer ACM certificates to
# reside in us-east-1 (aws.primary).
# =============================================================================

data "aws_caller_identity" "current" {
  provider = aws.primary
}

data "aws_region" "primary" {
  provider = aws.primary
}

data "aws_region" "secondary" {
  provider = aws.secondary
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

locals {
  account_id       = data.aws_caller_identity.current.account_id
  primary_region   = data.aws_region.primary.name
  secondary_region = data.aws_region.secondary.name

  region_short_map = {
    "us-east-1"      = "use1"
    "us-east-2"      = "use2"
    "us-west-2"      = "usw2"
    "ap-south-1"     = "aps1"
    "eu-west-1"      = "euw1"
    "ap-southeast-1" = "apse1"
  }

  primary_short   = lookup(local.region_short_map, local.primary_region, replace(local.primary_region, "-", ""))
  secondary_short = lookup(local.region_short_map, local.secondary_region, replace(local.secondary_region, "-", ""))

  name_prefix           = "${var.project_name}-${var.environment}"
  primary_bucket_name   = "${local.name_prefix}-${local.primary_short}-assets-${random_id.bucket_suffix.hex}"
  secondary_bucket_name = "${local.name_prefix}-${local.secondary_short}-assets-${random_id.bucket_suffix.hex}"
  use_custom_domain     = var.custom_domain_name != ""
}

# -----------------------------------------------------------------------------
# 1. Customer-Managed KMS Keys for S3 Static Assets (Primary & Secondary)
#    Must allow CloudFront (delivery.logs.amazonaws.com / cloudfront.amazonaws.com)
#    and the S3 CRR Replication IAM Role to encrypt/decrypt objects.
# -----------------------------------------------------------------------------
resource "aws_kms_key" "primary_s3" {
  provider                = aws.primary
  description             = "KMS key for primary S3 static assets in ${local.primary_region}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccountPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowCloudFrontServicePrincipalDecrypt"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey*"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}

resource "aws_kms_key" "secondary_s3" {
  provider                = aws.secondary
  description             = "KMS key for secondary S3 replica assets in ${local.secondary_region}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccountPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowCloudFrontServicePrincipalDecrypt"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey*"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# 2. Primary S3 Bucket (us-east-1) & Secondary Replica S3 Bucket (ap-south-1)
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "primary" {
  provider      = aws.primary
  bucket        = local.primary_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "primary" {
  provider = aws.primary
  bucket   = aws_s3_bucket.primary.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "primary" {
  provider = aws.primary
  bucket   = aws_s3_bucket.primary.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.primary_s3.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "primary" {
  provider                = aws.primary
  bucket                  = aws_s3_bucket.primary.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "secondary" {
  provider      = aws.secondary
  bucket        = local.secondary_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "secondary" {
  provider = aws.secondary
  bucket   = aws_s3_bucket.secondary.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "secondary" {
  provider = aws.secondary
  bucket   = aws_s3_bucket.secondary.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.secondary_s3.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "secondary" {
  provider                = aws.secondary
  bucket                  = aws_s3_bucket.secondary.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# 3. Least-Privilege IAM Role & Configuration for S3 Cross-Region Replication
# -----------------------------------------------------------------------------
resource "aws_iam_role" "s3_crr" {
  provider = aws.primary
  name     = "${local.name_prefix}-s3-crr-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "s3_crr" {
  provider = aws.primary
  name     = "${local.name_prefix}-s3-crr-policy"
  role     = aws_iam_role.s3_crr.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowReadSourceBucketMetadata"
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.primary.arn
      },
      {
        Sid    = "AllowReadSourceBucketObjectVersions"
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Resource = "${aws_s3_bucket.primary.arn}/*"
      },
      {
        Sid    = "AllowReplicateToDestinationBucket"
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = "${aws_s3_bucket.secondary.arn}/*"
      },
      {
        Sid      = "AllowDecryptPrimaryKMS"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = aws_kms_key.primary_s3.arn
        Condition = {
          StringLike = {
            "kms:ViaService"                   = "s3.${local.primary_region}.amazonaws.com"
            "kms:EncryptionContext:aws:s3:arn" = "${aws_s3_bucket.primary.arn}/*"
          }
        }
      },
      {
        Sid      = "AllowEncryptSecondaryKMS"
        Effect   = "Allow"
        Action   = ["kms:Encrypt"]
        Resource = aws_kms_key.secondary_s3.arn
        Condition = {
          StringLike = {
            "kms:ViaService"                   = "s3.${local.secondary_region}.amazonaws.com"
            "kms:EncryptionContext:aws:s3:arn" = "${aws_s3_bucket.secondary.arn}/*"
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_replication_configuration" "primary_to_secondary" {
  provider   = aws.primary
  role       = aws_iam_role.s3_crr.arn
  bucket     = aws_s3_bucket.primary.id
  depends_on = [aws_s3_bucket_versioning.primary, aws_s3_bucket_versioning.secondary]

  rule {
    id     = "replicate-all-static-assets-to-${local.secondary_short}"
    status = "Enabled"

    filter {}

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }

    destination {
      bucket        = aws_s3_bucket.secondary.arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.secondary_s3.arn
      }

      metrics {
        status = "Enabled"
        event_threshold {
          minutes = 15
        }
      }

      replication_time {
        status = "Enabled"
        time {
          minutes = 15
        }
      }
    }

    delete_marker_replication {
      status = "Enabled"
    }
  }
}

# -----------------------------------------------------------------------------
# 4. Optional ACM Certificate in us-east-1 (Required Region for CloudFront)
# -----------------------------------------------------------------------------
resource "aws_acm_certificate" "cloudfront" {
  count             = local.use_custom_domain ? 1 : 0
  provider          = aws.primary
  domain_name       = var.custom_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# 5. CloudFront Origin Access Control (OAC) & Origin Group (Primary -> Secondary)
# -----------------------------------------------------------------------------
resource "aws_cloudfront_origin_access_control" "s3_oac" {
  provider                          = aws.primary
  name                              = "${local.name_prefix}-s3-oac"
  description                       = "Origin Access Control for Multi-Region S3 Static Assets"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "cdn" {
  provider            = aws.primary
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${local.name_prefix} Multi-Region Failover CDN"
  default_root_object = "index.html"
  price_class         = "PriceClass_200"
  aliases             = local.use_custom_domain ? [var.custom_domain_name] : []

  # Origin Group: Automatically fails over GET/HEAD requests on 500/502/503/504
  origin_group {
    origin_id = "s3-multi-region-origin-group"

    failover_criteria {
      status_codes = [500, 502, 503, 504]
    }

    member {
      origin_id = "s3-primary-${local.primary_short}"
    }

    member {
      origin_id = "s3-secondary-${local.secondary_short}"
    }
  }

  origin {
    domain_name              = aws_s3_bucket.primary.bucket_regional_domain_name
    origin_id                = "s3-primary-${local.primary_short}"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3_oac.id
  }

  origin {
    domain_name              = aws_s3_bucket.secondary.bucket_regional_domain_name
    origin_id                = "s3-secondary-${local.secondary_short}"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3_oac.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-multi-region-origin-group"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 60
    max_ttl     = 300
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = !local.use_custom_domain
    acm_certificate_arn            = local.use_custom_domain ? aws_acm_certificate.cloudfront[0].arn : null
    ssl_support_method             = local.use_custom_domain ? "sni-only" : null
    minimum_protocol_version       = "TLSv1.2_2021"
  }
}

# -----------------------------------------------------------------------------
# 6. S3 Bucket Policies Allowing CloudFront OAC + Enforcing TLS
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_policy" "primary" {
  provider = aws.primary
  bucket   = aws_s3_bucket.primary.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipalReadOnly"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.primary.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.cdn.arn
          }
        }
      },
      {
        Sid       = "DenyNonTLSRequests"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.primary.arn,
          "${aws_s3_bucket.primary.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_policy" "secondary" {
  provider = aws.secondary
  bucket   = aws_s3_bucket.secondary.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipalReadOnly"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.secondary.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.cdn.arn
          }
        }
      },
      {
        Sid       = "DenyNonTLSRequests"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.secondary.arn,
          "${aws_s3_bucket.secondary.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# 7. Seed Default Status UI Object (index.html) into Primary S3 Bucket
# -----------------------------------------------------------------------------
resource "aws_s3_object" "index_html" {
  provider     = aws.primary
  bucket       = aws_s3_bucket.primary.id
  key          = "index.html"
  content_type = "text/html"
  kms_key_id   = aws_kms_key.primary_s3.arn
  content      = <<-EOT
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8" />
      <title>Multi-Region HA & DR Status Portal (${var.project_name})</title>
      <style>
        body { font-family: system-ui, sans-serif; max-width: 720px; margin: 3rem auto; padding: 1.5rem; background: #0f172a; color: #f8fafc; }
        .card { background: #1e293b; border: 1px solid #334155; border-radius: 8px; padding: 1.5rem; }
        .badge { display: inline-block; padding: 0.25rem 0.75rem; border-radius: 999px; background: #22c55e; color: #052e16; font-weight: 700; }
      </style>
    </head>
    <body>
      <div class="card">
        <h1>Multi-Region High Availability on AWS</h1>
        <p><span class="badge">CloudFront Origin Group + S3 CRR Active</span></p>
        <p><strong>Primary Origin Region:</strong> ${local.primary_region} (${local.primary_bucket_name})</p>
        <p><strong>Failover Replica Region:</strong> ${local.secondary_region} (${local.secondary_bucket_name})</p>
      </div>
    </body>
    </html>
  EOT

  depends_on = [aws_s3_bucket_replication_configuration.primary_to_secondary]
}
