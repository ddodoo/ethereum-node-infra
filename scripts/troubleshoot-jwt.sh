#!/bin/bash

echo "🔍 JWT Authentication Troubleshooting"
echo "======================================"

# Check if JWT file exists
echo "1. Checking JWT file on host:"
if [ -f "./data/jwt/secret" ]; then
    echo "✅ JWT file exists"
    echo "   Path: $(pwd)/data/jwt/secret"
    echo "   Size: $(stat -c%s ./data/jwt/secret) bytes"
    echo "   Permissions: $(stat -c%A ./data/jwt/secret)"
    echo "   Content length: $(wc -c < ./data/jwt/secret) characters"
    
    # Check if it's valid hex
    if [[ $(cat ./data/jwt/secret) =~ ^[0-9a-fA-F]{64}$ ]]; then
        echo "✅ JWT format is valid (64 hex characters)"
    else
        echo "❌ JWT format is invalid (should be 64 hex characters)"
        echo "   Content: $(cat ./data/jwt/secret)"
    fi
else
    echo "❌ JWT file not found"
    exit 1
fi

echo ""
echo "2. Checking JWT file in containers:"

# Check Geth container
echo "   Geth container:"
if docker exec geth-node test -f /root/jwt/secret 2>/dev/null; then
    echo "   ✅ JWT file exists in geth container"
    GETH_JWT=$(docker exec geth-node cat /root/jwt/secret 2>/dev/null)
    echo "   Content: $GETH_JWT"
else
    echo "   ❌ JWT file not accessible in geth container"
fi

# Check Lighthouse container
echo "   Lighthouse container:"
if docker exec lighthouse test -f /root/jwt/secret 2>/dev/null; then
    echo "   ✅ JWT file exists in lighthouse container"
    LIGHTHOUSE_JWT=$(docker exec lighthouse cat /root/jwt/secret 2>/dev/null)
    echo "   Content: $LIGHTHOUSE_JWT"
else
    echo "   ❌ JWT file not accessible in lighthouse container"
fi

echo ""
echo "3. Checking if JWT contents match:"
if [ "$GETH_JWT" = "$LIGHTHOUSE_JWT" ] && [ -n "$GETH_JWT" ]; then
    echo "✅ JWT contents match between containers"
else
    echo "❌ JWT contents don't match or are empty"
fi

echo ""
echo "4. Testing network connectivity:"
echo "   Testing geth auth RPC endpoint from lighthouse:"

# Try multiple methods to test connectivity
CONNECTIVITY_SUCCESS=false

# Method 1: Try netcat if available
if docker exec lighthouse nc -z geth-node 8551 2>/dev/null; then
    echo "   ✅ Can reach geth:8551 from lighthouse (via nc)"
    CONNECTIVITY_SUCCESS=true
fi

# Method 2: Try telnet if available
if [ "$CONNECTIVITY_SUCCESS" = false ]; then
    if docker exec lighthouse timeout 5 telnet geth-node 8551 2>/dev/null | grep -q "Connected"; then
        echo "   ✅ Can reach geth:8551 from lighthouse (via telnet)"
        CONNECTIVITY_SUCCESS=true
    fi
fi

# Method 3: Try curl if available
if [ "$CONNECTIVITY_SUCCESS" = false ]; then
    if docker exec lighthouse curl -s --connect-timeout 5 http://geth-node:8551 2>/dev/null; then
        echo "   ✅ Can reach geth:8551 from lighthouse (via curl)"
        CONNECTIVITY_SUCCESS=true
    fi
fi

# Method 4: Use /dev/tcp (bash built-in)
if [ "$CONNECTIVITY_SUCCESS" = false ]; then
    if docker exec lighthouse bash -c "timeout 5 bash -c '</dev/tcp/geth-node/8551'" 2>/dev/null; then
        echo "   ✅ Can reach geth:8551 from lighthouse (via /dev/tcp)"
        CONNECTIVITY_SUCCESS=true
    fi
fi

