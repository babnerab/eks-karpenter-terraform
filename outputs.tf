output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "cluster_iam_role_name" {
  description = "IAM role name associated with EKS cluster"
  value       = aws_iam_role.cluster.name
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster for the OpenID Connect identity provider"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "vpc_id" {
  description = "ID of the VPC where the cluster and its nodes were deployed"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = aws_subnet.private[*].id
}

output "public_subnets" {
  description = "List of IDs of public subnets"
  value       = aws_subnet.public[*].id
}

output "karpenter_queue_name" {
  description = "Name of the SQS queue used by Karpenter"
  value       = aws_sqs_queue.karpenter.name
}

output "karpenter_queue_arn" {
  description = "ARN of the SQS queue used by Karpenter"
  value       = aws_sqs_queue.karpenter.arn
}

output "karpenter_instance_profile_name" {
  description = "Name of the instance profile used by Karpenter"
  value       = aws_iam_instance_profile.karpenter.name
}

output "karpenter_service_account_role_arn" {
  description = "ARN of the IAM role for Karpenter service account"
  value       = var.enable_irsa ? aws_iam_role.karpenter_service_account[0].arn : null
}

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}
