gcloud compute instances create jira \
    --project "${PROJECT_ID}" \
    --zone "us-east1-b" \
    --machine-type "n1-standard-1" \
    --subnet "default" \
    --tags "http-server,https-server" \
    --image "centos-7-v20181210" \
    --image-project "centos-cloud" \
    --boot-disk-size "10GB" \
    --boot-disk-type "pd-standard" \
    --boot-disk-device-name "jira" \
    --metadata-from-file startup-script=jira-startup-self.sh

gcloud compute --project=vault-jira-kubernetes-gcp-3 firewall-rules create default-allow-http --direction=INGRESS --priority=1000 --network=default --action=ALLOW --rules=tcp:80 --source-ranges=0.0.0.0/0 --target-tags=http-server

gcloud compute --project=vault-jira-kubernetes-gcp-3 firewall-rules create default-allow-https --direction=INGRESS --priority=1000 --network=default --action=ALLOW --rules=tcp:443 --source-ranges=0.0.0.0/0 --target-tags=https-server

gcloud compute --project=vault-jira-kubernetes-gcp-3 firewall-rules create default-allow-8080 --direction=INGRESS --priority=1000 --network=default --action=ALLOW --rules=tcp:8080 --source-ranges=0.0.0.0/0 --target-tags=http-server
