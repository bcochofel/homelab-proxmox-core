# METADATA
# title: Ensure UEFI VMs have an EFI disk for secure boot state
# description: VMs booting with OVMF need an efi_disk block to persist UEFI/secure-boot variables
# schemas:
#   - input: schema["input"]
# custom:
#   id: PROXMOX-004
#   avd_id: AVD-PROXMOX-0004
#   severity: HIGH
#   short_code: efi-disk-required-for-uefi
#   recommended_action: Add an efi_disk block when bios = "ovmf"
#   input:
#     selector:
#       - type: terraform
package user.proxmox.PROXMOX004

import rego.v1

deny contains res if {
	some resource in input.resource.proxmox_virtual_environment_vm
	resource.bios == "ovmf"
	not resource.efi_disk
	res := {
		"msg": sprintf("Virtual machine '%s' uses UEFI (bios = \"ovmf\") but has no efi_disk block for secure boot state", [resource.__address__]),
		"file": resource.__file__,
		"line": resource.__line__,
	}
}
