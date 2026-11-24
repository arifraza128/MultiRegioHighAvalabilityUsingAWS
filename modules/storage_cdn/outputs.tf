output "primary_bucket_name" {
  description = "Name of the primary S3 static assets bucket"
  value       = aws_s3_bucket.primary.id
}

output "secondary_bucket_name" {
  description = "Name of the secondary S3 replica static assets bucket"
  value       = aws_s3_bucket.secondary.id
}

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution with multi-region Origin Group failover"
  value       = aws_cloudfront_distribution.cdn.id
}

output "cloudfront_domain_name" {
  description = "Default domain name of the CloudFront distribution (*.cloudfront.net)"
  value       = aws_cloudfront_distribution.cdn.domain_name
}
