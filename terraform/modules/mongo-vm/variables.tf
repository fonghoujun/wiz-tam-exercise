variable "vpc_id" {
  description = "VPC ID to deploy into"
  type        = string
}

variable "public_subnet_id" {
  description = "Public subnet ID for the Mongo VM"
  type        = string
}

variable "eks_node_security_group_id" {
  description = "Security group ID of EKS worker nodes, allowed to reach Mongo on 27017"
  type        = string
}

variable "key_name" {
  description = "Name of the manually-created EC2 key pair"
  type        = string
  default     = "wiz-tam-mongo-key"
}

variable "mongo_admin_password" {
  description = "MongoDB admin user password"
  type        = string
  sensitive   = true
}

variable "mongo_app_password" {
  description = "MongoDB app user password"
  type        = string
  sensitive   = true
}

variable "backup_bucket_name" {
  description = "S3 bucket name for MongoDB backups"
  type        = string
}

variable "project_name" {
  type    = string
  default = "wiz-tam"
}

variable "environment" {
  type    = string
  default = "dev"
}