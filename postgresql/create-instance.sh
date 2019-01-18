#!/usr/bin/env bash
set -e
# Create CloudSQL instance
gcloud sql instances create atlassian-sql-instance\
    --database-version POSTGRES_9_6 \
    --tier db-f1-micro \
    --region us-east1 \
    --gce-zone us-east1-b \
    --authorized-networks 0.0.0.0/0
