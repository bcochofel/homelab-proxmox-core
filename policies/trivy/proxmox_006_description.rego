# METADATA
# title: Ensure VMs have proper annotation/documentation
# description: Virtual machines should have a description for documentation and tracking
# schemas:
#   - input: schema["input"]
# custom:
#   id: PROXMOX-006
#   avd_id: AVD-PROXMOX-0006
#   severity: LOW
#   short_code: vm-description-required
#   recommended_action: Set the description attribute
#   input:
#     selector:
#       - type: terraform
package user.proxmox.PROXMOX006

import rego.v1

deny contains res if {
	some resource in input.resource.proxmox_virtual_environment_vm
	not resource.description
	res := {
		"msg": sprintf("Virtual machine '%s' does not have a description", [resource.__address__]),
		"file": resource.__file__,
		"line": resource.__line__,
	}
}
