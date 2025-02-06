# IAM role for EBS CSI driver
resource "aws_iam_role" "ebs_csi_driver_role" {
  name = "AmazonEKS_EBS_CSI_RoleT"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })
  tags = local.tags
}

# Attach policy to EBS CSI driver role
resource "aws_iam_role_policy_attachment" "ebs_csi_driver_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_driver_role.name
}

# IAM role for VPC CNI
resource "aws_iam_role" "vpc_cni_role" {
  name = "AmazonEKS_CNI_RoleT"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })
  tags = local.tags
}

# Attach policy to VPC CNI role
resource "aws_iam_role_policy_attachment" "vpc_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.vpc_cni_role.name
}

# Local variables for EKS cluster
locals {
  name = "k8s"
  tags = {
    Environment = var.env
    Creator     = var.creator
  }
}

resource "aws_security_group" "istio_ports" {
  name        = "istio-ports-${local.name}"
  description = "Security group for Istio ports"
  vpc_id      = module.vpc.id

  # Allow all traffic from VPC CIDR and Kubernetes Service CIDR
  ingress {
    description = "All internal cluster and VPC traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [
      var.vpc_cidr_block,    # Your VPC CIDR (10.0.0.0/16)
      "172.20.0.0/16"        # Default EKS Service CIDR
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

# EKS cluster module
module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 20.33"
  cluster_name    = local.name
  cluster_version = "1.32"

  cluster_endpoint_public_access           = true
  cluster_endpoint_private_access          = true
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.id
  subnet_ids = module.vpc.public_subnets

  eks_managed_node_groups = {
    spot = {
      capacity_type = "SPOT"

      instance_types = ["t3a.medium"]
      # instance_types = ["t3a.medium", "t3a.large", "m7a.medium", "m7i-flex.large", "m6i.large", "m6a.large", "m5.large", "m5a.large"]

      # This value is ignored after the initial creation
      min_size     = 1
      max_size     = 5
      desired_size = 2

      # Enable node auto-repair
      node_repair_config = {
        enabled = true
      }

      vpc_security_group_ids = [aws_security_group.istio_ports.id]
    }
  }

  # EKS add-ons
  cluster_addons = {
    eks-pod-identity-agent = {
      most_recent       = true
      resolve_conflicts = "OVERWRITE"
    }
    vpc-cni = {
      most_recent = true
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION          = "true"
          ENABLE_POD_ENI                    = "true"
          POD_SECURITY_GROUP_ENFORCING_MODE = "standard"
          WARM_PREFIX_TARGET                = "1"
          MINIMUM_IP_TARGET                 = "10"
          WARM_IP_TARGET                    = "5"
          WARM_ENI_TARGET                   = "1"
        }
        enableNetworkPolicy = "true"
      })
      resolve_conflicts = "OVERWRITE"
      pod_identity_association = [{
        service_account = "aws-node"
        role_arn        = aws_iam_role.vpc_cni_role.arn
      }]
    }
    kube-proxy = {
      most_recent       = true
      resolve_conflicts = "OVERWRITE"
    }
    coredns = {
      most_recent       = true
      resolve_conflicts = "OVERWRITE"
    }
    aws-ebs-csi-driver = {
      most_recent       = true
      resolve_conflicts = "OVERWRITE"
      pod_identity_association = [{
        service_account = "ebs-csi-controller-sa"
        role_arn        = aws_iam_role.ebs_csi_driver_role.arn
      }]
    }
  }

  cluster_zonal_shift_config = {
    enabled = true
  }

  # Disable KMS encryption
  create_kms_key            = false
  cluster_encryption_config = {}

  tags = local.tags
}
