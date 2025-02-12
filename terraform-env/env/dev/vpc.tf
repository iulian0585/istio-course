# Make DNS for the VPC - environment in Route53
# Uncomment the following resource if you need to create a Route53 zone for the VPC
# resource "aws_route53_zone" "main" {
#   name = "${var.account}.it."
# }

##Building basic vpc
module "vpc" {
  source     = "../../modules/aws_vpc"
  name       = var.account
  env        = var.env
  cidr_block = var.vpc_cidr_block
}

