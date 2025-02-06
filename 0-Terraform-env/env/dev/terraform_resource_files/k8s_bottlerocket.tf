# https://github.com/terraform-aws-modules/terraform-aws-eks/tree/master/examples

# Create IAM role for the node group
# resource "aws_iam_role" "node_group_role" {
#   name = "eks-node-group-role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Principal = {
#           Service = "ec2.amazonaws.com"
#         }
#         Action = "sts:AssumeRole"
#       }
#     ]
#   })
# }

# # Attach required policies to the node group role
# resource "aws_iam_role_policy_attachment" "node_group_AmazonEKSWorkerNodePolicy" {
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
#   role       = aws_iam_role.node_group_role.name
# }

# resource "aws_iam_role_policy_attachment" "node_group_AmazonEKS_CNI_Policy" {
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
#   role       = aws_iam_role.node_group_role.name
# }

# resource "aws_iam_role_policy_attachment" "node_group_AmazonEC2ContainerRegistryReadOnly" {
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
#   role       = aws_iam_role.node_group_role.name
# }



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
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_driver_role.name
}

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
}


resource "aws_iam_role_policy_attachment" "vpc_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.vpc_cni_role.name
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "k8s-istio"
}


module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.33.1"

  cluster_name    = var.cluster_name
  cluster_version = "1.32"


  cluster_endpoint_public_access           = true
  cluster_endpoint_private_access          = false
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.id
  subnet_ids = module.vpc.public_subnets

  # Example node group with recommended settings
  eks_managed_node_groups = {
    bottlerocket = {
      name = "bottlerocket-nodes"

      ami_type = "BOTTLEROCKET_x86_64"
      platform = "bottlerocket"

      instance_types = ["t3a.medium", "t3a.large", "m7a.medium", "m7i-flex.large", "m6i.large", "m6a.large", "m5.large", "m5a.large"]

      min_size     = 1
      max_size     = 5
      desired_size = 1

      # Enable monitoring
      enable_monitoring = true

      # Use spot instances for cost optimization
      capacity_type = "SPOT"

      # Enable automatic updates
      update_config = {
        max_unavailable_percentage = 33
      }

      # Labels and taints
      labels = {
        Environment = "dev"
        OS          = "bottlerocket"
      }

      # Bootstrap configuration
      bootstrap_extra_args = <<-EOT
      [settings.kubernetes]
      max-pods = 110

      [settings.host-containers.admin]
      enabled = true
      superpowered = true

      [settings.host-containers.control]
      enabled = true

    EOT
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

  # Disable KMS encryption
  create_kms_key            = false
  cluster_encryption_config = {}

  tags = {
    Environment = var.env
    Terraform   = "true"
  }
}
