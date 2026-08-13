# METADATA
# title: Ensure VMs use the modern q35 machine type
# description: The q35 chipset (vs legacy pc/i440FX) supports PCIe passthrough and IOMMU features
# schemas:
#   - input: schema["input"]
# custom:
#   id: PROXMOX-005
#   avd_id: AVD-PROXMOX-0005
#   severity: LOW
#   short_code: use-q35-machine-type
#   recommended_action: Set machine = "q35"
#   input:
#     selector:
#       - type: terraform
package user.proxmox.PROXMOX005

import rego.v1

deny contains res if {
	some resource in input.resource.proxmox_virtual_environment_vm
	not resource.machine == "q35"
	res := {
		"msg": sprintf("Virtual machine '%s' does not use machine type 'q35'", [resource.__address__]),
		"file": resource.__file__,
		"line": resource.__line__,
	}
}
