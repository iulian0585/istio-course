# https://github.com/terraform-aws-modules/terraform-aws-eks/tree/master/examples
# First, make sure you have updated your local kubeconfig
# aws eks --region eu-west-1 update-kubeconfig --name k8s-karpenter

# # Second, deploy the Karpenter NodeClass/NodePool
# kubectl apply -f karpenter.yaml

# # Second, deploy the example deployment
# kubectl apply -f inflate.yaml

# # You can watch Karpenter's controller logs with
# kubectl logs -f -n kube-system -l app.kubernetes.io/name=karpenter -c controller

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

provider "aws" {
  region = "us-east-1"
  alias  = "virginia"
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}

locals {
  name   = replace(basename(abspath("${path.module}/k8s-karpenter.tf")), ".tf", "")
  tags = {
    Environment = var.env
    Terraform   = "true"
  }
}

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

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.33"

  cluster_name    = local.name
  cluster_version = "1.32"


  cluster_endpoint_public_access           = true
  cluster_endpoint_private_access          = true
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.id
  subnet_ids = module.vpc.public_subnets
  control_plane_subnet_ids = module.vpc.public_subnets

  # EKS managed node groups

  eks_managed_node_groups = {
    karp-spot = {
      ami_type       = "BOTTLEROCKET_x86_64"
      capacity_type = "SPOT"
      instance_types = ["t3a.medium"]

      min_size     = 1
      max_size     = 3
      desired_size = 2

      labels = {
        # Used to ensure Karpenter runs on nodes that it does not manage
        "karpenter.sh/controller" = "true"
      }
    }

    work-spot = {
      capacity_type = "SPOT"

      instance_types = ["t3a.medium"]
     # instance_types = ["t3a.medium", "t3a.large", "m7a.medium", "m7i-flex.large", "m6i.large", "m6a.large", "m5.large", "m5a.large"]

      # This value is ignored after the initial creation
      min_size = 1
      max_size = 3
      desired_size = 2

      labels = {
        # Used to ensure Karpenter runs on nodes that it does not manage
        "karpenter.sh/discovery" = local.name
      }
    }
  }

  # EKS add-ons
  cluster_addons = {
    eks-pod-identity-agent = {
      most_recent       = false
      addon_version               = "v1.3.4-eksbuild.1"
      resolve_conflicts = "OVERWRITE"
    }
    vpc-cni = {
      most_recent = false
      addon_version = "v1.19.2-eksbuild.1"
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
      addon_version               = "v1.32.0-eksbuild.2"
      most_recent       = false
      resolve_conflicts = "OVERWRITE"
    }
    coredns = {
      most_recent       = false
      addon_version     = "v1.11.4-eksbuild.2"
      resolve_conflicts = "OVERWRITE"
    }
    aws-ebs-csi-driver = {
      most_recent       = false
      addon_version     = "v1.38.1-eksbuild.2"
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

  tags = local.tags
}

################################################################################
# Karpenter
################################################################################

module "karpenter" {
  source = "../../modules/karpenter"

  cluster_name          = module.eks.cluster_name
  enable_v1_permissions = true

  # Name needs to match role name passed to the EC2NodeClass
  node_iam_role_use_name_prefix   = false
  node_iam_role_name              = local.name
  create_pod_identity_association = true

  # Used to attach additional IAM policies to the Karpenter node IAM role
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = local.tags
}

module "karpenter_disabled" {
  source = "../../modules/karpenter"

  create = false
}

################################################################################
# Karpenter Helm chart & manifests
# Not required; just to demonstrate functionality of the sub-module
################################################################################

resource "helm_release" "karpenter" {
  namespace           = "kube-system"
  name                = "karpenter"
  repository          = "oci://public.ecr.aws/karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  chart               = "karpenter"
  version             = "1.1.1"
  wait                = false

  values = [
    <<-EOT
    nodeSelector:
      karpenter.sh/controller: 'true'
    dnsPolicy: Default
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    webhook:
      enabled: false
    EOT
  ]
}
