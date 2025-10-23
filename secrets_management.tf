# AWS Secrets Manager
resource "aws_secretsmanager_secret" "database_credentials" {
  name                    = "${local.cluster_name}/database/credentials"
  description             = "Database credentials for the application"
  recovery_window_in_days  = 7
  kms_key_id              = aws_kms_key.secrets.arn

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "database_credentials" {
  secret_id = aws_secretsmanager_secret.database_credentials.id
  secret_string = jsonencode({
    username = "admin"
    password = "secure-password-123"
    host     = "database.example.com"
    port     = "5432"
  })
}

# KMS Key for encryption
resource "aws_kms_key" "secrets" {
  description             = "KMS key for secrets encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-secrets-key"
  })
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${local.cluster_name}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

# External Secrets Operator
resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = "0.9.11"
  namespace  = "external-secrets"

  create_namespace = true

  values = [yamlencode({
    serviceAccount = {
      annotations = {
        "eks.amazonaws.com/role-arn" = aws_iam_role.external_secrets.arn
      }
    }
  })]

  depends_on = [aws_eks_cluster.main]
}

# IAM Role for External Secrets Operator
resource "aws_iam_role" "external_secrets" {
  name = "${local.cluster_name}-external-secrets-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.cluster[0].arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.cluster[0].url, "https://", "")}:sub" = "system:serviceaccount:external-secrets:external-secrets"
            "${replace(aws_iam_openid_connect_provider.cluster[0].url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "external_secrets" {
  name = "${local.cluster_name}-external-secrets-policy"
  role = aws_iam_role.external_secrets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          aws_secretsmanager_secret.database_credentials.arn,
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${local.cluster_name}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = aws_kms_key.secrets.arn
      }
    ]
  })
}

# Secret Store for External Secrets
resource "kubernetes_manifest" "secret_store" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "SecretStore"
    metadata = {
      name      = "aws-secrets-manager"
      namespace = "default"
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.aws_region
          auth = {
            jwt = {
              serviceAccountRef = {
                name = "external-secrets"
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.external_secrets]
}

# External Secret
resource "kubernetes_manifest" "external_secret" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "database-credentials"
      namespace = "default"
    }
    spec = {
      refreshInterval = "1m"
      secretStoreRef = {
        name = "aws-secrets-manager"
        kind = "SecretStore"
      }
      target = {
        name = "database-credentials"
        creationPolicy = "Owner"
      }
      data = [
        {
          secretKey = "username"
          remoteRef = {
            key  = aws_secretsmanager_secret.database_credentials.name
            property = "username"
          }
        },
        {
          secretKey = "password"
          remoteRef = {
            key  = aws_secretsmanager_secret.database_credentials.name
            property = "password"
          }
        },
        {
          secretKey = "host"
          remoteRef = {
            key  = aws_secretsmanager_secret.database_credentials.name
            property = "host"
          }
        },
        {
          secretKey = "port"
          remoteRef = {
            key  = aws_secretsmanager_secret.database_credentials.name
            property = "port"
          }
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.secret_store]
}

# Vault Integration (Optional)
resource "helm_release" "vault" {
  count = var.enable_vault ? 1 : 0

  name       = "vault"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  version    = "0.25.0"
  namespace  = "vault"

  create_namespace = true

  values = [yamlencode({
    server = {
      ha = {
        enabled = true
        replicas = 3
        raft = {
          enabled = true
        }
      }
    }
  })]

  depends_on = [aws_eks_cluster.main]
}

# Vault Agent Injector
resource "helm_release" "vault_agent_injector" {
  count = var.enable_vault ? 1 : 0

  name       = "vault-agent-injector"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  version    = "0.25.0"
  namespace  = "vault"

  values = [yamlencode({
    injector = {
      enabled = true
    }
    server = {
      enabled = false
    }
  })]

  depends_on = [helm_release.vault]
}
