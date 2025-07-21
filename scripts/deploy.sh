#!/bin/bash
set -e

echo "🚀 Deploying Ethereum Node Infrastructure..."

# Stop any running containers and clean up
echo "🧹 Cleaning up existing deployment..."
docker compose down -v

# Remove old data directories 
sudo rm -rf data/

# Create config directories (these are bind-mounted and contain our configuration files)
echo "📁 Creating configuration directories..."
mkdir -p configs/{geth,prometheus,grafana,alertmanager}
mkdir -p backups
mkdir -p data

# Create JWT secret (required by Geth & Lighthouse)
echo "🔐 Generating JWT secret..."
openssl rand -hex 32 | tr -d "\n" > ./data/jwtsecret

# Ensure the JWT secret is a file and has proper permissions
chmod 644 ./data/jwtsecret
ls -la ./data/jwtsecret  # Verify it's a file

# Ensure config directories have proper permissions
sudo chown -R $(id -u):$(id -g) configs/
sudo chmod -R 755 configs/

# Pull latest images
echo "📥 Pulling Docker images..."
docker compose pull

# Deploy stack
echo "🏗️  Starting services..."
docker compose up -d

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 30

# Check container status
echo "📊 Container status:"
docker compose ps

# Show logs for troubleshooting if needed
echo "📋 Recent logs (last 5 lines per service):"
echo "--- Grafana ---"
docker logs grafana 2>&1 | tail -5
echo "--- Prometheus ---"
docker logs prometheus 2>&1 | tail -5
echo "--- AlertManager ---"
docker logs alertmanager 2>&1 | tail -5

# Run health check
echo "🔍 Running health checks..."
chmod +x ./health-check.sh
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
echo ""
echo "💾 Data is stored in Docker volumes:"
echo "   - grafana-data"
echo "   - prometheus-data"  
echo "   - geth-data"
echo "   - lighthouse-data"
echo "   - alertmanager-data"
echo ""
echo "🔧 To backup data: docker run --rm -v grafana-data:/data alpine tar czf /backup.tar.gz -C /data ."