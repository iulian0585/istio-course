terraform {
  backend "s3" {
    bucket  = "terraform-k8s-workshop"
    key     = "dev/terraform.tfstate"
    region  = "eu-west-1"
    profile = "default"
  }
}

