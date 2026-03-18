#!/bin/bash
# Run this ONCE after Vault is configured to set up K8s auth for the kli namespace
# Prerequisites: vault login already done, kubectl configured

set -e

echo "==> Enabling Kubernetes auth in Vault..."
vault auth enable kubernetes || echo "already enabled"

echo "==> Configuring Kubernetes auth..."
vault write auth/kubernetes/config \
  kubernetes_host="https://$(kubectl get svc kubernetes -o jsonpath='{.spec.clusterIP}'):443"

echo "==> Creating kli secrets engine (kv-v2)..."
vault secrets enable -path=kli kv-v2 2>/dev/null || echo "already enabled"

echo "==> Adding app secrets to Vault..."
vault kv put kli/app \
  DB_HOST="postgres.kli.svc.cluster.local" \
  DB_PORT="5432" \
  DB_USER="kli_user" \
  DB_PASSWORD="$(openssl rand -base64 32)" \
  DB_NAME="kli_db"

echo "==> Adding Redis secret to Vault..."
vault kv put kli/redis \
  REDIS_PASSWORD="$(openssl rand -base64 32)"

echo "==> Adding Cloudflare tunnel token..."
echo "    ATENTIE: inlocuieste TUNNEL_TOKEN cu tokenul real din Cloudflare dashboard"
vault kv put kli/cloudflare \
  TUNNEL_TOKEN="TUNNEL_TOKEN_PRODUCTION"

echo "==> Writing Vault policy for kli..."
vault policy write kli-policy - <<POLICY
path "kli/data/app" {
  capabilities = ["read"]
}
path "kli/data/cloudflare" {
  capabilities = ["read"]
}
path "kli/data/redis" {
  capabilities = ["read"]
}
POLICY

echo "==> Creating Vault role for kli-backend serviceaccount..."
vault write auth/kubernetes/role/kli-backend \
  bound_service_account_names=kli-backend,kli-cloudflared \
  bound_service_account_namespaces=kli \
  policies=kli-policy \
  ttl=1h

echo "==> Done! Vault is ready for kli namespace."
echo ""
echo "Secrets stored in Vault:"
vault kv list kli/