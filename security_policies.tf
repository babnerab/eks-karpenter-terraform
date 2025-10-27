# OPA Gatekeeper for Policy Enforcement
resource "helm_release" "gatekeeper" {
  count = var.enable_kubernetes_addons ? 1 : 0
  name       = "gatekeeper"
  repository = "https://open-policy-agent.github.io/gatekeeper/charts"
  chart      = "gatekeeper"
  version    = "3.14.0"
  namespace  = "gatekeeper-system"

  create_namespace = true

  values = [yamlencode({
    postInstall = {
      labelNamespace = {
        enabled = true
      }
    }
  })]

  depends_on = [aws_eks_cluster.main]
}

# Constraint Templates
resource "kubernetes_manifest" "k8s_required_labels" {
  count = var.enable_kubernetes_addons ? 1 : 0
  manifest = {
    apiVersion = "templates.gatekeeper.sh/v1beta1"
    kind       = "ConstraintTemplate"
    metadata = {
      name = "k8srequiredlabels"
    }
    spec = {
      crd = {
        spec = {
          names = {
            kind = "K8sRequiredLabels"
          }
          validation = {
            properties = {
              labels = {
                type = "array"
                items = {
                  type = "string"
                }
              }
            }
            type = "object"
          }
        }
      }
      targets = [
        {
          target = "admission.k8s.gatekeeper.sh"
          rego  = <<-EOT
            package k8srequiredlabels

            violation[{"msg": msg}] {
              required := input.parameters.labels
              provided := input.review.object.metadata.labels
              missing := required[_]
              not provided[missing]
              msg := sprintf("Missing required label: %v", [missing])
            }
          EOT
        }
      ]
    }
  }

  depends_on = [helm_release.gatekeeper]
}

# Constraint for required labels
resource "kubernetes_manifest" "required_labels_constraint" {
  count = var.enable_kubernetes_addons ? 1 : 0
  manifest = {
    apiVersion = "constraints.gatekeeper.sh/v1beta1"
    kind       = "K8sRequiredLabels"
    metadata = {
      name = "required-labels"
    }
    spec = {
      match = {
        kinds = [
          {
            apiGroups = ["apps"]
            kinds     = ["Deployment"]
          }
        ]
      }
      parameters = {
        labels = ["app", "version", "environment"]
      }
    }
  }

  depends_on = [kubernetes_manifest.k8s_required_labels]
}

# Constraint Template for resource limits
resource "kubernetes_manifest" "k8s_required_limits" {
  count = var.enable_kubernetes_addons ? 1 : 0
  manifest = {
    apiVersion = "templates.gatekeeper.sh/v1beta1"
    kind       = "ConstraintTemplate"
    metadata = {
      name = "k8srequiredlimits"
    }
    spec = {
      crd = {
        spec = {
          names = {
            kind = "K8sRequiredLimits"
          }
          validation = {
            properties = {
              limits = {
                type = "array"
                items = {
                  type = "string"
                }
              }
            }
            type = "object"
          }
        }
      }
      targets = [
        {
          target = "admission.k8s.gatekeeper.sh"
          rego  = <<-EOT
            package k8srequiredlimits

            violation[{"msg": msg}] {
              required := input.parameters.limits
              container := input.review.object.spec.containers[_]
              missing := required[_]
              not container.resources.limits[missing]
              msg := sprintf("Missing required resource limit: %v", [missing])
            }
          EOT
        }
      ]
    }
  }

  depends_on = [helm_release.gatekeeper]
}

# Constraint for resource limits
resource "kubernetes_manifest" "required_limits_constraint" {
  count = var.enable_kubernetes_addons ? 1 : 0
  manifest = {
    apiVersion = "constraints.gatekeeper.sh/v1beta1"
    kind       = "K8sRequiredLimits"
    metadata = {
      name = "required-limits"
    }
    spec = {
      match = {
        kinds = [
          {
            apiGroups = [""]
            kinds     = ["Pod"]
          }
        ]
      }
      parameters = {
        limits = ["cpu", "memory"]
      }
    }
  }

  depends_on = [kubernetes_manifest.k8s_required_limits]
}

# Constraint Template for image security
resource "kubernetes_manifest" "k8s_allowed_images" {
  count = var.enable_kubernetes_addons ? 1 : 0
  manifest = {
    apiVersion = "templates.gatekeeper.sh/v1beta1"
    kind       = "ConstraintTemplate"
    metadata = {
      name = "k8sallowedimages"
    }
    spec = {
      crd = {
        spec = {
          names = {
            kind = "K8sAllowedImages"
          }
          validation = {
            properties = {
              allowedRegistries = {
                type = "array"
                items = {
                  type = "string"
                }
              }
            }
            type = "object"
          }
        }
      }
      targets = [
        {
          target = "admission.k8s.gatekeeper.sh"
          rego  = <<-EOT
            package k8sallowedimages

            violation[{"msg": msg}] {
              allowed := input.parameters.allowedRegistries
              container := input.review.object.spec.containers[_]
              image := container.image
              not starts_with(image, allowed[_])
              msg := sprintf("Image not from allowed registry: %v", [image])
            }
          EOT
        }
      ]
    }
  }

  depends_on = [helm_release.gatekeeper]
}

# Constraint for allowed images
resource "kubernetes_manifest" "allowed_images_constraint" {
  count = var.enable_kubernetes_addons ? 1 : 0
  manifest = {
    apiVersion = "constraints.gatekeeper.sh/v1beta1"
    kind       = "K8sAllowedImages"
    metadata = {
      name = "allowed-images"
    }
    spec = {
      match = {
        kinds = [
          {
            apiGroups = [""]
            kinds     = ["Pod"]
          }
        ]
      }
      parameters = {
        allowedRegistries = [
          "docker.io/",
          "gcr.io/",
          "quay.io/",
          "public.ecr.aws/"
        ]
      }
    }
  }

  depends_on = [kubernetes_manifest.k8s_allowed_images]
}

# Kyverno for additional policy enforcement
resource "helm_release" "kyverno" {
  count = var.enable_kubernetes_addons ? 1 : 0
  name       = "kyverno"
  repository = "https://kyverno.github.io/kyverno/"
  chart      = "kyverno"
  version    = "3.0.0"
  namespace  = "kyverno"

  create_namespace = true

  values = [yamlencode({
    replicaCount = 3
  })]

  depends_on = [aws_eks_cluster.main]
}

# Kyverno Policy for Pod Security
resource "kubernetes_manifest" "kyverno_pod_security" {
  count = var.enable_kubernetes_addons ? 1 : 0
  manifest = {
    apiVersion = "kyverno.io/v1"
    kind       = "ClusterPolicy"
    metadata = {
      name = "pod-security"
    }
    spec = {
      validationFailureAction = "enforce"
      background = true
      rules = [
        {
          name = "check-security-context"
          match = {
            any = [
              {
                resources = {
                  kinds = ["Pod"]
                }
              }
            ]
          }
          validate = {
            message = "Security context is required"
            pattern = {
              spec = {
                securityContext = {
                  runAsNonRoot = true
                  runAsUser = ">0"
                }
              }
            }
          }
        },
        {
          name = "check-resource-limits"
          match = {
            any = [
              {
                resources = {
                  kinds = ["Pod"]
                }
              }
            ]
          }
          validate = {
            message = "Resource limits are required"
            pattern = {
              spec = {
                containers = [
                  {
                    resources = {
                      limits = {
                        memory = "?*"
                        cpu = "?*"
                      }
                    }
                  }
                ]
              }
            }
          }
        }
      ]
    }
  }

  depends_on = [helm_release.kyverno]
}
