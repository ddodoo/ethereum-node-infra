terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# GKE Cluster
resource "google_container_cluster" "ethereum_cluster" {
  name     = "ethereum-node-cluster"
  location = var.region

  initial_node_count = 1
  remove_default_node_pool = true

  network = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name

  logging_service = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }
}

resource "google_container_node_pool" "ethereum_nodes" {
  name       = "ethereum-node-pool"
  cluster    = google_container_cluster.ethereum_cluster.name
  location   = var.region
  node_count = var.node_count

  node_config {
    preemptible  = false
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb
    disk_type    = "pd-ssd"

    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/devstorage.read_only",
    ]
  }
}

# Persistent Disks for blockchain data
resource "google_compute_disk" "ethereum_data" {
  count = var.node_count
  name  = "ethereum-data-${count.index}"
  type  = "pd-ssd"
  zone  = "${var.region}-a"
  size  = var.blockchain_disk_size_gb
}

# Load Balancer
resource "google_compute_global_address" "ethereum_lb_ip" {
  name = "ethereum-lb-ip"
}