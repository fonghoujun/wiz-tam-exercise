terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "network" {
  source = "./modules/network"

  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
}

module "eks" {
  source = "./modules/eks"

  vpc_id                  = module.network.vpc_id
  private_subnet_ids      = module.network.private_subnet_ids
  public_subnet_ids       = module.network.public_subnet_ids
  github_actions_role_arn = module.oidc.role_arn
}

module "storage" {
  source = "./modules/storage"

  project_name = "wiz-tam"
  environment  = "dev"
}

module "mongo_vm" {
  source = "./modules/mongo-vm"

  vpc_id                     = module.network.vpc_id
  public_subnet_id           = module.network.public_subnet_ids[0]
  eks_node_security_group_id = module.eks.node_security_group_id
  backup_bucket_name         = module.storage.bucket_name
  mongo_admin_password       = var.mongo_admin_password
  mongo_app_password         = var.mongo_app_password
}

module "oidc" {
  source = "./modules/oidc"

  github_org  = "fonghoujun"
  github_repo = "wiz-tam-exercise"
}
