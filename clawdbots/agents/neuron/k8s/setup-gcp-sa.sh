#!/bin/bash
# Create GCP service account for Neuron agent with least-privilege IAM
set -euo pipefail

PROJECT="brandlovers-prod"
SA_NAME="clawdbot-neuron"
SA_EMAIL="${SA_NAME}@${PROJECT}.iam.gserviceaccount.com"
NAMESPACE="clawdbots-dev"

echo "🔐 Creating GCP service account: $SA_NAME"

# Create service account
gcloud iam service-accounts create $SA_NAME \
  --project=$PROJECT \
  --display-name="ClawdBot Neuron Agent" \
  --description="Data Intelligence agent — read-only access to BigQuery and Cloud SQL" || true

# BigQuery read-only
gcloud projects add-iam-policy-binding $PROJECT \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/bigquery.dataViewer" \
  --condition=None

# BigQuery job execution (needed to run queries)
gcloud projects add-iam-policy-binding $PROJECT \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/bigquery.jobUser" \
  --condition=None

# Cloud SQL client (for proxy connection)
gcloud projects add-iam-policy-binding $PROJECT \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/cloudsql.client" \
  --condition=None

# Bind Workload Identity
gcloud iam service-accounts add-iam-policy-binding $SA_EMAIL \
  --project=$PROJECT \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:${PROJECT}.svc.id.goog[${NAMESPACE}/${SA_NAME}]"

echo ""
echo "✅ Service account created with roles:"
echo "   - bigquery.dataViewer (read-only BQ access)"
echo "   - bigquery.jobUser (execute queries)"
echo "   - cloudsql.client (proxy connection)"
echo "   - workloadIdentityUser (GKE binding)"
echo ""
echo "⚠️  Remember to create a MySQL read-only user for this SA"
