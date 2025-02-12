# Get available AWS availability zones
data "aws_availability_zones" "available" {}

# Get current AWS region
data "aws_region" "current" {}

# Get the most recent Amazon Linux 2023 AMI
data "aws_ami" "amzn_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["al2023-ami-2023*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  owners = ["amazon"]
}
