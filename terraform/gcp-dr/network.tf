resource "google_compute_network" "klist_vpc" {
  name                    = "klist-dr-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "klist_subnet" {
  name          = "klist-dr-subnet"
  ip_cidr_range = "10.0.1.0/24"
  network       = google_compute_network.klist_vpc.id
  region        = var.region
}

# 1. Regula originală (NU O ȘTERGE) - Necesară pentru K3s
resource "google_compute_firewall" "allow_internal" {
  name    = "klist-allow-internal"
  network = google_compute_network.klist_vpc.name

  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }

  source_ranges = ["10.0.1.0/24"]
}

# 2. Regula nouă (ADAUG-O AICI) - Pentru SSH prin IAP
resource "google_compute_firewall" "allow_ssh_iap" {
  name    = "klist-allow-ssh-iap"
  network = google_compute_network.klist_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"] 
}

# Permitem accesul la API-ul Kubernetes de oriunde (pentru testare)
resource "google_compute_firewall" "allow_k8s_api" {
  name    = "klist-allow-k8s-api"
  network = google_compute_network.klist_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }

  source_ranges = ["0.0.0.0/0"]
}