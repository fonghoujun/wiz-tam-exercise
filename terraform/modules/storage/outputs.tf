output "bucket_name" {
  value = aws_s3_bucket.mongo_backups.id
}

output "bucket_arn" {
  value = aws_s3_bucket.mongo_backups.arn
}