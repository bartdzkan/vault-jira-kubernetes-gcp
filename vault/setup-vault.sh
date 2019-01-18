#!/usr/bin/env bash
set -e

export PROJECT_ID="vault-jira-kubernetes-gcp"
COMPUTE_ZONE="us-east1-b"
COMPUTE_REGION="us-east1"
GCS_BUCKET_NAME="${PROJECT_ID}-vault-storage"
KMS_KEY_ID="projects/${PROJECT_ID}/locations/global/keyRings/vault/cryptoKeys/vault-init"

if [ -z "${PROJECT_ID}" ]; then
  echo "Missing GOOGLE_CLOUD_PROJECT!"
  exit 1
fi

##Create GCP Services
gcloud services enable \
    cloudapis.googleapis.com \
    cloudkms.googleapis.com \
    container.googleapis.com \
    containerregistry.googleapis.com \
    iam.googleapis.com \
    --project ${PROJECT_ID}

echo "GCP Services Created"

#Create the `vault` kms keyring:
gcloud kms keyrings create vault \
    --location global \
    --project ${PROJECT_ID}

echo "Vault KMS keyring Created"

#Create the `vault-init` encryption key:
gcloud kms keys create vault-init \
    --location global \
    --keyring vault \
    --purpose encryption \
    --project ${PROJECT_ID}

echo "Vault-init encryption Created"

#Create a Google Cloud Storage Bucket
gsutil mb -p ${PROJECT_ID} gs://${GCS_BUCKET_NAME}

echo "GCS Bucket Created"

#Create Cloud SQL Proxy Service Account
gcloud iam service-accounts create cloud-sql-proxy\
    --display-name "Cloud SQL Proxy Sidecar" \
    --project ${PROJECT_ID}

echo "Cloud SQL Proxy IAM service account Created"

#Add SQL Admin to Cloud SQL Proxy service account
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member "serviceAccount:cloud-sql-proxy@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role "roles/cloudsql.admin"
echo "Cloud SQL Proxy add to role SQL Admin"
#Create the Vault IAM Service Account
gcloud iam service-accounts create vault-server \
    --display-name "vault service account" \
    --project ${PROJECT_ID}

echo "Vault IAM service account Created"

SERVICE_ACCOUNT="vault-server@${PROJECT_ID}.iam.gserviceaccount.com"

#Grant the service account the ability to generate new service
# accounts. This is required to use the Vault GCP secrets engine, otherwise it
# can be omitted.
#ROLES=(
#  "roles/resourcemanager.projectIamAdmin"
#  "roles/iam.serviceAccountAdmin"
#  "roles/iam.serviceAccountKeyAdmin"
#  "roles/iam.serviceAccountTokenCreator"
#  "roles/iam.serviceAccountUser"
#  "roles/viewer"
#)
#for role in "${ROLES[@]}"; do
#  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
#    --member "serviceAccount:${SERVICE_ACCOUNT}" \
#    --role "${role}"
#done

#echo "Roles Created"
#Grant access to the vault storage bucket:
gsutil iam ch \
    serviceAccount:vault-server@${PROJECT_ID}.iam.gserviceaccount.com:objectAdmin \
    gs://${GCS_BUCKET_NAME}

gsutil iam ch \
    serviceAccount:vault-server@${PROJECT_ID}.iam.gserviceaccount.com:legacyBucketReader \
    gs://${GCS_BUCKET_NAME}

echo "Access granted vault storage bucket"
#Grant access to the `vault-init` KMS encryption key:
gcloud kms keys add-iam-policy-binding \
    vault-init \
    --location global \
    --keyring vault \
    --member serviceAccount:vault-server@${PROJECT_ID}.iam.gserviceaccount.com \
    --role roles/cloudkms.cryptoKeyEncrypterDecrypter \
    --project ${PROJECT_ID}

echo "Access granted vault init kms encryption key"
# Provision a Kubernetes Cluster
gcloud container clusters create vault \
    --enable-autorepair \
    --cluster-version 1.11.5-gke.5 \
    --machine-type g1-small \
    --service-account vault-server@${PROJECT_ID}.iam.gserviceaccount.com \
    --num-nodes "1" \
    --zone ${COMPUTE_ZONE} \
    --project ${PROJECT_ID} \
    --enable-ip-alias --network "projects/${PROJECT_ID}/global/networks/default" \
    --subnetwork "projects/${PROJECT_ID}/regions/us-east1/subnetworks/default"


echo "Vault cluster created"
#Provision IP Address
gcloud compute addresses create vault \
    --region ${COMPUTE_REGION} \
    --project ${PROJECT_ID}

echo "Provisioned IP Address"
echo "Sleeping for 2 mins while address is created"
sleep 120
echo "Awake and running again."
#Store the `vault` compute address in an environment variable:
VAULT_LOAD_BALANCER_IP=$(gcloud compute addresses describe vault \
    --region ${COMPUTE_REGION} \
    --project ${PROJECT_ID} \
    --format='value(address)')
echo $VAULT_LOAD_BALANCER_IP

### Generate TLS Certificates
#In this section you will generate the self-signed TLS certificates used to secure communication between Vault clients and servers.
#Create a Certificate Authority:
cfssl gencert -initca ca-csr.json | cfssljson -bare ca

#Generate the Vault TLS certificates:
cfssl gencert \
    -ca=ca.pem \
    -ca-key=ca-key.pem \
    -config=ca-config.json \
    -hostname="vault,vault.default.svc.cluster.local,localhost,127.0.0.1,${VAULT_LOAD_BALANCER_IP}" \
    -profile=default \
    vault-csr.json | cfssljson -bare vault
echo "Generated vault TLS certificates"
#Connect to Kubernetes Cluster
gcloud container clusters get-credentials vault --zone ${COMPUTE_ZONE} --project ${PROJECT_ID}
echo "Connected to Vault Kubernetes Cluster"
### Deploy Vault
#In this section you will deploy the multi-node Vault cluster using a collection of Kubernetes and application configuration files.
#Create the `vault` secret to hold the Vault TLS certificates:
cat vault.pem ca.pem > vault-combined.pem

kubectl create secret generic vault \
    --from-file=ca.pem \
      --from-file=vault.pem=vault-combined.pem \
      --from-file=vault-key.pem
echo "Created secret generic vault"
#The `vault` configmap holds the Google Cloud Platform settings required bootstrap the Vault cluster.
#Create the `vault` configmap:

kubectl create configmap vault \
    --from-literal api-addr=https://${VAULT_LOAD_BALANCER_IP}:8200 \
    --from-literal gcs-bucket-name=${GCS_BUCKET_NAME} \
    --from-literal kms-key-id=${KMS_KEY_ID}

echo "Created Vault configmap"
#### Create the Vault StatefulSet
#In this section you will create the `vault` statefulset used to provision and manage two Vault server instances.
#Create the `vault` statefulset:
kubectl apply -f vault.yaml

echo "Vault yaml deployed"
## Expose the Vault Cluster

#In this section you will expose the Vault cluster using an external network load balancer.
#Generate the `vault` service configuration:

cat > vault-load-balancer.yaml <<EOF
  apiVersion: v1
  kind: Service
  metadata:
    name: vault-load-balancer
  spec:
    type: LoadBalancer
    loadBalancerIP: ${VAULT_LOAD_BALANCER_IP}
    ports:
      - name: http
        port: 8200
      - name: server
        port: 8201
    selector:
      app: vault
EOF

echo "Vault ladbalancer yaml created"

#Create the `vault-load-balancer` service:
kubectl apply -f vault-load-balancer.yaml

echo "Vault load balancer deployed"

echo "Deployment Complete"
