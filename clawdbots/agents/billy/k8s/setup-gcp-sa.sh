#!/bin/bash
# Create GCP service account for billy agent
# Run this once during initial setup

set -euo pipefail

PROJECT="brandlovers-prod"
SA_NAME="clawdbot-billy"
SA_EMAIL="${SA_NAME}@${PROJECT}.iam.gserviceaccount.com"
NAMESPACE="clawdbots-dev"
KSA_NAME="clawdbot-billy"

echo "🔐 Creating GCP service account: $SA_NAME"

# Create service account
gcloud iam service-accounts create $SA_NAME \
  --project=$PROJECT \
  --display-name="ClawdBot Billy Agent" \
  --description="Non-tech team helper: data queries + presentation generation" || true

# Bind Workload Identity
gcloud iam service-accounts add-iam-policy-binding $SA_EMAIL \
  --project=$PROJECT \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:$PROJECT.svc.id.goog[$NAMESPACE/$KSA_NAME]"

echo "✅ Service account created and bound to K8s SA"
echo ""
echo "📌 Next: Add specific IAM roles based on agent needs:"
echo "   gcloud projects add-iam-policy-binding $PROJECT \\"
echo "     --member=serviceAccount:$SA_EMAIL \\"
echo "     --role=roles/bigquery.dataViewer"
