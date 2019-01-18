#!/bin/sh
/etc/init.d/jira stop

rm -f /var/atlassian/application-data/jira/dbconfig.xml

#Change Vault Token and Vault Address to your environment.
vault=$(curl  -H "X-Vault-Token: CLIENT_TOKEN" \
        -X GET https://VAULT_LOAD_BALANCER_IP:8200/v1/database/creds/jira-sql-admin-role -k)

DB_USER=$(echo $vault | jq -r .data.username)
DB_PASSWORD=$(echo $vault | jq -r .data.password)

header='<?xml version="1.0" encoding="UTF-8"?>
<jira-database-config>'

fmt='
  <name>defaultDS</name>
  <delegator-name>default</delegator-name>
  <database-type>postgres72</database-type>
  <schema-name>public</schema-name>
  <jdbc-datasource>
    <url>jdbc:postgresql://10.90.80.4:5432/jira-db</url>
    <driver-class>org.postgresql.Driver</driver-class>
    <username>'$DB_USER'</username>
    <password>'$DB_PASSWORD'</password>
    <pool-min-size>20</pool-min-size>
    <pool-max-size>20</pool-max-size>
    <pool-max-wait>30000</pool-max-wait>
    <validation-query>select 1</validation-query>
    <min-evictable-idle-time-millis>60000</min-evictable-idle-time-millis>
    <time-between-eviction-runs-millis>300000</time-between-eviction-runs-millis>
    <pool-max-idle>20</pool-max-idle>
    <pool-remove-abandoned>true</pool-remove-abandoned>
    <pool-remove-abandoned-timeout>300</pool-remove-abandoned-timeout>
    <pool-test-on-borrow>false</pool-test-on-borrow>
    <pool-test-while-idle>true</pool-test-while-idle>
  </jdbc-datasource>

'
footer='</jira-database-config>'

{
printf "%s\n" "$header"
printf "%s\n" "$fmt"
printf "%s\n" "$footer"
} > /var/atlassian/application-data/jira/dbconfig.xml

/etc/init.d/jira start
