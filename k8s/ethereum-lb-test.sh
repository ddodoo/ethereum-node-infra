#!/bin/bash

# Your LoadBalancer external IP
GETH_IP="34.61.101.186"
GETH_HTTP_PORT="8545"
GETH_WS_PORT="8546"

echo "🧪 Testing Ethereum Node via LoadBalancer..."
echo "🌐 LoadBalancer IP: $GETH_IP"
echo ""

# Test basic RPC calls via HTTP
echo "📞 Testing HTTP RPC calls..."

# Get chain ID (should be 11155111 for Sepolia)
echo -n "Chain ID: "
CHAIN_ID=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
    http://$GETH_IP:$GETH_HTTP_PORT | jq -r '.result')
echo "$CHAIN_ID ($(printf "%d" $CHAIN_ID))"

# Get latest block number
echo -n "Latest Block: "
BLOCK_NUM=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    http://$GETH_IP:$GETH_HTTP_PORT | jq -r '.result')
echo "$BLOCK_NUM ($(printf "%d" $BLOCK_NUM))"

# Get peer count
echo -n "Connected Peers: "
PEER_COUNT=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
    http://$GETH_IP:$GETH_HTTP_PORT | jq -r '.result')
echo "$PEER_COUNT ($(printf "%d" $PEER_COUNT))"

# Check sync status
echo "Sync Status:"
curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
    http://$GETH_IP:$GETH_HTTP_PORT | jq '.'

# Get client version
echo -n "Client Version: "
curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' \
    http://$GETH_IP:$GETH_HTTP_PORT | jq -r '.result'

# Test WebSocket connection (basic connectivity test)
echo ""
echo "🔌 Testing WebSocket connectivity..."
timeout 5 curl -s --http1.1 \
    --header "Connection: Upgrade" \
    --header "Upgrade: websocket" \
    --header "Sec-WebSocket-Key: x3JJHMbDL1EzLkh9GBhXDw==" \
    --header "Sec-WebSocket-Version: 13" \
    http://$GETH_IP:$GETH_WS_PORT && echo "✅ WebSocket endpoint responding" || echo "❌ WebSocket endpoint not responding"

# Test specific Sepolia functionality
echo ""
echo "🔗 Testing Sepolia-specific functionality..."

# Get latest block details
echo "Latest Block Details:"
curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest",false],"id":1}' \
    http://$GETH_IP:$GETH_HTTP_PORT | jq '.result | {number, timestamp, hash, parentHash, gasUsed, gasLimit}'

# Test account balance (using a known address - Ethereum Foundation)
echo ""
echo "Testing balance query (Ethereum Foundation address):"
curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_getBalance","params":["0xde0B295669a9FD93d5F28D9Ec85E40f4cb697BAe","latest"],"id":1}' \
    http://$GETH_IP:$GETH_HTTP_PORT | jq -r '.result' | xargs printf "Balance: %d wei\n"

echo ""
echo "✅ LoadBalancer testing complete!"
echo ""
echo "📊 Quick Access URLs:"
echo "   HTTP RPC: http://$GETH_IP:$GETH_HTTP_PORT"
echo "   WebSocket: ws://$GETH_IP:$GETH_WS_PORT"
echo "   Grafana: http://34.66.0.117" # Your Grafana LoadBalancer IP