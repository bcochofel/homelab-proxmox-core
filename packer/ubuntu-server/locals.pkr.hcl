locals {
  # VM settings
  node       = "pve"
  qemu_agent = true
  cpu_type   = "host"
  memory     = 2048
  sockets    = 1
  cores      = 1

  # disks settings
  scsi_controller = "virtio-scsi-pci"
  type            = "scsi"
  disk_size       = "12G"
  format          = "raw"
  storage_pool    = "local-lvm"

  # network settings
  bridge   = "vmbr0"
  firewall = true

  # cloud-init settings
  ci              = true
  ci_storage_pool = "local-lvm"
}
