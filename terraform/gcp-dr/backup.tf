# ── GCS Backup Bucket ─────────────────────────────────────────────────────────

resource "google_storage_bucket" "klist_backups" {
  name          = "klist-backups-${var.project_id}"
  location      = var.region
  force_destroy = false

  # Versioning — păstrează istoric obiectelor
  versioning {
    enabled = true
  }

  # Lifecycle — șterge automat backup-urile mai vechi de 3 zile
  lifecycle_rule {
    condition {
      age = 3
    }
    action {
      type = "Delete"
    }
  }

  # Retenție uniformă la nivel de bucket
  uniform_bucket_level_access = true
}

# ── Service Account pentru backup (Velero + pg_dump) ──────────────────────────

resource "google_service_account" "backup" {
  account_id   = "klist-backup-sa"
  display_name = "kli.st Backup Service Account"
  description  = "Folosit de Velero si pg_dump CronJob pentru acces la GCS"
}

# Permisiuni pe bucket — objectAdmin permite read/write/delete obiecte
resource "google_storage_bucket_iam_member" "backup_sa_access" {
  bucket = google_storage_bucket.klist_backups.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.backup.email}"
}

# Cheie JSON pentru service account — folosita ca K8s secret
resource "google_service_account_key" "backup" {
  service_account_id = google_service_account.backup.name
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "backup_bucket_name" {
  description = "Numele bucket-ului GCS pentru backup-uri"
  value       = google_storage_bucket.klist_backups.name
}

output "backup_sa_email" {
  description = "Email-ul service account-ului pentru backup"
  value       = google_service_account.backup.email
}

output "backup_sa_key_base64" {
  description = "Cheia JSON a service account-ului (base64) — folosita ca K8s secret"
  value       = google_service_account_key.backup.private_key
  sensitive   = true
}
