output "state_bucket_name" {
  description = "S3 bucket used by the main infrastructure's encrypted, locked remote state."
  value       = aws_s3_bucket.terraform_state.id
}
