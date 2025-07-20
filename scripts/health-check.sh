#!/bin/bash

echo "🔍 Performing health checks..."

# Check if containers are running
services=("geth-node" "prometheus" "grafana" "alertmanager" "node-exporter")

for service in "${services[@]}"; do
    if docker ps --format "table {{.Names}}" | grep -q "^${service}$"; then
        echo "✅ ${service} is running"
    else
        echo "❌ ${service} is not running"
        exit 1
    fi
done

# Check Geth RPC
echo "🔗 Testing Geth RPC..."
response=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    http://localhost:8545)

if echo "$response" | grep -q "result"; then
    block_hex=$(echo "$response" | jq -r '.result')
    block_decimal=$((16#${block_hex#0x}))
    echo "✅ Geth RPC responding - Current block: $block_decimal"
else
    echo "❌ Geth RPC not responding"
    exit 1
fi

# Check Prometheus
echo "📊 Testing Prometheus..."
if curl -s http://localhost:9090/-/healthy | grep -q "Prometheus"; then
    echo "✅ Prometheus is healthy"
else
    echo "❌ Prometheus is not healthy"
    exit 1
fi

# Check Grafana
echo "📈 Testing Grafana..."
if curl -s http://localhost:3000/api/health | grep -q "ok"; then
    echo "✅ Grafana is healthy"
else
    echo "❌ Grafana is not healthy"
    exit 1
fi

echo "🎉 All health checks passed!"