# Pod Security Standards
resource "kubernetes_manifest" "pod_security_standards" {
  count = var.enable_kubernetes_addons ? 1 : 0
  manifest = {
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = "pod-security"
      labels = {
        "pod-security.kubernetes.io/enforce" = "restricted"
        "pod-security.kubernetes.io/audit"   = "restricted"
        "pod-security.kubernetes.io/warn"   = "restricted"
      }
    }
  }

  depends_on = [aws_eks_cluster.main]
}

# Network Policies
resource "kubernetes_manifest" "default_deny_ingress" {
  count = var.enable_kubernetes_addons ? 1 : 0
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata = {
      name      = "default-deny-ingress"
      namespace = "default"
    }
    spec = {
      podSelector = {}
      policyTypes = ["Ingress"]
    }
  }

  depends_on = [aws_eks_cluster.main]
}

resource "kubernetes_manifest" "default_deny_egress" {
  count = var.enable_kubernetes_addons ? 1 : 0
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata = {
      name      = "default-deny-egress"
      namespace = "default"
    }
    spec = {
      podSelector = {}
      policyTypes = ["Egress"]
    }
  }

  depends_on = [aws_eks_cluster.main]
}

# RBAC - Cluster Admin Role
resource "kubernetes_cluster_role" "cluster_admin" {
  count = var.enable_kubernetes_addons ? 1 : 0
  metadata {
    name = "cluster-admin"
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }

  depends_on = [aws_eks_cluster.main]
}

# RBAC - Read-only Role
resource "kubernetes_cluster_role" "read_only" {
  count = var.enable_kubernetes_addons ? 1 : 0
  metadata {
    name = "read-only"
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["get", "list", "watch"]
  }

  depends_on = [aws_eks_cluster.main]
}

# RBAC - Developer Role
resource "kubernetes_cluster_role" "developer" {
  count = var.enable_kubernetes_addons ? 1 : 0
  metadata {
    name = "developer"
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "services", "configmaps", "secrets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["networkpolicies"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  depends_on = [aws_eks_cluster.main]
}

# Service Account for Karpenter with minimal permissions
resource "kubernetes_service_account" "karpenter" {
  count = var.enable_kubernetes_addons ? 1 : 0
  metadata {
    name      = "karpenter"
    namespace = "karpenter"
    annotations = {
      "eks.amazonaws.com/role-arn" = var.enable_irsa ? aws_iam_role.karpenter_service_account[0].arn : ""
    }
  }

  depends_on = [aws_eks_cluster.main]
}

# Pod Security Policy (if supported)
resource "kubernetes_manifest" "pod_security_policy" {
  count = var.enable_kubernetes_addons && var.enable_psp ? 1 : 0
  manifest = {
    apiVersion = "policy/v1beta1"
    kind       = "PodSecurityPolicy"
    metadata = {
      name = "restricted"
    }
    spec = {
      privileged                = false
      allowPrivilegeEscalation  = false
      requiredDropCapabilities  = ["ALL"]
      volumes = [
        "configMap",
        "emptyDir",
        "projected",
        "secret",
        "downwardAPI",
        "persistentVolumeClaim"
      ]
      runAsUser = {
        rule = "MustRunAsNonRoot"
      }
      seLinux = {
        rule = "RunAsAny"
      }
      fsGroup = {
        rule = "MustRunAs"
        ranges = [
          {
            min = 1
            max = 65535
          }
        ]
      }
    }
  }

  depends_on = [aws_eks_cluster.main]
}

# Security Context Constraints
resource "kubernetes_manifest" "security_context_constraints" {
  count = var.enable_kubernetes_addons && var.enable_scc ? 1 : 0
  manifest = {
    apiVersion = "security.openshift.io/v1"
    kind       = "SecurityContextConstraints"
    metadata = {
      name = "restricted"
    }
    spec = {
      allowHostDirVolumePlugin        = false
      allowHostIPC                    = false
      allowHostNetwork                = false
      allowHostPID                    = false
      allowHostPorts                  = false
      allowPrivilegeEscalation        = false
      allowPrivilegedContainer        = false
      allowedCapabilities             = null
      defaultAddCapabilities          = null
      fsGroup = {
        type = "MustRunAs"
        ranges = [
          {
            min = 1
            max = 65535
          }
        ]
      }
      readOnlyRootFilesystem = false
      requiredDropCapabilities = [
        "KILL",
        "MKNOD",
        "SETUID",
        "SETGID"
      ]
      runAsUser = {
        type = "MustRunAsNonRoot"
      }
      seLinuxContext = {
        type = "MustRunAs"
      }
      volumes = [
        "configMap",
        "downwardAPI",
        "emptyDir",
        "persistentVolumeClaim",
        "projected",
        "secret"
      ]
    }
  }

  depends_on = [aws_eks_cluster.main]
}

# Admission Controllers
resource "kubernetes_manifest" "admission_webhook" {
  count = var.enable_kubernetes_addons && var.enable_admission_webhook ? 1 : 0
  manifest = {
    apiVersion = "admissionregistration.k8s.io/v1"
    kind       = "ValidatingAdmissionWebhook"
    metadata = {
      name = "pod-security-policy"
    }
    webhooks = [
      {
        name = "pod-security-policy.example.com"
        clientConfig = {
          service = {
            name      = "pod-security-policy"
            namespace = "kube-system"
            path      = "/validate"
          }
        }
        rules = [
          {
            operations = ["CREATE", "UPDATE"]
            apiGroups  = [""]
            apiVersions = ["v1"]
            resources  = ["pods"]
          }
        ]
        admissionReviewVersions = ["v1", "v1beta1"]
        sideEffects             = "None"
        failurePolicy           = "Fail"
      }
    ]
  }

  depends_on = [aws_eks_cluster.main]
}
