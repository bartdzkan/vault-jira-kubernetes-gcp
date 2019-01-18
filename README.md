# vault-jira-kubernetes-gcp
Kubernetes Vault deployment, GCP PostgreSql Dynamic Vault secrets, JIRA dbconfig.xml vault secured.

Credit to [Kelsey Hightower](https://github.com/kelseyhightower/vault-on-google-kubernetes-engine) and [Seth Vargo](https://github.com/sethvargo/vault-kubernetes-workshop) for putting out these amazing guides. I took a lot of inspiration from these two repos for the vault integration piece.


## JIRA dbconfig.xml Usecase

dbconfig.xml is holding a plain text username and password for the DB connection.

To tackle this problem: we will use a Kubernetes Vault deployment, specifically [Vault Dynamic Secrets](https://learn.hashicorp.com/vault/getting-started/dynamic-secrets).
One caveat, XML does not take environment variables,  JIRA needs a cron job to reboot and rewrite the secret to dbconfigxml.
No one said security is easy or convenient. For production I would set the cron job to once a week or month when patching. You would need to change the cronjob and TTL and MAX_TTL in the Vault policy.

## Prerequisites &amp; Caveats

- You must have a Google Cloud Platform account and be authenticated as a
  project owner. If you are running locally, you will need to download and
  install the [Google Cloud SDK](https://cloud.google.com/sdk/), and then authenticate to Google Cloud
  appropriately.

- You must install kubectl to work with kubernetes
  ```text
  gcloud components install kubectl
  ```

- This tutorial generates self-signed SSL certificates and does not encrypt the
  resulting keys. For more details on a production-hardened setup, please see
  the [Vault production hardening docs](https://www.vaultproject.io/guides/operations/production).

- To install Vault client, find the [appropriate package](https://www.vaultproject.io/downloads.html) for    your system and download it.
  Vault is packaged as a zip archive.
  After downloading Vault, unzip the package. Vault runs as a single binary named vault. Any other files in the package can be safely removed and Vault will still function.

  The final step is to make sure that the vault binary is available on the PATH.
  ```text
  OSX: brew install vault
  ```
- You will need to install [jq](https://stedolan.github.io/jq/download/)
  ```text
  OSX: brew install jq
  ```
- You will need to install [cfssl](https://pkg.cfssl.org/)
  ```text
  OSX: brew install cfssl
  ```

- I've had issues in the past with other deployments. These scripts where ran with bash --version 4.4.23
  Instructions to [upgrade](https://clubmate.fi/upgrade-to-bash-4-in-mac-os-x/) bash  

- You must clone this repo:

    ```text
    git clone https://github.com/bartdzkan/vault-jira-kubernetes-gcp.git
    cd vault-jira-kubernetes-gcp
    ```
- You create a single node cluster, in production you would create 3. This would be changed in setup_vault.sh
  Also in the vault.yaml you would increase the replica to 3.

# Tutorial

## Create a New Project

To create a new project:

Go to the Manage resources page in the GCP Console.
GO TO [THE MANAGE RESOURCES PAGE](https://console.cloud.google.com/cloud-resource-manager)
On the Select organization drop-down list at the top of the page, select the organization in which you want to create a project. If you are a free trial user, skip this step, as this list does not appear.
Click Create Project.
In the New Project window that appears, enter a project name and select a billing account as applicable.
When you're finished entering new project details, click Create.

[Enable billing](https://cloud.google.com/billing/docs/how-to/modify-project#enable_billing_for_a_new_project) on the new project before moving on to the next step.

Once the Project is created, click on Compute Engine and Kubernetes engine to enable the API's.

## Connect to GCP Project

In your shell run:
```
gcloud init
```
If you are a new user you will need to create a new configuration, otherwise select 1.
```
Pick configuration to use:
 [1] Re-initialize this configuration [default] with new settings
 [2] Create a new configuration
```
 Select your account or login with new one.
```
 Choose the account you would like to use to perform operations for
 this configuration:
  [1] example@example.com
  [2] Log in with a new account
```
You might have a longer list but select the project you created.
```
Pick cloud project to use:
  [1] vault-jira-kubernetes-gcp
```
You are all set.

## Create Kubernetes Cluster and Vault

In vault/setup-vault.sh

Change the PROJECT_ID to the GCP project you created earlier.   

PROJECT_ID="vault-jira-kubernetes-gcp"

```
cd vault
sh setup-vault.sh
```

This will take around 5 minutes to deploy.

setup-vaul.sh will create:
```
- GCP Services
- Vault KMS keyring
- Vault-init encryption key
- GCS Bucket
- Cloud SQL Proxy service account
- Vault IAM service account
- Grant the service account the ability to generate new service accounts.
- Grant access vault storage bucket
- Grant vault init kms encryption key
- Provision a Kubernetes Cluster (With VPC-Native - using alias IP)
- Provisioned Static IP Address to vault
- Generate TLS Certificates
- Connect to Kubernetes Cluster
- Create Kubernetes Secret
- Create Vault configmap
- Apply vault.yaml
- Create and apply vault-load-balancer.yaml
```
### VPC-Native - using alias IP
This is needed for private IP communication with CloudSQL


## Set Vault Environment and Check Status

To set the environment variables for Vault, run vault.env
```
source vault.env

vault status
```

Vault should display your unsealed vault
```
Key             Value
---             -----
Seal Type       shamir
Initialized     true
Sealed          false
Total Shares    5
Threshold       3
Version         0.11.4
Cluster Name    vault-cluster-000000
Cluster ID      69238f95-2f45-253e-5355-0000000
HA Enabled      true
HA Cluster      https://10.0.0.0:8201
HA Mode         active
```
## Create GCP PostgreSql DB for JIRA

First create the PostgreSql DB instance, this can take some time.
Then create DB and User.

```
cd postgresql
sh create-instance.sh
sh create-db-user.sh
```

Change the password in create-db-user.sh - Randomly generated of course.

Next you will need to login to the GCP console, since there is no way to script this. :
https://console.cloud.google.com

Go to SQL
Select your instances
Go to Connections
Hit the checkbox Private IP
Allocate and connect
Remove Public IP

[For more information on SQL connections](https://cloud.google.com/blog/products/databases/introducing-private-networking-connection-for-cloud-sql)

Also Cloud SQL Admin API needs to be enabled.

Once this has finished copy the Private Ip.


## CloudSQL Proxy and Helm
Initialize Helm
```
cd tiller
kubectl create -f rbac.yaml
helm init --service-account tiller
```
Go to IAM in console, find cloud-sql-proxy service account.
Download json.
Copy json file to gcloud-sqlproxy and rename to credentials.json

Create secret from json file
```

kubectl create secret generic cloudsql-oauth-credentials --from-file gcloud-sqlproxy/credentials.json
```


Deploy Cloud SQL Proxy sidecar. This will allow vault to connect to SQL.
```
helm install -n sidecar-proxy ./gcloud-sqlproxy
```
NAME                                            READY  STATUS   RESTARTS  AGE
sidecar-proxy-gcloud-sqlproxy-85d85c8898-fbmvp  1/1    Running  0         5s


NOTES:
** Please be patient while the chart is being deployed **



The SQL server instances can be accessed via ports:
  - 5432 (atlassian-sql-db)
on the following DNS name from within your cluster:
- sidecar-proxy-gcloud-sqlproxy.default


## Vault Configuration

It is best practice not to use the root token.

Create the admin policy
```
vault policy write admin hcl/admin.hcl
```

Create admin token
```
vault token create -policy=admin -no-default-policy
```
Copy the token and replace VAULT_ADMIN_TOKEN in jira-secrets.sh

Run jira-secrets.sh

```
sh jira-secrets.sh
```

Run, use the token from client_token.json, since it only has read rights:
```
curl  -H "X-Vault-Token: VAULT_CLIENT_TOKEN" \
      -X GET $VAULT_ADDR/v1/database/creds/jira-sql-admin-role -k | jq '.data'> \
      database-creds.json
```

This will create your first user and secret in your CloudSQL instance.
The file database-creds.json has the username and password (Secret) for JIRA.
This is just a test, to see if everything is working.

## Jira Deployment

SSH into your jira server
```
gcloud compute --project "${PROJECT_ID}" ssh --zone "us-east1-b" "jira"
```

Install JIRA
```
https://confluence.atlassian.com/adminjiraserver/installing-jira-applications-on-linux-938846841.html
```
To install silently, upload response.varfile
```
wget https://www.atlassian.com/software/jira/downloads/binary/atlassian-jira-software-7.13.0-x64.bin
chmod a+x atlassian-jira-software-7.13.0-x64.bin
sudo ./atlassian-jira-software-7.13.0-x64.bin -q -varfile response.varfile
```

Connect to your jira instance
http://EXTERNAL_IP:8080

Configure JIRA

Select your own DB
postgresql
SQL_PRIVATE_IP
jira-db

Use the crendentials jira-db-user initially.

Please wait while the setup completes.

Name your instance.
Generate License Key or Apply one you already have.

And you are done.
Configure JIRA with SSL cert and change to port 443. (Not done in this demo)

Back to your ssh session.

Now time to create vault.sh
You will need to change permissions for the folder to complete this task.
```
sudo chmod 775 var/atlassian/application/jira
cd var/atlassian/application/jira
```
Edit jira/vault.sh

Copy token from client_token.json
This token has only read access for the secret.
Replace TOKEN with this token.
Replace VAULT_ADDR with your vault address
Replace SQL_PRIVATE_IP with your SQL Private IP.
Copy jira/vault.sh

To generate a new dbconfig.xml with secrets run vault.sh

```
sudo sh vault.sh
```

Now your JIRA has dynamic secrets.

```
sudo cat dbconfig.xml
```
To see the new config file.

## Set up cron job

This cronjob needs to run as root, and will run everyday at 12:00am
```
sudo crontab -e
0 0 * * * /bin/bash /var/atlassian/application-data/jira/vault.sh
```

Chnage JIRA directory back to previous permissions.
```
sudo chmod 750 var/atlassian/application/jira
```

You are done!
Remove all the .json and .csr files

# Troubleshooting

## Check cronjob or edit
```
sudo crontab -l -u root
```

## Starting Stopping JIRA service
```
sudo /etc/init.d/jira start/stop
```

## Get logs from cloud proxy
```
kubectl get pods --namespace=default
```

Copy your pod name and run command to get logs

```
kubectl logs sidecar-proxy-gcloud-sqlproxy-85d85c8898-f4mt8
```

## Vault errors

When vault gives you a connection error, it is because you are not in the
/vault folder. Vault needs your ca.pem certificate to authenticate.
