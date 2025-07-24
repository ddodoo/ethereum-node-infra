resource "google_container_cluster" "this" {
  name     = var.cluster_name
  location = var.region
  resource_labels = var.resource_labels

  remove_default_node_pool = true
  initial_node_count       = 1
  network    = var.vpc_id
  subnetwork = var.subnet_id

  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }
}

resource "google_container_node_pool" "nodes" {
  name       = "${var.cluster_name}-pool"
  cluster    = google_container_cluster.this.name
  location   = var.region
  node_count = var.node_count

  node_config {
    preemptible  = false
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb
    disk_type    = "pd-standard"
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/devstorage.read_only",
    ]
  }
}
