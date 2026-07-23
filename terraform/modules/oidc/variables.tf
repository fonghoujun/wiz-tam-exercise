variable "github_org" {
  description = "GitHub username or org that owns the repo"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without org prefix)"
  type        = string
}

variable "project_name" {
  type    = string
  default = "wiz-tam"
}