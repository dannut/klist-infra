#!/bin/bash
# Run this ONCE after Vault is configured to set up K8s auth pentru kli-staging
# Prerequisites: vault login already done, kubectl configured
set -e

echo "==> Enabling Kubernetes auth in Vault (if not already enabled)..."
vault auth enable kubernetes 2>/dev/null || echo "already enabled"

echo "==> Configuring Kubernetes auth..."
vault write auth/kubernetes/config \
  kubernetes_host="https://$(kubectl get svc kubernetes -o jsonpath='{.spec.clusterIP}'):443"

echo "==> Creating kli-staging secrets engine..."
vault secrets enable -path=kli-staging kv-v2 2>/dev/null || echo "already enabled"

echo "==> Adding app secrets to Vault for staging..."
vault kv put kli-staging/app \
  DB_HOST="postgres.kli-staging.svc.cluster.local" \
  DB_PORT="5432" \
  DB_USER="kli_user" \
  DB_PASSWORD="$(openssl rand -base64 32)" \
  DB_NAME="kli_db"

echo "==> Adding Redis secret to Vault for staging..."
vault kv put kli-staging/redis \
  REDIS_PASSWORD="$(openssl rand -base64 32)"

echo "==> Adding Cloudflare tunnel token for test.kli.st..."
echo "    ATENTIE: inlocuieste TUNNEL_TOKEN_STAGING cu tokenul real din Cloudflare dashboard"
vault kv put kli-staging/cloudflare \
  TUNNEL_TOKEN="TUNNEL_TOKEN_STAGING"

echo "==> Writing Vault policy for kli-staging..."
vault policy write kli-staging-policy - <<POLICY
path "kli-staging/data/app" {
  capabilities = ["read"]
}
path "kli-staging/data/redis" {
  capabilities = ["read"]
}
path "kli-staging/data/cloudflare" {
  capabilities = ["read"]
}
POLICY

echo "==> Creating Vault role for kli-staging-backend serviceaccount..."
vault write auth/kubernetes/role/kli-staging-backend \
  bound_service_account_names=kli-backend,kli-cloudflared \
  bound_service_account_namespaces=kli-staging \
  policies=kli-staging-policy \
  ttl=1h

echo "==> Done! Vault is ready for kli-staging namespace."
echo ""
echo "Secrets stored in Vault:"
vault kv list kli-staging/
