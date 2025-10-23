# Karpenter Node Pool for x86 instances
resource "kubernetes_manifest" "karpenter_node_pool_x86" {
  manifest = {
    apiVersion = "karpenter.sh/v1beta1"
    kind       = "NodePool"
    metadata = {
      name = "x86-nodepool"
    }
    spec = {
      template = {
        metadata = {
          labels = {
            "karpenter.sh/nodepool" = "x86-nodepool"
            "node-type"             = "x86"
          }
        }
        spec = {
          requirements = [
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["on-demand", "spot"]
            },
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]
            },
            {
              key      = "node.kubernetes.io/instance-type"
              operator = "In"
              values   = var.node_instance_types
            }
          ]
          nodeClassRef = {
            apiVersion = "karpenter.k8s.aws/v1beta1"
            kind       = "EC2NodeClass"
            name       = "default"
          }
          taints = []
          startupTaints = []
        }
      }
      limits = {
        cpu    = "1000"
        memory = "1000Gi"
      }
      disruption = {
        consolidateAfter = "30s"
        expireAfter      = "2160h"
      }
    }
  }

  depends_on = [helm_release.karpenter]
}

# Karpenter Node Pool for ARM64 (Graviton) instances
resource "kubernetes_manifest" "karpenter_node_pool_arm64" {
  manifest = {
    apiVersion = "karpenter.sh/v1beta1"
    kind       = "NodePool"
    metadata = {
      name = "arm64-nodepool"
    }
    spec = {
      template = {
        metadata = {
          labels = {
            "karpenter.sh/nodepool" = "arm64-nodepool"
            "node-type"             = "arm64"
          }
        }
        spec = {
          requirements = [
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["on-demand", "spot"]
            },
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["arm64"]
            },
            {
              key      = "node.kubernetes.io/instance-type"
              operator = "In"
              values   = var.spot_instance_types
            }
          ]
          nodeClassRef = {
            apiVersion = "karpenter.k8s.aws/v1beta1"
            kind       = "EC2NodeClass"
            name       = "default"
          }
          taints = []
          startupTaints = []
        }
      }
      limits = {
        cpu    = "1000"
        memory = "1000Gi"
      }
      disruption = {
        consolidateAfter = "30s"
        expireAfter      = "2160h"
      }
    }
  }

  depends_on = [helm_release.karpenter]
}

# Karpenter Node Pool for Spot instances (mixed x86 and ARM64)
resource "kubernetes_manifest" "karpenter_node_pool_spot" {
  manifest = {
    apiVersion = "karpenter.sh/v1beta1"
    kind       = "NodePool"
    metadata = {
      name = "spot-nodepool"
    }
    spec = {
      template = {
        metadata = {
          labels = {
            "karpenter.sh/nodepool" = "spot-nodepool"
            "node-type"             = "spot"
          }
        }
        spec = {
          requirements = [
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["spot"]
            },
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64", "arm64"]
            },
            {
              key      = "node.kubernetes.io/instance-type"
              operator = "In"
              values   = var.spot_instance_types
            }
          ]
          nodeClassRef = {
            apiVersion = "karpenter.k8s.aws/v1beta1"
            kind       = "EC2NodeClass"
            name       = "default"
          }
          taints = []
          startupTaints = []
        }
      }
      limits = {
        cpu    = "1000"
        memory = "1000Gi"
      }
      disruption = {
        consolidateAfter = "30s"
        expireAfter      = "2160h"
      }
    }
  }

  depends_on = [helm_release.karpenter]
}

# EC2 Node Class
resource "kubernetes_manifest" "karpenter_ec2_node_class" {
  manifest = {
    apiVersion = "karpenter.k8s.aws/v1beta1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "default"
    }
    spec = {
      amiFamily = "AL2"
      role      = aws_iam_role.karpenter.name
      subnetSelectorTerms = [
        {
          tags = {
            "kubernetes.io/role/internal-elb" = "1"
          }
        }
      ]
      securityGroupSelectorTerms = [
        {
          tags = {
            "kubernetes.io/cluster/${local.cluster_name}" = "owned"
          }
        }
      ]
      instanceStorePolicy = "RAID0"
      userData = base64encode(<<-EOT
        #!/bin/bash
        /etc/eks/bootstrap.sh ${local.cluster_name}
        /opt/aws/bin/cfn-signal -e $? --stack ${local.cluster_name} --resource AutoScalingGroup --region ${var.aws_region}
      EOT
      )
      tags = merge(local.common_tags, {
        "karpenter.sh/discovery" = local.cluster_name
      })
      blockDeviceMappings = [
        {
          deviceName = "/dev/xvda"
          ebs = {
            volumeSize          = "100Gi"
            volumeType          = "gp3"
            iops                = 3000
            throughput          = 125
            deleteOnTermination = true
            encrypted           = true
          }
        }
      ]
    }
  }

  depends_on = [helm_release.karpenter]
}
