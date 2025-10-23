This document outlines the cloud infrastructure architecture for Innovate Inc.

# Production Account (innovate-prod)
- Purpose: Live application hosting and production workloads 
- Billing: Separate cost tracking for production resources 
- Access: Restricted to production team only
- Resources:EKS cluster, RDS, production databases, production monitoring 

# Devops Account (innovate-devops)
- Purpose: Manage devops clusters tools
- Billing: billing with cost alloaction tags
- Access: Devops Team
• Resources: Devops EKS cluster, CI/CD pipelines/codepipeline

# Staging Account (innovate-staging)
- Purpose: Pre-production testing and validation
- Billing: Cost-optimized with auto-shutdown policies
- Access: Development and QA teams
• Resources: Staging EKS cluster, staging RDS databases. 

# Development Account (innovate-dev)
- Purpose: Development and testing environments
- Billing: Cost-optimized with auto-shutdown policies
- Access: All development teams
• Resources: Development EKS cluster, Dev RDS databases.

# Security/audit Account (innovate-security/audit)
- Purpose: Centralized security services 
- Billing: Shared across all accounts
- Access: Security team only
-Resources: GuardDuty, SecurityHub, Config, IAM access analyzer

# Network Account (innovate-networking)
- Purpose: To centralize and control all network components.
- Billing: Shared across all accounts
- Access: Networking team only
• Resources: VPCs,TGW,accounts,guardrails.

# Logging Account (innovate-logs)
- Purpose: Centralized logging and monitoring.
- Billing: Shared across all accounts.
- Access: DevOps and Security teams.
- Resources: Cloudtrail, cloudwatch config logs.

# Shared Account (innovate-shared)
- Purpose: Shared Resources between accounts.
- Billing: Shared across all accounts.
- Access: Architects and Security teams.

# Justification for this structure:
- Isolation: Prevents a blast radius in case of security incidents and a better management of the account for the different envs.
- Billing: Clear cost attribution and budget management.
- Compliance: Easier to meet regulatory requirements.
- Resources: Creating the necessary resources in the account that belongs to.
- Access Control: Granular permissions per environment following the least privileges principle of the cloud.

2. Network Design

VPC Architecture

AWS Virtual Private Cloud (VPC) Design:

Production VPC (10.0.0.0/16)

Public Subnets (10.0.1.0/24, 10.0.2.0/24) - Multi-AZ
Private Subnets (10.0.10.0/24, 10.0.11.0/24) - Multi-AZ
Database Subnets (10.0.20.0/24, 10.0.21.0/24) - Multi-AZ

Staging VPC (10.1.0.0/16)

Public Subnets (10.1.1.0/24, 10.1.2.0/24) - Multi-AZ
Private Subnets (10.1.10.0/24, 10.1.11.0/24) - Multi-AZ
Database Subnets (10.1.20.0/24, 10.1.21.0/24) - Multi-AZ

Development VPC (10.2.0.0/16)
├── Public Subnets (10.2.1.0/24, 10.2.2.0/24) - Multi-AZ
├── Private Subnets (10.2.10.0/24, 10.2.11.0/24) - Multi-AZ
└── Database Subnets (10.2.20.0/24, 10.2.21.0/24) - Multi-AZ

CIDR Planning	to Allocate IP ranges to avoid overlap across environments

Security Measures:

Subnets, Network ACLs and Security Groups
- Restrictive ingress/egress rules
- ACM certificate manager for TLS
- Principle of least privilege
- Regular security group audits
- public and private subnets
- NACLs

WAF and DDoS Protection
- AWS WAF for application-layer 7 attacks protection.
- AWS Shield Advanced for DDoS mitigation.
- GuardDuty for threat detection.
- CloudFlare or Akamai integration for additional protection if needed.

TGW and VPC Peering
- Transit Gateway to connect multiple VPCs in multiple account environments.
- VPC Peering one or two VPCs.
- AWS Private Link for private connectivity between services.

Network Segmentation
- Micro-segmentation using security groups.
- Network isolation between environments.
- Private endpoints for sensitive services.


# Compute Platform

I’d use Amazon Elastic Kubernetes Service (EKS) as the managed control plane for Kubernetes.

The approach:

Use EKS to handle cluster management (API server, etcd, control plane scaling).
- Worker nodes run on EC2 instances with ASG, or Karpenter.
- Manage deployments via GitHub Actions/Jenkins CI/CD pipelines.
- Use Namespaces to separate environments (dev,devops, staging, prod).

Leverage IAM roles for service accounts (IRSA) for secure pod-level permissions.

Benefits:

- High availability (multi-AZ control plane).
- Simplified upgrades and cluster patching.
- Close integration with AWS networking (VPC CNI plugin).



# Node Groups, Scaling, and Resource Allocation

EKS uses Managed Node Groups or Fargate profiles for compute resources.

Node Groups Strategy:
- Use Managed Node Groups with EC2 Spot ,Reserved Instances or On-Demand mix for cost efficiency.
- Group nodes by purpose or resource type (frontend, backend, batch).
- Label and taint nodes appropriately to control scheduling.

Scaling:
# Cluster and pod scaling

- Cluster Autoscaler : scales node groups based on pod demand.
- Horizontal Pod Autoscaler (HPA): scales pods based on CPU/memory usage/custom metrics.
- Vertical Pod Autoscaler (VPA): adjusts container resource requests automatically for efficiency.

Resource Allocation:
- Node groups (pools)
- Cost-optimized (spot): cron jobs, use taints/tolerations.
- Memory or CPU optimized pools as needed.
- Label pools (example., nodepool=spot, workload=web) and schedule via nodeSelector/affinity.
- Define CPU/memory requests and limits for every pod.
- Use ResourceQuotas and LimitRanges in each namespace to prevent resource exhaustion.


