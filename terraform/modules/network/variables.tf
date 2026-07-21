variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
}

variable "availability_zones" {
  description = "Availability zones to spread subnets across"
  type        = list(string)
}

variable "project_name" {
  description = "Project name used for tagging/naming"
  type        = string
  default     = "wiz-tam"
}

variable "environment" {
  description = "Environment name used for tagging"
  type        = string
  default     = "dev"
}