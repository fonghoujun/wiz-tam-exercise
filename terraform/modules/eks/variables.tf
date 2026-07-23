variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "wiz-tam-eks"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for worker nodes"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs (control plane needs both for endpoint access)"
  type        = list(string)
}

variable "node_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "kubernetes_version" {
  type    = string
  default = "1.33"
}

variable "project_name" {
  type    = string
  default = "wiz-tam"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions, granted Kubernetes access"
  type        = string
}