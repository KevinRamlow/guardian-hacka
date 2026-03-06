# ─── Agent Service Account Module ────────────────────────────────────
# Add new agents here. Each block creates a GCP SA + Workload Identity binding.

variable "agents" {
  description = "Map of agent configs"
  type = map(object({
    description = string
    roles       = list(string)
    namespace   = string
  }))
  default = {
    neuron = {
      description = "Data Intelligence agent — read-only BigQuery and Cloud SQL"
      roles = [
        "roles/bigquery.dataViewer",
        "roles/bigquery.jobUser",
        "roles/cloudsql.client",
      ]
      namespace = "clawdbots-dev"
    }
    # Uncomment when ready:
    # billy = {
    #   description = "Customer success agent"
    #   roles = [
    #     "roles/bigquery.dataViewer",
    #   ]
    #   namespace = "clawdbots-dev"
    # }
  }
}

# ─── GCP Service Accounts ───────────────────────────────────────────

resource "google_service_account" "agent" {
  for_each = var.agents

  account_id   = "clawdbot-${each.key}"
  display_name = "ClawdBot ${title(each.key)} Agent"
  description  = each.value.description
  project      = var.project_id
}

# ─── IAM Role Bindings ──────────────────────────────────────────────

locals {
  # Flatten agent→roles into a list of {agent, role} pairs
  agent_roles = flatten([
    for agent_name, config in var.agents : [
      for role in config.roles : {
        agent = agent_name
        role  = role
      }
    ]
  ])
}

resource "google_project_iam_member" "agent_roles" {
  for_each = {
    for ar in local.agent_roles : "${ar.agent}-${ar.role}" => ar
  }

  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.agent[each.value.agent].email}"
}

# ─── Workload Identity Bindings ──────────────────────────────────────

resource "google_service_account_iam_member" "workload_identity" {
  for_each = var.agents

  service_account_id = google_service_account.agent[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${each.value.namespace}/clawdbot-${each.key}]"
}

# ─── K8s Service Accounts ───────────────────────────────────────────

resource "kubernetes_service_account" "agent" {
  for_each = var.agents

  metadata {
    name      = "clawdbot-${each.key}"
    namespace = each.value.namespace
    labels = {
      platform = "clawdbots"
      agent    = each.key
    }
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.agent[each.key].email
    }
  }

  depends_on = [kubernetes_namespace.clawdbots]
}
