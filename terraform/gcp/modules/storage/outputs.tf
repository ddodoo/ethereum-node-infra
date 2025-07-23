output "disk_names" {
  value = google_compute_disk.ethereum_data[*].name
}
