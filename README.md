# AWS EKS with Karpenter - Graviton & Spot Instances

This Terraform repository deploys an AWS EKS cluster with Karpenter for advanced autoscaling, supporting both x86 and ARM64 (Graviton) instances with Spot pricing optimization.

# Prerequisites
- AWS CLI configured with appropriate permissions
- Terraform >= 1.0
- kubectl
- Helm 3.x
- AWS Account with sufficient permissions

# Quick Start

# 1. Clone and Initialize

```bash
git clone <"repository-url">
cd eks-karpenter-terraform
```
### 2. Configure Variables
Create a `terraform.tfvars` file:

```hcl
aws_region = "us-west-2"
project_name = "my-company"
environment = "dev"
cluster_version = "1.28"
```

# 3. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Configure kubectl

```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-west-2 --name my-company-dev

# Verify cluster access
kubectl get nodes
```

### 5. Verify Karpenter Installation

```bash
# Check Karpenter pods
kubectl get pods -n karpenter

# Check node pools
kubectl get nodepools
kubectl get ec2nodeclasses
```
# Deploying EKS Workloads

# Deploy to x86 Instances

Create a deployment that will run on x86 instances:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: x86-workload
spec:
  replicas: 3
  selector:
    matchLabels:
      app: x86-workload
  template:
    metadata:
      labels:
        app: x86-workload
    spec:
      nodeSelector:
        kubernetes.io/arch: amd64
        node-type: x86
      containers:
      - name: nginx
        image: nginx:1.21
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
```

# Deploy to ARM64 (Graviton) Instances
Create a deployment that will run on ARM64 instances:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: arm64-workload
spec:
  replicas: 3
  selector:
    matchLabels:
      app: arm64-workload
  template:
    metadata:
      labels:
        app: arm64-workload
    spec:
      nodeSelector:
        kubernetes.io/arch: arm64
        node-type: arm64
      containers:
      - name: nginx
        image: nginx:1.21
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
```

# Deploy to Spot Instances

Create a deployment that can run on spot instances:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spot-workload
spec:
  replicas: 5
  selector:
    matchLabels:
      app: spot-workload
  template:
    metadata:
      labels:
        app: spot-workload
    spec:
      nodeSelector:
        node-type: spot
      tolerations:
      - key: karpenter.sh/capacity-type
        operator: Equal
        value: spot
        effect: NoSchedule
      containers:
      - name: nginx
        image: nginx:1.21
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
```

### Karpenter Metrics
```bash
# View Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter

# Check node provisioning events
kubectl get events --sort-by='.lastTimestamp'
```
 # Useful Commands

```bash
# Check cluster status
kubectl get nodes -o wide

# View node labels
kubectl get nodes --show-labels

# Check Karpenter configuration
kubectl get nodepools -o yaml
kubectl get ec2nodeclasses -o yaml

# Monitor resource usage
kubectl top nodes
kubectl top pods --all-namespaces
```

# Cleanup

To destroy the infrastructure:

```bash
# Remove all workloads first
kubectl delete deployment --all

# Destroy Terraform resources
terraform destroy
```