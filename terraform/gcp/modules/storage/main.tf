resource "google_compute_disk" "ethereum_data" {
  count = var.disk_count
  name  = "${var.disk_prefix}-${count.index}"
  type  = "pd-standard"
  zone  = "${var.region}-a"
  size  = var.disk_size
}
