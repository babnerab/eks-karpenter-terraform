provider "aws" {
  region = var.aws_region
  profile = var.aws_profile
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# EKS cluster connection for providers
data "aws_eks_cluster" "main" {
  name = local.cluster_name

  depends_on = [aws_eks_cluster.main]
}

data "aws_eks_cluster_auth" "main" {
  name = local.cluster_name

  depends_on = [aws_eks_cluster.main]
}

# Local values
locals {
  cluster_name = "${var.project_name}-${var.environment}"
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Kubernetes provider (connects directly to EKS API)
provider "kubernetes" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
}

# Helm provider (connects directly to EKS API)
provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.main.token
  }
}
