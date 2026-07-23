variable "project_name" {
  type    = string
  default = "wiz-tam"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "allowed_ip_cidr" {
  description = "Your public IP in CIDR notation, allowed to reach the EKS public endpoint"
  type        = string
}