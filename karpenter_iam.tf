# IAM Role for Karpenter Nodes (EC2 Instance Profile)
resource "aws_iam_role" "karpenter" {
  name = "${local.cluster_name}-karpenter-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "karpenter_worker_node" {
  role       = aws_iam_role.karpenter.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "karpenter_cni" {
  role       = aws_iam_role.karpenter.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "karpenter_ecr_read" {
  role       = aws_iam_role.karpenter.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "karpenter_ssm" {
  role       = aws_iam_role.karpenter.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "karpenter" {
  name = "${local.cluster_name}-karpenter-instance-profile"
  role = aws_iam_role.karpenter.name
  tags = local.common_tags
}

# OIDC provider for IRSA
data "tls_certificate" "oidc" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  count = var.enable_irsa ? 1 : 0

  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
  client_id_list = [
    "sts.amazonaws.com"
  ]
  thumbprint_list = [
    data.tls_certificate.oidc.certificates[0].sha1_fingerprint
  ]
  tags = local.common_tags
}

# IAM Role for Karpenter Controller (IRSA)
resource "aws_iam_role" "karpenter_service_account" {
  count = var.enable_irsa ? 1 : 0

  name = "${local.cluster_name}-karpenter-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRoleWithWebIdentity"
        Principal = {
          Federated = aws_iam_openid_connect_provider.cluster[0].arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.cluster[0].url, "https://", "")}:sub" = "system:serviceaccount:karpenter:karpenter",
            "${replace(aws_iam_openid_connect_provider.cluster[0].url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "karpenter_controller" {
  count = var.enable_irsa ? 1 : 0

  name = "${local.cluster_name}-karpenter-controller-policy"
  role = aws_iam_role.karpenter_service_account[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ec2:CreateLaunchTemplate",
          "ec2:DeleteLaunchTemplate",
          "ec2:CreateFleet",
          "ec2:RunInstances",
          "ec2:TerminateInstances",
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "ec2:Describe*"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "iam:PassRole"
        ],
        Resource = aws_iam_role.karpenter.arn
      },
      {
        Effect = "Allow",
        Action = [
          "ssm:GetParameter",
          "pricing:GetProducts"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ReceiveMessage",
          "sqs:ChangeMessageVisibility"
        ],
        Resource = aws_sqs_queue.karpenter.arn
      }
    ]
  })
}


