variable "project_name" {
  description = "Project name used for naming/tagging"
  type        = string
  default     = "wiz-tam"
}

variable "environment" {
  description = "Environment name used for tagging"
  type        = string
  default     = "dev"
}