# ── GCS Backup Bucket ─────────────────────────────────────────────────────────
# Bucket activ pentru Velero — creat manual, importat în terraform state

resource "google_storage_bucket" "klist_backups" {
  name          = "klist-velero-backups"
  location      = "EU"
  force_destroy = false

  uniform_bucket_level_access = true

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [location, lifecycle_rule, versioning, soft_delete_policy]
  }
}

# ── Service Account pentru backup (Velero) ────────────────────────────────────

resource "google_service_account" "backup" {
  account_id   = "klist-backup-sa"
  display_name = "kli.st Backup Service Account"
  description  = "Folosit de Velero pentru acces la GCS"
}

# Permisiuni pe bucket — storage.admin permite read/write/delete obiecte
resource "google_storage_bucket_iam_member" "backup_sa_access" {
  bucket = google_storage_bucket.klist_backups.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.backup.email}"
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
