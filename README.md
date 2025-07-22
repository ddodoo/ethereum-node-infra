# Ethereum Node Infrastructure Deployment Guide

### Prerequisites:
- Docker Engine 20.10+
- Docker Compose 2.0+
- 4+ CPU cores
- 8GB+ RAM
- 250 GB+ SSD storage
- Ports 8545, 8546, 30303, 8551

### Local Deployment
1. Clone the repository:

```
git clone https://github.com/your-repo/ethereum-node-infra.git
cd ethereum-node-infra
```

2. Run the deployment script:

```
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

3. Verify deployment:

```
./scripts/health-check.sh
./scripts/test-node.sh
```

### Production Deployment (GCP)

![GCP Ethereum Node Infrastructure]("Architecture Design_ Ethereum Node Infrastructure and Reliability.jpg")


1. Initialize Terraform:

```
cd terraform/gcp
terraform init
```

2. Configure variables in terraform.tfvars:

```
project_id = "your-gcp-project"
region = "us-central1"
node_count = 3
machine_type = "e2-standard-4"
```

3. Apply the configuration:

```
terraform apply
```

4. Deploy Kubernetes manifests:

```
kubectl apply -f k8s/namespace.yml
kubectl apply -f k8s/geth-deployment.yml
kubectl apply -f k8s/monitoring-stack.yml
kubectl apply -f k8s/services.yml
kubectl apply -f k8s/ingress.yml
```


### Backup and Restore

```
./scripts/backup.sh
```

Available backup modes:

- geth: Only backup Geth data
- configs: Only backup configuration files
- monitoring: Only backup monitoring data
- full: Complete backup (default)


### Monitoring Architecture

```
Geth (6060) ──┐
              ├─> Prometheus ──> Grafana
Lighthouse ───┘               └─> Alertmanager
Node Exporter ─┘
```

Accessing Dashboards: 
- Grafana: http://localhost:3000 `username: admin, password: admin123`
- Prometheus: http://localhost:9090
- Alertmanager: http://localhost:9093


Key Metrics: 
1. Node Health:
- Sync status
- Peer count
- Chain head block

2. Resource Usage:
- CPU/Memory/Disk
- Network I/O

3. Performance:
- Block processing time
- RPC call latency
- Queue sizes

Customizing Alerts: 
Edit configs/alertmanager/alertmanager.yml to configure:

- Email notifications
- Alert grouping and throttling
- Silence rules

Adding New Dashboards: 
1. Create JSON dashboard in configs/grafana/dashboards/
2. Update configs/grafana/provisioning/dashboards.yml

### Scaling Strategies:

Horizontal Scaling:

1. Read Replicas:

```
# k8s/geth-deployment.yml
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
```
- Deploy multiple Geth nodes with --syncmode light
- Use load balancer for RPC requests

2. Sharding


Vertical Scaling:
Development: 4vCPU, 8GB RAM, 250GB SSD
Production: 8vCPU, 16GB RAM, 1TB SSD


Database Optimization: 
1. Enable pruning:

```
command:
  - --syncmode=snap
  - --gcmode=archive
```

2. Adjust cache size:

```
command:
  - --cache=2048
```

### Security Best Practices: 

Network Security: 
1. Firewall Rules:

- Restrict RPC ports (8545,8546) to internal IPs

- Allow P2P port (30303) only from known peers

2. Authentication:

```
command:
  - --http.api=eth,net,web3
  - --ws.origins="https://yourdomain.com"
```