# Containerization Strategy

Build lightweight, secure, and consistent containers.
- Image Building:
- Build Docker images using multi-stage builds (to reduce size).
- Integrate the build process into CI/CD (Jenkins or GitHub Actions).

Registry:

- Use Amazon Elastic Container Registry (ECR) to store and manage container images.
- Enable image scanning and lifecycle policies to remove old images automatically.
- Use IAM roles and fine-grained policies for secure push/pull access.

Deployment:

- Use Helm for application manifests.
- Blue-Green Deployments: Zero-downtime deployments example 50% blue / 50% green until new release has passed the sanity.
- Canary Releases: Gradual rollout for risk mitigation.
- Deploy automatically via Jenkins pipeline.
- Use Rolling Updates(EKS default) or Blue/Green,canary deployments.

# Deployment Strategy: 

Kubernetes Service: deploy and manage the application

- Essentials (manifests)
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 3
  selector: { matchLabels: { app: web } }
  template:
    metadata: { labels: { app: web } }
    spec:
      securityContext: { runAsNonRoot: true }
      containers:
      - name: web
        image: ghcr.io/org/app:1.4.2@sha256:...
        ports: [{ containerPort: 8080, name: http }]
        resources:
          requests: { cpu: "250m", memory: "256Mi" }
          limits:   { cpu: "1",    memory: "512Mi" }
        readinessProbe: { httpGet: { path: /healthz, port: http }, periodSeconds: 5 }
        livenessProbe:  { httpGet: { path: /livez,   port: http }, periodSeconds: 10 }
---
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  type: ClusterIP
  selector: { app: web }
  ports: [{ port: 80, targetPort: http, name: http }]
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: web
spec:
  scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: web }
  minReplicas: 3
  maxReplicas: 15
  metrics:
  - type: Resource
    resource: { name: cpu, target: { type: Utilization, averageUtilization: 70 } }
```

```yaml
spec:
  template:
    spec:
      tolerations:
      - key: "spot"
        operator: "Exists"
        effect: "NoSchedule"
      nodeSelector: { nodepool: spot }
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              topologyKey: "kubernetes.io/hostname"
              labelSelector: { matchLabels: { app: web } }
```
# Deploy to EKS (Kubernetes)

1. Define Deployment manifest

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 2
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: myapp
        image: 123456789012.dkr.ecr.us-east-1.amazonaws.com/myapp:1.0.0
        ports:
        - containerPort: 3000
```

2. Apply 

```bash
kubectl apply -f deployment.yaml
```

3. Expose the service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp-service
spec:
  type: LoadBalancer
  selector:
    app: myapp
  ports:
    - port: 80
      targetPort: 3000
```

4. Automation via CI/CD

A best-practice containerization pipeline automates:

1. Code commit → Trigger pipeline
2. Run tests → Build Docker image
3. Push image to registry (ECR)
4. Update deployment YAML (or Helm values)
5. Deploy to cluster (EKS or Fargate)

 # Example using Jenkins pipeline:

```groovy
pipeline {
  agent any
  stages{
    stage("set credentials"){
      steps{
        script{
          if ("${params.env.name})" == "DEV" {
            CRED = DEV
          }
        }
      }
    }
  }

  stages {
    stage('Build') {
      steps {
        sh 'docker build -t myapp:${BUILD_NUMBER} .'
      }
    }

    stage('Push to ECR') {
      steps {
        sh '''
        $(aws ecr get-login --no-include-email --region us-east-1)
        docker tag myapp:${BUILD_NUMBER} 123456789012.dkr.ecr.us-east-1.amazonaws.com/myapp:${BUILD_NUMBER}
        docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/myapp:${BUILD_NUMBER}
        '''
      }
    }

    stage('Deploy') {
      steps {
        sh 'kubectl set image deployment/myapp myapp=123456789012.dkr.ecr.us-east-1.amazonaws.com/myapp:${BUILD_NUMBER}'
      }
    }
  }
}
```

 # Database Strategy
For production environment.
Aurora Global Database is a multi-region deployment of Amazon Aurora (MySQL or PostgreSQL compatible) designed for:

Disaster recovery (DR)
Low-latency global reads
Business continuity across regions

Non production environment
Aurora single region, single cluster, same engine but smaller instance size for cost optimized.


Justification:
- Managed Service Reduces operational overhead.
- High Availability Built-in failover capabilities for production environment.
- Backup & Recovery: Automated backup strategies.
- Security: Encryption at rest and in transit.
- Monitoring: Integrated monitoring and alerting.

Database High Availability & Disaster Recovery

Database High Availability Strategy:
1. Multi-AZ Deployment: Automatic failover within region.
2. Read Replicas: Cross-AZ read replicas for read scaling.
3. Connection Pooling: PgBouncer for connection management.
4. Monitoring: CloudWatch/Cloud Monitoring for database metrics.


Disaster Recovery Strategy:

Ensure service can continue in regional outages or major failures.

1. Cross-Region Replication: Read replicas in secondary region
2. Backup Strategy: 
- Daily automated backups  
- Weekly full backups
- Transaction log backups every 15 minutes

RTO & RPO depends on business line.
Aurora Global Database replicating to another region
EKS Cluster deployed via Terraform in multiple AZs
S3 with Cross-Region Replication enabled
CloudWatch Alarms trigger Lambda or Step Functions to spin up DR infra
Route 53 Failover to redirect traffic to standby region
