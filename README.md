# ethereum-node-infra

Interacting with the Node
# Get latest block number
```
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:8545
```

# Get balance of an address
```
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_getBalance","params":["0x742d35cc6ba9d4c4d686e0e4c2dd11de89b94faf", "latest"],"id":1}' \
  http://localhost:8545
```

# Get transaction by hash
```
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_getTransactionByHash","params":["0x..."],"id":1}' \
  http://localhost:8545
```

Monitoring Queries
# Block production rate
rate(geth_blockchain_head_block[5m])

# Memory usage
process_resident_memory_bytes{job="geth"}

# Peer connections
geth_p2p_peers

# Sync status
geth_blockchain_head_block - geth_blockchain_head_header
