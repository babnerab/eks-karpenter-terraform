variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "eks-karpenter"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "cluster_version" {
  description = "Kubernetes version to use for the EKS cluster"
  type        = string
  default     = "1.28"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = []
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

variable "enable_irsa" {
  description = "Whether to create OpenID Connect (OIDC) Identity provider for IRSA"
  type        = bool
  default     = true
}

variable "karpenter_version" {
  description = "Version of Karpenter to deploy"
  type        = string
  default     = "0.35.0"
}

variable "node_instance_types" {
  description = "List of instance types for the node group"
  type        = list(string)
  default     = ["m5.large", "m5.xlarge", "m6g.large", "m6g.xlarge", "c5.large", "c5.xlarge", "c6g.large", "c6g.xlarge"]
}

variable "spot_instance_types" {
  description = "List of instance types for spot instances"
  type        = list(string)
  default     = ["m5.large", "m5.xlarge", "m6g.large", "m6g.xlarge", "c5.large", "c5.xlarge", "c6g.large", "c6g.xlarge", "r5.large", "r5.xlarge", "r6g.large", "r6g.xlarge"]
}
