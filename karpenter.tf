# Karpenter Helm Chart
resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_version
  namespace  = "karpenter"

  create_namespace = true

  values = [yamlencode({
    settings = {
      aws = {
        clusterName            = aws_eks_cluster.main.name
        clusterEndpoint        = aws_eks_cluster.main.endpoint
        defaultInstanceProfile = aws_iam_instance_profile.karpenter.name
        interruptionQueue      = aws_sqs_queue.karpenter.name
      }
    }
    serviceAccount = {
      annotations = var.enable_irsa ? {
        "eks.amazonaws.com/role-arn" = aws_iam_role.karpenter_service_account[0].arn
      } : {}
    }
  })]

  depends_on = [
    aws_eks_cluster.main,
    aws_eks_addon.vpc_cni,
    aws_eks_addon.coredns,
    aws_eks_addon.kube_proxy,
    aws_eks_addon.ebs_csi_driver
  ]
}

# SQS Queue for Karpenter
resource "aws_sqs_queue" "karpenter" {
  name = "${local.cluster_name}-karpenter-queue"

  message_retention_seconds = 300
  visibility_timeout_seconds = 60

  tags = local.common_tags
}

# SQS Queue Policy
resource "aws_sqs_queue_policy" "karpenter" {
  queue_url = aws_sqs_queue.karpenter.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = "sqs:SendMessage"
        Resource = aws_sqs_queue.karpenter.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.karpenter.arn
          }
        }
      }
    ]
  })
}

# SNS Topic for Karpenter
resource "aws_sns_topic" "karpenter" {
  name = "${local.cluster_name}-karpenter-topic"

  tags = local.common_tags
}

# SNS Topic Subscription
resource "aws_sns_topic_subscription" "karpenter" {
  topic_arn = aws_sns_topic.karpenter.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.karpenter.arn
}

# EventBridge Rule for Spot Interruption
resource "aws_cloudwatch_event_rule" "karpenter" {
  name = "${local.cluster_name}-karpenter-spot-interruption"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "karpenter" {
  rule      = aws_cloudwatch_event_rule.karpenter.name
  target_id = "KarpenterInterruptionQueueTarget"
  arn       = aws_sns_topic.karpenter.arn
}

# EventBridge Rule for Instance State Change
resource "aws_cloudwatch_event_rule" "karpenter_state_change" {
  name = "${local.cluster_name}-karpenter-state-change"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
    detail = {
      state = ["terminated", "stopped"]
    }
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "karpenter_state_change" {
  rule      = aws_cloudwatch_event_rule.karpenter_state_change.name
  target_id = "KarpenterStateChangeQueueTarget"
  arn       = aws_sns_topic.karpenter.arn
}

# EventBridge Rule for Instance Rebalance Recommendation
resource "aws_cloudwatch_event_rule" "karpenter_rebalance" {
  name = "${local.cluster_name}-karpenter-rebalance"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance Rebalance Recommendation"]
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "karpenter_rebalance" {
  rule      = aws_cloudwatch_event_rule.karpenter_rebalance.name
  target_id = "KarpenterRebalanceQueueTarget"
  arn       = aws_sns_topic.karpenter.arn
}
