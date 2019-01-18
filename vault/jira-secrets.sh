#!/usr/bin/env bash
set -e

vault auth enable approle
vault secrets enable database

vault policy write jira hcl/jira-policy.hcl
vault write auth/approle/role/jira policies="jira"


curl --header "X-Vault-Token: VAULT_ADMIN_TOKEN" --request GET \
       $VAULT_ADDR/v1/auth/approle/role/jira/role-id -k |  jq '.data'> payload.json

curl --header "X-Vault-Token: VAULT_ADMIN_TOKEN" --request POST --data @payload.json \
       $VAULT_ADDR/v1/auth/approle/role/jira/secret-id -k | jq '.data'> payload2.json

jq -s '.[0] * .[1]' payload.json payload2.json > finalpayload.json

curl --request POST --data @finalpayload.json $VAULT_ADDR/v1/auth/approle/login -k | jq '.auth'> client_token.json


curl --header "X-Vault-Token: VAULT_ADMIN_TOKEN" \
     --request POST \
     --data @db-config-payload.json \
     $VAULT_ADDR/v1/database/config/jira-db -k | jq

#curl --header "X-Vault-Token: 5LALC34RjWwdzbZo4yC4qqSn" \
#     --request POST \
#     --data @db-role-payload.json \
#     $VAULT_ADDR/v1/database/roles/jira-sql-admin-role -k

vault write database/roles/jira-sql-admin-role \
    db_name=jira-db \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
        GRANT ALL ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    default_ttl="1h" \
    max_ttl="24h"
