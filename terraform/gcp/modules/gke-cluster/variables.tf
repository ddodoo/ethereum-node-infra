variable "cluster_name" {}
variable "region" {}
variable "vpc_id" {}
variable "subnet_id" {}
variable "node_count" {
  default = 1
}
variable "machine_type" {
  default = "e2-standard-2"
}
variable "disk_size_gb" {
  default = 50
}

variable "resource_labels" {
  type        = map(string)
  description = "Labels to apply to the GKE cluster"
  default     = {}
}