# Method 5: Use echo and redirect (last resort)
if [ "$CONNECTIVITY_SUCCESS" = false ]; then
    if docker exec lighthouse bash -c "echo '' | timeout 5 nc geth-node 8551" 2>/dev/null; then
        echo "   ✅ Can reach geth:8551 from lighthouse (via echo/nc)"
        CONNECTIVITY_SUCCESS=true
    fi
fi

if [ "$CONNECTIVITY_SUCCESS" = false ]; then
    echo "   ❌ Cannot reach geth:8551 from lighthouse"
    echo "   Trying to diagnose network issues..."
    
    # Check if containers are on the same network
    echo "   Checking Docker networks:"
    docker network ls
    echo ""
    
    # Check container network settings
    echo "   Geth container network info:"
    docker exec geth-node ip addr show 2>/dev/null | grep inet || echo "   Could not get IP info"
    echo "   Lighthouse container network info:"
    docker exec lighthouse ip addr show 2>/dev/null | grep inet || echo "   Could not get IP info"
fi

echo ""
echo "5. Checking if Geth auth RPC is actually listening:"
echo "   Checking Geth processes and ports:"
docker exec geth-node netstat -tlnp 2>/dev/null | grep 8551 || \
docker exec geth-node ss -tlnp 2>/dev/null | grep 8551 || \
echo "   Could not check listening ports (netstat/ss not available)"

echo ""
echo "6. Checking container status:"
docker compose ps

echo ""
echo "7. Testing actual JWT authentication:"
if [ "$CONNECTIVITY_SUCCESS" = true ] && [ -n "$GETH_JWT" ]; then
    echo "   Testing JWT authentication with a simple request..."
    
    # Create a simple JSON-RPC request
    JWT_TOKEN="$GETH_JWT"
    
    # Try to make an authenticated request
    AUTH_TEST=$(docker exec lighthouse sh -c "
        curl -s -X POST \
        -H 'Content-Type: application/json' \
        -H 'Authorization: Bearer $JWT_TOKEN' \
        -d '{\"jsonrpc\":\"2.0\",\"method\":\"engine_exchangeCapabilities\",\"params\":[[\"engine_forkchoiceUpdatedV1\",\"engine_getPayloadV1\",\"engine_newPayloadV1\"]],\"id\":1}' \
        http://geth-node:8551
    " 2>/dev/null)
    
    if echo "$AUTH_TEST" | grep -q "result\|error"; then
        echo "   ✅ JWT authentication appears to be working"
        echo "   Response: $AUTH_TEST"
    else
        echo "   ❌ JWT authentication test failed"
        echo "   Response: $AUTH_TEST"
    fi
fi

echo ""
echo "8. Recent error logs:"
echo "   Geth errors (last 10 lines):"
docker logs geth-node 2>&1 | grep -i "error\|warn\|fail" | tail -10
echo ""
echo "   Lighthouse errors (last 10 lines):"
docker logs lighthouse 2>&1 | grep -i "error\|fail\|warn" | tail -10

echo ""
echo "9. Container environment check:"
echo "   Geth container environment:"
docker exec geth-node env | grep -E "(JWT|AUTH|RPC)" || echo "   No JWT/AUTH/RPC env vars found"
echo "   Lighthouse container environment:"
docker exec lighthouse env | grep -E "(JWT|AUTH|RPC)" || echo "   No JWT/AUTH/RPC env vars found"

echo ""
echo "10. If issues persist, try these solutions:"
echo "    - Recreate JWT: docker compose down && rm -f ./data/jwt/secret && ./deploy.sh"
echo "    - Check file permissions: ls -la ./data/jwt/"
echo "    - Verify no trailing newlines: hexdump -C ./data/jwt/secret | head -1"
echo "    - Check Docker network: docker network inspect \$(docker compose ps -q | head -1 | xargs docker inspect --format '{{range .NetworkSettings.Networks}}{{.NetworkID}}{{end}}')"
echo "    - Restart containers: docker compose restart"
echo "    - Check firewall rules on host system"
echo "    - Verify Geth is started with correct --authrpc.* flags"