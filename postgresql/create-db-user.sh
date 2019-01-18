#!/usr/bin/env bash
set -e

#Change Password
gcloud sql users set-password postgres --instance atlassian-sql-db --password password
gcloud sql users create jira-db-user --instance atlassian-sql-db --password jira-db-user
gcloud sql databases create jira-db --instance=atlassian-sql-db
