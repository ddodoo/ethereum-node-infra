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

# Use networking module
module "networking" {
  source       = "./modules/networking"
  region       = var.region
  network_name = "ethereum-vpc"
  subnet_name  = "ethereum-subnet"
  subnet_cidr  = "10.10.0.0/16"
}

# Use GKE cluster module
module "gke_cluster" {
  source       = "./modules/gke-cluster"
  region       = var.region
  cluster_name = "ethereum-node-cluster"
  vpc_id       = module.networking.vpc_id
  subnet_id    = module.networking.subnet_id
  node_count   = 1

  machine_type = "e2-highcpu-8"
  disk_size_gb = 50
}

# Use storage module for Ethereum persistent disks
module "storage" {
  source     = "./modules/storage"
  region     = var.region
  disk_count = var.node_count
  disk_size  = 150

}

# Load Balancer (still inline — optional to modularize)
resource "google_compute_global_address" "ethereum_lb_ip" {
  name = "ethereum-lb-ip"
}
