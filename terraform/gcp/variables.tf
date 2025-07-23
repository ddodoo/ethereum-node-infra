variable "project_id" {
  description = "The ID of the GCP project"
  type        = string
}

variable "region" {
  description = "The GCP region to deploy resources in"
  type        = string
  default     = "us-central1"
}

variable "node_count" {
  description = "Number of nodes in the GKE node pool"
  type        = number
  default     = 1
}

variable "machine_type" {
  description = "Type of machine for GKE nodes"
  type        = string
  default     = "e2-standard-2"
}

variable "disk_size_gb" {
  description = "Boot disk size (GB) for each node"
  type        = number
  default     = 50
}

variable "blockchain_disk_size_gb" {
  description = "Size (GB) for Ethereum data persistent disk"
  type        = number
  default     = 100
}
