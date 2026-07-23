terraform {
  backend "s3" {
    bucket         = "wiz-tam-terraform-state-334716554729"
    key            = "wiz-tam-exercise/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "wiz-tam-terraform-locks"
    encrypt        = true
  }
}