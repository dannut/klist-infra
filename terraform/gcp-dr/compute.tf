# ---- CONTROL PLANE (MASTER) ----
resource "google_compute_instance" "k3s_master" {
  name         = "klist-dr-master"
  machine_type = "e2-medium" # 2 vCPU, 4GB RAM
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 30
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.klist_subnet.id
    access_config {} # IP Public efemer pentru acces internet (Cloudflare/Pachete)
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    curl -sfL https://get.k3s.io | K3S_TOKEN=${random_password.k3s_cluster_token.result} sh -s - server \
      --disable traefik \
      --disable servicelb \
      --node-external-ip=$(curl -s ifconfig.me)
  EOF
}

# ---- WORKER NODE (SPOT INSTANCE) ----
resource "google_compute_instance" "k3s_worker" {
  name         = "klist-dr-worker-1"
  machine_type = "e2-medium"
  zone         = var.zone

  # Configurare SPOT pentru costuri reduse
  scheduling {
    preemptible       = true
    automatic_restart = false
    provisioning_model = "SPOT"
  }

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 30
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.klist_subnet.id
    access_config {}
  }

  # Se leagă automat de Master folosind IP-ul intern al acestuia
  metadata_startup_script = <<-EOF
    #!/bin/bash
    # Așteptăm câteva secunde să fim siguri că masterul a pornit complet
    sleep 30 
    curl -sfL https://get.k3s.io | K3S_URL=https://${google_compute_instance.k3s_master.network_interface.0.network_ip}:6443 K3S_TOKEN=${random_password.k3s_cluster_token.result} sh -s - agent
  EOF

  depends_on = [google_compute_instance.k3s_master]
}