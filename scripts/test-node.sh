#!/bin/bash

echo "🧪 Testing Ethereum Node Functionality..."

# Test basic RPC calls
echo "📞 Testing RPC calls..."

# Get chain ID
echo -n "Chain ID: "
curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
    http://localhost:8545 | jq -r '.result'

# Get latest block number
echo -n "Latest Block: "
curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    http://localhost:8545 | jq -r '.result' | xargs printf "%d\n"

# Get peer count
echo -n "Connected Peers: "
curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
    http://localhost:8545 | jq -r '.result' | xargs printf "%d\n"

# Check sync status
echo "Sync Status:"
curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
    http://localhost:8545 | jq '.'

echo ""
echo "✅ Node testing complete!"