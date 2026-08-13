# METADATA
# title: Ensure VMs use UEFI firmware for modern deployments
# description: UEFI firmware (OVMF) provides better security features than legacy SeaBIOS
# schemas:
#   - input: schema["input"]
# custom:
#   id: PROXMOX-003
#   avd_id: AVD-PROXMOX-0003
#   severity: MEDIUM
#   short_code: use-uefi-firmware
#   recommended_action: Set bios = "ovmf"
#   input:
#     selector:
#       - type: terraform
package user.proxmox.PROXMOX003

import rego.v1

deny contains res if {
	some resource in input.resource.proxmox_virtual_environment_vm
	not resource.bios == "ovmf"
	res := {
		"msg": sprintf("Virtual machine '%s' uses SeaBIOS instead of UEFI (bios = \"ovmf\")", [resource.__address__]),
		"file": resource.__file__,
		"line": resource.__line__,
	}
}
