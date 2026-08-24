mock_provider "aws" {
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }
}

run "secure_state_backend" {
  command = plan

  assert {
    condition     = aws_s3_bucket_public_access_block.terraform_state.restrict_public_buckets
    error_message = "Terraform state must never be publicly reachable."
  }

  assert {
    condition     = aws_s3_bucket_versioning.terraform_state.versioning_configuration[0].status == "Enabled"
    error_message = "Terraform state must retain versions for recovery."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.terraform_state.rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"
    error_message = "Terraform state must be encrypted at rest."
  }
}
