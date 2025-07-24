#!/bin/bash

set -e

echo "📁 Creating namespace..."
kubectl apply -f namespace.yml

echo "🚀 Deploying main services..."
kubectl apply -f geth-deployment.yml

echo "📈 Deploying monitoring stack..."
kubectl apply -f monitoring-stack.yml

echo "🌐 Creating services..."
kubectl apply -f services.yml

# echo "🔀 Setting up ingress..."
# kubectl apply -f k8s/ingress.yml

echo "✅ Deployment complete."
