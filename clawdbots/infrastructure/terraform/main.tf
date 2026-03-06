terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
  }

  backend "gcs" {
    bucket = "brandlovers-terraform-state"
    prefix = "clawdbots"
  }
}

# ─── Variables ───────────────────────────────────────────────────────

variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "brandlovers-prod"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-east1"
}

variable "cluster_name" {
  description = "GKE cluster name"
  type        = string
  default     = "bl-cluster-prod"
}

variable "environments" {
  description = "Namespaces to create"
  type        = list(string)
  default     = ["clawdbots-dev", "clawdbots-prod"]
}

# ─── Providers ───────────────────────────────────────────────────────

provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_container_cluster" "main" {
  name     = var.cluster_name
  location = var.region
}

provider "kubernetes" {
  host                   = "https://${data.google_container_cluster.main.endpoint}"
  cluster_ca_certificate = base64decode(data.google_container_cluster.main.master_auth[0].cluster_ca_certificate)
  token                  = data.google_client_config.default.access_token
}

data "google_client_config" "default" {}

# ─── Artifact Registry ──────────────────────────────────────────────

resource "google_artifact_registry_repository" "clawdbots" {
  location      = var.region
  repository_id = "clawdbots"
  description   = "ClawdBots agent container images"
  format        = "DOCKER"

  cleanup_policies {
    id     = "keep-last-10"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }
}

# ─── Namespaces ──────────────────────────────────────────────────────

resource "kubernetes_namespace" "clawdbots" {
  for_each = toset(var.environments)

  metadata {
    name = each.value
    labels = {
      platform    = "clawdbots"
      environment = endswith(each.value, "-prod") ? "production" : "development"
      managed-by  = "terraform"
    }
  }
}

# ─── Resource Quotas (per namespace) ────────────────────────────────

resource "kubernetes_resource_quota" "clawdbots" {
  for_each = toset(var.environments)

  metadata {
    name      = "clawdbots-quota"
    namespace = each.value
  }

  spec {
    hard = {
      "requests.cpu"    = endswith(each.value, "-prod") ? "8" : "4"
      "requests.memory" = endswith(each.value, "-prod") ? "16Gi" : "8Gi"
      "limits.cpu"      = endswith(each.value, "-prod") ? "16" : "8"
      "limits.memory"   = endswith(each.value, "-prod") ? "32Gi" : "16Gi"
      "pods"            = endswith(each.value, "-prod") ? "50" : "20"
    }
  }

  depends_on = [kubernetes_namespace.clawdbots]
}

# ─── Network Policies (default deny ingress) ────────────────────────

resource "kubernetes_network_policy" "default_deny" {
  for_each = toset(var.environments)

  metadata {
    name      = "default-deny-ingress"
    namespace = each.value
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]
  }

  depends_on = [kubernetes_namespace.clawdbots]
}

# ─── Secret Manager secrets ─────────────────────────────────────────

resource "google_secret_manager_secret" "openclaw_api_key" {
  secret_id = "clawdbots-openclaw-api-key"
  
  replication {
    auto {}
  }

  labels = {
    platform = "clawdbots"
  }
}

resource "google_secret_manager_secret" "slack_tokens" {
  secret_id = "clawdbots-slack-tokens"
  
  replication {
    auto {}
  }

  labels = {
    platform = "clawdbots"
  }
}

resource "google_secret_manager_secret" "anthropic_api_key" {
  secret_id = "clawdbots-anthropic-api-key"
  
  replication {
    auto {}
  }

  labels = {
    platform = "clawdbots"
  }
}

# ─── Outputs ─────────────────────────────────────────────────────────

output "artifact_registry_url" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.clawdbots.repository_id}"
}

output "namespaces" {
  value = [for ns in kubernetes_namespace.clawdbots : ns.metadata[0].name]
}
