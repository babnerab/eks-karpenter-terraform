# Pod Security Standards
resource "kubernetes_manifest" "pod_security_standards" {
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
}

# Network Policies
resource "kubernetes_manifest" "default_deny_ingress" {
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
}

resource "kubernetes_manifest" "default_deny_egress" {
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
}

# RBAC - Cluster Admin Role
resource "kubernetes_cluster_role" "cluster_admin" {
  metadata {
    name = "cluster-admin"
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }
}

# RBAC - Read-only Role
resource "kubernetes_cluster_role" "read_only" {
  metadata {
    name = "read-only"
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["get", "list", "watch"]
  }
}

# RBAC - Developer Role
resource "kubernetes_cluster_role" "developer" {
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
}

# Service Account for Karpenter with minimal permissions
resource "kubernetes_service_account" "karpenter" {
  metadata {
    name      = "karpenter"
    namespace = "karpenter"
    annotations = {
      "eks.amazonaws.com/role-arn" = var.enable_irsa ? aws_iam_role.karpenter_service_account[0].arn : ""
    }
  }
}

# Pod Security Policy (if supported)
resource "kubernetes_manifest" "pod_security_policy" {
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
}

# Security Context Constraints
resource "kubernetes_manifest" "security_context_constraints" {
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
}

# Admission Controllers
resource "kubernetes_manifest" "admission_webhook" {
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
}
