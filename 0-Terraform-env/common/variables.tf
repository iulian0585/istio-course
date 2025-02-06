# The account name
variable "account" {
  description = "The name of the AWS account"
}

variable "region" {
  description = "The AWS region to deploy resources in"
}

variable "env" {
  description = "The environment name (e.g., dev, prod)"
}

variable "vpc_cidr_block" {
  description = "The CIDR block for the VPC"
}

variable "creator" {
  type        = string
  default     = "Managed by Terraform"
  description = "The creator of the resources"
}

variable "default_trusted_cidrs" {
  type        = list(string)
  default     = []
  description = "List of default trusted CIDRs"
  # Needs to be set in '[env].auto.tfvars' file before using this variable in the respective env
}

# Defaults for each env
variable "account_ids" {
  type = map(any)
  default = {
    dev  = "891377043185"
    prod = "991287142927"
  }
  description = "Map of account IDs for different environments"
}

variable "subnet_count" {
  default     = 3
  description = "Number of subnets to create"
}

variable "trusted_cidrs" {
  type = list(any)
  default = [
    "94.177.40.42/32",   # Levi9 Iasi Office ISP1
    "89.238.253.230/32", # Levi9 Iasi Office ISP1
  ]
  description = "List of trusted CIDRs"
}

variable "team_tags" {
  type = list(string)
  default = [
    "platform",
    "workplace",
    "support-office",
    "data",
    "customer-service",
    "finance",
    "buying-and-sales",
  ]
  description = "List of team tags"
}

# Tags for BusinessUnit's
variable "aws_tags_BU_product" {
  default     = "product"
  description = "Tag for the product business unit"
}
variable "aws_tags_BU_marketing" {
  default     = "marketing"
  description = "Tag for the marketing business unit"
}
variable "aws_tags_BU_technology" {
  default     = "technology"
  description = "Tag for the technology business unit"
}

variable "arn_central_backup_account_id" {
  default     = "arn:aws:iam::217314892615:root"
  description = "ARN of the central backup account"
}

variable "central_backup_account_name" {
  default     = "demo_backup"
  description = "Name of the central backup account"
}