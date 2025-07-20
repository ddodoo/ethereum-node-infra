#!/bin/bash
set -e

echo "🚀 Deploying Ethereum Node Infrastructure..."

# Create data directories
mkdir -p data/{geth,prometheus,grafana,alertmanager}
mkdir -p backups

# Set proper permissions
sudo chown -R 472:472 data/grafana  # Grafana UID
sudo chown -R 65534:65534 data/prometheus  # Nobody UID

# Pull latest images
echo "📥 Pulling Docker images..."
docker compose pull

# Deploy stack
echo "🏗️  Starting services..."
docker compose up -d

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 30

# Run health check
echo "🔍 Running health checks..."
./health-check.sh

echo "✅ Deployment complete!"
echo ""
echo "🌐 Access URLs:"
echo "   Grafana:      http://localhost:3000 (admin/admin123)"
echo "   Prometheus:   http://localhost:9090"
echo "   AlertManager: http://localhost:9093"
echo "   Geth RPC:     http://localhost:8545"
echo ""
echo "📊 Test the node:"
echo "   ./scripts/test-node.sh"