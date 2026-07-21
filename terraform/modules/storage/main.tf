locals {
    common_tags = {
        Project = var.project_name
        Environment = var.environment
        ManagedBy = "terraform"
    }
}

data "aws_caller_identity" "current" {}

# 1. AWS Bucket
resource "aws_s3_bucket" "mongo_backups" {
    bucket = "${var.project_name}-mongo-backups-${data.aws_caller_identity.current.account_id}"

    tags = merge(local.common_tags, {
    Name = "${var.project_name}-mongo-backups"
  })
}

# 2. Intentional Misconfiguration - Disable all Block Public Access Protections
resource "aws_s3_bucket_public_access_block" "mongo_backups" {
  bucket = aws_s3_bucket.mongo_backups.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# 3. Intentional Misconfiguration - Bucket Policy Granting Public Read + List
resource "aws_s3_bucket_policy" "mongo_backups_public" {
  bucket = aws_s3_bucket.mongo_backups.id

  # Must be applied after the public access block is disabled, or AWS
  # will reject a public policy attempt
  # When you attempt PutBucketPolicy with a poliy that grants public access, S3
  # checks the bucket's current Block Public Access configuration. If block_public_policy
  # is still true, S3 will reject the PutBucketPolicy
  depends_on = [aws_s3_bucket_public_access_block.mongo_backups]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.mongo_backups.arn}/*"
      },
      {
        Sid       = "PublicListBucket"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:ListBucket"
        Resource  = aws_s3_bucket.mongo_backups.arn
      }
    ]
  })
}

# 4. S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "mongo_backups" {
  bucket = aws_s3_bucket.mongo_backups.id

  versioning_configuration {
    status = "Enabled"
  }
}