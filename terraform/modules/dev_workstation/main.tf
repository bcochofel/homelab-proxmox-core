resource "random_pet" "vm_name" {
}

resource "proxmox_vm_qemu" "ci" {

  target_node = var.target_node

  name = var.vm_name != "" ? var.vm_name : random_pet.vm_name.id
  vmid = var.vm_id
  desc = var.vm_desc

  clone      = var.vm_template
  full_clone = var.full_clone

  onboot = var.onboot
  boot   = var.boot_order

  agent = var.agent

  memory  = var.memory
  sockets = var.sockets
  cores   = var.cores

  os_type = var.os_type

  scsihw = var.scsihw

  disks {
    ide {
      ide2 {
        cloudinit {
          storage = "local-lvm"
        }
      }
    }
    scsi {
      scsi0 {
        disk {
          size    = 12
          storage = "local-lvm"
          format  = "raw"
        }
      }
      #      scsi1 {
      #        disk {
      #          size    = 20
      #          storage = "Proxmox-QNAP-LUN"
      #          format  = "raw"
      #        }
      #      }
    }
  }

  network {
    model  = var.network_model
    bridge = var.network_bridge
  }

  ipconfig0 = "ip=${var.ip_cidr},gw=${var.gateway}"

  tags = var.tags
}
