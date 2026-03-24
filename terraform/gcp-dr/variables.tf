variable "project_id" {
  description = "ID-ul proiectului Google Cloud"
  type        = string
  default     = "project-092a68fd-42f4-4f6a-8fb" # Aici punem ID-ul, nu Numele!
}

variable "region" {
  description = "Regiunea GCP"
  type        = string
  default     = "europe-west4" # Olanda
}

variable "zone" {
  description = "Zona GCP pentru mașini virtuale"
  type        = string
  default     = "europe-west4-a"
}