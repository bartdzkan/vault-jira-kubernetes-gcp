# Login with AppRole
path "auth/approle/login" {
  capabilities = [ "read" ]
}


# Read Database Secrets
path "secret/database/*" {
  capabilities = [ "read" ]
}
# Read creds
path "database/creds/jira-sql-admin-role"{
  capabilities = [ "read" ]
}
