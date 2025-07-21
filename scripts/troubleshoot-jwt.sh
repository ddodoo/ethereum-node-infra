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
echo "   Geth auth RPC endpoint from lighthouse:"
if docker exec lighthouse wget -q --tries=1 --timeout=5 --spider http://geth-node:8551 2>/dev/null; then
    echo "   ✅ Can reach geth:8551 from lighthouse"
else
    echo "   ❌ Cannot reach geth:8551 from lighthouse"
fi

echo ""
echo "5. Checking container status:"
docker compose ps

echo ""
echo "6. Recent error logs:"
echo "   Geth errors:"
docker logs geth-node 2>&1 | grep -i "error\|warn" | tail -5
echo "   Lighthouse errors:"
docker logs lighthouse 2>&1 | grep -i "error\|fail" | tail -5

echo ""
echo "7. If issues persist, try:"
echo "   - Recreate JWT: docker compose down && rm -f ./data/jwt/secret && ./deploy.sh"
echo "   - Check file permissions: ls -la ./data/jwt/"
echo "   - Verify no trailing newlines: hexdump -C ./data/jwt/secret"
